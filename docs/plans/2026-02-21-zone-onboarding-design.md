# Zone Setup Onboarding Design

**Date:** 2026-02-21

## Problem

Zone layout presets and per-channel pickers live in Settings — a place users visit rarely. First-time users start Screen Sync with wrong defaults (all Full Screen) and have no obvious path to fix it. Zone configuration is a one-time physical setup step, not a daily setting.

## Solution

Move zone configuration into the bridge setup wizard as a required step. Retain a "Reconfigure" entry point in Settings for users who rearrange their lights.

---

## SetupView — Step 4: Configure Zones

Appears inline after the user selects an entertainment group (existing Step 3). The channel count is known at this point, so the UI is tailored immediately.

### Layout

```
┌─ Configure Zones ──────────────────────────────┐
│  [ Sides ]  [ Top + Sides ]  [ Surround ]       │  ← filtered by channelCount
│                                                  │
│  Channel 0   [ Left        ▼ ]                  │
│  Channel 1   [ Right       ▼ ]                  │
│  Channel 2   [ Top         ▼ ]                  │
│  …                                               │
│                                                  │
│  ┌──────────────────────────────────────────┐   │
│  │            (zone preview)                │   │  ← 16:9, static triangles
│  └──────────────────────────────────────────┘   │
│                                                  │
│  ✓ Done                                          │
└──────────────────────────────────────────────────┘
```

### Behavior by channel count

| Channels | Preset buttons | Notes |
|----------|---------------|-------|
| 1        | None          | Single picker defaults to Full Screen |
| 2        | Sides         | |
| 3        | Sides, Top + Sides | |
| 4+       | Sides, Top + Sides, Surround | 5+ channels: first 4 get presets, extras default to Full Screen; view scrolls |

- Selecting a preset updates the pickers and preview instantly
- "Done" writes ZoneConfig to UserDefaults and completes setup

### 4+ channel users

Users with 4+ channels are treated as advanced users. No extra hand-holding required — pickers and preview are sufficient.

---

## SettingsView — Screen Sync section

Collapses the current full zone config section to three rows:

```
┌─ Screen Sync ──────────────────────────────────┐
│  Source Display   [ Built-in Retina ▼ ]        │  ← multi-monitor only
│  ─────────────────────────────────────────────  │
│  Zone Layout      [ Reconfigure… ]             │  ← opens sheet
│  ─────────────────────────────────────────────  │
│  Edge Bias   Uniform ──●────────── Edge         │
└────────────────────────────────────────────────┘
```

- "Reconfigure…" opens a sheet containing the same `ZoneSetupStep` view
- Sheet has a "Done" button that saves and dismisses
- Edge bias stays in Settings only — not in onboarding

---

## Implementation

### New component: `ZoneSetupStep`

Extracted as a standalone view used in both:
- `SetupView` (inline, after group selection)
- `SettingsView` (as a sheet via "Reconfigure…")

Takes `channelCount: Int` and a `ZoneConfig` binding. Owns the preset buttons, pickers, and preview canvas.

### Files changed

- `SpillAura/UI/SetupView.swift` — add Step 4 after group selection
- `SpillAura/UI/SettingsView.swift` — replace zone config section with Reconfigure row + sheet
- `SpillAura/UI/ZoneSetupStep.swift` — new shared component
