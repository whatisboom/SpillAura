# Sleep/Wake Handling — Design

**Date:** 2026-02-21
**Scope:** M5 Polish — `SyncController.swift` only

---

## Problem

When the Mac sleeps, the network interface goes down and the DTLS UDP session silently dies. The app needs to stop gracefully on sleep and resume automatically on wake — provided the user was streaming when the Mac slept (not if they had already stopped manually).

## Decision

**Always resume on wake if streaming at sleep time.** No new preference. Sleeping is a system event, not a user decision about streaming. If the user explicitly stopped before sleeping, `wasStreamingBeforeSleep` will be `false` and nothing happens on wake.

Sleep handling is already implemented (`willSleepNotification → stop()`). Only wake handling is new.

---

## Design

### State

Add one private flag to `SyncController`:

```swift
private var wasStreamingBeforeSleep = false
```

### Sleep observer (update existing)

Capture streaming state before stopping:

```swift
wasStreamingBeforeSleep = connectionStatus == .streaming
stop()
```

### Wake observer (new)

Register `NSWorkspace.didWakeNotification` in `init()`. On wake:

```swift
guard wasStreamingBeforeSleep else { return }
wasStreamingBeforeSleep = false
resumeLastSession()
```

### `resumeLastSession()` (extracted helper)

Extract the resume logic from `autoStartIfNeeded()` into a shared private method:

```swift
private func resumeLastSession() {
    let mode = UserDefaults.standard.string(forKey: "lastMode").flatMap(SyncMode.init)
    if mode == .screen {
        startScreenSync()
    } else if mode == .aura,
              let data = UserDefaults.standard.data(forKey: "lastAura"),
              let aura = try? JSONDecoder().decode(Aura.self, from: data) {
        startAura(aura)
    }
}
```

`autoStartIfNeeded()` calls `resumeLastSession()` after its guard checks.

---

## Files Changed

- `SpillAura/Sync/SyncController.swift` — only file

## No new UI, no new preferences.
