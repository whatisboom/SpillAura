# Zone Onboarding Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Move zone layout configuration into the bridge setup wizard as a required step, with a "Reconfigure" entry point in Settings for returning users.

**Architecture:** Extract `ZoneLayoutPreset` to `ZoneConfig.swift` and the preview canvas to a shared `ZonePreviewCanvas` component. Build a new `ZoneSetupStep` view reused in both `SetupView` (wizard step 4) and a `SettingsView` sheet (reconfigure path). SettingsView's full zone config section is replaced by a single "Reconfigure…" button + edge bias slider.

**Tech Stack:** SwiftUI, AppStorage, `ZoneConfig`/`ScreenRegion` from `SpillAura/Config/ZoneConfig.swift`

---

### Task 1: Move ZoneLayoutPreset to ZoneConfig.swift

**Files:**
- Modify: `SpillAura/Config/ZoneConfig.swift`
- Modify: `SpillAura/UI/SettingsView.swift`

**Step 1: Add ZoneLayoutPreset to ZoneConfig.swift**

Append this to the bottom of `SpillAura/Config/ZoneConfig.swift`, after the closing brace of `ZoneConfig`:

```swift
enum ZoneLayoutPreset {
    case twoBar, threeBar, fourBar

    func regions(for count: Int) -> [ScreenRegion] {
        let all: [ScreenRegion]
        switch self {
        case .twoBar:   all = [.left, .right]
        case .threeBar: all = [.top, .left, .right]
        case .fourBar:  all = [.top, .right, .bottom, .left]
        }
        return (0..<count).map { i in i < all.count ? all[i] : .fullScreen }
    }
}
```

**Step 2: Remove the duplicate from SettingsView.swift**

Delete the entire `// MARK: - ZoneLayoutPreset` block from `SpillAura/UI/SettingsView.swift` (lines ~210–216, the `private enum ZoneLayoutPreset` definition). The `applyPreset` method in `ScreenSyncSettingsSection` references `ZoneLayoutPreset` — it will now resolve from ZoneConfig.swift.

**Step 3: Build and verify**

Run: `Cmd+B` in Xcode (or `xcodebuild -scheme SpillAura -destination 'platform=macOS' build 2>&1 | tail -5`)
Expected: `** BUILD SUCCEEDED **`

**Step 4: Commit**

```bash
git add SpillAura/Config/ZoneConfig.swift SpillAura/UI/SettingsView.swift
git commit -m "refactor: move ZoneLayoutPreset to ZoneConfig"
```

---

### Task 2: Create ZonePreviewCanvas

This extracts the 16:9 preview canvas from `ScreenSyncView` into a reusable component. It shows static triangles (with region labels) when no live colors are provided, and live channel colors when streaming.

**Files:**
- Create: `SpillAura/UI/ZonePreviewCanvas.swift`
- Modify: `SpillAura/UI/ScreenSyncView.swift`

**Step 1: Create ZonePreviewCanvas.swift**

```swift
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
                    let previewColor = liveColors.first(where: { $0.channel == zone.channelID })
                    let fill: Color = previewColor.map {
                        Color(red: Double($0.r), green: Double($0.g), blue: Double($0.b))
                    } ?? Color.secondary.opacity(0.25)
                    let label = previewColor != nil ? "Ch \(zone.channelID)" : zone.region.label

                    ZStack {
                        zone.region.previewPath(in: CGRect(origin: .zero, size: geo.size))
                            .fill(fill)
                        Text(label)
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
```

**Step 2: Simplify ScreenSyncView to use ZonePreviewCanvas**

Replace the entire `GeometryReader { geo in ... }` block in `ScreenSyncView` (the zone preview section, roughly lines 26–64) with:

```swift
ZonePreviewCanvas(
    zones: syncController.zoneConfig.zones,
    liveColors: syncController.connectionStatus == .streaming ? syncController.previewColors : []
)
.frame(maxWidth: 480)
```

Also remove the `.help(...)` and `.frame(maxWidth: 480)` that were on the old GeometryReader — they are now inside `ZonePreviewCanvas`.

**Step 3: Build and verify**

Run: `xcodebuild -scheme SpillAura -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 4: Commit**

```bash
git add SpillAura/UI/ZonePreviewCanvas.swift SpillAura/UI/ScreenSyncView.swift
git commit -m "refactor: extract ZonePreviewCanvas from ScreenSyncView"
```

---

### Task 3: Create ZoneSetupStep

A self-contained view showing preset buttons (filtered by channel count), per-channel pickers, and the zone preview canvas. Used in both the setup wizard and the Settings reconfigure sheet.

**Files:**
- Create: `SpillAura/UI/ZoneSetupStep.swift`

**Step 1: Create ZoneSetupStep.swift**

```swift
import SwiftUI

/// Zone assignment UI: preset shortcuts, per-channel pickers, and a live preview.
/// Used in the setup wizard (SetupView) and the Settings reconfigure sheet.
struct ZoneSetupStep: View {
    let channelCount: Int
    @Binding var config: ZoneConfig

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

            // Per-channel pickers
            ForEach(config.zones.indices, id: \.self) { i in
                LabeledContent("Channel \(config.zones[i].channelID)") {
                    Picker("", selection: $config.zones[i].region) {
                        ForEach(ScreenRegion.allCases) { region in
                            Text(region.label).tag(region)
                        }
                    }
                    .frame(maxWidth: 160)
                    .help("Which screen region this channel samples.")
                }
            }

            // Zone preview
            ZonePreviewCanvas(zones: config.zones)
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
```

**Step 2: Build and verify**

Run: `xcodebuild -scheme SpillAura -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add SpillAura/UI/ZoneSetupStep.swift
git commit -m "feat: add ZoneSetupStep shared component"
```

---

### Task 4: Add zone step to SetupView

After the user selects an entertainment group (step 3), show the zone setup as step 4. "Done" saves the config and shows the completion message.

**Files:**
- Modify: `SpillAura/UI/SetupView.swift`

**Step 1: Add state properties to SetupView**

Add these properties to `SetupView` below the existing `@State` declarations:

```swift
@AppStorage("entertainmentGroupID")    private var storedGroupID: String = ""
@AppStorage("entertainmentChannelCount") private var storedChannelCount: Int = 1
@State private var zoneConfig: ZoneConfig = ZoneConfig.defaultConfig(channelCount: 1)
@State private var setupComplete: Bool = false
```

**Step 2: Replace the post-pairing section**

Find and replace the entire block that begins `// Step 3: Select entertainment group (appears after pairing)` through the closing `}` of the `if pairingState == .success` block. Replace it with:

```swift
// Step 3: Select entertainment group (appears after pairing)
if pairingState == .success, let creds = credentials {
    GroupBox("Select Lighting Group") {
        EntertainmentGroupPicker(credentials: creds, auth: auth)
            .padding(4)
    }
}

// Step 4: Configure zones (appears after group is selected)
if pairingState == .success && !storedGroupID.isEmpty {
    GroupBox("Configure Zones") {
        VStack(alignment: .leading, spacing: 12) {
            Text("Match each channel to where its light bar sits relative to your monitor.")
                .font(.callout)
                .foregroundStyle(.secondary)

            ZoneSetupStep(channelCount: storedChannelCount, config: $zoneConfig)

            Button("Done") {
                zoneConfig.save()
                setupComplete = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(4)
    }
}

if setupComplete {
    Label("Setup complete — use the menu bar icon to control your lights.", systemImage: "checkmark.circle.fill")
        .foregroundStyle(.green)
        .font(.callout)
}
```

**Step 3: Reinitialize zoneConfig when channel count changes**

Add this modifier to the outer `ScrollView` in `SetupView.body` (alongside the existing `.onAppear`):

```swift
.onChange(of: storedChannelCount) { _, newCount in
    if newCount > 0 {
        zoneConfig = ZoneConfig.defaultConfig(channelCount: newCount)
        setupComplete = false
    }
}
```

**Step 4: Build and verify**

Run: `xcodebuild -scheme SpillAura -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 5: Commit**

```bash
git add SpillAura/UI/SetupView.swift
git commit -m "feat: add zone setup step to bridge pairing wizard"
```

---

### Task 5: Replace zone config section in SettingsView

Collapse the current zone pickers + presets in `SettingsView` to a single "Reconfigure…" button that opens a sheet with `ZoneSetupStep`.

**Files:**
- Modify: `SpillAura/UI/SettingsView.swift`

**Step 1: Add sheet state to ScreenSyncSettingsSection**

Add this property to `ScreenSyncSettingsSection`, below `@State private var pulseTask`:

```swift
@State private var showingZoneSheet = false
```

**Step 2: Replace the layout presets + zone pickers block**

Find and remove the entire `// Layout presets` block and `// Zone pickers — one row per channel` ForEach (roughly lines 98–140 in the current file). Replace them with:

```swift
// Zone layout
LabeledContent("Zone Layout") {
    Button("Reconfigure…") { showingZoneSheet = true }
        .buttonStyle(.borderless)
}
```

**Step 3: Also remove the now-unused applyPreset and startIdentify helper methods**

Remove `private func applyPreset(_ preset: ZoneLayoutPreset)` — it's no longer used in SettingsView. Keep `startIdentify` and `stopIdentify` only if the identify button is still present elsewhere; since we're removing the per-channel pickers, remove those too.

**Step 4: Add the sheet**

Add this modifier to the `GroupBox("Screen Sync")` in `ScreenSyncSettingsSection.body` (alongside `.task`):

```swift
.sheet(isPresented: $showingZoneSheet) {
    ZoneReconfigureSheet()
        .environmentObject(syncController)
}
```

**Step 5: Add ZoneReconfigureSheet below ScreenSyncSettingsSection**

Add this private struct at the bottom of SettingsView.swift, before `// MARK: - BridgePairingSection`:

```swift
// MARK: - ZoneReconfigureSheet

private struct ZoneReconfigureSheet: View {
    @EnvironmentObject var syncController: SyncController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Configure Zones")
                .font(.title2)
                .fontWeight(.semibold)

            ZoneSetupStep(
                channelCount: syncController.zoneConfig.zones.count,
                config: Binding(
                    get: { syncController.zoneConfig },
                    set: { syncController.zoneConfig = $0; syncController.saveZoneConfig() }
                )
            )

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(minWidth: 400)
    }
}
```

**Step 6: Build and verify**

Run: `xcodebuild -scheme SpillAura -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 7: Run tests**

Run: `xcodebuild -scheme SpillAura -destination 'platform=macOS' test 2>&1 | grep -E "passed|failed|SUCCEEDED|FAILED"`
Expected: All tests pass.

**Step 8: Commit**

```bash
git add SpillAura/UI/SettingsView.swift
git commit -m "feat: replace zone config section with Reconfigure sheet"
```
