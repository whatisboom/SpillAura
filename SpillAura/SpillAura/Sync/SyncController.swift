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

    // MARK: - Private

    private let syncActor = SyncActor()
    private var session: EntertainmentSession?
    private var sessionStateCancellable: AnyCancellable?

    // Pending color to send once streaming starts
    private var pendingColor: (r: Float, g: Float, b: Float)? = nil

    // MARK: - M2 API

    /// Activate the entertainment session and send a static color to all lights.
    ///
    /// If credentials or group ID are missing from storage, this logs an error
    /// and returns without doing anything.
    ///
    /// - Parameters:
    ///   - r: Red 0.0–1.0
    ///   - g: Green 0.0–1.0
    ///   - b: Blue 0.0–1.0
    func startStaticColor(r: Float, g: Float, b: Float) {
        guard connectionStatus == .disconnected else { return }

        guard let credentials = HueBridgeAuth().loadFromKeychain() else {
            connectionStatus = .error("No bridge credentials found. Complete setup first.")
            return
        }

        let groupID = UserDefaults.standard.string(forKey: "entertainmentGroupID") ?? ""
        guard !groupID.isEmpty else {
            connectionStatus = .error("No entertainment group selected. Complete setup first.")
            return
        }

        let channelCount = UserDefaults.standard.object(forKey: "entertainmentChannelCount") as? Int ?? 1

        let newSession = EntertainmentSession(
            credentials: credentials,
            groupID: groupID,
            channelCount: channelCount
        )
        session = newSession
        pendingColor = (r, g, b)
        isRunning = true

        // Observe state changes and mirror them to connectionStatus
        sessionStateCancellable = newSession.$state
            .dropFirst()  // @Published emits the current .idle on subscription — skip it
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

    /// Stop the entertainment session.
    func stop() {
        session?.stop()
        pendingColor = nil
    }

    // MARK: - Private

    private func handleSessionState(_ state: EntertainmentSession.State) {
        switch state {
        case .idle:
            // Check for error BEFORE clearing session so we can surface it
            if let errorMessage = session?.lastError {
                connectionStatus = .error(errorMessage)
            } else {
                connectionStatus = .disconnected
            }
            isRunning = false
            session = nil
            sessionStateCancellable = nil
            Task { [weak self] in
                guard let self else { return }
                await self.syncActor.clearSession()
            }

        case .activating, .connecting:
            connectionStatus = .connecting

        case .reconnecting:
            connectionStatus = .connecting

        case .streaming:
            connectionStatus = .streaming
            if let color = pendingColor {
                pendingColor = nil
                let (r, g, b) = (color.r, color.g, color.b)
                // Stream continuously at ~25Hz until the session stops.
                // A single packet isn't enough — the bridge requires sustained streaming.
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    while self.connectionStatus == .streaming {
                        await self.syncActor.sendStaticColor(r: r, g: g, b: b)
                        try? await Task.sleep(for: .milliseconds(40))
                    }
                }
            }

        case .deactivating:
            connectionStatus = .disconnected
        }

        // Surface session errors for non-idle states
        if case .idle = state { } else if let errorMessage = session?.lastError {
            connectionStatus = .error(errorMessage)
        }
    }
}
