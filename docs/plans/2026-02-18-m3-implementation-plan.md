# M3 Implementation Plan — Vibe System

**Date:** 2026-02-18
**Goal:** Replace the hardcoded "Send Red" test button with a real vibe system: static colors + cycling palettes across all channels, with a proper MenuBar UI.

---

## Current State (M2 complete)

- `EntertainmentSession` manages DTLS state machine ✓
- `SyncController.startStaticColor(r:g:b:)` activates a session and loops at 25Hz ✓
- `MenuBarView` has "Send Red" / "Stop" test buttons ✓
- `SyncActor.sendStaticColor` bounces to MainActor to call `session.sendColor` ✓
- Stub files exist: `LightSource.swift`, `StaticColorSource.swift`, `PaletteSource.swift`, `BuiltinVibes.swift`, `VibeLibrary.swift`

---

## What Needs to Change

### 1. `ColorPacketBuilder` — per-channel colors

Add an overload that accepts different colors per channel (needed for PaletteSource with channelOffset):

**File:** `SpillAura/SpillAura/Hue/ColorPacketBuilder.swift`

Add alongside the existing `buildPacket`:

```swift
/// Builds a packet where each channel has an independent color.
static func buildPacket(
    channelColors: [(channel: UInt8, r: Float, g: Float, b: Float)],
    sequence: UInt8,
    groupID: String
) -> Data {
    var data = Data()
    // Header (16 bytes) — identical to existing method
    data.append(contentsOf: [0x48, 0x75, 0x65, 0x53, 0x74, 0x72, 0x65, 0x61, 0x6D])
    data.append(contentsOf: [0x02, 0x00])
    data.append(sequence)
    data.append(contentsOf: [0x00, 0x00])
    data.append(0x00)
    data.append(0x00)
    // UUID (36 bytes ASCII)
    data.append(contentsOf: groupID.utf8)
    // Per-channel entries (7 bytes each)
    for entry in channelColors {
        let r = UInt16(min(max(entry.r, 0), 1) * 65535)
        let g = UInt16(min(max(entry.g, 0), 1) * 65535)
        let b = UInt16(min(max(entry.b, 0), 1) * 65535)
        data.append(entry.channel)
        data.append(UInt8(r >> 8)); data.append(UInt8(r & 0xFF))
        data.append(UInt8(g >> 8)); data.append(UInt8(g & 0xFF))
        data.append(UInt8(b >> 8)); data.append(UInt8(b & 0xFF))
    }
    return data
}
```

### 2. `EntertainmentSession` — per-channel send

**File:** `SpillAura/SpillAura/Hue/EntertainmentSession.swift`

Add alongside `sendColor(r:g:b:)`:

```swift
/// Send one packet with independent colors per channel.
func sendColors(_ channelColors: [(channel: UInt8, r: Float, g: Float, b: Float)]) {
    guard state == .streaming, let connection else { return }
    let packet = ColorPacketBuilder.buildPacket(
        channelColors: channelColors,
        sequence: sequenceNumber,
        groupID: groupID
    )
    sequenceNumber = sequenceNumber == 255 ? 0 : sequenceNumber + 1
    connection.send(content: packet, completion: .contentProcessed({ error in
        if let error = error { print("[EntertainmentSession] send error: \(error)") }
    }))
}
```

### 3. `LightSource` protocol

**File:** `SpillAura/SpillAura/Sync/LightSource.swift`

```swift
import Foundation

protocol LightSource {
    /// Returns the color for each channel at the given timestamp.
    /// - Parameters:
    ///   - channelCount: Number of channels in the active entertainment group.
    ///   - timestamp: Monotonic time (e.g. `Date().timeIntervalSinceReferenceDate`).
    func nextColors(channelCount: Int, at timestamp: TimeInterval) -> [(channel: UInt8, r: Float, g: Float, b: Float)]
}
```

### 4. `StaticColorSource`

**File:** `SpillAura/SpillAura/LightSources/StaticColorSource.swift`

```swift
import Foundation

struct StaticColorSource: LightSource {
    let r: Float
    let g: Float
    let b: Float

    func nextColors(channelCount: Int, at timestamp: TimeInterval) -> [(channel: UInt8, r: Float, g: Float, b: Float)] {
        (0..<channelCount).map { (channel: UInt8($0), r: r, g: g, b: b) }
    }
}
```

### 5. `PaletteSource`

**File:** `SpillAura/SpillAura/LightSources/PaletteSource.swift`

Interpolates through a Vibe's palette over time, with per-channel phase offset.

```swift
import Foundation

struct PaletteSource: LightSource {
    let vibe: Vibe

    func nextColors(channelCount: Int, at timestamp: TimeInterval) -> [(channel: UInt8, r: Float, g: Float, b: Float)] {
        guard !vibe.palette.isEmpty else {
            return (0..<channelCount).map { (UInt8($0), 0, 0, 0) }
        }

        // Static vibe: all channels get palette[0]
        if vibe.type == .static {
            let c = vibe.palette[0]
            return (0..<channelCount).map { (UInt8($0), Float(c.red), Float(c.green), Float(c.blue)) }
        }

        // Dynamic: position in cycle based on timestamp and speed
        let cycleT = vibe.speed > 0 ? (timestamp / vibe.speed).truncatingRemainder(dividingBy: 1.0) : 0

        return (0..<channelCount).map { i in
            var t = (cycleT + Double(i) * vibe.channelOffset).truncatingRemainder(dividingBy: 1.0)
            if t < 0 { t += 1.0 }

            // .bounce: reflect at 0.5
            let effectiveT: Double
            if vibe.pattern == .bounce {
                effectiveT = t < 0.5 ? t * 2 : (1.0 - t) * 2
            } else {
                effectiveT = t
            }

            let color = interpolatePalette(vibe.palette, at: effectiveT)
            return (UInt8(i), Float(color.red), Float(color.green), Float(color.blue))
        }
    }

    private func interpolatePalette(_ palette: [CodableColor], at t: Double) -> CodableColor {
        let n = palette.count
        guard n > 1 else { return palette[0] }
        let scaled = t * Double(n)
        let lo = Int(scaled) % n
        let hi = (lo + 1) % n
        let frac = scaled - Double(Int(scaled))
        return CodableColor(
            red:   palette[lo].red   + frac * (palette[hi].red   - palette[lo].red),
            green: palette[lo].green + frac * (palette[hi].green - palette[lo].green),
            blue:  palette[lo].blue  + frac * (palette[hi].blue  - palette[lo].blue)
        )
    }
}
```

Note: `.random` pattern can be left as `.cycle` behavior for now (true randomness needs per-channel state, add later).

### 6. `BuiltinVibes`

**File:** `SpillAura/SpillAura/Vibes/BuiltinVibes.swift`

```swift
import Foundation

enum BuiltinVibes {
    static let all: [Vibe] = [
        warmSunset, ocean, forest, neon, candlelight, arctic, ember, twilight
    ]

    static let warmSunset = Vibe(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "Warm Sunset",
        type: .dynamic,
        palette: [
            CodableColor(red: 1.0, green: 0.3, blue: 0.0),
            CodableColor(red: 1.0, green: 0.6, blue: 0.1),
            CodableColor(red: 0.9, green: 0.2, blue: 0.1),
        ],
        speed: 8.0,
        pattern: .cycle,
        channelOffset: 0.2
    )

    static let ocean = Vibe(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        name: "Ocean",
        type: .dynamic,
        palette: [
            CodableColor(red: 0.0, green: 0.4, blue: 1.0),
            CodableColor(red: 0.0, green: 0.8, blue: 0.9),
            CodableColor(red: 0.1, green: 0.2, blue: 0.7),
        ],
        speed: 10.0,
        pattern: .bounce,
        channelOffset: 0.25
    )

    static let forest = Vibe(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
        name: "Forest",
        type: .dynamic,
        palette: [
            CodableColor(red: 0.0, green: 0.6, blue: 0.1),
            CodableColor(red: 0.2, green: 0.9, blue: 0.2),
            CodableColor(red: 0.0, green: 0.4, blue: 0.0),
        ],
        speed: 12.0,
        pattern: .cycle,
        channelOffset: 0.3
    )

    static let neon = Vibe(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
        name: "Neon",
        type: .dynamic,
        palette: [
            CodableColor(red: 1.0, green: 0.0, blue: 1.0),
            CodableColor(red: 0.0, green: 1.0, blue: 1.0),
            CodableColor(red: 1.0, green: 1.0, blue: 0.0),
        ],
        speed: 4.0,
        pattern: .cycle,
        channelOffset: 0.33
    )

    static let candlelight = Vibe(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!,
        name: "Candlelight",
        type: .dynamic,
        palette: [
            CodableColor(red: 1.0, green: 0.5, blue: 0.05),
            CodableColor(red: 1.0, green: 0.3, blue: 0.0),
            CodableColor(red: 0.9, green: 0.4, blue: 0.0),
        ],
        speed: 3.0,
        pattern: .bounce,
        channelOffset: 0.1
    )

    static let arctic = Vibe(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000006")!,
        name: "Arctic",
        type: .dynamic,
        palette: [
            CodableColor(red: 0.7, green: 0.9, blue: 1.0),
            CodableColor(red: 0.4, green: 0.7, blue: 1.0),
            CodableColor(red: 0.9, green: 1.0, blue: 1.0),
        ],
        speed: 15.0,
        pattern: .bounce,
        channelOffset: 0.2
    )

    static let ember = Vibe(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000007")!,
        name: "Ember",
        type: .dynamic,
        palette: [
            CodableColor(red: 1.0, green: 0.1, blue: 0.0),
            CodableColor(red: 1.0, green: 0.4, blue: 0.0),
            CodableColor(red: 0.6, green: 0.0, blue: 0.0),
        ],
        speed: 5.0,
        pattern: .cycle,
        channelOffset: 0.25
    )

    static let twilight = Vibe(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000008")!,
        name: "Twilight",
        type: .dynamic,
        palette: [
            CodableColor(red: 0.4, green: 0.0, blue: 0.8),
            CodableColor(red: 0.8, green: 0.2, blue: 0.6),
            CodableColor(red: 0.1, green: 0.0, blue: 0.5),
        ],
        speed: 9.0,
        pattern: .cycle,
        channelOffset: 0.2
    )
}
```

### 7. `VibeLibrary`

**File:** `SpillAura/SpillAura/Vibes/VibeLibrary.swift`

```swift
import Foundation
import Combine

@MainActor
class VibeLibrary: ObservableObject {
    @Published private(set) var vibes: [Vibe] = []

    private let userVibesURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("SpillAura/vibes", isDirectory: true)
    }()

    init() {
        load()
    }

    func load() {
        var all = BuiltinVibes.all
        // Load user vibes from ~/Library/Application Support/SpillAura/vibes/*.json
        if let contents = try? FileManager.default.contentsOfDirectory(
            at: userVibesURL, includingPropertiesForKeys: nil
        ) {
            let decoder = JSONDecoder()
            for url in contents where url.pathExtension == "json" {
                if let data = try? Data(contentsOf: url),
                   let vibe = try? decoder.decode(Vibe.self, from: data) {
                    all.append(vibe)
                }
            }
        }
        vibes = all
    }

    func save(_ vibe: Vibe) throws {
        try FileManager.default.createDirectory(at: userVibesURL, withIntermediateDirectories: true)
        let url = userVibesURL.appendingPathComponent("\(vibe.id).json")
        let data = try JSONEncoder().encode(vibe)
        try data.write(to: url)
        load()
    }

    func delete(_ vibe: Vibe) throws {
        // Cannot delete built-ins
        guard !BuiltinVibes.all.contains(where: { $0.id == vibe.id }) else { return }
        let url = userVibesURL.appendingPathComponent("\(vibe.id).json")
        try FileManager.default.removeItem(at: url)
        load()
    }
}
```

### 8. `SyncController` — vibe-driven API

**File:** `SpillAura/SpillAura/Sync/SyncController.swift`

Replace the current `startStaticColor(r:g:b:)` / `pendingColor` implementation with a `LightSource`-driven approach.

Key changes:
- Add `@Published var activeVibe: Vibe? = nil`
- Replace `pendingColor: (r,g,b)?` with `pendingSource: LightSource?`
- Add `func startVibe(_ vibe: Vibe)` — creates `PaletteSource` and calls internal start
- Keep `func startStaticColor(r:g:b:)` for backward compat / can remove test buttons later
- Streaming loop uses `source.nextColors(channelCount:at:)` and calls `session.sendColors(_:)`

New streaming loop in `handleSessionState(.streaming)`:

```swift
case .streaming:
    connectionStatus = .streaming
    if let source = pendingSource {
        pendingSource = nil
        let channelCount = UserDefaults.standard.object(forKey: "entertainmentChannelCount") as? Int ?? 1
        Task { @MainActor [weak self] in
            guard let self else { return }
            while self.connectionStatus == .streaming {
                let colors = source.nextColors(
                    channelCount: channelCount,
                    at: Date().timeIntervalSinceReferenceDate
                )
                self.session?.sendColors(colors)
                try? await Task.sleep(for: .milliseconds(16)) // ~60fps
            }
        }
    }
```

New public API:

```swift
func startVibe(_ vibe: Vibe) {
    guard connectionStatus == .disconnected else { return }
    activeVibe = vibe
    pendingSource = PaletteSource(vibe: vibe)
    _startSession()
}

func startStaticColor(r: Float, g: Float, b: Float) {
    guard connectionStatus == .disconnected else { return }
    pendingSource = StaticColorSource(r: r, g: g, b: b)
    _startSession()
}
```

Where `_startSession()` holds the shared credential loading + session creation logic currently in `startStaticColor`.

### 9. `SyncActor` — simplify

**File:** `SpillAura/SpillAura/Sync/SyncActor.swift`

The M2 `sendStaticColor` can be removed — the streaming loop now lives on MainActor in `SyncController`. `SyncActor` retains only `setSession` / `clearSession` for lifecycle management. (Or remove `SyncActor` entirely since the loop moved to MainActor — decide at implementation time.)

### 10. `MenuBarView` — vibe picker UI

**File:** `SpillAura/SpillAura/UI/MenuBarView.swift`

Replace test buttons with:

```
┌──────────────────────────────────┐
│  SpillAura                       │
├──────────────────────────────────┤
│  ● Streaming                     │
├──────────────────────────────────┤
│  VIBE                            │
│  ◀  Warm Sunset  ▶               │
│  [▶ Start]  [■ Stop]             │
├──────────────────────────────────┤
│  Open Settings                   │
└──────────────────────────────────┘
```

Key elements:
- `EnvironmentObject` for `VibeLibrary` (added to app-level environment in `SpillAuraApp`)
- `@State var vibeIndex: Int = 0`
- Prev/next buttons cycle through `vibeLibrary.vibes`
- Start button calls `syncController.startVibe(selectedVibe)`
- Disabled states same as before

### 11. `SpillAuraApp` — inject VibeLibrary

**File:** `SpillAura/SpillAura/App/SpillAuraApp.swift`

Add `@StateObject private var vibeLibrary = VibeLibrary()` and inject `.environmentObject(vibeLibrary)` into both `MenuBarExtra` and `WindowGroup`.

---

## Verification

Success criteria:
1. App launches, MenuBar shows vibe picker with "Warm Sunset" selected
2. Click Start → lights cycle through orange/gold palette over ~8 seconds with offset between channels
3. Navigate to "Neon" → click Start → lights cycle through pink/cyan/yellow faster
4. Click Stop → lights return to normal
5. Second Start works (zombie session fix still works)
6. All 8 built-in vibes produce visible, distinct effects

---

## Files to Create/Modify

| File | Action |
|------|--------|
| `Hue/ColorPacketBuilder.swift` | Add per-channel-color overload |
| `Hue/EntertainmentSession.swift` | Add `sendColors(_:)` |
| `Sync/LightSource.swift` | Implement protocol |
| `LightSources/StaticColorSource.swift` | Implement |
| `LightSources/PaletteSource.swift` | Implement |
| `Vibes/BuiltinVibes.swift` | Implement 8 built-ins |
| `Vibes/VibeLibrary.swift` | Implement load/save/delete |
| `Sync/SyncController.swift` | Replace M2 API with vibe-driven API |
| `Sync/SyncActor.swift` | Simplify (remove `sendStaticColor`) |
| `UI/MenuBarView.swift` | Vibe picker UI |
| `App/SpillAuraApp.swift` | Inject `VibeLibrary` |
