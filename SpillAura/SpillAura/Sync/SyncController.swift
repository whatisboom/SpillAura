import Foundation
import Combine

@MainActor
class SyncController: ObservableObject {

    // MARK: - Published state

    @Published var isRunning: Bool = false

    /// Mirrors EntertainmentSession.State for the UI.
    enum ConnectionStatus: Equatable {
        case disconnected
        case connecting
        case streaming
        case error(String)
    }

    @Published private(set) var connectionStatus: ConnectionStatus = .disconnected
    @Published private(set) var activeVibe: Vibe? = nil

    // MARK: - Private

    private let syncActor = SyncActor()
    private var session: EntertainmentSession?
    private var sessionStateCancellable: AnyCancellable?

    private var pendingSource: LightSource? = nil
    private var channelCount: Int = 1

    // MARK: - Public API

    /// Activate the entertainment session and animate using a palette-based vibe.
    func startVibe(_ vibe: Vibe) {
        guard connectionStatus == .disconnected else { return }
        activeVibe = vibe
        pendingSource = PaletteSource(vibe: vibe)
        startSession()
    }

    /// Activate the entertainment session and send a static color to all lights.
    func startStaticColor(r: Float, g: Float, b: Float) {
        guard connectionStatus == .disconnected else { return }
        activeVibe = nil
        pendingSource = StaticColorSource(r: r, g: g, b: b)
        startSession()
    }

    /// Stop the entertainment session.
    func stop() {
        session?.stop()
        pendingSource = nil
        activeVibe = nil
    }

    // MARK: - Private

    private func startSession() {
        guard let credentials = HueBridgeAuth().loadFromKeychain() else {
            connectionStatus = .error("No bridge credentials found. Complete setup first.")
            return
        }

        let groupID = UserDefaults.standard.string(forKey: "entertainmentGroupID") ?? ""
        guard !groupID.isEmpty else {
            connectionStatus = .error("No entertainment group selected. Complete setup first.")
            return
        }

        channelCount = UserDefaults.standard.object(forKey: "entertainmentChannelCount") as? Int ?? 1

        let newSession = EntertainmentSession(
            credentials: credentials,
            groupID: groupID,
            channelCount: channelCount
        )
        session = newSession
        isRunning = true

        sessionStateCancellable = newSession.$state
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                self?.handleSessionState(state)
            }

        Task { [weak self] in
            guard let self else { return }
            await self.syncActor.setSession(newSession)
        }

        newSession.start()
    }

    private func handleSessionState(_ state: EntertainmentSession.State) {
        switch state {
        case .idle:
            if let errorMessage = session?.lastError {
                connectionStatus = .error(errorMessage)
            } else {
                connectionStatus = .disconnected
            }
            isRunning = false
            activeVibe = nil
            session = nil
            sessionStateCancellable = nil
            Task { [weak self] in
                guard let self else { return }
                await self.syncActor.clearSession()
            }

        case .activating, .connecting, .reconnecting:
            connectionStatus = .connecting

        case .streaming:
            connectionStatus = .streaming
            if let source = pendingSource {
                pendingSource = nil
                let capturedChannelCount = channelCount
                let startTime = Date.timeIntervalSinceReferenceDate
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    while self.connectionStatus == .streaming {
                        let elapsed = Date.timeIntervalSinceReferenceDate - startTime
                        let colors = source.nextColors(channelCount: capturedChannelCount, at: elapsed)
                        self.session?.sendColors(colors)
                        try? await Task.sleep(for: .milliseconds(16))
                    }
                }
            }

        case .deactivating:
            connectionStatus = .disconnected
        }

        if case .idle = state { } else if let errorMessage = session?.lastError {
            connectionStatus = .error(errorMessage)
        }
    }
}
