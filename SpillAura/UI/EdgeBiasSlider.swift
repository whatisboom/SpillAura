import SwiftUI

/// Reusable Edge Bias slider with Uniform/Edge labels.
struct EdgeBiasSlider: View {
    @EnvironmentObject var syncController: SyncController
    @State private var edgeBiasDebounceTask: Task<Void, Never>?

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
                            edgeBiasDebounceTask?.cancel()
                            let value = newVal
                            edgeBiasDebounceTask = Task {
                                try? await Task.sleep(for: .milliseconds(500))
                                guard !Task.isCancelled else { return }
                                Analytics.send(.edgeBiasChanged(value: value))
                            }
                        }
                    ),
                    in: 0...1
                )
                .frame(maxWidth: UIConstants.Size.edgeBiasSliderMaxWidth)
                .help("Uniform: all pixels in the zone contribute equally. Edge: pixels at the screen edge — where your light bar sits — are weighted more heavily.")
                .accessibilityLabel("Edge bias")
                Text("Edge").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
