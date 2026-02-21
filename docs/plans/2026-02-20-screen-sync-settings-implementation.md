# Screen Sync Settings Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Move all screen sync configuration into the Settings window, add configurable zone depth and edge weight, and simplify the main window Screen Sync tab to a live preview + responsiveness control.

**Architecture:** `ZoneConfig` gains two new fields (`depth`, `edgeWeight`). `ScreenRegion.rect` becomes a method taking `depth`. `ScreenCaptureSource` reads both from config. All zone/display config UI moves to a new "Screen Sync" GroupBox in `SettingsView`. `ScreenSyncView` is stripped to canvas + responsiveness only.

**Tech Stack:** SwiftUI, ScreenCaptureKit, existing `ZoneConfig`/`SyncController`/`ScreenCaptureSource` infrastructure.

---

### Task 1: Extend ZoneConfig — add depth/edgeWeight, change rect to method

**Files:**
- Modify: `SpillAura/Config/ZoneConfig.swift`

**Step 1: Replace the file contents**

```swift
import Foundation
import CoreGraphics

enum ScreenRegion: String, CaseIterable, Codable, Identifiable {
    case leftEdge, rightEdge, topEdge, bottomEdge, center, fullScreen

    var id: String { rawValue }

    var label: String {
        switch self {
        case .leftEdge:   return "Left Edge"
        case .rightEdge:  return "Right Edge"
        case .topEdge:    return "Top Edge"
        case .bottomEdge: return "Bottom Edge"
        case .center:     return "Center"
        case .fullScreen: return "Full Screen"
        }
    }

    /// Normalized CGRect (0.0–1.0) for this region.
    /// `depth` controls the width/height of edge regions (0.05–0.50).
    /// `center` and `fullScreen` ignore depth.
    func rect(depth: Double) -> CGRect {
        switch self {
        case .leftEdge:   return CGRect(x: 0.0,         y: 0.0,         width: depth, height: 1.0)
        case .rightEdge:  return CGRect(x: 1.0 - depth, y: 0.0,         width: depth, height: 1.0)
        case .topEdge:    return CGRect(x: 0.0,         y: 0.0,         width: 1.0,   height: depth)
        case .bottomEdge: return CGRect(x: 0.0,         y: 1.0 - depth, width: 1.0,   height: depth)
        case .center:     return CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        case .fullScreen: return CGRect(x: 0.0,  y: 0.0,  width: 1.0, height: 1.0)
        }
    }
}

struct Zone: Codable {
    let channelID: UInt8
    var region: ScreenRegion
}

struct ZoneConfig: Codable {
    var displayID: UInt32   // 0 = CGMainDisplayID()
    var zones: [Zone]
    var depth: Double       // zone region depth, 0.05–0.50, default 0.20
    var edgeWeight: Double  // edge pixel weight vs center, 1.0–6.0, default 3.0

    init(displayID: UInt32, zones: [Zone], depth: Double = 0.20, edgeWeight: Double = 3.0) {
        self.displayID = displayID
        self.zones = zones
        self.depth = depth
        self.edgeWeight = edgeWeight
    }

    // Custom Codable init so old stored JSON (without depth/edgeWeight) still decodes correctly.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        displayID  = try c.decode(UInt32.self, forKey: .displayID)
        zones      = try c.decode([Zone].self,  forKey: .zones)
        depth      = try c.decodeIfPresent(Double.self, forKey: .depth)      ?? 0.20
        edgeWeight = try c.decodeIfPresent(Double.self, forKey: .edgeWeight) ?? 3.0
    }

    enum CodingKeys: String, CodingKey {
        case displayID, zones, depth, edgeWeight
    }

    /// Default: all channels sample Full Screen on the main display.
    static func defaultConfig(channelCount: Int) -> ZoneConfig {
        let zones = (0..<max(1, channelCount)).map { i in
            Zone(channelID: UInt8(i), region: .fullScreen)
        }
        return ZoneConfig(displayID: 0, zones: zones)
    }

    /// Load from UserDefaults; fall back to default if nothing saved.
    static func load(channelCount: Int) -> ZoneConfig {
        guard let data = UserDefaults.standard.data(forKey: "zoneConfig"),
              let config = try? JSONDecoder().decode(ZoneConfig.self, from: data),
              !config.zones.isEmpty else {
            return defaultConfig(channelCount: channelCount)
        }
        return config
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: "zoneConfig")
        }
    }
}
```

**Step 2: Build**

Run: `xcodebuild -project SpillAura.xcodeproj -scheme SpillAura -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"`

Expected: build errors referencing `zone.region.rect` (it was a property, now a method — callers need updating). That's expected; fix in next tasks.

**Step 3: Commit the data model change before touching callers**

```bash
git add SpillAura/Config/ZoneConfig.swift
git commit -m "feat: add depth and edgeWeight to ZoneConfig; rect becomes method"
```

---

### Task 2: Update ScreenCaptureSource to use config.depth and config.edgeWeight

**Files:**
- Modify: `SpillAura/LightSources/ScreenCaptureSource.swift`

Two changes needed in `extractColors(from:)`:
1. Zone rect: `zone.region.rect` → `zone.region.rect(depth: config.depth)`
2. Edge pixel weight: hardcoded `3.0` → `config.edgeWeight`

**Step 1: Fix the zone rect call**

Find:
```swift
        for (i, zone) in config.zones.enumerated() {
            let r = zone.region.rect
```

Replace with:
```swift
        for (i, zone) in config.zones.enumerated() {
            let r = zone.region.rect(depth: config.depth)
```

**Step 2: Fix the edge weight**

Find:
```swift
                    let w = isEdge ? 3.0 : 1.0
```

Replace with:
```swift
                    let w = isEdge ? config.edgeWeight : 1.0
```

**Step 3: Build**

Run: `xcodebuild -project SpillAura.xcodeproj -scheme SpillAura -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"`

Expected: `** BUILD SUCCEEDED **` (ScreenSyncView still references `zone.region.rect` — that's the remaining caller, fixed in Task 5).

Actually there may still be a build error from ScreenSyncView. Check the error output — if it's only `zone.region.rect` in `ScreenSyncView.swift`, proceed to commit and fix it in Task 5. If there are other errors, fix them now.

**Step 4: Commit**

```bash
git add SpillAura/LightSources/ScreenCaptureSource.swift
git commit -m "feat: use config.depth and config.edgeWeight in ScreenCaptureSource"
```

---

### Task 3: Inject syncController into Settings window

**Files:**
- Modify: `SpillAura/App/SpillAuraApp.swift`

`SettingsView` currently has no access to `SyncController`. The Screen Sync GroupBox needs it for zone config reads/writes and hover-to-identify.

**Step 1: Add environmentObject to the Settings window**

Find:
```swift
        Window("Settings", id: "settings") {
            SettingsView()
        }
        .windowResizability(.contentSize)
```

Replace with:
```swift
        Window("Settings", id: "settings") {
            SettingsView()
                .environmentObject(syncController)
        }
        .windowResizability(.contentSize)
```

**Step 2: Build**

Run: `xcodebuild -project SpillAura.xcodeproj -scheme SpillAura -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"`

Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add SpillAura/App/SpillAuraApp.swift
git commit -m "feat: inject syncController into Settings window environment"
```

---

### Task 4: Add Screen Sync GroupBox to SettingsView

**Files:**
- Modify: `SpillAura/UI/SettingsView.swift`

**Step 1: Add `import ScreenCaptureKit` at the top**

Find:
```swift
import SwiftUI
import ServiceManagement
```

Replace with:
```swift
import SwiftUI
import ServiceManagement
import ScreenCaptureKit
```

**Step 2: Add `@EnvironmentObject` and the Screen Sync GroupBox to `SettingsView`**

Find:
```swift
struct SettingsView: View {
    @State private var auth = HueBridgeAuth()
    @State private var credentials: BridgeCredentials? = nil
    @State private var showPairingFlow: Bool = false
```

Replace with:
```swift
struct SettingsView: View {
    @EnvironmentObject var syncController: SyncController
    @State private var auth = HueBridgeAuth()
    @State private var credentials: BridgeCredentials? = nil
    @State private var showPairingFlow: Bool = false
```

**Step 3: Insert the Screen Sync GroupBox between Bridge and App sections**

Find:
```swift
                // MARK: App
                GroupBox("App") {
```

Replace with:
```swift
                // MARK: Screen Sync
                ScreenSyncSettingsSection()

                // MARK: App
                GroupBox("App") {
```

**Step 4: Add the `ScreenSyncSettingsSection` private struct at the bottom of the file**

Append after the closing brace of `LaunchHiddenRow`:

```swift
// MARK: - ScreenSyncSettingsSection

private struct ScreenSyncSettingsSection: View {
    @EnvironmentObject var syncController: SyncController
    @State private var availableDisplays: [(id: UInt32, name: String)] = []
    @State private var pulseTask: Task<Void, Never>?

    var body: some View {
        GroupBox("Screen Sync") {
            VStack(alignment: .leading, spacing: 8) {
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
                    Divider()
                }

                ForEach(syncController.zoneConfig.zones.indices, id: \.self) { i in
                    let channelID = syncController.zoneConfig.zones[i].channelID
                    LabeledContent("Channel \(channelID)") {
                        Picker("", selection: Binding(
                            get: { syncController.zoneConfig.zones[i].region },
                            set: { newVal in
                                syncController.zoneConfig.zones[i].region = newVal
                                syncController.saveZoneConfig()
                                clearHighlight()
                            }
                        )) {
                            ForEach(ScreenRegion.allCases) { region in
                                Text(region.label).tag(region)
                            }
                        }
                        .frame(maxWidth: 160)
                    }
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        if hovering { startHighlight(channel: channelID) }
                    }
                }

                Divider()

                LabeledContent("Zone Depth") {
                    HStack {
                        Slider(value: Binding(
                            get: { syncController.zoneConfig.depth },
                            set: { newVal in
                                syncController.zoneConfig.depth = newVal
                                syncController.saveZoneConfig()
                            }
                        ), in: 0.05...0.50, step: 0.01)
                        Text("\(Int(syncController.zoneConfig.depth * 100))%")
                            .monospacedDigit()
                            .frame(width: 36, alignment: .trailing)
                    }
                    .frame(maxWidth: 220)
                }

                LabeledContent("Edge Weight") {
                    HStack {
                        Slider(value: Binding(
                            get: { syncController.zoneConfig.edgeWeight },
                            set: { newVal in
                                syncController.zoneConfig.edgeWeight = newVal
                                syncController.saveZoneConfig()
                            }
                        ), in: 1.0...6.0, step: 0.5)
                        Text(String(format: "%.1f×", syncController.zoneConfig.edgeWeight))
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                    .frame(maxWidth: 220)
                }
            }
            .padding(4)
        }
        .task { await loadDisplays() }
    }

    private func startHighlight(channel: UInt8) {
        pulseTask?.cancel()
        syncController.identify(channel: channel)
        pulseTask = Task {
            try? await Task.sleep(for: .seconds(8))
            if !Task.isCancelled { clearHighlight() }
        }
    }

    private func clearHighlight() {
        pulseTask?.cancel()
        pulseTask = nil
        syncController.stopIdentify()
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
```

**Step 5: Build**

Run: `xcodebuild -project SpillAura.xcodeproj -scheme SpillAura -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"`

Expected: `** BUILD SUCCEEDED **`

**Step 6: Commit**

```bash
git add SpillAura/UI/SettingsView.swift SpillAura/App/SpillAuraApp.swift
git commit -m "feat: add Screen Sync settings section with zone, depth, and edge weight controls"
```

---

### Task 5: Simplify ScreenSyncView — remove config UI, add responsiveness, fix rect call

**Files:**
- Modify: `SpillAura/UI/ScreenSyncView.swift`

Replace the entire file:

```swift
import SwiftUI
import ScreenCaptureKit
import AppKit

/// Live preview for Screen Sync mode.
/// Zone/display configuration lives in Settings.
struct ScreenSyncView: View {
    @EnvironmentObject var syncController: SyncController

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Responsiveness
            Picker("", selection: $syncController.responsiveness) {
                ForEach(SyncResponsiveness.allCases) { preset in
                    Text(preset.label).tag(preset)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: syncController.responsiveness) { _, _ in
                if syncController.connectionStatus == .streaming {
                    syncController.startScreenSync()
                }
            }

            // Live preview canvas
            GeometryReader { geo in
                ZStack {
                    Color.black

                    ForEach(syncController.zoneConfig.zones.indices, id: \.self) { i in
                        let zone = syncController.zoneConfig.zones[i]
                        let rect = zone.region.rect(depth: syncController.zoneConfig.depth)
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
                        let w = rect.width  * geo.size.width
                        let h = rect.height * geo.size.height

                        ZStack {
                            Rectangle().fill(fill)
                            Text(label)
                                .font(.caption2)
                                .foregroundStyle(.white)
                                .shadow(color: .black, radius: 1)
                        }
                        .frame(width: w, height: h)
                        .position(
                            x: rect.midX * geo.size.width,
                            y: rect.midY * geo.size.height
                        )
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
                Text("Open Settings to configure zones.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(minWidth: 320, minHeight: 280)
    }
}
```

**Step 2: Build**

Run: `xcodebuild -project SpillAura.xcodeproj -scheme SpillAura -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"`

Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add SpillAura/UI/ScreenSyncView.swift
git commit -m "feat: simplify ScreenSyncView to live preview + responsiveness; config moved to Settings"
```

---

## Verification

1. **Settings → Screen Sync section visible** — open Settings, confirm "Screen Sync" GroupBox appears below Bridge with channel pickers, Zone Depth slider, Edge Weight slider
2. **Zone depth responds** — move Zone Depth slider; the preview canvas zones in the main window update their size in real time
3. **Edge weight responds** — while streaming, move Edge Weight slider; lights should noticeably change how strongly they weight edge pixels
4. **Responsiveness in main window** — confirm segmented control appears in the Screen tab of the main window; changing it hot-swaps the stream
5. **Hover-to-identify in Settings** — hover a channel row in Settings → light pulses, preview canvas pulses the matching zone
6. **Old config survives upgrade** — if `zoneConfig` was already saved to UserDefaults, it decodes correctly with `depth: 0.20` and `edgeWeight: 3.0` defaults
7. **Aura mode unaffected** — switch to Aura tab, start a vibe, confirm nothing broke
