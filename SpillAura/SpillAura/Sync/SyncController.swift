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

    @Published var responsiveness: SyncResponsiveness = {
        let raw = UserDefaults.standard.string(forKey: "syncResponsiveness") ?? ""
        return SyncResponsiveness(rawValue: raw) ?? .balanced
    }() {
        didSet { UserDefaults.standard.set(responsiveness.rawValue, forKey: "syncResponsiveness") }
    }

    /// Latest per-channel colors from the active source. Updated every tick while streaming.
    /// Used by ScreenSyncView for the live zone preview.
    @Published private(set) var previewColors: [(channel: UInt8, r: Float, g: Float, b: Float)] = []

    @Published var zoneConfig: ZoneConfig = {
        let cc = UserDefaults.standard.object(forKey: "entertainmentChannelCount") as? Int ?? 1
        return ZoneConfig.load(channelCount: cc)
    }()

    // MARK: - Private

    private let syncActor = SyncActor()
    private var session: EntertainmentSession?
    private var sessionStateCancellable: AnyCancellable?

    /// The source the streaming loop reads each tick. Swap this to change vibes mid-stream.
    private var activeSource: LightSource? = nil
    private var channelCount: Int = 1

    /// When set, the streaming loop overrides this channel with a pulsing white signal
    /// so the user can physically identify which light maps to which channel.
    var pulsedChannel: UInt8? = nil

    // MARK: - Public API

    /// Start or hot-swap to a palette-based vibe.
    func startVibe(_ vibe: Vibe) {
        activeVibe = vibe
        activeSource = PaletteSource(vibe: vibe)
        if connectionStatus == .disconnected {
            startSession()
        }
    }

    /// Activate the entertainment session and send a static color to all lights.
    func startStaticColor(r: Float, g: Float, b: Float) {
        guard connectionStatus == .disconnected else { return }
        activeVibe = nil
        activeSource = StaticColorSource(r: r, g: g, b: b)
        startSession()
    }

    /// Start or hot-swap to screen sync mode.
    func startScreenSync() {
        activeVibe = nil
        activeSource = ScreenCaptureSource(config: zoneConfig, responsiveness: responsiveness)
        if connectionStatus == .disconnected {
            startSession()
        }
    }

    /// Persist zone config and hot-swap the capture source if currently streaming.
    func saveZoneConfig() {
        zoneConfig.save()
        if connectionStatus == .streaming {
            startScreenSync()
        }
    }

    /// Stop the entertainment session.
    func stop() {
        session?.stop()
        activeSource = nil
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
            let capturedChannelCount = channelCount
            let startTime = Date.timeIntervalSinceReferenceDate
            Task { @MainActor [weak self] in
                guard let self else { return }
                while self.connectionStatus == .streaming {
                    let elapsed = Date.timeIntervalSinceReferenceDate - startTime
                    if let source = self.activeSource {
                        var colors = source.nextColors(channelCount: capturedChannelCount, at: elapsed)
                        if let ch = self.pulsedChannel,
                           let idx = colors.firstIndex(where: { $0.channel == ch }) {
                            let brightness = Float(0.5 + 0.5 * sin(elapsed * .pi * 4))
                            colors[idx] = (channel: ch, r: brightness, g: brightness, b: brightness)
                        }
                        self.session?.sendColors(colors)
                        self.previewColors = colors
                    }
                    try? await Task.sleep(for: .milliseconds(16))
                }
                self.previewColors = []
            }

        case .deactivating:
            connectionStatus = .disconnected
        }

        if case .idle = state { } else if let errorMessage = session?.lastError {
            connectionStatus = .error(errorMessage)
        }
    }
}
