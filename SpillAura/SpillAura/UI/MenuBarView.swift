import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var syncController: SyncController
    @EnvironmentObject var vibeLibrary: VibeLibrary
    @Environment(\.openWindow) private var openWindow

    @State private var vibeIndex: Int = 0

    var body: some View {
        VStack(spacing: 12) {
            Text("SpillAura")
                .font(.headline)

            Divider()

            statusRow

            Divider()

            vibePicker

            Divider()

            Button("Open Settings") {
                openWindow(id: "main")
            }
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

                Button("Stop") {
                    syncController.stop()
                }
                .disabled(syncController.connectionStatus == .disconnected)
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
