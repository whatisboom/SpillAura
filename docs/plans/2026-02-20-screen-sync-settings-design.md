# Screen Sync Settings Redesign

**Date:** 2026-02-20

## Goal

Move all screen sync configuration (zone assignment, display picker, zone depth, edge weight) from the main window's Screen Sync tab into the Settings window. The main window Screen tab becomes a focused control surface: responsiveness picker + live preview only.

---

## Data Model

### `ZoneConfig` — two new fields

```swift
struct ZoneConfig: Codable {
    var displayID: UInt32   // 0 = CGMainDisplayID()
    var zones: [Zone]
    var depth: Double       // NEW — zone region depth, 0.05–0.50, default 0.20
    var edgeWeight: Double  // NEW — edge pixel weight vs center, 1.0–6.0, default 3.0
}
```

### `ScreenRegion.rect` — becomes a method

`rect` changes from a computed property to a function that takes `depth`:

```swift
func rect(depth: Double) -> CGRect
```

- `leftEdge`   → `CGRect(x: 0.0,        y: 0.0, width: depth,      height: 1.0)`
- `rightEdge`  → `CGRect(x: 1.0-depth,  y: 0.0, width: depth,      height: 1.0)`
- `topEdge`    → `CGRect(x: 0.0,        y: 0.0, width: 1.0,        height: depth)`
- `bottomEdge` → `CGRect(x: 0.0,        y: 1.0-depth, width: 1.0,  height: depth)`
- `center`     → `CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)` (depth ignored)
- `fullScreen` → `CGRect(x: 0.0,  y: 0.0,  width: 1.0, height: 1.0)` (depth ignored)

### `ScreenCaptureSource` — reads depth and edgeWeight from config

Replace hardcoded `0.2` (edge fraction) with `config.depth` and `3.0` (edge weight) with `config.edgeWeight`. Zone rects computed via `zone.region.rect(depth: config.depth)`.

---

## Settings Window — new "Screen Sync" GroupBox

Added between the Bridge and App sections in `SettingsView`:

```
┌─ Screen Sync ──────────────────────────────────┐
│  Source Display    [Main Display ▼]             │  ← hidden if only 1 monitor
│  ──────────────────────────────────────────── │
│  Channel 0         [Left Edge   ▼]              │
│  Channel 1         [Right Edge  ▼]              │
│  ...                                            │
│  ──────────────────────────────────────────── │
│  Zone Depth        ●────────────  20%           │
│  Edge Weight       ────●────────  3.0×          │
└────────────────────────────────────────────────┘
```

- **Source Display** — `SCShareableContent` picker, only rendered when `availableDisplays.count > 1`. Writes to `syncController.zoneConfig.displayID`, calls `saveZoneConfig()`.
- **Channel rows** — one `Picker` per channel (`ScreenRegion.allCases`). Hover-to-identify (pulse light + pulse preview overlay) lives here alongside the pickers.
- **Zone Depth slider** — `0.05...0.50`, formatted as a percentage ("20%"). Writes to `syncController.zoneConfig.depth`, calls `saveZoneConfig()`.
- **Edge Weight slider** — `1.0...6.0`, formatted as "Nx" ("3.0×"). Writes to `syncController.zoneConfig.edgeWeight`, calls `saveZoneConfig()`.

Both sliders hot-swap `ScreenCaptureSource` immediately via `saveZoneConfig()` if currently streaming.

---

## Main Window — Screen Sync Tab

`ScreenSyncView` is simplified to two elements:

```
┌─────────────────────────────────────────────────┐
│  [Instant][Snappy][Balanced][Smooth][Cinematic] │
├─────────────────────────────────────────────────┤
│                                                 │
│         16:9 live preview canvas                │
│                                                 │
└─────────────────────────────────────────────────┘
```

- **Responsiveness** — segmented control bound to `syncController.responsiveness`. Stays in sync with the MenuBar control via `@Published`.
- **Live preview canvas** — unchanged rendering logic. Zone rects use `zone.region.rect(depth: syncController.zoneConfig.depth)`. Labels show `region.label` when stopped, "Ch N" when streaming.
- **Hover-to-identify** — removed from here; it belongs next to zone pickers in Settings.
- Static hint text replaced with "Open Settings to configure zones." (shown only when not streaming).

---

## What Doesn't Change

- `EntertainmentSession`, `ColorPacketBuilder`, `LightSource` protocol — untouched.
- MenuBar Screen tab — Start/Stop + responsiveness picker only; zone config is Settings-only.
- The 60fps streaming loop — unchanged.
- `SyncController.saveZoneConfig()` — already hot-swaps `ScreenCaptureSource` when streaming; no change needed.
- `identify(channel:)` / `stopIdentify()` on `SyncController` — unchanged; just called from Settings instead of ScreenSyncView.

---

## Files Changed

| Action | File |
|---|---|
| Modify | `SpillAura/Config/ZoneConfig.swift` |
| Modify | `SpillAura/LightSources/ScreenCaptureSource.swift` |
| Modify | `SpillAura/UI/ScreenSyncView.swift` |
| Modify | `SpillAura/UI/SettingsView.swift` |
