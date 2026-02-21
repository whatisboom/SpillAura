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
            sequence: sequenceNumber,
            groupID: groupID
        )
        sequenceNumber = sequenceNumber == 255 ? 0 : sequenceNumber + 1

        connection.send(content: packet, completion: .contentProcessed({ error in
            if let error = error {
                print("[EntertainmentSession] send error: \(error)")
            }
        }))
    }

    /// Send a packet with per-channel colors.
    /// Only valid when `state == .streaming`.
    func sendColors(_ channelColors: [(channel: UInt8, r: Float, g: Float, b: Float)]) {
        guard state == .streaming, let connection else { return }
        let packet = ColorPacketBuilder.buildPacket(
            channelColors: channelColors,
            sequence: sequenceNumber,
            groupID: groupID
        )
        sequenceNumber = sequenceNumber == 255 ? 0 : sequenceNumber + 1
        connection.send(content: packet, completion: .contentProcessed({ _ in }))
    }

    // MARK: - REST Activation

    private func activate() {
        state = .activating
        Task { [weak self] in
            guard let self else { return }
            do {
                // Always stop first — if a previous session was left active (e.g. app killed
                // mid-stream), the bridge won't reopen UDP 2100 on a bare "start".
                try? await self.putAction("stop")
                try await Task.sleep(for: .milliseconds(500))
                try await self.putAction("start")
                // Verify the session is actually active before opening DTLS
                let status = try await self.fetchSessionStatus()
                if status != "active" {
                    throw URLError(.badServerResponse, userInfo: [
                        NSLocalizedDescriptionKey: "Expected session status 'active', got '\(status)'"
                    ])
                }
                // Brief delay to let the bridge fully open port 2100
                try await Task.sleep(for: .milliseconds(500))
                self.openDTLS()
            } catch {
                self.lastError = "Activation failed: \(error.localizedDescription)"
                self.state = .idle
            }
        }
    }

    private func fetchSessionStatus() async throws -> String {
        let urlString = "https://\(credentials.bridgeIP)/clip/v2/resource/entertainment_configuration/\(groupID)"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue(credentials.username, forHTTPHeaderField: "hue-application-key")
        let session = URLSession(configuration: .default, delegate: SessionSelfSignedCertDelegate(), delegateQueue: nil)
        let (data, _) = try await session.data(for: request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArr = json["data"] as? [[String: Any]],
              let first = dataArr.first,
              let status = first["status"] as? String else {
            return "unknown"
        }
        return status
    }

    private func deactivateREST() {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.putAction("stop")
            } catch {
                print("[EntertainmentSession] deactivation REST call failed: \(error)")
            }
            self.state = .idle
        }
    }

    private func putAction(_ action: String) async throws {
        let urlString = "https://\(credentials.bridgeIP)/clip/v2/resource/entertainment_configuration/\(groupID)"
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
        let (_, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1

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

        let pskIdentity = Data(credentials.username.utf8)
        let pskData = hexToData(credentials.clientKey)

        // NordVPN (and similar) creates utun interfaces that NWConnection may prefer over the
        // physical Ethernet/WiFi interface. VPN tunnels inherit the same interface *type* as the
        // underlying physical link, so type-based filtering doesn't help. Instead, use
        // NWPathMonitor to get the actual interface objects and filter by name prefix.
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            monitor.cancel()
            guard let self else { return }

            // Skip VPN tunnels (utun, ipsec, ppp); prefer wired Ethernet over WiFi
            let physicalIface = path.availableInterfaces
                .filter { !$0.name.hasPrefix("utun") && !$0.name.hasPrefix("ipsec") && !$0.name.hasPrefix("ppp") }
                .sorted { lhs, _ in lhs.type == .wiredEthernet }
                .first

            Task { @MainActor in
                self.startDTLS(pskIdentity: pskIdentity, pskData: pskData, via: physicalIface)
            }
        }
        monitor.start(queue: .global(qos: .userInteractive))
    }

    private func startDTLS(pskIdentity: Data, pskData: Data, via physicalIface: NWInterface?) {
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
        // Hue bridge uses PSK-only — no server certificate to verify
        sec_protocol_options_set_peer_authentication_required(
            tlsOptions.securityProtocolOptions, false
        )

        let params = NWParameters(dtls: tlsOptions, udp: NWProtocolUDP.Options())
        params.allowLocalEndpointReuse = true
        if let iface = physicalIface {
            params.requiredInterface = iface
        }

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

        // Fail fast if DTLS handshake doesn't complete in 15 seconds
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard let self, case .connecting = self.state else { return }
            print("[EntertainmentSession] DTLS handshake timeout")
            conn.cancel()
        }
    }

    private func handleConnectionState(_ newState: NWConnection.State) {
        switch newState {
        case .ready:
            reconnectAttempts = 0
            state = .streaming

        case .failed(let error):
            print("[EntertainmentSession] connection failed: \(error)")
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
            connection = nil

        case .waiting(let error):
            print("[EntertainmentSession] connection waiting: \(error)")

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
