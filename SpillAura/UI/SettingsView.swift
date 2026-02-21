import SwiftUI
import ServiceManagement
import ScreenCaptureKit

struct SettingsView: View {
    @EnvironmentObject var syncController: SyncController
    @State private var auth = HueBridgeAuth()
    @State private var credentials: BridgeCredentials? = nil
    @State private var showPairingFlow: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Settings")
                    .font(.title2)
                    .fontWeight(.semibold)

                // MARK: Bridge
                GroupBox("Bridge") {
                    VStack(alignment: .leading, spacing: 12) {
                        if let creds = credentials, !showPairingFlow {
                            HStack {
                                Label(creds.bridgeIP, systemImage: "network")
                                Spacer()
                                Button("Re-pair") { showPairingFlow = true }
                                    .buttonStyle(.borderless)
                            }
                            Divider()
                            EntertainmentGroupPicker(credentials: creds, auth: auth)
                        } else {
                            BridgePairingSection(
                                onPaired: { newCreds in
                                    credentials = newCreds
                                    showPairingFlow = false
                                },
                                onCancel: credentials != nil ? { showPairingFlow = false } : nil
                            )
                        }
                    }
                    .padding(4)
                }

                // MARK: Screen Sync
                ScreenSyncSettingsSection()

                // MARK: App
                GroupBox("App") {
                    VStack(alignment: .leading, spacing: 8) {
                        LoginItemRow()
                        Divider()
                        AutoStartRow()
                        LaunchHiddenRow()
                    }
                    .padding(4)
                }
            }
            .padding(24)
        }
        .frame(minWidth: 420, maxWidth: 420, minHeight: 400)
        .onAppear { credentials = auth.loadFromKeychain() }
    }
}

// MARK: - ScreenSyncSettingsSection

private struct ScreenSyncSettingsSection: View {
    @EnvironmentObject var syncController: SyncController
    @State private var availableDisplays: [(id: UInt32, name: String)] = []
    @State private var pulseTask: Task<Void, Never>?

    var body: some View {
        GroupBox("Screen Sync") {
            VStack(alignment: .leading, spacing: 12) {

                // Display picker — only visible with multiple monitors
                if availableDisplays.count > 1 {
                    LabeledContent("Source Display") {
                        Picker("", selection: Binding(
                            get: { syncController.zoneConfig.displayID },
                            set: { newVal in
                                syncController.zoneConfig.displayID = newVal
                                syncController.saveZoneConfig()
                            }
                        )) {
                            ForEach(availableDisplays, id: \.id) { d in
                                Text(d.name).tag(d.id)
                            }
                        }
                        .frame(maxWidth: 200)
                    }
                    Divider()
                }

                // Layout presets
                HStack(spacing: 8) {
                    Button("2-Bar (L/R)")    { applyPreset(.twoBar) }
                    Button("3-Bar (T/L/R)")  { applyPreset(.threeBar) }
                    Button("4-Bar Surround") { applyPreset(.fourBar) }
                }
                .buttonStyle(.bordered)

                // Zone pickers — one row per channel
                ForEach(syncController.zoneConfig.zones.indices, id: \.self) { i in
                    let channelID = syncController.zoneConfig.zones[i].channelID
                    LabeledContent("Channel \(channelID)") {
                        Picker("", selection: Binding(
                            get: { syncController.zoneConfig.zones[i].region },
                            set: { newVal in
                                syncController.zoneConfig.zones[i].region = newVal
                                syncController.saveZoneConfig()
                            }
                        )) {
                            ForEach(ScreenRegion.allCases) { region in
                                Text(region.label).tag(region)
                            }
                        }
                        .frame(maxWidth: 160)
                    }
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        if hovering {
                            startIdentify(channel: channelID)
                        } else {
                            stopIdentify()
                        }
                    }
                }

                Divider()

                // Zone Depth slider
                LabeledContent("Zone Depth") {
                    HStack {
                        Slider(
                            value: Binding(
                                get: { syncController.zoneConfig.depth },
                                set: { newVal in
                                    syncController.zoneConfig.depth = newVal
                                    syncController.saveZoneConfig()
                                }
                            ),
                            in: 0.05...0.50
                        )
                        .frame(maxWidth: 160)
                        Text("\(Int(syncController.zoneConfig.depth * 100))%")
                            .frame(width: 36, alignment: .trailing)
                            .monospacedDigit()
                    }
                }

                // Edge Weight slider
                LabeledContent("Edge Weight") {
                    HStack {
                        Slider(
                            value: Binding(
                                get: { syncController.zoneConfig.edgeWeight },
                                set: { newVal in
                                    syncController.zoneConfig.edgeWeight = newVal
                                    syncController.saveZoneConfig()
                                }
                            ),
                            in: 1.0...5.0
                        )
                        .frame(maxWidth: 160)
                        Text(String(format: "%.1f×", syncController.zoneConfig.edgeWeight))
                            .frame(width: 36, alignment: .trailing)
                            .monospacedDigit()
                    }
                }
            }
            .padding(4)
        }
        .task { await loadDisplays() }
    }

    private func applyPreset(_ preset: ZoneLayoutPreset) {
        let regions = preset.regions(for: syncController.zoneConfig.zones.count)
        for i in syncController.zoneConfig.zones.indices {
            syncController.zoneConfig.zones[i].region = regions[i]
        }
        syncController.saveZoneConfig()
    }

    private func startIdentify(channel: UInt8) {
        pulseTask?.cancel()
        syncController.identify(channel: channel)
        pulseTask = Task {
            try? await Task.sleep(for: .seconds(8))
            if !Task.isCancelled {
                stopIdentify()
            }
        }
    }

    private func stopIdentify() {
        pulseTask?.cancel()
        pulseTask = nil
        syncController.stopIdentify()
    }

    private func loadDisplays() async {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: false
        ) else { return }

        let displays: [(id: UInt32, name: String)] = content.displays.map { display in
            let name = NSScreen.screens.first(where: {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32)
                    == UInt32(display.displayID)
            })?.localizedName ?? "Display \(display.displayID)"
            return (id: UInt32(display.displayID), name: name)
        }
        await MainActor.run { availableDisplays = displays }
    }
}

// MARK: - ZoneLayoutPreset

private enum ZoneLayoutPreset {
    case twoBar, threeBar, fourBar

    func regions(for count: Int) -> [ScreenRegion] {
        let all: [ScreenRegion]
        switch self {
        case .twoBar:   all = [.leftTriangle, .rightTriangle]
        case .threeBar: all = [.topTriangle, .leftTriangle, .rightTriangle]
        case .fourBar:  all = [.topTriangle, .rightTriangle, .bottomTriangle, .leftTriangle]
        }
        return (0..<count).map { i in i < all.count ? all[i] : .fullScreen }
    }
}

// MARK: - BridgePairingSection

private struct BridgePairingSection: View {
    let onPaired: (BridgeCredentials) -> Void
    let onCancel: (() -> Void)?

    @StateObject private var discovery = HueBridgeDiscovery()
    @State private var auth = HueBridgeAuth()
    @State private var selectedIP: String = ""
    @State private var manualIP: String = ""
    @State private var pairingState: PairingState = .idle
    @State private var errorMessage: String? = nil

    enum PairingState { case idle, waitingForButton, pairing, success, failed }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if discovery.isSearching {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.7)
                    Text("Searching for bridges…")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            }

            ForEach(discovery.discoveredBridges) { bridge in
                Button {
                    selectedIP = bridge.host
                } label: {
                    HStack {
                        Image(systemName: selectedIP == bridge.host
                              ? "checkmark.circle.fill" : "circle")
                        VStack(alignment: .leading, spacing: 1) {
                            Text(bridge.name).font(.callout).fontWeight(.medium)
                            Text(bridge.host).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            HStack {
                TextField("Manual IP (e.g. 192.168.1.100)", text: $manualIP)
                    .textFieldStyle(.roundedBorder)
                Button("Use") { selectedIP = manualIP }
                    .disabled(manualIP.isEmpty)
            }

            Button(discovery.isSearching ? "Searching…" : "Search Again") {
                discovery.startDiscovery()
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .disabled(discovery.isSearching)

            Divider()

            switch pairingState {
            case .idle:
                HStack {
                    if !selectedIP.isEmpty {
                        Text(selectedIP).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let cancel = onCancel {
                        Button("Cancel", action: cancel)
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                    }
                    Button("Start Pairing") { pairingState = .waitingForButton }
                        .disabled(selectedIP.isEmpty)
                }

            case .waitingForButton:
                VStack(alignment: .leading, spacing: 8) {
                    Text("Press the button on your Hue bridge, then tap Pair.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Pair") { Task { await pair() } }
                        Button("Cancel") { pairingState = .idle }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                    }
                }

            case .pairing:
                HStack {
                    ProgressView().scaleEffect(0.7)
                    Text("Pairing…").font(.callout)
                }

            case .success:
                Label("Paired successfully!", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)

            case .failed:
                VStack(alignment: .leading, spacing: 4) {
                    Label(errorMessage ?? "Pairing failed.", systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                    Button("Try Again") { pairingState = .idle }
                }
            }
        }
        .onAppear {
            discovery.startDiscovery()
        }
        .onDisappear { discovery.stopDiscovery() }
    }

    private func pair() async {
        pairingState = .pairing
        do {
            let creds = try await auth.pair(bridgeIP: selectedIP)
            onPaired(creds)
        } catch let error as AuthError {
            errorMessage = error.errorDescription
            pairingState = .failed
        } catch {
            errorMessage = error.localizedDescription
            pairingState = .failed
        }
    }
}

// MARK: - AutoStartRow

private struct AutoStartRow: View {
    @AppStorage("autoStartOnLaunch") private var autoStartOnLaunch = false

    var body: some View {
        Toggle("Start streaming automatically on launch", isOn: $autoStartOnLaunch)
    }
}

// MARK: - LaunchHiddenRow

private struct LaunchHiddenRow: View {
    @AppStorage("launchWindowHidden") private var launchWindowHidden = false

    var body: some View {
        Toggle("Launch with window hidden", isOn: $launchWindowHidden)
    }
}

// MARK: - LoginItemRow

private struct LoginItemRow: View {
    @State private var isEnabled: Bool = false

    var body: some View {
        Toggle("Launch at login", isOn: $isEnabled)
            .onChange(of: isEnabled) { _, enabled in
                do {
                    if enabled {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    // Revert if registration fails (e.g., unsigned dev build)
                    isEnabled = !enabled
                }
            }
            .onAppear {
                isEnabled = SMAppService.mainApp.status == .enabled
            }
    }
}
