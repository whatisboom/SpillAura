import SwiftUI

struct SetupView: View {
    @StateObject private var discovery = HueBridgeDiscovery()
    @State private var auth = HueBridgeAuth()

    @State private var selectedBridgeIP: String = ""
    @State private var manualIP: String = ""
    @State private var pairingState: PairingState = .idle
    @State private var credentials: BridgeCredentials? = nil
    @State private var errorMessage: String? = nil

    @AppStorage(StorageKey.entertainmentGroupID)    private var storedGroupID: String = ""
    @AppStorage(StorageKey.entertainmentChannelCount) private var storedChannelCount: Int = 1
    @State private var zoneConfig: ZoneConfig = ZoneConfig.defaultConfig(channelCount: 1)
    @State private var setupComplete: Bool = false

    enum PairingState {
        case idle, waitingForButton, pairing, success, failed
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Connect to Hue Bridge")
                    .font(.title2)
                    .bold()

                // Step 1: Find bridge
                GroupBox("Find Your Bridge") {
                    VStack(alignment: .leading, spacing: 8) {
                        if discovery.isSearching {
                            HStack {
                                ProgressView().scaleEffect(UIConstants.ProgressScale.inline)
                                Text("Searching for bridges…")
                                    .foregroundStyle(.secondary)
                            }
                        }

                        ForEach(discovery.discoveredBridges) { bridge in
                            Button(action: { selectedBridgeIP = bridge.host }) {
                                HStack {
                                    Image(systemName: selectedBridgeIP == bridge.host ? "checkmark.circle.fill" : "circle")
                                    VStack(alignment: .leading) {
                                        Text(bridge.name).bold()
                                        Text(bridge.host).foregroundStyle(.secondary).font(.caption)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .help("Select this bridge to pair with. SpillAura will connect to this IP address.")
                        }

                        Divider()

                        HStack {
                            TextField("Manual IP (e.g. 192.168.1.100)", text: $manualIP)
                                .textFieldStyle(.roundedBorder)
                                .help("Enter your bridge IP manually if it wasn't found automatically.")
                            Button("Use") {
                                selectedBridgeIP = manualIP
                            }
                            .disabled(manualIP.isEmpty)
                        }

                        Button(discovery.isSearching ? "Searching…" : "Search Again") {
                            discovery.startDiscovery()
                        }
                        .disabled(discovery.isSearching)
                        .help("Search for nearby Hue bridges.")
                    }
                    .padding(4)
                }

                // Step 2: Pair
                GroupBox("Pair") {
                    VStack(alignment: .leading, spacing: 8) {
                        if selectedBridgeIP.isEmpty {
                            Text("Choose a bridge above to get started.")
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Bridge: \(selectedBridgeIP)")
                                .foregroundStyle(.secondary)

                            switch pairingState {
                            case .idle:
                                Button("Start Pairing") {
                                    pairingState = .waitingForButton
                                }
                                .help("Start the pairing process.")
                            case .waitingForButton:
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Press the physical button on your Hue bridge now, then tap Pair.")
                                    HStack {
                                        Button("Pair") {
                                            Task { await pairWithBridge() }
                                        }
                                        .help("Complete pairing.")
                                        Button("Cancel") { pairingState = .idle }
                                            .buttonStyle(.plain)
                                            .foregroundStyle(.secondary)
                                            .help("Cancel pairing and return to the idle state.")
                                    }
                                }
                            case .pairing:
                                HStack {
                                    ProgressView().scaleEffect(UIConstants.ProgressScale.inline)
                                    Text("Pairing…")
                                }
                            case .success:
                                if let creds = credentials {
                                    Label("Paired successfully!", systemImage: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                    Text("Connected to \(creds.bridgeIP)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            case .failed:
                                VStack(alignment: .leading, spacing: 4) {
                                    Label(errorMessage ?? "Pairing failed.", systemImage: "xmark.circle.fill")
                                        .foregroundStyle(.red)
                                    Button("Try Again") { pairingState = .idle }
                                }
                            }
                        }
                    }
                    .padding(4)
                }

                // Step 3: Select entertainment group (appears after pairing)
                if pairingState == .success, let creds = credentials {
                    GroupBox("Select Lighting Group") {
                        EntertainmentGroupPicker(credentials: creds, auth: auth)
                            .padding(4)
                    }
                }

                // Step 4: Configure zones (appears after group is selected)
                if pairingState == .success && !storedGroupID.isEmpty {
                    GroupBox("Configure Zones") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Match each channel to where its light bar sits relative to your monitor.")
                                .font(.callout)
                                .foregroundStyle(.secondary)

                            ZoneSetupStep(channelCount: storedChannelCount, config: $zoneConfig)

                            Button("Done") {
                                zoneConfig.save()
                                setupComplete = true
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(4)
                    }
                }

                if setupComplete {
                    Label("Setup complete — use the menu bar icon to control your lights.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.callout)
                }

                Spacer()
            }
            .padding(24)
        }
        .frame(minWidth: 420, maxWidth: 480, minHeight: 460)
        .onAppear {
            discovery.startDiscovery()
            if let creds = auth.loadFromKeychain() {
                credentials = creds
                selectedBridgeIP = creds.bridgeIP
                pairingState = .success
            }
        }
        .onChange(of: storedChannelCount) { _, newCount in
            if newCount > 0 {
                zoneConfig = ZoneConfig.defaultConfig(channelCount: newCount)
                setupComplete = false
            }
        }
        .onDisappear {
            discovery.stopDiscovery()
        }
    }

    private func pairWithBridge() async {
        pairingState = .pairing
        do {
            credentials = try await auth.pair(bridgeIP: selectedBridgeIP)
            pairingState = .success
        } catch let error as AuthError {
            errorMessage = error.errorDescription
            pairingState = .failed
        } catch {
            errorMessage = error.localizedDescription
            pairingState = .failed
        }
    }
}

struct EntertainmentGroupPicker: View {
    let credentials: BridgeCredentials
    let auth: HueBridgeAuth
    @State private var groups: [HueBridgeAuth.EntertainmentGroup] = []
    @State private var selectedGroupID: String? = nil
    @State private var isLoading = true
    @State private var errorMessage: String? = nil
    @AppStorage(StorageKey.entertainmentGroupID) private var storedGroupID: String = ""
    @AppStorage(StorageKey.entertainmentChannelCount) private var storedChannelCount: Int = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isLoading {
                HStack {
                    ProgressView().scaleEffect(UIConstants.ProgressScale.inline)
                    Text("Loading lighting groups…")
                        .foregroundStyle(.secondary)
                }
            } else if let error = errorMessage {
                Text(error).foregroundStyle(.red)
            } else if groups.isEmpty {
                Text("No lighting groups found. Set one up in the Hue app first.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(groups) { group in
                    Button(action: {
                        selectedGroupID = group.id
                        storedGroupID = group.id
                        storedChannelCount = group.channelCount
                    }) {
                        HStack {
                            Image(systemName: selectedGroupID == group.id ? "checkmark.circle.fill" : "circle")
                            VStack(alignment: .leading) {
                                Text(group.name).bold()
                                Text("\(group.channelCount) channels")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Select this lighting group to control these channels.")
                }
            }
        }
        .task {
            do {
                groups = try await auth.fetchEntertainmentGroups(credentials: credentials)
                selectedGroupID = storedGroupID.isEmpty ? groups.first?.id : storedGroupID
                if let first = groups.first, storedGroupID.isEmpty {
                    storedGroupID = first.id
                    storedChannelCount = first.channelCount
                }
                isLoading = false
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
}
