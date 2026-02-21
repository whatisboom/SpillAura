import SwiftUI

/// Zone assignment UI: preset shortcuts, per-channel pickers, and a live preview.
/// Used in the setup wizard (SetupView) and the Settings reconfigure sheet.
struct ZoneSetupStep: View {
    let channelCount: Int
    @Binding var config: ZoneConfig
    var onIdentify: ((UInt8, ChannelColor) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // Preset shortcuts — hidden for single-channel setups
            if channelCount >= 2 {
                HStack(spacing: 8) {
                    Button("Sides") { applyPreset(.twoBar) }
                        .help("Assign left and right zones.")
                    if channelCount >= 3 {
                        Button("Top + Sides") { applyPreset(.threeBar) }
                            .help("Assign top, left, and right zones.")
                    }
                    if channelCount >= 4 {
                        Button("Surround") { applyPreset(.fourBar) }
                            .help("Assign top, right, bottom, and left zones.")
                    }
                }
                .buttonStyle(.bordered)
            }

            // Per-channel pickers with colored labels
            ForEach(config.zones.indices, id: \.self) { i in
                let channelColor = ChannelColor.color(for: i, of: channelCount)
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(channelColor.swiftUIColor)
                            .frame(width: 10, height: 10)
                        Text(channelColor.name)
                    }

                    Spacer()

                    Picker("", selection: $config.zones[i].region) {
                        ForEach(ScreenRegion.allCases) { region in
                            Text(region.label).tag(region)
                        }
                    }
                    .frame(maxWidth: 160)
                    .help("Which screen region this channel samples.")

                    if let onIdentify {
                        Button {
                            onIdentify(config.zones[i].channelID, channelColor)
                        } label: {
                            Image(systemName: "lightbulb.fill")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(channelColor.swiftUIColor)
                        .help("Light this channel in \(channelColor.name) to identify it.")
                    }
                }
            }

            // Zone preview
            ZonePreviewCanvas(zones: config.zones, showLabels: true)
                .frame(maxWidth: 400)
        }
    }

    private func applyPreset(_ preset: ZoneLayoutPreset) {
        let regions = preset.regions(for: config.zones.count)
        for i in config.zones.indices {
            config.zones[i].region = regions[i]
        }
    }
}
