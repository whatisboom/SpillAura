import SwiftUI

/// Unified connection status indicator used in MainWindow and MenuBarView.
struct StatusBadge: View {
    let status: SyncController.ConnectionStatus

    var body: some View {
        switch status {
        case .disconnected:
            Label("Disconnected", systemImage: "circle")
                .foregroundStyle(.secondary)
                .font(.caption)
                .help("Not connected — press Start to begin streaming.")

        case .connecting:
            HStack(spacing: UIConstants.Spacing.iconSliderGap) {
                ProgressView().scaleEffect(UIConstants.ProgressScale.inline)
                Text("Connecting…").font(.caption).foregroundStyle(.secondary)
            }
            .help("Connecting to your Hue bridge…")

        case .streaming:
            Label("Streaming", systemImage: "circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
                .help("Streaming to your lights.")

        case .error(let msg):
            Label(msg, systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .font(.caption)
                .lineLimit(UIConstants.LineLimit.statusBadge)
                .help("An error occurred. Check your bridge connection and try again.")
        }
    }
}
