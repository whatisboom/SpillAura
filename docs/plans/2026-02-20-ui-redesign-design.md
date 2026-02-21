# UI Redesign Design

**Date:** 2026-02-20

## Goal

Replace the current tab-based main window with a focused control surface. The main window is the primary place to control the lights. A separate Settings window (opened via a gear icon) handles bridge pairing and app preferences.

---

## Main Window

**Window ID:** `"main"` (existing)
**Size:** `minWidth: 480, minHeight: 520`

### Layout

```
┌─────────────────────────────────────────────────────┐
│  [Vibe │ Screen]                    ●  Streaming    │  ← top bar
├─────────────────────────────────────────────────────┤
│                                                     │
│   mode-specific content area                        │
│   (VibeControlView or ScreenSyncView)               │
│                                                     │
├─────────────────────────────────────────────────────┤
│  ☀ ─────────────────────────── ☀☀                  │  ← brightness
├─────────────────────────────────────────────────────┤
│  ⚙                          [      Start      ]     │  ← bottom bar
└─────────────────────────────────────────────────────┘
```

### Top Bar
- **Left:** segmented `Picker` — `[Vibe]  [Screen]`
- **Right:** small status badge — colored dot + text (Disconnected / Connecting / Streaming / error message)
- Switching mode while streaming stops the session

### Content Area — Vibe Mode (`VibeControlView`)
- Scrollable list of vibe cards
- Each card: animated color swatch strip (3–4 colors from palette) + vibe name + speed label
- Selected vibe is highlighted with a subtle border/background
- Tapping a card selects it; if already streaming, hot-swaps immediately (no reconnect)

### Content Area — Screen Mode
- Existing `ScreenSyncView` content: display picker (multi-monitor only), zone pickers, live preview canvas
- No changes to existing logic

### Brightness Row
- Always visible between content and bottom bar
- `☀ ─── slider ─── ☀☀` with leading/trailing sun icons

### Bottom Bar
- **Left:** gear button → `openWindow(id: "settings")`
- **Right:** large primary button — shows **Start** when disconnected, **Stop** when connecting/streaming
- Stop is always enabled when not disconnected; Start disabled when not disconnected

---

## Settings Window

**Window ID:** `"settings"` (new)
**Size:** `width: 420, minHeight: 480`
**Style:** plain `VStack` with `Form`-style sections using `GroupBox`

### Section 1 — Bridge
- Shows current bridge IP if paired ("Connected to 192.168.x.x")
- **Re-pair button** → inline replaces content with the existing pairing flow (bridge discovery + link button)
- Entertainment group picker below (same `EntertainmentGroupPicker` as today)

### Section 2 — App
- **Launch at login** toggle (via `SMAppService`)
- Placeholder row for future prefs

---

## Files

| Action | File |
|---|---|
| Rewrite | `SpillAura/SpillAura/UI/MainWindow.swift` |
| New | `SpillAura/SpillAura/UI/VibeControlView.swift` |
| New | `SpillAura/SpillAura/UI/SettingsView.swift` |
| Modify | `SpillAura/SpillAura/App/SpillAuraApp.swift` |
| Repurpose (gutted) | `SpillAura/SpillAura/UI/SetupView.swift` → Bridge section in SettingsView |
| Unchanged | `SpillAura/SpillAura/UI/ScreenSyncView.swift` |
| Unchanged | `SpillAura/SpillAura/UI/MenuBarView.swift` |
| Unchanged | `SpillAura/SpillAura/UI/VibeEditor.swift` |

## MenuBar
No changes to `MenuBarView`. "Open Settings" button renamed to "Open" and calls `openWindow(id: "main")` (already does this).
