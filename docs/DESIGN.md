# SpillAura — Master Design

**Created:** 2026-02-17
**Updated:** 2026-02-21
**Platform:** macOS 14+
**Distribution:** Notarized DMG (no App Sandbox)

---

## Goal

A macOS app that controls Philips Hue Play lights with rock-solid reliability and a great native UI — exceeding the official Hue Sync app in stability, aesthetics, and feature depth.

**Key differentiators over Hue Sync:**
- Reliable DTLS session management with auto-reconnect
- Beautiful macOS-native UI (MenuBar + main window)
- Configurable aura/palette system independent of screen content
- Screen sync and audio reactivity as additional modes

---

## Milestones

| Milestone | Deliverable | Status |
|---|---|---|
| **M1** | Bridge discovery, pairing, Keychain storage, entertainment group selection | Done |
| **M2** | DTLS 1.2 PSK connection, entertainment session state machine, color streaming | Done |
| **M3** | Aura system — static colors, cycling/bouncing palettes, AuraLibrary, MenuBar UI | Done |
| **M4** | Screen sync — ScreenCaptureKit, zone regions, weighted edge average, EMA smoothing | Done |
| **M5** | Polish — icon toggles, UI consistency, accessibility, notarization | Done (v1.0.0) |
| **M6** | Audio reactivity — system audio capture, frequency/beat-mapped lighting | Future |

---

## Architecture

### LightSource Protocol

All modes produce colors through a common protocol. The streaming loop doesn't care which source is active — switching modes means swapping the source.

```swift
// Sources/SpillAuraCore/LightSource.swift
public protocol LightSource: Sendable {
    func nextColors(channelCount: Int, at timestamp: TimeInterval)
        -> [(channel: UInt8, r: Float, g: Float, b: Float)]
}
```

**Implementations:**
- `StaticColorSource` — one fixed color for all channels
- `PaletteSource` — cycles/bounces through aura palette colors with per-channel phase offset
- `ScreenCaptureSource` — per-zone weighted average from screen frames
- `IdentifySource` — single channel solid color (channel identification)
- `IdentifyAllSource` — all channels in distinct ChannelColor (reconfigure sheet)

### Component Map

```
SpillAuraApp
├── MainWindow (mode switcher → content → controls → bottom bar)
│     ├── AuraControlView (scrollable aura browser, hot-swap while streaming)
│     └── ScreenSyncView (live zone preview + responsiveness picker)
├── MenuBarView (compact controls: mode tabs, aura/responsiveness pickers, start/stop)
├── SettingsView (bridge, screen sync config, app preferences)
│     ├── BridgePairingSection
│     ├── EntertainmentGroupPicker
│     ├── ScreenSyncSettingsSection + ZoneReconfigureSheet
│     └── App toggles (auto-start, launch hidden, login item)
└── SetupView (first-run wizard: discover → pair → select group → configure zones)

SyncController (@MainActor)
  └── SyncActor (background streaming loop, ~25 Hz)
        ├── LightSource (active mode — swappable)
        ├── HueSender (sends UDP packets via NWConnection)
        └── pulsedIdentify override (array of channel color overrides)

EntertainmentSession (@MainActor)
  ├── REST activation/deactivation (PUT action:start/stop)
  ├── DTLS 1.2 PSK connection (NWConnection, UDP port 2100)
  └── State machine: idle → activating → connecting → streaming → deactivating
                                                    → reconnecting (up to 3 retries)
```

### Actor Isolation

| Component | Isolation | Reason |
|---|---|---|
| `SyncController` — published state, mode, status | `@MainActor` | SwiftUI binding |
| `SyncActor` — 25 Hz tick loop, packet sends | Actor | Must not block main thread |
| `EntertainmentSession` — state machine, REST calls | `@MainActor` | Publishes state for UI |
| `ScreenCaptureSource` — frame processing | `frameQueue` (serial DispatchQueue) | SCKit callback thread |
| Sleep/wake observers | `@MainActor` | `NSWorkspace` fires on main |

**Rule:** No `await` inside the tick loop body. `ScreenCaptureSource.nextColors()` reads from `NSLock`-protected storage synchronously.

---

## DTLS + Entertainment API

### Session Lifecycle

```
idle
  → activate()       → activating   (PUT action:stop + 500ms + PUT action:start)
activating
  → REST success     → connecting   (open NWConnection with DTLS 1.2 PSK)
  → failure          → idle (error surfaced in UI)
connecting
  → DTLS handshake   → streaming    (start 25 Hz tick loop)
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

**Zombie session fix:** Always send `PUT action:stop` + 500ms sleep before `PUT action:start`. Bridge keeps REST status "active" after DTLS timeout.

### Connection Parameters

- DTLS 1.2 over UDP via `Network.framework`
- PSK identity: `username` as UTF-8 `DispatchData` (no null terminator)
- PSK value: `clientKey` hex string decoded to raw `DispatchData`
- Bridge UDP port: 2100
- **VPN fix:** Filter `NWPathMonitor` interfaces by name prefix (`!name.hasPrefix("utun")`) and set `params.requiredInterface` to physical interface

### HueStream v2.0 Packet Format

```
[16 bytes header] + [36 bytes group UUID as ASCII] + [7 bytes × N channels]
```

Header: `"HueStream"(9B) + 0x02,0x00(version) + seq(1B) + 0x00,0x00(reserved) + 0x00(RGB) + 0x00(reserved)`

Per channel: `channel_id(1B) + R(2B BE) + G(2B BE) + B(2B BE)` = 7 bytes

- channel_id is 1 byte (NOT 2-byte UInt16 — that was v1.0)
- Bridge silently ignores malformed packets — no error over DTLS
- Bridge requires ~25 Hz sustained streaming; single packets do nothing

---

## Aura System

### Model

```swift
// Sources/SpillAuraCore/Aura.swift
public struct Aura: Codable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var type: AuraType        // .static or .dynamic
    public var palette: [CodableColor]
    public var speed: Double         // cycle speed (0.08 slow … 0.80 fast)
    public var pattern: AuraPattern  // .cycle, .bounce, .random
    public var channelOffset: Double // 0.0–1.0, phase offset between lights
}
```

### Storage

- Built-in auras: `BuiltinAuras` enum (8 presets with fixed UUIDs)
- User auras: `~/Library/Application Support/SpillAura/auras.json` via `AuraLibrary`

### Built-in Auras

Disco, Neon, Fire, Warm Sunset, Forest, Ocean, Galaxy, Candy

### PaletteSource

Cycles or bounces through palette colors over time. Each channel receives a phase offset (`channelOffset × channelIndex / channelCount`) so adjacent lights show different colors simultaneously. Speed controls cycle rate. Outputs interpolated RGB per channel per tick.

---

## Screen Sync

### Capture Pipeline

1. **SCStream** captures main display at 160×90 resolution
2. **Frame delegate** runs on serial background `DispatchQueue`
3. For each zone: iterate pixels in `ScreenRegion.boundingRect()`, apply `contains(nx:ny:)` filter
4. **Weighted edge average:** pixels where `isEdge(nx:ny:)` is true get `edgeBias`-scaled weight (1× to 5×), others get 1×
5. **EMA smoothing:** `smoothed = smoothed × (1 - factor) + raw × factor`
6. Store results under `NSLock`; `nextColors()` reads synchronously

### Zone Configuration

```swift
struct Zone: Codable {
    let channelID: UInt8
    var region: ScreenRegion  // .top, .bottom, .left, .right, .center, .fullScreen
}

struct ZoneConfig: Codable {
    var displayID: UInt32   // 0 = CGMainDisplayID()
    var zones: [Zone]
    var edgeBias: Double    // 0 (uniform) … 1 (edge-dominated), default 0.0
}
```

`ScreenRegion` uses diagonal-split triangles for top/bottom/left/right — each region's `contains(nx:ny:)` and `isEdge(nx:ny:)` are computed geometrically.

### Smart Defaults

| Channels | Default Layout |
|---|---|
| 1 | Full Screen |
| 2 | Left, Right |
| 3 | Top, Left, Right |
| 4+ | Top, Right, Bottom, Left (+ Full Screen for extras) |

### Responsiveness Presets

| Preset | EMA Factor | Frame Rate |
|---|---|---|
| Instant | 1.0 | 60 fps |
| Snappy | 0.4 | 30 fps |
| Balanced | 0.2 | 20 fps |
| Smooth | 0.1 | 10 fps |
| Cinematic | 0.05 | 5 fps |

### Channel Identification

`ChannelColor` assigns visually distinct hue-wheel colors to each channel (evenly spaced, named: Red, Lime, Cyan, Purple, etc.). Used in:
- Zone preview canvas (colored region labels)
- ZoneSetupStep (per-channel identify buttons)
- Reconfigure sheet auto-identify (all channels light up on sheet open, tear down on close)

---

## UI

### Three Surfaces

| Surface | Purpose | Window ID |
|---|---|---|
| **Main Window** | Primary control: mode switcher, aura browser / screen preview, brightness/speed, start/stop | `"main"` |
| **MenuBar Popover** | Quick access: compact mode tabs, aura picker, responsiveness, start/stop | MenuBarExtra |
| **Settings Window** | Configuration: bridge pairing, zone layout, display picker, edge bias, app preferences | `"settings"` |

### Main Window Layout

```
┌──────────────────────────────────────────┐
│  [Aura │ Screen]           ● Streaming   │  ← mode picker + status badge
├──────────────────────────────────────────┤
│                                          │
│  (Aura: scrollable card list)            │  ← content area
│  (Screen: live zone preview canvas)      │
│                                          │
├──────────────────────────────────────────┤
│  🐢 ──●────── 🐇   ☀ ──●────── ☀       │  ← speed (aura only) + brightness
├──────────────────────────────────────────┤
│  ⚙                            [Start]   │  ← settings gear + action button
└──────────────────────────────────────────┘
```

### Settings Window Sections

- **Bridge:** paired IP, "Change Bridge" button, entertainment group picker
- **Screen Sync:** display picker (multi-monitor), "Reconfigure…" button → zone sheet, edge bias slider
- **App:** launch at login, auto-start streaming, launch with window hidden, show dock icon, show menu bar icon

### First-Run Setup Wizard (SetupView)

Step 1: Discover / enter bridge IP → Step 2: Press link button + pair → Step 3: Select entertainment group → Step 4: Configure zones (preset + per-channel region pickers + preview canvas)

### Sleep/Wake

- `willSleepNotification` → `stop()`, saves `wasStreamingBeforeSleep`
- `didWakeNotification` → if was streaming, `resumeLastSession()` (restores last aura or screen sync mode)

### Session Persistence

`SyncController` persists last mode (`"lastMode"`) and last aura JSON (`"lastAura"`) to UserDefaults on every `startAura`/`startScreenSync`. Auto-start on launch reads these to resume. First launch defaults to Disco.

---

## Project Structure

```
SpillAura/
├── App/
│   ├── SpillAuraApp.swift            # @main, MenuBarExtra + WindowGroup + Settings
│   └── AppDelegate.swift             # Launch-hidden, dock icon policy, ghost-state guard
├── Sync/
│   ├── SyncController.swift          # @MainActor, mode switching, session lifecycle
│   ├── SyncActor.swift               # Background 25 Hz streaming loop
│   └── (LightSource lives in SpillAuraCore)
├── LightSources/
│   ├── StaticColorSource.swift       # Fixed single color
│   └── ScreenCaptureSource.swift     # SCKit capture → weighted zone average
├── Hue/
│   ├── HueBridgeDiscovery.swift      # NetServiceBrowser mDNS + manual IP fallback
│   ├── HueBridgeAuth.swift           # Link button pairing, Keychain, entertainment groups
│   └── EntertainmentSession.swift    # REST + DTLS state machine
├── Config/
│   ├── ZoneConfig.swift              # Zone, ScreenRegion, ChannelColor, ZoneLayoutPreset
│   └── AppSettings.swift             # SyncMode, SyncResponsiveness, UserDefaults settings
├── UI/
│   ├── MenuBarView.swift             # Compact popover controls
│   ├── MainWindow.swift              # Primary control surface
│   ├── AuraControlView.swift         # Scrollable aura browser with cards
│   ├── AuraEditor.swift              # Create/edit custom auras (sheet)
│   ├── ScreenSyncView.swift          # Live zone preview + responsiveness
│   ├── SettingsView.swift            # Bridge, screen sync config, app prefs, reconfigure sheet
│   ├── SetupView.swift               # First-run wizard (discover → pair → group → zones)
│   ├── ZoneSetupStep.swift           # Shared: preset picker + per-channel region pickers
│   ├── ZonePreviewCanvas.swift       # Shared: triangular zone preview with live colors
│   ├── StatusBadge.swift             # Shared: connection status indicator
│   ├── EdgeBiasSlider.swift          # Shared: uniform/edge bias slider
│   └── UIConstants.swift             # Shared: spacing, sizing, scale constants
└── Vibes/                            # (Legacy group name — contains SpillAuraCore refs)

Sources/SpillAuraCore/                # Swift package — shared logic + tests
├── LightSource.swift                 # Protocol
├── Aura.swift                        # Model
├── AuraLibrary.swift                 # Load/save built-in + user auras
├── BuiltinAuras.swift                # 8 hardcoded presets
├── PaletteSource.swift               # Cycle/bounce palette animation
└── ColorPacketBuilder.swift          # HueStream v2.0 UDP packet builder
```

---

## Info.plist Requirements

```xml
<key>NSScreenCaptureUsageDescription</key>
<string>SpillAura needs screen access to match your lights to on-screen colors.</string>
```

No App Sandbox entitlements required.

---

## What's Next

### M5 — Polish

Priority: ship a distributable v1.0.

**Done:**
- **Dock icon toggle:** `DockIconRow` in Settings → `NSApp.setActivationPolicy(.accessory / .regular)`, applied on launch via AppDelegate
- **MenuBar icon toggle:** `MenuBarIconRow` in Settings → `MenuBarExtra(isInserted:)`, bidirectional safety guard (can't hide both)
- **Ghost-state guard:** AppDelegate detects both icons hidden (e.g. manual defaults edit) and forces dock visible
- **UI consistency:** Extracted shared components (StatusBadge, EdgeBiasSlider), centralized magic numbers in UIConstants, fixed LabeledContent outside Form, unified ProgressView scales
- **Accessibility:** VoiceOver labels on all icon-only buttons, sliders, zone preview canvas, and aura swatches

**Remaining:**
- **Notarization:** Code signing + notarized DMG for distribution

### M6 — Audio Reactivity (Future)

System audio capture via SCKit audio stream → frequency analysis + beat detection → color mapping. Two configurable modes: frequency-mapped (bands → channels) and beat-reactive (pulse on transients). Design TBD.
