import SwiftUI
import ServiceManagement

struct SettingsView: View {
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
