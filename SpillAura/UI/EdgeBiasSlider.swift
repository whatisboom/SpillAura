import SwiftUI

/// Reusable Edge Bias slider with Uniform/Edge labels.
struct EdgeBiasSlider: View {
    @EnvironmentObject var syncController: SyncController

    var body: some View {
        HStack {
            Text("Edge Bias")
            Spacer()
            HStack(spacing: UIConstants.Spacing.iconSliderGap) {
                Text("Uniform").font(.caption).foregroundStyle(.secondary)
                Slider(
                    value: Binding(
                        get: { syncController.zoneConfig.edgeBias },
                        set: { newVal in
                            syncController.zoneConfig.edgeBias = newVal
                            syncController.saveZoneConfig()
                        }
                    ),
                    in: 0...1
                )
                .frame(maxWidth: UIConstants.Size.edgeBiasSliderMaxWidth)
                .help("Uniform: all pixels in the zone contribute equally. Edge: pixels at the screen edge — where your light bar sits — are weighted more heavily.")
                Text("Edge").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
