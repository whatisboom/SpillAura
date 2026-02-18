# SpillAura — Product Design

**Date:** 2026-02-17
**Platform:** macOS 14+
**Distribution:** Notarized DMG (no App Sandbox)

---

## Goal

A macOS app that controls Philips Hue Play lights with rock-solid reliability and a great native UI — exceeding the official Hue Sync app in stability, aesthetics, and feature depth.

**Key differentiators over Hue Sync:**
- Reliable DTLS session management with auto-reconnect
- Beautiful macOS-native UI (MenuBar + main window)
- Configurable vibe/palette system independent of screen content
- Screen sync and audio reactivity as additional modes

---

## Product Milestones

| Milestone | Deliverable |
|---|---|
| **M1** | Xcode setup, project skeleton, bridge pairing UI |
| **M2** | DTLS proof-of-concept — static color to all lights |
| **M3** | Vibe system — static colors + cycling palettes |
| **M4** | Screen sync |
| **M5** | Polish — MenuBar UI, settings, sleep/wake, notarization |
| **M6** | Audio reactivity |

Each milestone is fully testable on real hardware before moving to the next.

---

## Architecture

### LightSource Protocol

All modes produce colors through a common protocol. The 60fps loop doesn't care which source is active — switching modes means swapping the source.

```swift
protocol LightSource {
    func colors(for zones: [Zone], at timestamp: TimeInterval) -> [(channelID: UInt8, r: Float, g: Float, b: Float)]
}
```

**Implementations:**
- `StaticColorSource` — holds one color for all channels
- `PaletteSource` — cycles through colors over time (M3)
- `ScreenCaptureSource` — per-zone color from screen frames (M4)
- `AudioSource` — frequency/beat driven (M6)

### Component Map

```
SyncController (@MainActor)
  └── SyncActor (background)
        ├── LightSource (active mode)
        │     ├── StaticColorSource
        │     ├── PaletteSource
        │     ├── ScreenCaptureSource
        │     └── AudioSource
        ├── EntertainmentSession (DTLS state machine)
        └── ColorPacketBuilder
```

### Actor Isolation

| Component | Isolation | Reason |
|---|---|---|
| `SyncController.isRunning`, mode, status | `@MainActor` | SwiftUI binding |
| 60fps tick loop | `SyncActor` | CPU-bound, must not block main thread |
| `NWConnection.send` | `SyncActor` | No actor hops per frame |
| Sleep/wake observers | `@MainActor` | `NSWorkspace` fires on main |

**Rule:** No `await` inside the tick loop body.

---

## DTLS Reliability

### Session State Machine

```
idle
  → activate()       → activating
activating
  → REST PUT start   → connecting
  → failure          → idle (error surfaced in UI)
connecting
  → DTLS handshake   → streaming
  → failure          → reconnecting
streaming
  → send fails       → reconnecting
  → stop()           → deactivating
reconnecting
  → wait 2s          → connecting (retry)
  → 3 retries fail   → idle (error surfaced in UI)
deactivating
  → REST PUT stop    → idle
```

The tick loop always runs — it is the keep-alive. Color sends pause during `reconnecting` but resume immediately when the connection is restored.

### Connection Parameters

- DTLS 1.2 over UDP via `Network.framework`
- PSK identity: `username` as UTF-8 Data (no null terminator)
- PSK value: `clientKey` hex string decoded to raw Data
- Bridge UDP port: 2100

---

## Vibe System

### Vibe Model

```swift
struct Vibe: Codable, Identifiable {
    let id: UUID
    var name: String
    var type: VibeType       // .static or .dynamic
    var palette: [Color]
    var speed: Double        // seconds per full cycle
    var pattern: VibePattern // .cycle, .bounce, .random
    var channelOffset: Double // 0.0–1.0, phase offset between lights
}

enum VibeType: String, Codable { case `static`, dynamic }
enum VibePattern: String, Codable { case cycle, bounce, random }
```

### Storage

- Built-in vibes: bundled in app bundle
- User vibes: `~/Library/Application Support/SpillAura/vibes/*.json`

### Built-in Vibes (ship with app)

Warm Sunset, Ocean, Forest, Neon, Candlelight, Arctic, Ember, Twilight

---

## UI

### Dual Surface

The app presents the same controls in two places:
1. **MenuBar popover** — quick access
2. **Main window** — full experience

Both surfaces are always available. Users can toggle MenuBar icon and Dock icon independently in Settings (but not both off simultaneously).

### MenuBar Popover Layout

```
┌─────────────────────────────────┐
│  ● SpillAura        [●] Active  │
├─────────────────────────────────┤
│  MODE                           │
│  [Vibe ▼]  [Screen]  [Audio]   │
├─────────────────────────────────┤
│  VIBE                           │
│  ◀ Warm Sunset ▶               │
│  ████████████████  Speed: ●──  │
├─────────────────────────────────┤
│  BRIGHTNESS    ●──────────  85%│
├─────────────────────────────────┤
│  [Settings...]    [Quit]        │
└─────────────────────────────────┘
```

### Status Indicator

MenuBar icon reflects connection state:
- Green dot: streaming
- Yellow dot: connecting / reconnecting
- Red dot: error

### Settings Window

- Bridge pairing / re-pair
- Zone configuration (screen regions → light IDs)
- Custom vibe editor
- Dock icon toggle
- MenuBar icon toggle
- Startup behavior

---

## Project Structure

```
SpillAura/
├── App/
│   ├── SpillAuraApp.swift          # Entry point, MenuBarExtra + WindowGroup
│   └── AppDelegate.swift           # Sleep/wake observers, Dock icon toggle
├── Sync/
│   ├── SyncController.swift        # @MainActor, UI state + mode switching
│   ├── SyncActor.swift             # Background 60fps loop
│   └── LightSource.swift           # Protocol
├── Sources/
│   ├── StaticColorSource.swift
│   ├── PaletteSource.swift
│   ├── ScreenCaptureSource.swift   # M4
│   └── AudioSource.swift           # M6
├── Hue/
│   ├── HueBridgeDiscovery.swift    # mDNS + manual IP fallback
│   ├── HueBridgeAuth.swift         # Link button pairing, Keychain storage
│   ├── EntertainmentSession.swift  # State machine + DTLS
│   └── ColorPacketBuilder.swift    # Entertainment API v2 packet format
├── Vibes/
│   ├── Vibe.swift                  # Model
│   ├── VibeLibrary.swift           # Load built-ins + user vibes
│   └── BuiltinVibes.swift          # Hardcoded presets
├── Config/
│   ├── ZoneConfig.swift            # Screen region → channel mapping
│   └── AppSettings.swift           # UserDefaults-backed settings
└── UI/
    ├── MenuBarView.swift
    ├── MainWindow.swift
    ├── SetupView.swift             # Bridge pairing + zone mapping
    └── VibeEditor.swift            # Custom vibe creation
```

---

## Info.plist Requirements

```xml
<key>NSScreenCaptureUsageDescription</key>
<string>SpillAura needs screen access to match your lights to on-screen colors.</string>
```

No App Sandbox entitlements required.

---

## Tuning Parameters (expose in Settings)

| Parameter | Default | Effect |
|---|---|---|
| Capture resolution | 128×72 | Lower = faster |
| Smoothing factor | 0.25 | Higher = snappier |
| Target FPS | 60 | 30fps fine for most content |
| Saturation boost | 1.2× | More vivid on lights |
| Zone edge inset | 10% | Bias toward screen edges |
