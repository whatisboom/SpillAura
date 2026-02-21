import SwiftUI

/// Live preview and responsiveness control for Screen Sync mode.
/// Zone and display configuration has moved to Settings → Screen Sync.
struct ScreenSyncView: View {
    @EnvironmentObject var syncController: SyncController

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Screen Sync")
                .font(.title2)
                .fontWeight(.semibold)

            // Responsiveness
            LabeledContent("Responsiveness") {
                Picker("", selection: $syncController.responsiveness) {
                    ForEach(SyncResponsiveness.allCases) { preset in
                        Text(preset.label).tag(preset)
                    }
                }
                .pickerStyle(.menu)
                .help("How quickly lights react to screen changes. Instant is best for gaming; Cinematic gives smooth, lag-tolerant transitions.")
            }

            // Live preview canvas
            ZonePreviewCanvas(
                zones: syncController.zoneConfig.zones,
                liveColors: syncController.connectionStatus == .streaming ? syncController.previewColors : []
            )
            .frame(maxWidth: 480)

            if syncController.connectionStatus != .streaming {
                Text("Start Screen Sync to see live colors.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(minWidth: 320, minHeight: 320)
    }
}
