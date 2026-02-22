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
                                Button("Change Bridge") { showPairingFlow = true }
                                    .buttonStyle(.borderless)
                                    .help("Switch to a different bridge or reconnect to the current one. Your zone configuration will be preserved.")
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
    @State private var showingZoneSheet = false

    var body: some View {
        GroupBox("Screen Sync") {
            VStack(alignment: .leading, spacing: 12) {

                // Display picker — only visible with multiple monitors
                if availableDisplays.count > 1 {
                    HStack {
                        Text("Source Display")
                        Spacer()
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
                        .fixedSize()
                        .help("Which display SpillAura captures for Screen Sync.")
                    }
                    Divider()
                }

                // Zone layout
                HStack {
                    Text("Zone Layout")
                    Spacer()
                    Button("Reconfigure\u{2026}") { showingZoneSheet = true }
                        .buttonStyle(.bordered)
                }

                Divider()

                // Edge Bias slider
                EdgeBiasSlider()
            }
            .padding(4)
        }
        .task { await loadDisplays() }
        .sheet(isPresented: $showingZoneSheet) {
            ZoneReconfigureSheet()
                .environmentObject(syncController)
        }
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

// MARK: - ZoneReconfigureSheet

private struct ZoneReconfigureSheet: View {
    @EnvironmentObject var syncController: SyncController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Configure Zones")
                .font(.title2)
                .fontWeight(.semibold)

            ZoneSetupStep(
                channelCount: syncController.zoneConfig.zones.count,
                config: Binding(
                    get: { syncController.zoneConfig },
                    set: { syncController.zoneConfig = $0; syncController.saveZoneConfig() }
                ),
                onIdentify: { channel, color in
                    syncController.identify(channel: channel, color: color)
                }
            )

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(minWidth: 400)
        .onAppear { syncController.identifyAll() }
        .onDisappear { syncController.stopIdentify() }
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
                    ProgressView().scaleEffect(UIConstants.ProgressScale.inline)
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
                .help("Select this bridge to pair with. SpillAura will connect to this IP address.")
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
                    ProgressView().scaleEffect(UIConstants.ProgressScale.inline)
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
            .help("Automatically resume the last active mode when SpillAura launches — no need to press Start manually.")
    }
}

// MARK: - LaunchHiddenRow

private struct LaunchHiddenRow: View {
    @AppStorage("launchWindowHidden") private var launchWindowHidden = false

    var body: some View {
        Toggle("Launch with window hidden", isOn: $launchWindowHidden)
            .help("Launch SpillAura silently to the menu bar without showing the main window.")
    }
}

// MARK: - LoginItemRow

private struct LoginItemRow: View {
    @State private var isEnabled: Bool = false

    var body: some View {
        Toggle("Launch at login", isOn: $isEnabled)
            .help("Start SpillAura automatically when you log in, so it's always ready in the menu bar.")
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
