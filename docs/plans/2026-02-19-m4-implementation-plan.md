# M4 Screen Sync Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a Screen Sync mode that captures the main display at low resolution, extracts per-zone colors using a weighted edge average, and streams them to Hue lights via the existing 60fps LightSource pipeline.

**Architecture:** `ScreenCaptureSource` implements `LightSource` and plugs into `SyncController` with no changes to `EntertainmentSession` or `ColorPacketBuilder`. SCKit delivers frames on a background serial queue; the delegate processes them immediately, applies EMA smoothing, and stores results behind an `NSLock`. The MainActor 60fps loop reads `nextColors()` synchronously — no `await` in the hot path.

**Tech Stack:** ScreenCaptureKit (macOS 14+), CoreVideo/CoreMedia, SwiftUI, existing `LightSource` / `SyncController` infrastructure.

---

## Task 1: `SyncResponsiveness` enum + expand `ZoneConfig`

**Files:**
- Modify: `SpillAura/SpillAura/Config/AppSettings.swift`
- Modify: `SpillAura/SpillAura/Config/ZoneConfig.swift`

### Step 1: Add `SyncResponsiveness` to AppSettings.swift

Add above the `class AppSettings` declaration:

```swift
enum SyncResponsiveness: String, CaseIterable, Identifiable {
    case instant, snappy, balanced, smooth, cinematic

    var id: String { rawValue }

    var label: String {
        switch self {
        case .instant:   return "Instant"
        case .snappy:    return "Snappy"
        case .balanced:  return "Balanced"
        case .smooth:    return "Smooth"
        case .cinematic: return "Cinematic"
        }
    }

    /// EMA blend factor: smoothed = smoothed * (1 - factor) + raw * factor
    var emaFactor: Double {
        switch self {
        case .instant:   return 1.0
        case .snappy:    return 0.4
        case .balanced:  return 0.2
        case .smooth:    return 0.1
        case .cinematic: return 0.05
        }
    }

    /// SCStream target frame rate
    var frameRate: Int {
        switch self {
        case .instant:   return 60
        case .snappy:    return 30
        case .balanced:  return 20
        case .smooth:    return 10
        case .cinematic: return 5
        }
    }
}
```

### Step 2: Replace `ZoneConfig.swift` entirely

```swift
import Foundation
import CoreGraphics

/// A single light zone: which channel it drives and where on screen it samples from.
struct Zone: Codable {
    let lightID: String
    let channelID: UInt8
    var region: CGRect  // normalized 0.0–1.0

    // CGRect is not natively Codable — encode as flat keys
    enum CodingKeys: String, CodingKey {
        case lightID, channelID, x, y, width, height
    }

    init(lightID: String, channelID: UInt8, region: CGRect) {
        self.lightID = lightID
        self.channelID = channelID
        self.region = region
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lightID   = try c.decode(String.self, forKey: .lightID)
        channelID = try c.decode(UInt8.self,  forKey: .channelID)
        let x = try c.decode(Double.self, forKey: .x)
        let y = try c.decode(Double.self, forKey: .y)
        let w = try c.decode(Double.self, forKey: .width)
        let h = try c.decode(Double.self, forKey: .height)
        region = CGRect(x: x, y: y, width: w, height: h)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(lightID,          forKey: .lightID)
        try c.encode(channelID,        forKey: .channelID)
        try c.encode(region.origin.x,  forKey: .x)
        try c.encode(region.origin.y,  forKey: .y)
        try c.encode(region.size.width, forKey: .width)
        try c.encode(region.size.height, forKey: .height)
    }
}

/// Manages the mapping of screen regions to Hue channel IDs.
struct ZoneConfig {
    var zones: [Zone]

    /// N equal vertical strips, left-to-right, channelID 0..N-1.
    /// Used as the default until the user configures drag-to-assign.
    static func defaultConfig(channelCount: Int) -> ZoneConfig {
        let count = max(1, channelCount)
        let zones = (0..<count).map { i in
            Zone(
                lightID: "channel_\(i)",
                channelID: UInt8(i),
                region: CGRect(
                    x: Double(i) / Double(count),
                    y: 0.0,
                    width: 1.0 / Double(count),
                    height: 1.0
                )
            )
        }
        return ZoneConfig(zones: zones)
    }

    /// Load from UserDefaults; fall back to default strips if nothing saved.
    static func load(channelCount: Int) -> ZoneConfig {
        guard let data = UserDefaults.standard.data(forKey: "zoneConfig"),
              let zones = try? JSONDecoder().decode([Zone].self, from: data),
              !zones.isEmpty else {
            return defaultConfig(channelCount: channelCount)
        }
        return ZoneConfig(zones: zones)
    }

    func save() {
        if let data = try? JSONEncoder().encode(zones) {
            UserDefaults.standard.set(data, forKey: "zoneConfig")
        }
    }
}
```

### Step 3: Build

```bash
xcodebuild -project SpillAura/SpillAura.xcodeproj -scheme SpillAura \
  -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```

Expected: `** BUILD SUCCEEDED **`

### Step 4: Commit

```bash
git add SpillAura/SpillAura/Config/AppSettings.swift \
        SpillAura/SpillAura/Config/ZoneConfig.swift
git commit -m "feat: add SyncResponsiveness presets and ZoneConfig with Codable Zone"
```

---

## Task 2: `ScreenCaptureSource.swift`

**Files:**
- Create: `SpillAura/SpillAura/LightSources/ScreenCaptureSource.swift`

This is the core of M4. Add this file to the Xcode project under the `LightSources` group.

```swift
import Foundation
import ScreenCaptureKit
import CoreMedia
import CoreVideo

/// A `LightSource` that samples the main display and maps zone regions to channel colors.
///
/// SCKit delivers frames on a background serial queue. The delegate processes each frame
/// immediately — weighted edge average + EMA smoothing — then stores the result under
/// `lock`. `nextColors()` reads synchronously: no `await` in the hot path.
final class ScreenCaptureSource: NSObject, LightSource, SCStreamOutput, SCStreamDelegate {

    // MARK: - Private state

    private let zones: [Zone]
    private let responsiveness: SyncResponsiveness

    private var stream: SCStream?
    private let frameQueue = DispatchQueue(label: "com.spillaura.screencapture", qos: .userInteractive)

    /// Per-zone smoothed colors, only accessed on `frameQueue`.
    private var smoothed: [(channel: UInt8, r: Float, g: Float, b: Float)]

    /// Latest processed colors exposed to the MainActor 60fps loop.
    private let lock = NSLock()
    private var _currentColors: [(channel: UInt8, r: Float, g: Float, b: Float)] = []

    // MARK: - Init / deinit

    init(zones: [Zone], responsiveness: SyncResponsiveness) {
        self.zones = zones
        self.responsiveness = responsiveness
        self.smoothed = zones.map { (channel: $0.channelID, r: 0, g: 0, b: 0) }
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
            guard let display = content.displays.first else {
                print("[ScreenCaptureSource] No display found")
                return
            }

            let filter = SCContentFilter(display: display, excludingWindows: [])

            let config = SCStreamConfiguration()
            config.width = 160
            config.height = 90
            config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(responsiveness.frameRate))
            config.queueDepth = 3
            config.pixelFormat = kCVPixelFormatType_32BGRA

            let newStream = SCStream(filter: filter, configuration: config, delegate: self)
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

        for (i, zone) in zones.enumerated() {
            let zx = Int(zone.region.minX  * Double(pw))
            let zy = Int(zone.region.minY  * Double(ph))
            let zw = max(1, Int(zone.region.width  * Double(pw)))
            let zh = max(1, Int(zone.region.height * Double(ph)))

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

**Note:** The project uses `PBXFileSystemSynchronizedRootGroup` — Xcode automatically includes any `.swift` file on disk. Just creating the file is sufficient; no manual project registration needed.

### Step 2: Build

```bash
xcodebuild -project SpillAura/SpillAura.xcodeproj -scheme SpillAura \
  -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```

Expected: `** BUILD SUCCEEDED **`

### Step 3: Commit

```bash
git add SpillAura/SpillAura/LightSources/ScreenCaptureSource.swift
git commit -m "feat: add ScreenCaptureSource — weighted edge average + EMA smoothing"
```

---

## Task 3: `SyncController` — screen sync API

**Files:**
- Modify: `SpillAura/SpillAura/Sync/SyncController.swift`

### Step 1: Add `responsiveness` and `previewColors` properties

Add after `@Published private(set) var activeVibe: Vibe? = nil`:

```swift
@Published var responsiveness: SyncResponsiveness = {
    let raw = UserDefaults.standard.string(forKey: "syncResponsiveness") ?? ""
    return SyncResponsiveness(rawValue: raw) ?? .balanced
}() {
    didSet { UserDefaults.standard.set(responsiveness.rawValue, forKey: "syncResponsiveness") }
}

/// Latest per-channel colors from the active source. Updated every tick while streaming.
/// Used by ScreenSyncView for the live zone preview.
@Published private(set) var previewColors: [(channel: UInt8, r: Float, g: Float, b: Float)] = []
```

### Step 2: Add `startScreenSync()`

Add after `startStaticColor(r:g:b:)`:

```swift
/// Start or hot-swap to screen sync mode.
func startScreenSync() {
    activeVibe = nil
    let cc = UserDefaults.standard.object(forKey: "entertainmentChannelCount") as? Int ?? 1
    let zones = ZoneConfig.load(channelCount: cc).zones
    activeSource = ScreenCaptureSource(zones: zones, responsiveness: responsiveness)
    if connectionStatus == .disconnected {
        startSession()
    }
}
```

### Step 3: Update streaming loop to publish `previewColors`

In `handleSessionState`, replace the `.streaming` case loop body:

```swift
case .streaming:
    connectionStatus = .streaming
    let capturedChannelCount = channelCount
    let startTime = Date.timeIntervalSinceReferenceDate
    Task { @MainActor [weak self] in
        guard let self else { return }
        while self.connectionStatus == .streaming {
            let elapsed = Date.timeIntervalSinceReferenceDate - startTime
            if let source = self.activeSource {
                let colors = source.nextColors(channelCount: capturedChannelCount, at: elapsed)
                self.session?.sendColors(colors)
                self.previewColors = colors
            }
            try? await Task.sleep(for: .milliseconds(16))
        }
        self.previewColors = []
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
git commit -m "feat: add startScreenSync(), responsiveness, and previewColors to SyncController"
```

---

## Task 4: `MenuBarView` — mode tabs + Screen tab

**Files:**
- Modify: `SpillAura/SpillAura/UI/MenuBarView.swift`

### Step 1: Replace the full file

```swift
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var syncController: SyncController
    @EnvironmentObject var vibeLibrary: VibeLibrary
    @Environment(\.openWindow) private var openWindow

    @State private var vibeIndex: Int = 0
    @State private var mode: Mode = .vibe

    private enum Mode: String, CaseIterable {
        case vibe = "Vibe"
        case screen = "Screen"
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("SpillAura")
                .font(.headline)

            Divider()

            statusRow

            Divider()

            // Mode tabs
            Picker("", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: mode) { _, _ in
                // Switching mode while streaming stops the session
                if syncController.connectionStatus != .disconnected {
                    syncController.stop()
                }
            }

            switch mode {
            case .vibe:   vibePicker
            case .screen: screenControls
            }

            Divider()

            Button("Open Settings") { openWindow(id: "main") }
        }
        .padding()
        .frame(width: 260)
    }

    // MARK: - Vibe Picker

    @ViewBuilder
    private var vibePicker: some View {
        VStack(spacing: 8) {
            HStack {
                Button {
                    vibeIndex = (vibeIndex - 1 + vibeLibrary.vibes.count) % max(vibeLibrary.vibes.count, 1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(vibeLibrary.vibes.count < 2)

                Spacer()

                Text(vibeLibrary.vibes.isEmpty ? "No Vibes" : vibeLibrary.vibes[vibeIndex].name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Spacer()

                Button {
                    vibeIndex = (vibeIndex + 1) % max(vibeLibrary.vibes.count, 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(vibeLibrary.vibes.count < 2)
            }
            .onChange(of: vibeIndex) { _, newIndex in
                if syncController.connectionStatus == .streaming, !vibeLibrary.vibes.isEmpty {
                    syncController.startVibe(vibeLibrary.vibes[newIndex])
                }
            }

            HStack(spacing: 8) {
                Button("Start") {
                    guard !vibeLibrary.vibes.isEmpty else { return }
                    syncController.startVibe(vibeLibrary.vibes[vibeIndex])
                }
                .disabled(syncController.connectionStatus != .disconnected || vibeLibrary.vibes.isEmpty)

                Button("Stop") { syncController.stop() }
                    .disabled(syncController.connectionStatus == .disconnected)
            }
        }
    }

    // MARK: - Screen Controls

    @ViewBuilder
    private var screenControls: some View {
        VStack(spacing: 8) {
            Picker("", selection: $syncController.responsiveness) {
                ForEach(SyncResponsiveness.allCases) { preset in
                    Text(preset.label).tag(preset)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 8) {
                Button("Start") { syncController.startScreenSync() }
                    .disabled(syncController.connectionStatus != .disconnected)

                Button("Stop") { syncController.stop() }
                    .disabled(syncController.connectionStatus == .disconnected)
            }
        }
    }

    // MARK: - Status Row

    @ViewBuilder
    private var statusRow: some View {
        switch syncController.connectionStatus {
        case .disconnected:
            Label("Disconnected", systemImage: "circle")
                .foregroundStyle(.secondary)
                .font(.caption)

        case .connecting:
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.6)
                Text("Connecting…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .streaming:
            Label("Streaming", systemImage: "circle.fill")
                .foregroundStyle(.green)
                .font(.caption)

        case .error(let message):
            Label(message, systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .font(.caption)
                .lineLimit(3)
        }
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
git add SpillAura/SpillAura/UI/MenuBarView.swift
git commit -m "feat: add Vibe/Screen mode tabs to MenuBar with screen sync controls"
```

---

## Task 5: `ScreenSyncView.swift` — live zone preview

**Files:**
- Create: `SpillAura/SpillAura/UI/ScreenSyncView.swift`

Add to the `UI` group in Xcode.

```swift
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
git commit -m "feat: add ScreenSyncView with live zone color preview"
```

---

## Task 6: `MainWindow.swift` — add ScreenSyncView tab

**Files:**
- Modify: `SpillAura/SpillAura/UI/MainWindow.swift`

### Step 1: Replace the full file

```swift
import SwiftUI

struct MainWindow: View {
    @EnvironmentObject var syncController: SyncController

    var body: some View {
        TabView {
            SetupView()
                .tabItem { Label("Setup", systemImage: "gear") }

            ScreenSyncView()
                .tabItem { Label("Screen Sync", systemImage: "display") }
        }
        .frame(minWidth: 520, minHeight: 400)
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
git add SpillAura/SpillAura/UI/MainWindow.swift
git commit -m "feat: add Screen Sync tab to main window"
```

---

## Task 7: `NSScreenCaptureUsageDescription` build setting

ScreenCaptureKit requires this key in the app's Info.plist. Since the project uses `GENERATE_INFOPLIST_FILE = YES`, add it directly to `project.pbxproj`.

**Files:**
- Modify: `SpillAura/SpillAura.xcodeproj/project.pbxproj`

### Step 1: Add the key to both Debug and Release build settings

In `project.pbxproj`, find both occurrences of:
```
INFOPLIST_KEY_NSHumanReadableCopyright = "";
```

Immediately after each occurrence, add:
```
INFOPLIST_KEY_NSScreenCaptureUsageDescription = "SpillAura needs screen access to match your Hue lights to on-screen colors.";
```

There will be two occurrences (Debug + Release). Add the line after both.

### Step 2: Build

```bash
xcodebuild -project SpillAura/SpillAura.xcodeproj -scheme SpillAura \
  -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```

Expected: `** BUILD SUCCEEDED **`

### Step 3: Commit

```bash
git add SpillAura/SpillAura.xcodeproj/project.pbxproj
git commit -m "feat: add NSScreenCaptureUsageDescription to Info.plist"
```

---

## Task 8: End-to-end verification

### Step 1: Launch the app

Run from Xcode or:
```bash
open /Users/brandon/Library/Developer/Xcode/DerivedData/SpillAura-*/Build/Products/Debug/SpillAura.app
```

### Step 2: Verify MenuBar mode tabs

- Open the MenuBar popover
- Confirm `[Vibe] [Screen]` tabs appear at the top
- Switch to Screen tab — confirm responsiveness segmented control (Instant/Snappy/Balanced/Smooth/Cinematic) and Start/Stop buttons appear
- Switch back to Vibe — confirm vibe carousel is back, no crash

### Step 3: Verify screen capture permission prompt

- Click **Start** in the Screen tab
- macOS should prompt for Screen Recording permission (System Settings → Privacy & Security → Screen Recording)
- Grant permission
- Status indicator should change to "Connecting…" then "Streaming"

### Step 4: Verify lights respond to screen content

- With Screen Sync streaming, put a solid red image on screen
- Left-most light (channel 0) should go red
- Put a blue image on the right half — right-most light should shift to blue
- Confirm lights lag appropriately per the "Balanced" preset (~5 frame delay visible)

### Step 5: Verify responsiveness presets

- While streaming, switch to "Instant" — lights should snap immediately with no lag
- Switch to "Cinematic" — lights should fade very slowly on content changes

### Step 6: Verify main window zone preview

- Open Settings (Open Settings button in MenuBar)
- Navigate to Screen Sync tab
- While streaming, confirm the colored strips update to reflect current zone colors
- Each strip should match the corresponding region of the screen

### Step 7: Verify vibe mode still works

- Click Screen → Stop
- Switch to Vibe tab → select "Neon" → Start
- Confirm lights cycle as expected (M3 regression check)
