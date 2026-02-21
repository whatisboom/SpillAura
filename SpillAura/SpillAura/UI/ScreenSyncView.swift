import SwiftUI
import ScreenCaptureKit
import AppKit

/// Configuration + live preview for Screen Sync mode.
/// Lives in the Screen Sync tab of the main window.
struct ScreenSyncView: View {
    @EnvironmentObject var syncController: SyncController

    /// Populated on appear from SCShareableContent. Only shown if > 1 display.
    @State private var availableDisplays: [(id: UInt32, name: String)] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Screen Sync")
                .font(.title2)
                .fontWeight(.semibold)

            // Source Display — only visible with multiple monitors
            if availableDisplays.count > 1 {
                LabeledContent("Source Display") {
                    Picker("", selection: Binding(
                        get: { syncController.zoneConfig.displayID },
                        set: { newVal in
                            syncController.zoneConfig.displayID = newVal
                            syncController.saveZoneConfig()
                        }
                    )) {
                        ForEach(availableDisplays, id: \.id) { d in
                            Text(d.name).tag(d.id)
                        }
                    }
                    .frame(maxWidth: 200)
                }
            }

            // Zone assignment — one row per channel
            VStack(spacing: 6) {
                ForEach(syncController.zoneConfig.zones.indices, id: \.self) { i in
                    LabeledContent("Channel \(syncController.zoneConfig.zones[i].channelID)") {
                        Picker("", selection: Binding(
                            get: { syncController.zoneConfig.zones[i].region },
                            set: { newVal in
                                syncController.zoneConfig.zones[i].region = newVal
                                syncController.saveZoneConfig()
                            }
                        )) {
                            ForEach(ScreenRegion.allCases) { region in
                                Text(region.label).tag(region)
                            }
                        }
                        .frame(maxWidth: 160)
                    }
                }
            }

            // Live preview canvas
            GeometryReader { geo in
                ZStack {
                    Color.black

                    ForEach(syncController.zoneConfig.zones.indices, id: \.self) { i in
                        let zone = syncController.zoneConfig.zones[i]
                        let rect = zone.region.rect
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
                        let label = isStreaming
                            ? "Ch \(zone.channelID)"
                            : zone.region.label

                        ZStack {
                            Rectangle()
                                .fill(fill)
                                .frame(
                                    width:  rect.width  * geo.size.width,
                                    height: rect.height * geo.size.height
                                )
                                .position(
                                    x: rect.midX * geo.size.width,
                                    y: rect.midY * geo.size.height
                                )

                            Text(label)
                                .font(.caption2)
                                .foregroundStyle(.white)
                                .shadow(color: .black, radius: 1)
                                .position(
                                    x: rect.midX * geo.size.width,
                                    y: rect.midY * geo.size.height
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
            .frame(maxWidth: 480)

            if syncController.connectionStatus != .streaming {
                Text("Start Screen Sync from the MenuBar to see live colors.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(minWidth: 440, minHeight: 320)
        .task { await loadDisplays() }
    }

    private func loadDisplays() async {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: false
        ) else { return }

        let displays: [(id: UInt32, name: String)] = content.displays.map { display in
            let name = NSScreen.screens.first(where: {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32)
                    == UInt32(display.displayID)
            })?.localizedName ?? "Display \(display.displayID)"
            return (id: UInt32(display.displayID), name: name)
        }

        await MainActor.run { availableDisplays = displays }
    }
}
