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
                .onChange(of: syncController.responsiveness) { _, _ in
                    if syncController.connectionStatus == .streaming {
                        syncController.startScreenSync()
                    }
                }
            }

            // Live preview canvas
            GeometryReader { geo in
                ZStack {
                    Color.black

                    ForEach(syncController.zoneConfig.zones.indices, id: \.self) { i in
                        let zone = syncController.zoneConfig.zones[i]
                        let isStreaming = syncController.connectionStatus == .streaming
                        let previewColor = syncController.previewColors
                            .first(where: { $0.channel == zone.channelID })
                        let fill: Color = isStreaming
                            ? Color(
                                red:   Double(previewColor?.r ?? 0),
                                green: Double(previewColor?.g ?? 0),
                                blue:  Double(previewColor?.b ?? 0)
                              )
                            : Color.secondary.opacity(0.25)
                        let label = isStreaming ? "Ch \(zone.channelID)" : zone.region.label
                        let c = zone.region.centroid

                        ZStack {
                            zone.region.previewPath(in: CGRect(origin: .zero, size: geo.size))
                                .fill(fill)
                            Text(label)
                                .font(.caption2)
                                .foregroundStyle(.white)
                                .shadow(color: .black, radius: 1)
                                .position(x: c.x * geo.size.width, y: c.y * geo.size.height)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .frame(maxWidth: 480)

            if syncController.connectionStatus != .streaming {
                Text("Start Screen Sync from the MenuBar to see live colors.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(minWidth: 320, minHeight: 320)
    }
}
