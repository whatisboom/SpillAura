# Zone Configuration Design

**Date:** 2026-02-20

## Problem

`ScreenCaptureSource` currently maps N channels to N equal vertical strips across the full screen. This is wrong for real Hue Play setups — bars are positioned on the sides, top, or behind the monitor, not uniformly distributed across the screen width.

## Solution

Named screen regions per channel, with a single source-display picker for multi-monitor setups. Configuration lives in the main window's Screen Sync tab.

---

## Data Model

### `ScreenRegion` enum

Added to `ZoneConfig.swift`. Six named positions, each mapping to a normalized `CGRect`:

```swift
enum ScreenRegion: String, CaseIterable, Codable, Identifiable {
    case leftEdge, rightEdge, topEdge, bottomEdge, center, fullScreen

    var label: String { ... }

    var rect: CGRect {
        switch self {
        case .leftEdge:   return CGRect(x: 0.0,  y: 0.0, width: 0.2,  height: 1.0)
        case .rightEdge:  return CGRect(x: 0.8,  y: 0.0, width: 0.2,  height: 1.0)
        case .topEdge:    return CGRect(x: 0.0,  y: 0.0, width: 1.0,  height: 0.2)
        case .bottomEdge: return CGRect(x: 0.0,  y: 0.8, width: 1.0,  height: 0.2)
        case .center:     return CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        case .fullScreen: return CGRect(x: 0.0,  y: 0.0, width: 1.0,  height: 1.0)
        }
    }
}
```

### `Zone` struct

Simplified — `lightID` dropped, `region` is now `ScreenRegion` not `CGRect`:

```swift
struct Zone: Codable {
    let channelID: UInt8
    var region: ScreenRegion
}
```

### `ZoneConfig` struct

Gains `displayID: UInt32` (stored as `UInt32` for Codable; `0` means main display):

```swift
struct ZoneConfig: Codable {
    var displayID: UInt32   // 0 = CGMainDisplayID()
    var zones: [Zone]
}
```

**Default config:** `displayID = 0`, all channels → `.fullScreen`. Honest about not knowing where the bars are until the user configures it.

---

## `ScreenCaptureSource` Changes

- Receives a `ZoneConfig` instead of `[Zone]` + `SyncResponsiveness` separately
- Resolves `displayID == 0` → `CGMainDisplayID()`, finds matching `SCDisplay`
- Uses `zone.region.rect` for pixel sampling (replaces raw `CGRect`)
- No other changes to the extraction or EMA smoothing logic

---

## `SyncController` Changes

- Replaces the ad-hoc `ZoneConfig.load()` call in `startScreenSync()` with a `@Published var zoneConfig: ZoneConfig` property (loaded from UserDefaults on init, saved on every mutation)
- Adds `saveZoneConfig()` method: persists to UserDefaults, then hot-swaps `ScreenCaptureSource` if currently streaming (same pattern as responsiveness hot-swap)

---

## UI — `ScreenSyncView` (Main Window)

Three sections stacked vertically:

### 1. Source Display
A `Picker` populated from `SCShareableContent.displays` on `.task`. Selection writes to `syncController.zoneConfig.displayID` and calls `saveZoneConfig()`.

### 2. Zone Assignment
A `ForEach` over `syncController.zoneConfig.zones` — one row per channel:
```
Channel 0   [Left Edge   ▼]
Channel 1   [Right Edge  ▼]
Channel 2   [Full Screen ▼]
```
Each picker writes to `syncController.zoneConfig.zones[i].region` and calls `saveZoneConfig()`.

### 3. Live Preview
A `GeometryReader` 16:9 canvas. Replaced the `HStack` of equal strips with a `ZStack`:
- For each zone, draw a `Rectangle` at the position/size derived from `zone.region.rect × canvasSize`
- Fill with the zone's current live color (from `syncController.previewColors`) while streaming
- While not streaming: dim gray fill, `ScreenRegion.label` text overlay — shows layout before starting
- `"Ch N"` label overlaid on each rect while streaming
- Outer `RoundedRectangle` border and clip shape unchanged

---

## What Doesn't Change

- `EntertainmentSession`, `ColorPacketBuilder`, `LightSource` protocol — untouched
- `SyncResponsiveness` — stays as a separate concern on `SyncController`
- MenuBar Screen tab — Start/Stop + responsiveness picker only; zone config is main-window-only
- The 60fps streaming loop — reads `previewColors` exactly as before
