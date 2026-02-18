import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var syncController: SyncController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 12) {
            Text("SpillAura")
                .font(.headline)

            Divider()

            // Connection status
            statusRow

            Divider()

            // M2 test controls
            HStack(spacing: 8) {
                Button("Send Red") {
                    syncController.startStaticColor(r: 1.0, g: 0.0, b: 0.0)
                }
                .disabled(syncController.connectionStatus != .disconnected)

                Button("Stop") {
                    syncController.stop()
                }
                .disabled(syncController.connectionStatus == .disconnected)
            }

            Divider()

            Button("Open Settings") {
                openWindow(id: "main")
            }
        }
        .padding()
        .frame(width: 260)
    }

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
