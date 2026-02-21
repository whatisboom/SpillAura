import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var syncController: SyncController
    @EnvironmentObject var vibeLibrary: VibeLibrary
    @Environment(\.openWindow) private var openWindow

    @State private var vibeIndex: Int = 0
    @State private var mode: Mode = .vibe

    private enum Mode: String, CaseIterable {
        case vibe = "Vibe"
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
            .onChange(of: mode) { _, _ in
                // Switching mode while streaming stops the session
                if syncController.connectionStatus != .disconnected {
                    syncController.stop()
                }
            }

            switch mode {
            case .vibe:   vibePicker
            case .screen: screenControls
            }

            Divider()

            HStack(spacing: 6) {
                Image(systemName: "sun.min")
                    .foregroundStyle(.secondary)
                Slider(value: $syncController.brightness, in: 0...1)
                Image(systemName: "sun.max")
                    .foregroundStyle(.secondary)
            }

            Divider()

            Button("Open Settings") { openWindow(id: "main") }
        }
        .padding()
        .frame(width: 260)
    }

    // MARK: - Vibe Picker

    @ViewBuilder
    private var vibePicker: some View {
        VStack(spacing: 8) {
            HStack {
                Button {
                    vibeIndex = (vibeIndex - 1 + vibeLibrary.vibes.count) % max(vibeLibrary.vibes.count, 1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(vibeLibrary.vibes.count < 2)

                Spacer()

                Text(vibeLibrary.vibes.isEmpty ? "No Vibes" : vibeLibrary.vibes[vibeIndex].name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Spacer()

                Button {
                    vibeIndex = (vibeIndex + 1) % max(vibeLibrary.vibes.count, 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(vibeLibrary.vibes.count < 2)
            }
            .onChange(of: vibeIndex) { _, newIndex in
                if syncController.connectionStatus == .streaming, !vibeLibrary.vibes.isEmpty {
                    syncController.startVibe(vibeLibrary.vibes[newIndex])
                }
            }

            HStack(spacing: 8) {
                Button("Start") {
                    guard !vibeLibrary.vibes.isEmpty else { return }
                    syncController.startVibe(vibeLibrary.vibes[vibeIndex])
                }
                .disabled(syncController.connectionStatus != .disconnected || vibeLibrary.vibes.isEmpty)

                Button("Stop") { syncController.stop() }
                    .disabled(syncController.connectionStatus == .disconnected)
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

            HStack(spacing: 8) {
                Button("Start") { syncController.startScreenSync() }
                    .disabled(syncController.connectionStatus != .disconnected)

                Button("Stop") { syncController.stop() }
                    .disabled(syncController.connectionStatus == .disconnected)
            }
        }
        .onChange(of: syncController.responsiveness) { _, _ in
            if syncController.connectionStatus == .streaming {
                syncController.startScreenSync()
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
