# Analytics & Diagnostics Design

## Overview

Add structured telemetry and diagnostics to SpillAura using [TelemetryDeck](https://telemetrydeck.com/) as the cloud backend. All signals flow through a single `Analytics.swift` wrapper — the rest of the codebase never imports TelemetryDeck directly.

**Goals:**
- Session reliability tracking (DTLS connection lifecycle, reconnects, failures)
- Streaming health monitoring (capture errors, mode switches, sleep/wake recovery)
- Basic usage analytics (aura selection, brightness, settings changes)

**Non-goals:**
- Local log files or split logging pipeline
- Consent banners or first-launch prompts
- VPN/network edge case tracking

## Architecture

```
┌─────────────────────────────────────────────┐
│  SyncController / EntertainmentSession / UI │
│         calls Analytics.send(...)           │
└──────────────────┬──────────────────────────┘
                   │
         ┌─────────▼──────────┐
         │   Analytics.swift  │  ← single wrapper
         │  (enum of signals) │
         └─────────┬──────────┘
                   │
         ┌─────────▼──────────┐
         │  TelemetryDeck SDK │  ← SPM dependency
         │  (batches & sends) │
         └─────────┬──────────┘
                   │
              TelemetryDeck Cloud
```

**Key decisions:**
- Enum-based signals: type-safe, discoverable, no raw strings scattered across files
- Opt-out via `StorageKey.analyticsEnabled` (defaults to `true`)
- No wrapper protocol — YAGNI; swap providers by refactoring one file

## Dependency

TelemetryDeck Swift SDK via SPM: `https://github.com/TelemetryDeck/SwiftSDK`

## Signal Definitions

```swift
enum AnalyticsSignal {
    // Session Reliability
    case entertainmentSessionStarted(channelCount: Int, groupId: String)
    case entertainmentSessionEnded(durationSeconds: Int, reconnectCount: Int)
    case entertainmentSessionFailed(errorReason: String, phase: String)
    case entertainmentSessionReconnect(attemptNumber: Int, previousDurationSeconds: Int)
    case bridgeDiscoveryCompleted(method: String, durationMs: Int)
    case appResumedFromSleep

    // Streaming Health
    case streamingModeActivated(mode: String, detail: String)
    case streamingModeSwitched(fromMode: String, toMode: String)
    case screenCaptureStarted(displayId: UInt32, zoneCount: Int, edgeBias: Double)
    case screenCaptureFailed(errorDescription: String)

    // Usage
    case auraSelected(auraName: String, isBuiltin: Bool)
    case brightnessChanged(value: Double)
    case settingsChanged(setting: String, newValue: String)
}
```

Each case maps to a TelemetryDeck signal name (e.g. `"entertainmentSessionStarted"`) with associated values becoming the `[String: String]` parameters dictionary.

## Integration Points

| Signal | Source File | Trigger Location |
|---|---|---|
| `entertainmentSessionStarted` | `EntertainmentSession.swift` | DTLS `stateUpdateHandler` → `.ready` |
| `entertainmentSessionEnded` | `EntertainmentSession.swift` | `deactivate()` completion |
| `entertainmentSessionFailed` | `EntertainmentSession.swift` | `stateUpdateHandler` → `.failed` / timeout |
| `entertainmentSessionReconnect` | `EntertainmentSession.swift` | `reconnect()` entry |
| `bridgeDiscoveryCompleted` | `HueBridgeDiscovery.swift` | `netServiceDidResolveAddress` / manual IP success |
| `appResumedFromSleep` | `SyncController.swift` | `NSWorkspace.didWakeNotification` handler |
| `streamingModeActivated` | `SyncController.swift` | `startStreaming()` |
| `streamingModeSwitched` | `SyncController.swift` | mode change while streaming |
| `screenCaptureStarted` | `ScreenCaptureSource.swift` | `startCapture()` success |
| `screenCaptureFailed` | `ScreenCaptureSource.swift` | `startCapture()` error |
| `auraSelected` | `SyncController.swift` | `selectedAura` didSet |
| `brightnessChanged` | `SyncController.swift` | `brightness` didSet |
| `settingsChanged` | `SettingsView.swift` | relevant control change handlers |

## Opt-Out

- New `StorageKey.analyticsEnabled` (Bool, defaults to `true`)
- Toggle in `SettingsView.swift` under a "Privacy" section:
  - Label: "Send Anonymous Analytics"
  - Description: "Helps improve SpillAura. No personal data is collected."
- On toggle off: `Analytics.send()` guard returns immediately, no further signals
- On toggle on: re-initialize TelemetryDeck

## Initialization

In `SpillAuraApp.swift` `init()`:
1. Read `StorageKey.analyticsEnabled`
2. If enabled: `TelemetryDeck.initialize(config:)` with app ID
3. If disabled: skip — no SDK calls, no network

## New Files

- `SpillAura/Analytics/Analytics.swift` — signal enum + `send()` wrapper

## Modified Files

- `Package.swift` — add TelemetryDeck SPM dependency
- `SpillAura/Config/StorageKey.swift` — add `analyticsEnabled` key
- `SpillAura/App/SpillAuraApp.swift` — TelemetryDeck init
- `SpillAura/Hue/EntertainmentSession.swift` — session lifecycle signals
- `SpillAura/Hue/HueBridgeDiscovery.swift` — discovery signal
- `SpillAura/Sync/SyncController.swift` — streaming + usage signals
- `SpillAura/LightSources/ScreenCaptureSource.swift` — capture signals
- `SpillAura/UI/SettingsView.swift` — privacy toggle + settings signals
