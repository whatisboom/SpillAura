import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var syncController: SyncController
    @EnvironmentObject var auraLibrary: AuraLibrary
    @Environment(\.openWindow) private var openWindow

    @State private var auraIndex: Int = 0
    @AppStorage("selectedMode") private var mode: Mode = .aura

    private enum Mode: String, CaseIterable {
        case aura = "Aura"
        case screen = "Screen"
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("SpillAura")
                .font(.headline)

            Divider()

            statusRow

            Divider()

            // Mode tabs
            Picker("", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .help("Aura: animated color cycles. Screen: match your display content.")
            .onChange(of: mode) { _, _ in
                // Switching mode while streaming stops the session
                if syncController.connectionStatus != .disconnected {
                    syncController.stop()
                }
            }

            switch mode {
            case .aura:   auraPicker
            case .screen: screenControls
            }

            Divider()

            HStack(spacing: 6) {
                Image(systemName: "sun.min")
                    .foregroundStyle(.secondary)
                Slider(value: $syncController.brightness, in: 0...1)
                    .help("Overall brightness of all lights")
                Image(systemName: "sun.max")
                    .foregroundStyle(.secondary)
            }

            Divider()

            Button("Open") { openWindow(id: "main") }
                .help("Open the main SpillAura window")
        }
        .padding()
        .frame(width: 260)
    }

    // MARK: - Aura Picker

    @ViewBuilder
    private var auraPicker: some View {
        VStack(spacing: 8) {
            HStack {
                Button {
                    auraIndex = (auraIndex - 1 + auraLibrary.auras.count) % max(auraLibrary.auras.count, 1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(auraLibrary.auras.count < 2)
                .help("Previous aura")

                Spacer()

                Text(auraLibrary.auras.isEmpty ? "No Auras" : auraLibrary.auras[auraIndex].name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Spacer()

                Button {
                    auraIndex = (auraIndex + 1) % max(auraLibrary.auras.count, 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(auraLibrary.auras.count < 2)
                .help("Next aura")
            }
            .onChange(of: auraIndex) { _, newIndex in
                if syncController.connectionStatus == .streaming, !auraLibrary.auras.isEmpty {
                    syncController.startAura(auraLibrary.auras[newIndex])
                }
            }
            .onChange(of: syncController.activeAura?.id) { _, newID in
                guard let newID,
                      let idx = auraLibrary.auras.firstIndex(where: { $0.id == newID }) else { return }
                auraIndex = idx
            }

            HStack(spacing: 8) {
                Button("Start") {
                    guard !auraLibrary.auras.isEmpty else { return }
                    syncController.startAura(auraLibrary.auras[auraIndex])
                }
                .disabled(syncController.connectionStatus != .disconnected || auraLibrary.auras.isEmpty)
                .help("Stream the selected aura to your Hue lights")

                Button("Stop") { syncController.stop() }
                    .disabled(syncController.connectionStatus == .disconnected)
                    .help("Stop the active streaming session")
            }
        }
    }

    // MARK: - Screen Controls

    @ViewBuilder
    private var screenControls: some View {
        VStack(spacing: 8) {
            Picker("", selection: $syncController.responsiveness) {
                ForEach(SyncResponsiveness.allCases) { preset in
                    Text(preset.label).tag(preset)
                }
            }
            .pickerStyle(.segmented)
            .help("How quickly the lights react to screen changes. Instant tracks fast motion; Cinematic gives smooth transitions.")

            HStack(spacing: 8) {
                Button("Start") { syncController.startScreenSync() }
                    .disabled(syncController.connectionStatus != .disconnected)
                    .help("Stream screen colors to your Hue lights")

                Button("Stop") { syncController.stop() }
                    .disabled(syncController.connectionStatus == .disconnected)
                    .help("Stop the active streaming session")
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

        case .connecting:
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.6)
                Text("Connecting…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .streaming:
            Label("Streaming", systemImage: "circle.fill")
                .foregroundStyle(.green)
                .font(.caption)

        case .error(let message):
            Label(message, systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .font(.caption)
                .lineLimit(3)
        }
    }
}
