import Foundation
import Network
import Combine

/// Manages one Hue entertainment session: REST activation → DTLS → streaming → teardown.
@MainActor
final class EntertainmentSession: ObservableObject {

    // MARK: - State

    enum State: Equatable {
        case idle
        case activating
        case connecting
        case streaming
        case reconnecting(attempt: Int)
        case deactivating
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var lastError: String? = nil

    // MARK: - Private

    private let credentials: BridgeCredentials
    private let groupID: String
    private let channelCount: Int

    private var connection: NWConnection?
    private var sequenceNumber: UInt8 = 0
    private var reconnectAttempts: Int = 0
    private static let maxReconnectAttempts = 3

    // MARK: - Init

    /// - Parameters:
    ///   - credentials: Bridge credentials loaded from Keychain
    ///   - groupID: Entertainment configuration group UUID from UserDefaults
    ///   - channelCount: Number of channels in the selected group
    init(credentials: BridgeCredentials, groupID: String, channelCount: Int) {
        self.credentials = credentials
        self.groupID = groupID
        self.channelCount = channelCount
    }

    // MARK: - Public API

    /// Start the session: activate via REST, then open DTLS connection.
    func start() {
        guard state == .idle else { return }
        lastError = nil
        reconnectAttempts = 0
        activate()
    }

    /// Stop the session: close DTLS, then deactivate via REST.
    func stop() {
        guard state != .idle && state != .deactivating else { return }
        teardown()
    }

    /// Send a packet setting all channels to the given RGB color.
    /// Only valid when `state == .streaming`.
    func sendColor(r: Float, g: Float, b: Float) {
        guard state == .streaming, let connection else { return }

        let channels = (0..<channelCount).map { UInt16($0) }
        let packet = ColorPacketBuilder.buildPacket(
            r: r,
            g: g,
            b: b,
            channels: channels,
            sequence: sequenceNumber
        )
        sequenceNumber = sequenceNumber == 255 ? 0 : sequenceNumber + 1

        connection.send(content: packet, completion: .idempotent)
    }

    // MARK: - REST Activation

    private func activate() {
        state = .activating
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.putAction("start")
                self.openDTLS()
            } catch {
                self.lastError = "Activation failed: \(error.localizedDescription)"
                self.state = .idle
            }
        }
    }

    private func deactivateREST() {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.putAction("stop")
            } catch {
                // Log but don't surface — we're already tearing down
                print("[EntertainmentSession] deactivation REST call failed: \(error)")
            }
            self.state = .idle
        }
    }

    private func putAction(_ action: String) async throws {
        let urlString = "https://\(credentials.bridgeIP)/clip/v2/resource/entertainment_configuration/\(groupID)"
        print("[EntertainmentSession] PUT \(action) → \(urlString)")
        print("[EntertainmentSession] username: \(credentials.username.prefix(8))… groupID: \(groupID)")
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(credentials.username, forHTTPHeaderField: "hue-application-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["action": action])

        let session = URLSession(
            configuration: .default,
            delegate: SessionSelfSignedCertDelegate(),
            delegateQueue: nil
        )
        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        print("[EntertainmentSession] PUT \(action) response: HTTP \(statusCode)")
        print("[EntertainmentSession] response body: \(String(data: data, encoding: .utf8) ?? "nil")")

        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse, userInfo: [
                NSLocalizedDescriptionKey: "PUT \(action) returned HTTP \(statusCode)"
            ])
        }
    }

    // MARK: - DTLS Connection

    private func openDTLS() {
        state = .connecting

        let pskIdentity = credentials.username.data(using: .utf8)!
        let pskData = hexToData(credentials.clientKey)

        let tlsOptions = NWProtocolTLS.Options()
        sec_protocol_options_set_min_tls_protocol_version(
            tlsOptions.securityProtocolOptions, .DTLSv12
        )
        sec_protocol_options_set_max_tls_protocol_version(
            tlsOptions.securityProtocolOptions, .DTLSv12
        )

        let pskDispatch = pskData.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
            DispatchData(bytes: ptr)
        }
        let identityDispatch = pskIdentity.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
            DispatchData(bytes: ptr)
        }
        sec_protocol_options_add_pre_shared_key(
            tlsOptions.securityProtocolOptions,
            pskDispatch as __DispatchData,
            identityDispatch as __DispatchData
        )

        let params = NWParameters(dtls: tlsOptions, udp: NWProtocolUDP.Options())
        params.allowLocalEndpointReuse = true

        let conn = NWConnection(
            host: NWEndpoint.Host(credentials.bridgeIP),
            port: 2100,
            using: params
        )
        connection = conn

        conn.stateUpdateHandler = { [weak self] newState in
            Task { @MainActor [weak self] in
                self?.handleConnectionState(newState)
            }
        }

        conn.start(queue: .global(qos: .userInteractive))
    }

    private func handleConnectionState(_ newState: NWConnection.State) {
        switch newState {
        case .ready:
            reconnectAttempts = 0
            state = .streaming

        case .failed(let error):
            connection?.cancel()
            connection = nil

            if reconnectAttempts < Self.maxReconnectAttempts && state != .deactivating {
                reconnectAttempts += 1
                state = .reconnecting(attempt: reconnectAttempts)
                scheduleReconnect()
            } else {
                lastError = "Connection failed: \(error.localizedDescription)"
                state = .deactivating
                deactivateREST()
            }

        case .cancelled:
            // Triggered by our own teardown — don't reconnect
            connection = nil

        case .waiting(let error):
            print("[EntertainmentSession] waiting: \(error)")

        default:
            break
        }
    }

    private func scheduleReconnect() {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let self, case .reconnecting = self.state else { return }
            self.openDTLS()
        }
    }

    // MARK: - Teardown

    private func teardown() {
        state = .deactivating
        connection?.cancel()
        connection = nil
        deactivateREST()
    }

    // MARK: - Helpers

    private func hexToData(_ hex: String) -> Data {
        var data = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            if let byte = UInt8(hex[index..<nextIndex], radix: 16) {
                data.append(byte)
            }
            index = nextIndex
        }
        return data
    }
}

// MARK: - Self-Signed Certificate Delegate

/// Bypasses certificate validation for the Hue bridge's self-signed TLS cert.
/// The bridge is local-network only, so this is acceptable.
private final class SessionSelfSignedCertDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
