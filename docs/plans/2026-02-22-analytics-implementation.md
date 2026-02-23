# Analytics & Telemetry Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add TelemetryDeck-backed analytics with session reliability, streaming health, and usage signals.

**Architecture:** Single `Analytics.swift` wrapper with enum-based signals. All call sites go through `Analytics.send()` — no direct TelemetryDeck imports elsewhere. Opt-out via `StorageKey.analyticsEnabled` defaulting to `true`.

**Tech Stack:** TelemetryDeck Swift SDK (SPM), Swift, SwiftUI

**Design Doc:** `docs/plans/2026-02-22-analytics-design.md`

**Important Context:**
- Project uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` — all types are MainActor by default
- Xcode uses `PBXFileSystemSynchronizedRootGroup` — new files in `SpillAura/` are auto-discovered, no manual pbxproj file references needed
- TelemetryDeck SDK has no `terminate()` API — opt-out is handled by guarding in `Analytics.send()`
- TelemetryDeck auto-detects DEBUG builds and marks those signals as test data

---

### Task 1: Add TelemetryDeck SPM dependency to Xcode project

**Files:**
- Modify: `SpillAura.xcodeproj/project.pbxproj`

**Step 1: Add remote package reference**

In `project.pbxproj`, add a new section after `/* End XCLocalSwiftPackageReference section */`:

```
/* Begin XCRemoteSwiftPackageReference section */
		CA6A0B302F50A00000EE4898 /* XCRemoteSwiftPackageReference "SwiftSDK" */ = {
			isa = XCRemoteSwiftPackageReference;
			repositoryURL = "https://github.com/TelemetryDeck/SwiftSDK";
			requirement = {
				kind = upToNextMajorVersion;
				minimumVersion = 2.0.0;
			};
		};
/* End XCRemoteSwiftPackageReference section */
```

**Step 2: Add package to project's packageReferences**

Change:
```
			packageReferences = (
				CA5B0B2A2F45900000EE4898 /* XCLocalSwiftPackageReference "." */,
			);
```

To:
```
			packageReferences = (
				CA5B0B2A2F45900000EE4898 /* XCLocalSwiftPackageReference "." */,
				CA6A0B302F50A00000EE4898 /* XCRemoteSwiftPackageReference "SwiftSDK" */,
			);
```

**Step 3: Add product dependency + build file for app target**

In `/* Begin PBXBuildFile section */`, add:
```
		CA6A0B312F50A00000EE4898 /* TelemetryDeck in Frameworks */ = {isa = PBXBuildFile; productRef = CA6A0B322F50A00000EE4898 /* TelemetryDeck */; };
```

In `/* Begin XCSwiftPackageProductDependency section */`, add:
```
		CA6A0B322F50A00000EE4898 /* TelemetryDeck */ = {
			isa = XCSwiftPackageProductDependency;
			package = CA6A0B302F50A00000EE4898 /* XCRemoteSwiftPackageReference "SwiftSDK" */;
			productName = TelemetryDeck;
		};
```

**Step 4: Link TelemetryDeck in app target's frameworks phase**

In the SpillAura target's `PBXFrameworksBuildPhase` (ID `CA5B0B082F45794800EE4898`), add to files array:
```
				CA6A0B312F50A00000EE4898 /* TelemetryDeck in Frameworks */,
```

In the SpillAura target (`CA5B0B0A2F45794800EE4898`), add to `packageProductDependencies`:
```
				CA6A0B322F50A00000EE4898 /* TelemetryDeck */,
```

**Step 5: Resolve packages and verify build**

Run:
```bash
xcodebuild -resolvePackageDependencies -project SpillAura.xcodeproj -scheme SpillAura
xcodebuild build -project SpillAura.xcodeproj -scheme SpillAura -destination 'platform=macOS' -quiet
```

Expected: Build succeeds with TelemetryDeck resolved.

**Step 6: Commit**

```bash
git add SpillAura.xcodeproj/project.pbxproj
git commit -m "add TelemetryDeck Swift SDK dependency"
```

---

### Task 2: Create Analytics.swift and StorageKey entry

**Files:**
- Create: `SpillAura/Analytics/Analytics.swift`
- Modify: `SpillAura/Config/StorageKey.swift` (line 21, add new key)

**Step 1: Add analyticsEnabled to StorageKey**

In `SpillAura/Config/StorageKey.swift`, add after line 20 (`static let launchWindowHidden`):

```swift
    static let analyticsEnabled = "analyticsEnabled"
```

**Step 2: Create Analytics.swift**

Create directory `SpillAura/Analytics/` and file `SpillAura/Analytics/Analytics.swift`:

```swift
import Foundation
import TelemetryDeck

enum AnalyticsSignal {
    // Session Reliability
    case entertainmentSessionStarted(channelCount: Int, groupId: String)
    case entertainmentSessionEnded(durationSeconds: Int, reconnectCount: Int)
    case entertainmentSessionFailed(errorReason: String, phase: String)
    case entertainmentSessionReconnect(attemptNumber: Int, previousDurationSeconds: Int)
    case bridgeDiscoveryCompleted(method: String, durationMs: Int)
    case appResumedFromSleep(sessionRecovered: Bool)

    // Streaming Health
    case streamingModeActivated(mode: String, detail: String)
    case streamingModeSwitched(fromMode: String, toMode: String)
    case screenCaptureStarted(displayId: UInt32, zoneCount: Int, edgeBias: Double)
    case screenCaptureFailed(errorDescription: String)

    // Usage
    case auraSelected(auraName: String, isBuiltin: Bool)
    case brightnessChanged(value: Double)
    case settingsChanged(setting: String, newValue: String)

    var name: String {
        switch self {
        case .entertainmentSessionStarted: return "entertainmentSessionStarted"
        case .entertainmentSessionEnded: return "entertainmentSessionEnded"
        case .entertainmentSessionFailed: return "entertainmentSessionFailed"
        case .entertainmentSessionReconnect: return "entertainmentSessionReconnect"
        case .bridgeDiscoveryCompleted: return "bridgeDiscoveryCompleted"
        case .appResumedFromSleep: return "appResumedFromSleep"
        case .streamingModeActivated: return "streamingModeActivated"
        case .streamingModeSwitched: return "streamingModeSwitched"
        case .screenCaptureStarted: return "screenCaptureStarted"
        case .screenCaptureFailed: return "screenCaptureFailed"
        case .auraSelected: return "auraSelected"
        case .brightnessChanged: return "brightnessChanged"
        case .settingsChanged: return "settingsChanged"
        }
    }

    var parameters: [String: String] {
        switch self {
        case .entertainmentSessionStarted(let channelCount, let groupId):
            return ["channelCount": "\(channelCount)", "groupId": groupId]
        case .entertainmentSessionEnded(let durationSeconds, let reconnectCount):
            return ["durationSeconds": "\(durationSeconds)", "reconnectCount": "\(reconnectCount)"]
        case .entertainmentSessionFailed(let errorReason, let phase):
            return ["errorReason": errorReason, "phase": phase]
        case .entertainmentSessionReconnect(let attemptNumber, let previousDurationSeconds):
            return ["attemptNumber": "\(attemptNumber)", "previousDurationSeconds": "\(previousDurationSeconds)"]
        case .bridgeDiscoveryCompleted(let method, let durationMs):
            return ["method": method, "durationMs": "\(durationMs)"]
        case .appResumedFromSleep(let sessionRecovered):
            return ["sessionRecovered": "\(sessionRecovered)"]
        case .streamingModeActivated(let mode, let detail):
            return ["mode": mode, "detail": detail]
        case .streamingModeSwitched(let fromMode, let toMode):
            return ["fromMode": fromMode, "toMode": toMode]
        case .screenCaptureStarted(let displayId, let zoneCount, let edgeBias):
            return ["displayId": "\(displayId)", "zoneCount": "\(zoneCount)", "edgeBias": String(format: "%.1f", edgeBias)]
        case .screenCaptureFailed(let errorDescription):
            return ["errorDescription": errorDescription]
        case .auraSelected(let auraName, let isBuiltin):
            return ["auraName": auraName, "isBuiltin": "\(isBuiltin)"]
        case .brightnessChanged(let value):
            return ["value": String(format: "%.2f", value)]
        case .settingsChanged(let setting, let newValue):
            return ["setting": setting, "newValue": newValue]
        }
    }
}

enum Analytics {
    static func send(_ signal: AnalyticsSignal) {
        guard UserDefaults.standard.bool(forKey: StorageKey.analyticsEnabled) else { return }
        TelemetryDeck.signal(signal.name, parameters: signal.parameters)
    }

    static func initialize() {
        guard UserDefaults.standard.bool(forKey: StorageKey.analyticsEnabled) else { return }
        let config = TelemetryDeck.Config(appID: "YOUR-TELEMETRYDECK-APP-ID")
        TelemetryDeck.initialize(config: config)
    }
}
```

> **Note:** Replace `"YOUR-TELEMETRYDECK-APP-ID"` with the real app ID from https://dashboard.telemetrydeck.com after creating the app.

**Step 3: Handle first-launch default**

`UserDefaults.standard.bool(forKey:)` returns `false` for unset keys. Since we want analytics ON by default, register the default. This goes in `Analytics.initialize()`. Update the method:

```swift
    static func initialize() {
        UserDefaults.standard.register(defaults: [StorageKey.analyticsEnabled: true])
        guard UserDefaults.standard.bool(forKey: StorageKey.analyticsEnabled) else { return }
        let config = TelemetryDeck.Config(appID: "YOUR-TELEMETRYDECK-APP-ID")
        TelemetryDeck.initialize(config: config)
    }
```

**Step 4: Build to verify compilation**

Run:
```bash
xcodebuild build -project SpillAura.xcodeproj -scheme SpillAura -destination 'platform=macOS' -quiet
```

Expected: Build succeeds.

**Step 5: Commit**

```bash
git add SpillAura/Analytics/Analytics.swift SpillAura/Config/StorageKey.swift
git commit -m "add Analytics wrapper and analyticsEnabled storage key"
```

---

### Task 3: Initialize TelemetryDeck at app launch

**Files:**
- Modify: `SpillAura/App/SpillAuraApp.swift`

**Step 1: Add init() to SpillAuraApp**

In `SpillAura/App/SpillAuraApp.swift`, add an `init()` method to the struct:

```swift
@main
struct SpillAuraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var syncController = SyncController()
    @StateObject private var auraLibrary = AuraLibrary()
    @AppStorage(StorageKey.showMenuBarIcon) private var showMenuBarIcon = true

    init() {
        Analytics.initialize()
    }

    var body: some Scene {
```

**Step 2: Build to verify**

Run:
```bash
xcodebuild build -project SpillAura.xcodeproj -scheme SpillAura -destination 'platform=macOS' -quiet
```

Expected: Build succeeds.

**Step 3: Commit**

```bash
git add SpillAura/App/SpillAuraApp.swift
git commit -m "initialize TelemetryDeck analytics on app launch"
```

---

### Task 4: Add session reliability signals to EntertainmentSession

**Files:**
- Modify: `SpillAura/Hue/EntertainmentSession.swift`

The session needs to track timing for `durationSeconds` and reconnect count for `entertainmentSessionEnded`.

**Step 1: Add tracking properties**

After line 33 (`private static let maxReconnectAttempts = 3`), add:

```swift
    private var sessionStartDate: Date?
    private var totalReconnects: Int = 0
```

**Step 2: Send `entertainmentSessionStarted` when DTLS connects**

In `handleConnectionState()`, in the `.ready` case (around line 228), after `state = .streaming` (line 232), add:

```swift
            sessionStartDate = Date()
            Analytics.send(.entertainmentSessionStarted(
                channelCount: channelCount,
                groupId: groupID
            ))
```

**Step 3: Send `entertainmentSessionFailed` on failure**

In `handleConnectionState()`, in the `.failed` case, after the `if reconnectAttempts < Self.maxReconnectAttempts` block — specifically at the `else` branch (around line 244), before `state = .deactivating`, add:

```swift
                let elapsed = sessionStartDate.map { Int(Date().timeIntervalSince($0)) } ?? 0
                Analytics.send(.entertainmentSessionFailed(
                    errorReason: error.localizedDescription,
                    phase: "streaming"
                ))
```

Also in the `activate()` method's catch block (around line 86), before `self.state = .idle`, add:

```swift
                Analytics.send(.entertainmentSessionFailed(
                    errorReason: error.localizedDescription,
                    phase: "activating"
                ))
```

**Step 4: Send `entertainmentSessionReconnect` on reconnect**

In `handleConnectionState()`, in the `.failed` case, inside the `if reconnectAttempts < Self.maxReconnectAttempts` branch (around line 240), after `state = .reconnecting(attempt: reconnectAttempts)`, add:

```swift
                totalReconnects += 1
                let elapsed = sessionStartDate.map { Int(Date().timeIntervalSince($0)) } ?? 0
                Analytics.send(.entertainmentSessionReconnect(
                    attemptNumber: reconnectAttempts,
                    previousDurationSeconds: elapsed
                ))
```

**Step 5: Send `entertainmentSessionEnded` on clean teardown**

In `deactivateREST()` (around line 105), before `self.state = .idle` (line 113), add:

```swift
            let duration = self.sessionStartDate.map { Int(Date().timeIntervalSince($0)) } ?? 0
            Analytics.send(.entertainmentSessionEnded(
                durationSeconds: duration,
                reconnectCount: self.totalReconnects
            ))
            self.sessionStartDate = nil
            self.totalReconnects = 0
```

**Step 6: Build to verify**

Run:
```bash
xcodebuild build -project SpillAura.xcodeproj -scheme SpillAura -destination 'platform=macOS' -quiet
```

Expected: Build succeeds.

**Step 7: Commit**

```bash
git add SpillAura/Hue/EntertainmentSession.swift
git commit -m "add session reliability analytics signals"
```

---

### Task 5: Add streaming and usage signals to SyncController

**Files:**
- Modify: `SpillAura/Sync/SyncController.swift`

**Step 1: Send `streamingModeActivated` when streaming starts**

In `startAura()` (around line 138), after `activeSource = PaletteSource(aura: aura)` (line 140), add:

```swift
        Analytics.send(.streamingModeActivated(mode: "aura", detail: aura.name))
```

In `startScreenSync()` (around line 161), after `activeSource = ScreenCaptureSource(...)` (line 163), add:

```swift
        Analytics.send(.streamingModeActivated(mode: "screenSync", detail: ""))
```

**Step 2: Send `streamingModeSwitched` on hot-swap**

In `startAura()`, detect hot-swap: before the existing code at line 138, check if already streaming:

```swift
    func startAura(_ aura: Aura) {
        if connectionStatus == .streaming {
            let fromMode = activeAura != nil ? "aura" : "screenSync"
            Analytics.send(.streamingModeSwitched(fromMode: fromMode, toMode: "aura"))
        }
        activeAura = aura
```

In `startScreenSync()`, similarly before existing code:

```swift
    func startScreenSync() {
        if connectionStatus == .streaming {
            let fromMode = activeAura != nil ? "aura" : "screenSync"
            Analytics.send(.streamingModeSwitched(fromMode: fromMode, toMode: "screenSync"))
        }
        activeAura = nil
```

**Step 3: Send `appResumedFromSleep`**

In the `didWakeNotification` handler (around line 93), inside the Task, after `wasStreamingBeforeSleep = false`:

```swift
                Analytics.send(.appResumedFromSleep(sessionRecovered: true))
```

Also add an else-branch for when the app wasn't streaming before sleep:

The current code already guards `guard let self, wasStreamingBeforeSleep else { return }`. The signal should only fire when we attempt recovery, so the existing placement is correct — just add after `wasStreamingBeforeSleep = false`.

**Step 4: Send `auraSelected`**

In `startAura()`, after `activeAura = aura`, add:

```swift
        Analytics.send(.auraSelected(auraName: aura.name, isBuiltin: BuiltinAuras.isBuiltin(aura.id)))
```

> **Note:** This requires checking if `BuiltinAuras` has an `isBuiltin(_:)` method or similar. If not, check `AuraLibrary.isBuiltin(id:)` — it exists per the test file. Since `startAura` doesn't have access to the library, use `BuiltinAuras.all.contains { $0.id == aura.id }`.

**Step 5: Send `brightnessChanged`**

In the `brightness` property's `didSet` (around line 49), add:

```swift
            Analytics.send(.brightnessChanged(value: Double(brightness)))
```

**Step 6: Build to verify**

Run:
```bash
xcodebuild build -project SpillAura.xcodeproj -scheme SpillAura -destination 'platform=macOS' -quiet
```

Expected: Build succeeds.

**Step 7: Commit**

```bash
git add SpillAura/Sync/SyncController.swift
git commit -m "add streaming and usage analytics signals"
```

---

### Task 6: Add discovery and screen capture signals

**Files:**
- Modify: `SpillAura/Hue/HueBridgeDiscovery.swift`
- Modify: `SpillAura/LightSources/ScreenCaptureSource.swift`

**Step 1: Add discovery timing and signal**

In `HueBridgeDiscovery`, add a start time property after `private var resolvingServices` (line 10):

```swift
    private var discoveryStartDate: Date?
```

In `startDiscovery()` (line 18), after `isSearching = true`, add:

```swift
        discoveryStartDate = Date()
```

In the `netServiceDidResolveAddress` delegate (line 60), inside the `Task { @MainActor in` block, after `self.discoveredBridges.append(bridge)` (line 70), add:

```swift
                let elapsed = self.discoveryStartDate.map { Int(Date().timeIntervalSince($0) * 1000) } ?? 0
                Analytics.send(.bridgeDiscoveryCompleted(method: "mdns", durationMs: elapsed))
```

**Step 2: Add screen capture signals**

In `ScreenCaptureSource.swift`, in `startCapture()` (line 63):

After `stream = newStream` (line 90), add:

```swift
            Analytics.send(.screenCaptureStarted(
                displayId: targetID,
                zoneCount: config.zones.count,
                edgeBias: config.edgeBias
            ))
```

In the catch block (line 91), after the existing print, add:

```swift
            Analytics.send(.screenCaptureFailed(errorDescription: error.localizedDescription))
```

> **Note:** `startCapture()` is an async function called from MainActor context, so `Analytics.send()` (MainActor) is callable directly.

**Step 3: Build to verify**

Run:
```bash
xcodebuild build -project SpillAura.xcodeproj -scheme SpillAura -destination 'platform=macOS' -quiet
```

Expected: Build succeeds.

**Step 4: Commit**

```bash
git add SpillAura/Hue/HueBridgeDiscovery.swift SpillAura/LightSources/ScreenCaptureSource.swift
git commit -m "add discovery and screen capture analytics signals"
```

---

### Task 7: Add privacy toggle to SettingsView

**Files:**
- Modify: `SpillAura/UI/SettingsView.swift`

**Step 1: Add Privacy section to SettingsView**

In `SettingsView.swift`, after the "App" `GroupBox` closing brace (around line 59), add a new section:

```swift
                // MARK: Privacy
                GroupBox("Privacy") {
                    VStack(alignment: .leading, spacing: 8) {
                        AnalyticsToggleRow()
                    }
                    .padding(4)
                }
```

**Step 2: Create AnalyticsToggleRow**

Add at the bottom of `SettingsView.swift`, before the closing of the file:

```swift
// MARK: - AnalyticsToggleRow

private struct AnalyticsToggleRow: View {
    @AppStorage(StorageKey.analyticsEnabled) private var analyticsEnabled = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Send anonymous analytics", isOn: $analyticsEnabled)
                .help("Help improve SpillAura by sharing anonymous usage data. No personal information is collected.")
            Text("Helps improve SpillAura. No personal data is collected.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
```

> **Note:** When the user toggles OFF, `Analytics.send()` will immediately stop sending because it checks `UserDefaults` on every call. When toggled ON, signals will send but TelemetryDeck may not be initialized (if the app launched with it off). To handle this edge case, re-initialize in the toggle's onChange. Add:

```swift
            Toggle("Send anonymous analytics", isOn: $analyticsEnabled)
                .help("Help improve SpillAura by sharing anonymous usage data. No personal information is collected.")
                .onChange(of: analyticsEnabled) { _, enabled in
                    if enabled { Analytics.initialize() }
                }
```

**Step 3: Add settingsChanged signal for responsiveness**

In `SyncController.swift`, in the `responsiveness` property's `didSet` (around line 39), add:

```swift
            Analytics.send(.settingsChanged(setting: "responsiveness", newValue: responsiveness.rawValue))
```

**Step 4: Build to verify**

Run:
```bash
xcodebuild build -project SpillAura.xcodeproj -scheme SpillAura -destination 'platform=macOS' -quiet
```

Expected: Build succeeds.

**Step 5: Commit**

```bash
git add SpillAura/UI/SettingsView.swift SpillAura/Sync/SyncController.swift
git commit -m "add privacy toggle and settings change signal"
```

---

### Task 8: Run full test suite and verify

**Step 1: Run all tests**

Run:
```bash
xcodebuild test -project SpillAura.xcodeproj -scheme SpillAura -destination 'platform=macOS' 2>&1 | grep -E '(Test Suite|Executed|FAILED|passed|failed)'
```

Expected: All 48 tests pass, 0 failures. No existing tests should break.

**Step 2: Verify clean build**

Run:
```bash
xcodebuild build -project SpillAura.xcodeproj -scheme SpillAura -destination 'platform=macOS' -quiet 2>&1
```

Expected: Build succeeds with only pre-existing Sendable warnings (from NetService).

**Step 3: Final commit if any cleanup needed**

If any adjustments were made during verification, commit them.
