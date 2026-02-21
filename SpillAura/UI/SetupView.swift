import SwiftUI

struct SetupView: View {
    @StateObject private var discovery = HueBridgeDiscovery()
    @State private var auth = HueBridgeAuth()

    @State private var selectedBridgeIP: String = ""
    @State private var manualIP: String = ""
    @State private var pairingState: PairingState = .idle
    @State private var credentials: BridgeCredentials? = nil
    @State private var errorMessage: String? = nil

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
                GroupBox("Step 1: Find Your Bridge") {
                    VStack(alignment: .leading, spacing: 8) {
                        if discovery.isSearching {
                            HStack {
                                ProgressView().scaleEffect(0.7)
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
                        }

                        Divider()

                        HStack {
                            TextField("Manual IP (e.g. 192.168.1.100)", text: $manualIP)
                                .textFieldStyle(.roundedBorder)
                                .help("Enter the bridge IP address manually if it wasn't found by discovery")
                            Button("Use") {
                                selectedBridgeIP = manualIP
                            }
                            .disabled(manualIP.isEmpty)
                            .help("Use this IP address as the bridge address")
                        }

                        Button(discovery.isSearching ? "Searching…" : "Search Again") {
                            discovery.startDiscovery()
                        }
                        .disabled(discovery.isSearching)
                        .help("Scan the local network for Hue bridges via mDNS")
                    }
                    .padding(4)
                }

                // Step 2: Pair
                GroupBox("Step 2: Pair") {
                    VStack(alignment: .leading, spacing: 8) {
                        if selectedBridgeIP.isEmpty {
                            Text("Select a bridge above first.")
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Bridge: \(selectedBridgeIP)")
                                .foregroundStyle(.secondary)

                            switch pairingState {
                            case .idle:
                                Button("Start Pairing") {
                                    pairingState = .waitingForButton
                                }
                                .help("Begin the pairing process — you'll be prompted to press the button on your bridge")
                            case .waitingForButton:
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Press the physical button on your Hue bridge now, then tap Pair.")
                                    HStack {
                                        Button("Pair") {
                                            Task { await pairWithBridge() }
                                        }
                                        .help("Complete pairing with the bridge")
                                        Button("Cancel") { pairingState = .idle }
                                            .buttonStyle(.plain)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            case .pairing:
                                HStack {
                                    ProgressView().scaleEffect(0.7)
                                    Text("Pairing…")
                                }
                            case .success:
                                if let creds = credentials {
                                    Label("Paired successfully!", systemImage: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                    Text("Username: \(creds.username.prefix(12))…")
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
                    GroupBox("Step 3: Select Entertainment Group") {
                        EntertainmentGroupPicker(credentials: creds, auth: auth)
                            .padding(4)
                    }

                    Label("Setup complete — use the menu bar icon to control your lights.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.callout)
                }

                Spacer()
            }
            .padding(24)
        }
        .frame(width: 480, height: 520)
        .onAppear {
            discovery.startDiscovery()
            if let creds = auth.loadFromKeychain() {
                credentials = creds
                selectedBridgeIP = creds.bridgeIP
                pairingState = .success
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
    @AppStorage("entertainmentGroupID") private var storedGroupID: String = ""
    @AppStorage("entertainmentChannelCount") private var storedChannelCount: Int = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isLoading {
                HStack {
                    ProgressView().scaleEffect(0.7)
                    Text("Fetching entertainment groups…")
                        .foregroundStyle(.secondary)
                }
            } else if let error = errorMessage {
                Text(error).foregroundStyle(.red)
            } else if groups.isEmpty {
                Text("No entertainment groups found. Create one in the Hue app.")
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
                                Text("\(group.channelCount) channels · ID: \(group.id.prefix(8))…")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
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
