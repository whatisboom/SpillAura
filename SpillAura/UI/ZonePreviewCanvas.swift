import SwiftUI

/// 16:9 zone preview canvas. Shows static region labels when `liveColors` is empty,
/// live channel colors when streaming.
struct ZonePreviewCanvas: View {
    let zones: [Zone]
    var liveColors: [(channel: UInt8, r: Float, g: Float, b: Float)] = []

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black

                ForEach(zones.indices, id: \.self) { i in
                    let zone = zones[i]
                    let channelColor = ChannelColor.color(for: i, of: zones.count)
                    let previewColor = liveColors.first(where: { $0.channel == zone.channelID })
                    let fill: Color = previewColor.map {
                        Color(red: Double($0.r), green: Double($0.g), blue: Double($0.b))
                    } ?? Color.secondary.opacity(0.25)

                    ZStack {
                        zone.region.previewPath(in: CGRect(origin: .zero, size: geo.size))
                            .fill(fill)

                        Group {
                            if previewColor != nil {
                                // Streaming: colored dot + region name
                                HStack(spacing: 3) {
                                    Circle()
                                        .fill(channelColor.swiftUIColor)
                                        .frame(width: 6, height: 6)
                                    Text(zone.region.label)
                                }
                            } else {
                                // Static: color name
                                Text(channelColor.name)
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .shadow(color: .black, radius: 1)
                        .position(
                            x: zone.region.centroid.x * geo.size.width,
                            y: zone.region.centroid.y * geo.size.height
                        )
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
        .help("Live preview of your screen zones. Colors update in real time while streaming.")
    }
}
