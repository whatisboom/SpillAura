import SwiftUI
import SpillAuraCore

struct MenuBarView: View {
    @EnvironmentObject var syncController: SyncController
    @EnvironmentObject var auraLibrary: AuraLibrary
    @Environment(\.openWindow) private var openWindow

    @State private var selectedAuraID: Aura.ID? = nil

    var body: some View {
        VStack(spacing: 12) {
            Text("SpillAura")
                .font(.headline)

            Divider()

            statusRow

            Divider()

            // Mode tabs
            Picker("", selection: $syncController.selectedMode) {
                ForEach(SyncMode.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .help("Switch between Aura mode (animated color cycles) and Screen Sync (mirrors your display content in real time).")
            .onChange(of: syncController.selectedMode) { _, newMode in
                guard syncController.connectionStatus == .streaming else { return }
                switch newMode {
                case .aura:
                    let aura = selectedAuraID.flatMap { id in auraLibrary.auras.first(where: { $0.id == id }) }
                             ?? auraLibrary.auras.first
                    if let aura { syncController.startAura(aura) }
                case .screen:
                    syncController.startScreenSync()
                }
            }

            switch syncController.selectedMode {
            case .aura:   auraControls
            case .screen: screenControls
            }

            Divider()

            HStack(spacing: 6) {
                Image(systemName: "sun.min")
                    .foregroundStyle(.secondary)
                Slider(value: $syncController.brightness, in: 0...1)
                    .help("Master brightness for all lights.")
                Image(systemName: "sun.max")
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "settings")
                } label: {
                    Image(systemName: "gear").imageScale(.large)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Open Settings to configure your bridge, screen zones, and launch behavior.")

                Spacer()

                Button("Open") {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "main")
                }
                    .help("Open the main window to browse auras, preview screen zones, and access full controls.")
            }
        }
        .padding()
        .frame(width: 260)
    }

    // MARK: - Aura Controls

    @ViewBuilder
    private var auraControls: some View {
        VStack(spacing: 8) {
            Picker("Aura", selection: $selectedAuraID) {
                ForEach(auraLibrary.auras) { aura in
                    Text(aura.name).tag(Optional(aura.id))
                }
            }
            .pickerStyle(.menu)
            .disabled(auraLibrary.auras.isEmpty)
            .help("Choose a color animation to stream. You can swap auras while streaming — no need to stop.")
            .onAppear {
                selectedAuraID = syncController.activeAura?.id ?? auraLibrary.auras.first?.id
            }
            .onChange(of: selectedAuraID) { _, id in
                guard let id,
                      let aura = auraLibrary.auras.first(where: { $0.id == id }) else { return }
                if syncController.connectionStatus == .streaming {
                    syncController.startAura(aura)
                }
            }
            .onChange(of: syncController.activeAura?.id) { _, id in
                selectedAuraID = id
            }

            HStack(spacing: 6) {
                Image(systemName: "tortoise").foregroundStyle(.secondary)
                Slider(value: $syncController.speedMultiplier, in: 0.25...1.5)
                    .help("How fast the color animation cycles. Slower is ambient; faster is energetic.")
                Image(systemName: "hare").foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button("Start") {
                    guard let id = selectedAuraID,
                          let aura = auraLibrary.auras.first(where: { $0.id == id })
                                  ?? auraLibrary.auras.first else { return }
                    syncController.startAura(aura)
                }
                .buttonStyle(.borderedProminent)
                .disabled(syncController.connectionStatus != .disconnected || auraLibrary.auras.isEmpty)
                .help("Begin streaming the selected aura. Your lights will start animating immediately.")

                Button("Stop") { syncController.stop() }
                    .buttonStyle(.bordered)
                    .disabled(syncController.connectionStatus == .disconnected)
                    .help("Stop streaming. Your lights will return to their previous state.")
            }
        }
    }

    // MARK: - Screen Controls

    @ViewBuilder
    private var screenControls: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Responsiveness")
                Spacer()
                Picker("", selection: $syncController.responsiveness) {
                    ForEach(SyncResponsiveness.allCases) { preset in
                        Text(preset.label).tag(preset)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
                .help("How quickly lights react to screen changes. Instant is best for gaming and fast content; Cinematic gives smooth, lag-tolerant transitions.")
            }

            HStack(spacing: 8) {
                Button("Start") { syncController.startScreenSync() }
                    .buttonStyle(.borderedProminent)
                    .disabled(syncController.connectionStatus != .disconnected)
                    .help("Start capturing your display and matching your lights to on-screen colors.")

                Button("Stop") { syncController.stop() }
                    .buttonStyle(.bordered)
                    .disabled(syncController.connectionStatus == .disconnected)
                    .help("Stop streaming. Your lights will return to their previous state.")
            }
        }
    }

    // MARK: - Status Row

    @ViewBuilder
    private var statusRow: some View {
        switch syncController.connectionStatus {
        case .disconnected:
            Label("Disconnected", systemImage: "circle")
                .foregroundStyle(.secondary)
                .font(.caption)
                .help("Not connected — press Start to begin streaming.")

        case .connecting:
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.6)
                Text("Connecting…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .help("Connecting to your Hue bridge…")

        case .streaming:
            Label("Streaming", systemImage: "circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
                .help("Streaming to your lights.")

        case .error(let message):
            Label(message, systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .font(.caption)
                .lineLimit(3)
                .help("An error occurred. Check your bridge connection and try again.")
        }
    }
}
