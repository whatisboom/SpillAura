# Zone Configuration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the hard-coded equal-column zone layout with user-configurable named screen regions per channel and a source display picker for multi-monitor setups.

**Architecture:** `ScreenRegion` enum replaces raw `CGRect` in `Zone`. `ZoneConfig` gains `displayID: UInt32`. `SyncController` owns a `@Published var zoneConfig` and exposes `saveZoneConfig()` for hot-swap. `ScreenSyncView` adds a display picker and per-channel region pickers above a redesigned `ZStack`-based preview canvas.

**Tech Stack:** SwiftUI, ScreenCaptureKit, CoreGraphics, UserDefaults (JSON), existing `LightSource` / `SyncController` / `ScreenCaptureSource` infrastructure.

---

## Task 1: Rewrite `ZoneConfig.swift`

**Files:**
- Modify: `SpillAura/SpillAura/Config/ZoneConfig.swift`

### Step 1: Replace the entire file

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
    var rect: CGRect {
        switch self {
        case .leftEdge:   return CGRect(x: 0.0,  y: 0.0,  width: 0.2,  height: 1.0)
        case .rightEdge:  return CGRect(x: 0.8,  y: 0.0,  width: 0.2,  height: 1.0)
        case .topEdge:    return CGRect(x: 0.0,  y: 0.0,  width: 1.0,  height: 0.2)
        case .bottomEdge: return CGRect(x: 0.0,  y: 0.8,  width: 1.0,  height: 0.2)
        case .center:     return CGRect(x: 0.25, y: 0.25, width: 0.5,  height: 0.5)
        case .fullScreen: return CGRect(x: 0.0,  y: 0.0,  width: 1.0,  height: 1.0)
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

### Step 2: Build

```bash
xcodebuild -project SpillAura/SpillAura.xcodeproj -scheme SpillAura \
  -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```

Expected: errors from `ScreenCaptureSource` and `SyncController` because `Zone` no longer has `lightID` or a raw `CGRect` region. That is expected — fix in subsequent tasks.

### Step 3: Commit

```bash
git add SpillAura/SpillAura/Config/ZoneConfig.swift
git commit -m "feat: replace raw CGRect zones with ScreenRegion enum and add displayID to ZoneConfig"
```

---

## Task 2: Update `ScreenCaptureSource.swift`

**Files:**
- Modify: `SpillAura/SpillAura/LightSources/ScreenCaptureSource.swift`

### Step 1: Replace the entire file

```swift
import Foundation
import ScreenCaptureKit
import CoreMedia
import CoreVideo

/// A `LightSource` that samples a specific display and maps zone regions to channel colors.
///
/// SCKit delivers frames on a background serial queue. The delegate processes each frame
/// immediately — weighted edge average + EMA smoothing — then stores the result under
/// `lock`. `nextColors()` reads synchronously: no `await` in the hot path.
final class ScreenCaptureSource: NSObject, LightSource, SCStreamOutput, SCStreamDelegate {

    // MARK: - Private state

    private let config: ZoneConfig
    private let responsiveness: SyncResponsiveness

    private var stream: SCStream?
    private let frameQueue = DispatchQueue(label: "com.spillaura.screencapture", qos: .userInteractive)

    /// Per-zone smoothed colors, only accessed on `frameQueue`.
    private var smoothed: [(channel: UInt8, r: Float, g: Float, b: Float)]

    /// Latest processed colors exposed to the MainActor 60fps loop.
    private let lock = NSLock()
    private var _currentColors: [(channel: UInt8, r: Float, g: Float, b: Float)] = []

    // MARK: - Init / deinit

    init(config: ZoneConfig, responsiveness: SyncResponsiveness) {
        self.config = config
        self.responsiveness = responsiveness
        self.smoothed = config.zones.map { (channel: $0.channelID, r: 0, g: 0, b: 0) }
        super.init()
        Task { await startCapture() }
    }

    deinit {
        if let s = stream {
            Task { try? await s.stopCapture() }
        }
    }

    // MARK: - LightSource

    func nextColors(channelCount: Int, at timestamp: TimeInterval) -> [(channel: UInt8, r: Float, g: Float, b: Float)] {
        lock.lock()
        let colors = _currentColors
        lock.unlock()
        if colors.isEmpty {
            return (0..<channelCount).map { (channel: UInt8($0), r: 0, g: 0, b: 0) }
        }
        return colors
    }

    // MARK: - Capture setup

    private func startCapture() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: false
            )

            let targetID: CGDirectDisplayID = config.displayID == 0
                ? CGMainDisplayID()
                : CGDirectDisplayID(config.displayID)
            guard let display = content.displays.first(where: { $0.displayID == targetID })
                             ?? content.displays.first else {
                print("[ScreenCaptureSource] No display found")
                return
            }

            let filter = SCContentFilter(display: display, excludingWindows: [])

            let streamConfig = SCStreamConfiguration()
            streamConfig.width = 160
            streamConfig.height = 90
            streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(responsiveness.frameRate))
            streamConfig.queueDepth = 3
            streamConfig.pixelFormat = kCVPixelFormatType_32BGRA

            let newStream = SCStream(filter: filter, configuration: streamConfig, delegate: self)
            try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: frameQueue)
            try await newStream.startCapture()
            stream = newStream
        } catch {
            print("[ScreenCaptureSource] Failed to start capture: \(error)")
        }
    }

    // MARK: - SCStreamOutput

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let processed = extractColors(from: pixelBuffer)
        lock.lock()
        _currentColors = processed
        lock.unlock()
    }

    // MARK: - SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("[ScreenCaptureSource] Stream stopped: \(error)")
    }

    // MARK: - Color extraction

    /// Weighted edge average: outer 20% of each zone weighted 3× vs inner 80%.
    /// Followed by EMA smoothing per channel component.
    private func extractColors(
        from pixelBuffer: CVPixelBuffer
    ) -> [(channel: UInt8, r: Float, g: Float, b: Float)] {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let pw = CVPixelBufferGetWidth(pixelBuffer)
        let ph = CVPixelBufferGetHeight(pixelBuffer)
        let bpr = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return [] }
        let buf = base.assumingMemoryBound(to: UInt8.self)

        let factor = Float(responsiveness.emaFactor)
        var result: [(channel: UInt8, r: Float, g: Float, b: Float)] = []

        for (i, zone) in config.zones.enumerated() {
            let r = zone.region.rect
            let zx = Int(r.minX   * Double(pw))
            let zy = Int(r.minY   * Double(ph))
            let zw = max(1, Int(r.width  * Double(pw)))
            let zh = max(1, Int(r.height * Double(ph)))

            let edgeW = max(1, Int(Double(zw) * 0.2))
            let edgeH = max(1, Int(Double(zh) * 0.2))

            var sumR = 0.0, sumG = 0.0, sumB = 0.0, sumW = 0.0

            for y in zy..<min(zy + zh, ph) {
                for x in zx..<min(zx + zw, pw) {
                    let isEdge = (x - zx) < edgeW || (zx + zw - 1 - x) < edgeW
                              || (y - zy) < edgeH || (zy + zh - 1 - y) < edgeH
                    let w = isEdge ? 3.0 : 1.0
                    let off = y * bpr + x * 4  // BGRA
                    sumB += Double(buf[off])     / 255.0 * w
                    sumG += Double(buf[off + 1]) / 255.0 * w
                    sumR += Double(buf[off + 2]) / 255.0 * w
                    sumW += w
                }
            }

            guard sumW > 0 else { result.append(smoothed[i]); continue }

            let rawR = Float(sumR / sumW)
            let rawG = Float(sumG / sumW)
            let rawB = Float(sumB / sumW)

            let prev = smoothed[i]
            smoothed[i] = (
                channel: zone.channelID,
                r: prev.r * (1 - factor) + rawR * factor,
                g: prev.g * (1 - factor) + rawG * factor,
                b: prev.b * (1 - factor) + rawB * factor
            )
            result.append(smoothed[i])
        }

        return result
    }
}
```

### Step 2: Build

```bash
xcodebuild -project SpillAura/SpillAura.xcodeproj -scheme SpillAura \
  -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```

Expected: error in `SyncController.swift` (`startScreenSync` still passes old `zones:` arg). That is expected — fix next.

### Step 3: Commit

```bash
git add SpillAura/SpillAura/LightSources/ScreenCaptureSource.swift
git commit -m "feat: update ScreenCaptureSource to use ZoneConfig with ScreenRegion and display selection"
```

---

## Task 3: Update `SyncController.swift`

**Files:**
- Modify: `SpillAura/SpillAura/Sync/SyncController.swift`

### Step 1: Add `zoneConfig` property

Add after the `previewColors` declaration (around line 31):

```swift
@Published var zoneConfig: ZoneConfig = {
    let cc = UserDefaults.standard.object(forKey: "entertainmentChannelCount") as? Int ?? 1
    return ZoneConfig.load(channelCount: cc)
}()
```

### Step 2: Replace `startScreenSync()`

Replace the existing `startScreenSync()` method body:

```swift
/// Start or hot-swap to screen sync mode.
func startScreenSync() {
    activeVibe = nil
    activeSource = ScreenCaptureSource(config: zoneConfig, responsiveness: responsiveness)
    if connectionStatus == .disconnected {
        startSession()
    }
}
```

### Step 3: Add `saveZoneConfig()`

Add after `startScreenSync()`:

```swift
/// Persist zone config and hot-swap the capture source if currently streaming.
func saveZoneConfig() {
    zoneConfig.save()
    if connectionStatus == .streaming {
        startScreenSync()
    }
}
```

### Step 4: Build

```bash
xcodebuild -project SpillAura/SpillAura.xcodeproj -scheme SpillAura \
  -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```

Expected: `** BUILD SUCCEEDED **`

### Step 5: Commit

```bash
git add SpillAura/SpillAura/Sync/SyncController.swift
git commit -m "feat: add zoneConfig and saveZoneConfig() to SyncController"
```

---

## Task 4: Rewrite `ScreenSyncView.swift`

**Files:**
- Modify: `SpillAura/SpillAura/UI/ScreenSyncView.swift`

### Step 1: Replace the entire file

```swift
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
```

### Step 2: Build

```bash
xcodebuild -project SpillAura/SpillAura.xcodeproj -scheme SpillAura \
  -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```

Expected: `** BUILD SUCCEEDED **`

### Step 3: Commit

```bash
git add SpillAura/SpillAura/UI/ScreenSyncView.swift
git commit -m "feat: redesign ScreenSyncView with display picker, zone assignment, and ZStack preview"
```

---

## Task 5: End-to-end verification

### Step 1: Build and launch

```bash
xcodebuild -project SpillAura/SpillAura.xcodeproj -scheme SpillAura \
  -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
open $(find ~/Library/Developer/Xcode/DerivedData -name "SpillAura.app" -path "*/Debug/*" | head -1)
```

### Step 2: Verify zone assignment UI

- Open Settings → Screen Sync tab
- Confirm zone rows appear (one per channel, e.g. "Channel 0", "Channel 1")
- Each row has a picker with: Left Edge, Right Edge, Top Edge, Bottom Edge, Center, Full Screen
- Change Channel 0 to "Left Edge" — preview canvas should immediately show the left 20% highlighted in gray

### Step 3: Verify live preview

- Start Screen Sync from the MenuBar
- The gray regions should turn to live colors reflecting the assigned screen area
- Change a zone picker — color region should move immediately (hot-swap, no reconnect)

### Step 4: Verify display picker (multi-monitor only)

- If only one display: Source Display picker should not be visible
- If multiple displays: picker appears, selecting a different display changes which screen is sampled

### Step 5: Verify persistence

- Assign Left Edge to Channel 0, Right Edge to Channel 1
- Quit and relaunch the app
- Zone assignments should be restored

### Step 6: Vibe mode regression

- Stop Screen Sync, switch to Vibe tab in MenuBar, start a vibe — confirm lights animate correctly
