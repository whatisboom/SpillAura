import AppKit
import Foundation
import Combine
import SpillAuraCore

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

    @Published var selectedMode: SyncMode = {
        let raw = UserDefaults.standard.string(forKey: "selectedMode") ?? ""
        return SyncMode(rawValue: raw) ?? .screen
    }() {
        didSet { UserDefaults.standard.set(selectedMode.rawValue, forKey: "selectedMode") }
    }

    @Published private(set) var connectionStatus: ConnectionStatus = .disconnected {
        didSet { menuBarIcon = Self.icon(for: connectionStatus) }
    }
    @Published private(set) var activeAura: Aura? = nil

    @Published private(set) var menuBarIcon: String = "lightbulb"

    @Published var responsiveness: SyncResponsiveness = {
        let raw = UserDefaults.standard.string(forKey: "syncResponsiveness") ?? ""
        return SyncResponsiveness(rawValue: raw) ?? .balanced
    }() {
        didSet {
            UserDefaults.standard.set(responsiveness.rawValue, forKey: "syncResponsiveness")
            (activeSource as? ScreenCaptureSource)?.updateResponsiveness(responsiveness)
        }
    }

    @Published var brightness: Float = {
        let stored = UserDefaults.standard.float(forKey: "brightness")
        return stored == 0 ? 1.0 : stored
    }() {
        didSet { UserDefaults.standard.set(brightness, forKey: "brightness") }
    }

    @Published var speedMultiplier: Double = {
        let stored = UserDefaults.standard.double(forKey: "speedMultiplier")
        return stored == 0 ? 1.0 : stored
    }() {
        didSet { UserDefaults.standard.set(speedMultiplier, forKey: "speedMultiplier") }
    }

    /// Latest per-channel colors from the active source. Updated every tick while streaming.
    /// Used by ScreenSyncView for the live zone preview.
    @Published private(set) var previewColors: [(channel: UInt8, r: Float, g: Float, b: Float)] = []

    @Published var zoneConfig: ZoneConfig = {
        let cc = UserDefaults.standard.object(forKey: "entertainmentChannelCount") as? Int ?? 1
        return ZoneConfig.load(channelCount: cc)
    }()

    // MARK: - Init / deinit

    init() {
        let nc = NSWorkspace.shared.notificationCenter
        systemObservers.append(nc.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                wasStreamingBeforeSleep = connectionStatus == .streaming
                stop()
            }
        })
        systemObservers.append(nc.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, wasStreamingBeforeSleep else { return }
                wasStreamingBeforeSleep = false
                resumeLastSession()
            }
        })
        Task { @MainActor [weak self] in
            // Brief yield so SwiftUI finishes scene setup before we touch Keychain/session.
            try? await Task.sleep(for: .milliseconds(200))
            self?.autoStartIfNeeded()
        }
    }

    deinit {
        systemObservers.forEach {
            NSWorkspace.shared.notificationCenter.removeObserver($0)
        }
    }

    // MARK: - Private

    private var systemObservers: [any NSObjectProtocol] = []
    private var wasStreamingBeforeSleep = false

    private let syncActor = SyncActor()
    private var session: EntertainmentSession?
    private var sessionStateCancellable: AnyCancellable?

    /// The source the streaming loop reads each tick. Swap this to change auras mid-stream.
    private var activeSource: LightSource? = nil
    private var channelCount: Int = 1

    private var hasAutoStarted = false
    private var streamingTask: Task<Void, Never>?

    /// True when the current session was started solely for channel identification.
    /// Lets stopIdentify() know it owns the session and should tear it down.
    private var isIdentifySession: Bool = false

    /// Set by identify(channel:). The streaming loop reads this to pulse the light.
    private(set) var pulsedChannel: UInt8? = nil

    // MARK: - Public API

    /// Start or hot-swap to a palette-based aura.
    func startAura(_ aura: Aura) {
        activeAura = aura
        activeSource = PaletteSource(aura: aura)
        UserDefaults.standard.set(SyncMode.aura.rawValue, forKey: "lastMode")
        if let data = try? JSONEncoder().encode(aura) {
            UserDefaults.standard.set(data, forKey: "lastAura")
        }
        if connectionStatus == .disconnected {
            startSession()
        }
    }

    /// Activate the entertainment session and send a static color to all lights.
    func startStaticColor(r: Float, g: Float, b: Float) {
        guard connectionStatus == .disconnected else { return }
        activeAura = nil
        activeSource = StaticColorSource(r: r, g: g, b: b)
        startSession()
    }

    /// Start or hot-swap to screen sync mode.
    func startScreenSync() {
        activeAura = nil
        activeSource = ScreenCaptureSource(config: zoneConfig, responsiveness: responsiveness)
        UserDefaults.standard.set(SyncMode.screen.rawValue, forKey: "lastMode")
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

    /// Pulse one channel white so the user can physically identify which light it is.
    /// If not currently streaming, starts a temporary session. If already streaming,
    /// the streaming loop overrides that channel's color in-place.
    /// Switching channels while identifying just swaps the source — no reconnect.
    func identify(channel: UInt8) {
        pulsedChannel = channel
        switch connectionStatus {
        case .disconnected:
            isIdentifySession = true
            activeSource = IdentifySource(channel: channel)
            startSession()
        case .streaming where isIdentifySession:
            activeSource = IdentifySource(channel: channel)
        default:
            break  // real session active — pulsedChannel override in streaming loop handles it
        }
    }

    /// Stop channel identification. If a temporary identify session was started, tears it down.
    func stopIdentify() {
        pulsedChannel = nil
        guard isIdentifySession else { return }
        isIdentifySession = false
        stop()
    }

    /// Stop the entertainment session.
    func stop() {
        isIdentifySession = false
        streamingTask?.cancel()
        streamingTask = nil
        session?.stop()
        activeSource = nil
        activeAura = nil
    }

    // MARK: - Private

    private func autoStartIfNeeded() {
        guard !hasAutoStarted else { return }
        hasAutoStarted = true
        guard UserDefaults.standard.bool(forKey: "autoStartOnLaunch") else { return }
        guard resumeLastSession() else {
            // First launch — no saved session. Start with Disco.
            startAura(BuiltinAuras.disco)
            return
        }
    }

    /// Resumes the last mode from UserDefaults. Returns true if a session was started.
    @discardableResult
    private func resumeLastSession() -> Bool {
        let mode = UserDefaults.standard.string(forKey: "lastMode").flatMap(SyncMode.init)
        if mode == .screen {
            selectedMode = .screen
            startScreenSync()
            return true
        } else if mode == .aura,
                  let data = UserDefaults.standard.data(forKey: "lastAura"),
                  let aura = try? JSONDecoder().decode(Aura.self, from: data) {
            selectedMode = .aura
            startAura(aura)
            return true
        }
        return false
    }

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
            streamingTask?.cancel()
            streamingTask = nil
            if let errorMessage = session?.lastError {
                connectionStatus = .error(errorMessage)
            } else {
                connectionStatus = .disconnected
            }
            isRunning = false
            activeAura = nil
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
            streamingTask?.cancel()
            streamingTask = Task { @MainActor [weak self] in
                guard let self else { return }
                var tick: UInt8 = 0
                while !Task.isCancelled && self.connectionStatus == .streaming {
                    let elapsed = Date.timeIntervalSinceReferenceDate - startTime
                    if let source = self.activeSource {
                        var colors = source.nextColors(channelCount: capturedChannelCount, at: elapsed * self.speedMultiplier)
                        if let ch = self.pulsedChannel,
                           let idx = colors.firstIndex(where: { $0.channel == ch }) {
                            let pulse = Float(0.5 + 0.5 * sin(elapsed * .pi))
                            colors[idx] = (channel: ch, r: pulse, g: pulse, b: pulse)
                        }
                        let scale = self.brightness
                        colors = colors.map { (channel: $0.channel, r: $0.r * scale, g: $0.g * scale, b: $0.b * scale) }
                        self.session?.sendColors(colors)
                        tick &+= 1
                        if tick % 4 == 0 {
                            self.previewColors = colors
                        }
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

// MARK: - Helpers

extension SyncController {
    private static func icon(for status: ConnectionStatus) -> String {
        switch status {
        case .disconnected: return "lightbulb"
        case .connecting:   return "lightbulb"
        case .streaming:    return "lightbulb.fill"
        case .error:        return "lightbulb.slash"
        }
    }
}

// MARK: - IdentifySource

/// Pulses a single channel white at 2 Hz; all other channels black.
/// Used by identify(channel:) to let users match channel numbers to physical lights.
private final class IdentifySource: LightSource {
    let channel: UInt8
    init(channel: UInt8) { self.channel = channel }

    func nextColors(channelCount: Int, at timestamp: TimeInterval) -> [(channel: UInt8, r: Float, g: Float, b: Float)] {
        let brightness = Float(0.5 + 0.5 * sin(timestamp * .pi))
        return (0..<channelCount).map { i in
            let ch = UInt8(i)
            let v = ch == channel ? brightness : 0
            return (channel: ch, r: v, g: v, b: v)
        }
    }
}
