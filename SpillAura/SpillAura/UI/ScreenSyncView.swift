import SwiftUI

/// Shows a live preview of per-zone colors while Screen Sync is streaming.
/// Zones are rendered as equal vertical strips matching the current ZoneConfig.
struct ScreenSyncView: View {
    @EnvironmentObject var syncController: SyncController

    var body: some View {
        VStack(spacing: 20) {
            Text("Screen Sync")
                .font(.title2)
                .fontWeight(.semibold)

            let channelCount = max(1, UserDefaults.standard.integer(forKey: "entertainmentChannelCount"))
            let zones = ZoneConfig.load(channelCount: channelCount).zones

            // 16:9 preview rectangle, each zone as a colored strip
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(Array(zones.enumerated()), id: \.offset) { _, zone in
                        let color = syncController.previewColors
                            .first(where: { $0.channel == zone.channelID })
                        ZStack {
                            Rectangle()
                                .fill(Color(
                                    red:   Double(color?.r ?? 0),
                                    green: Double(color?.g ?? 0),
                                    blue:  Double(color?.b ?? 0)
                                ))
                                .animation(.linear(duration: 0.05), value: color?.r)

                            Text("Ch \(zone.channelID)")
                                .font(.caption2)
                                .foregroundStyle(.white)
                                .shadow(color: .black, radius: 1)
                        }
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .frame(maxWidth: 480)

            if syncController.connectionStatus != .streaming {
                Text("Start Screen Sync from the MenuBar to see live colors.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Text("Drag-to-assign zone layout coming in M5.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .frame(minWidth: 400, minHeight: 280)
    }
}
