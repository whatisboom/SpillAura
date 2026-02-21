# Launch Settings Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add "Start streaming automatically on launch" and "Launch with window hidden" settings, with smart session resume (last vibe or screen sync) and a Disco first-launch default.

**Architecture:** `SyncController` persists the last session (mode + full vibe JSON) in UserDefaults on every `startVibe`/`startScreenSync` call, then auto-starts from `init()` via a deferred `Task`. AppDelegate closes the main window if the "launch hidden" toggle is on. Two new toggles appear in the existing "App" GroupBox in SettingsView.

**Tech Stack:** SwiftUI `@AppStorage`, `UserDefaults`, `NSApplicationDelegate`, `JSONEncoder/Decoder`, existing `BuiltinVibes.disco` as first-launch default.

---

### Task 1: Persist last session in SyncController

**Files:**
- Modify: `SpillAura/SpillAura/Sync/SyncController.swift`

**Step 1: Add session-persistence writes to `startVibe()` and `startScreenSync()`**

In `SyncController.startVibe(_:)` (currently ~line 90), add after `activeSource = PaletteSource(vibe: vibe)`:

```swift
UserDefaults.standard.set("vibe", forKey: "lastMode")
if let data = try? JSONEncoder().encode(vibe) {
    UserDefaults.standard.set(data, forKey: "lastVibe")
}
```

In `SyncController.startScreenSync()` (currently ~line 107), add after `activeSource = ScreenCaptureSource(...)`:

```swift
UserDefaults.standard.set("screen", forKey: "lastMode")
```

**Step 2: Build — confirm no errors**

Run: `xcodebuild -project SpillAura/SpillAura.xcodeproj -scheme SpillAura -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"`

Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add SpillAura/SpillAura/Sync/SyncController.swift
git commit -m "feat: persist last mode and vibe to UserDefaults on start"
```

---

### Task 2: Add autoStartIfNeeded() and trigger from init

**Files:**
- Modify: `SpillAura/SpillAura/Sync/SyncController.swift`

**Step 1: Add `hasAutoStarted` private flag and `autoStartIfNeeded()` method**

Add directly after the `private var isIdentifySession` declaration (~line 82):

```swift
private var hasAutoStarted = false
```

Add a new private method in the `// MARK: - Private` section:

```swift
private func autoStartIfNeeded() {
    guard !hasAutoStarted else { return }
    hasAutoStarted = true
    guard UserDefaults.standard.bool(forKey: "autoStartOnLaunch") else { return }

    let mode = UserDefaults.standard.string(forKey: "lastMode")

    if mode == "screen" {
        startScreenSync()
    } else if mode == "vibe",
              let data = UserDefaults.standard.data(forKey: "lastVibe"),
              let vibe = try? JSONDecoder().decode(Vibe.self, from: data) {
        startVibe(vibe)
    } else {
        // First launch — no saved session. Start with Disco.
        startVibe(BuiltinVibes.disco)
    }
}
```

**Step 2: Trigger from `init()` with a deferred Task**

At the end of `SyncController.init()`, add:

```swift
Task { @MainActor [weak self] in
    // Brief yield so SwiftUI finishes scene setup before we touch Keychain/session.
    try? await Task.sleep(for: .milliseconds(200))
    self?.autoStartIfNeeded()
}
```

**Step 3: Build**

Run: `xcodebuild -project SpillAura/SpillAura.xcodeproj -scheme SpillAura -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"`

Expected: `** BUILD SUCCEEDED **`

**Step 4: Commit**

```bash
git add SpillAura/SpillAura/Sync/SyncController.swift
git commit -m "feat: auto-start streaming on launch with last session resume"
```

---

### Task 3: "Launch with window hidden" in AppDelegate

**Files:**
- Modify: `SpillAura/SpillAura/App/AppDelegate.swift`

**Step 1: Implement `applicationDidFinishLaunching`**

Replace the empty `AppDelegate` with:

```swift
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard UserDefaults.standard.bool(forKey: "launchWindowHidden") else { return }
        // SwiftUI restores windows before this fires, so close them async.
        DispatchQueue.main.async {
            NSApp.windows
                .filter { $0.title == "SpillAura" }
                .forEach { $0.close() }
        }
    }
}
```

**Step 2: Build**

Run: `xcodebuild -project SpillAura/SpillAura.xcodeproj -scheme SpillAura -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"`

Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add SpillAura/SpillAura/App/AppDelegate.swift
git commit -m "feat: close main window on launch when launchWindowHidden is set"
```

---

### Task 4: Add settings toggles to SettingsView

**Files:**
- Modify: `SpillAura/SpillAura/UI/SettingsView.swift`

**Step 1: Replace the "App" GroupBox content**

The current "App" GroupBox contains only `LoginItemRow()`. Replace the entire GroupBox with:

```swift
// MARK: App
GroupBox("App") {
    VStack(alignment: .leading, spacing: 8) {
        LoginItemRow()
        Divider()
        AutoStartRow()
        LaunchHiddenRow()
    }
    .padding(4)
}
```

**Step 2: Add `AutoStartRow` and `LaunchHiddenRow` private structs**

Add after the closing brace of `LoginItemRow`:

```swift
// MARK: - AutoStartRow

private struct AutoStartRow: View {
    @AppStorage("autoStartOnLaunch") private var autoStartOnLaunch = false

    var body: some View {
        Toggle("Start streaming automatically on launch", isOn: $autoStartOnLaunch)
    }
}

// MARK: - LaunchHiddenRow

private struct LaunchHiddenRow: View {
    @AppStorage("launchWindowHidden") private var launchWindowHidden = false

    var body: some View {
        Toggle("Launch with window hidden", isOn: $launchWindowHidden)
    }
}
```

**Step 3: Build**

Run: `xcodebuild -project SpillAura/SpillAura.xcodeproj -scheme SpillAura -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"`

Expected: `** BUILD SUCCEEDED **`

**Step 4: Commit**

```bash
git add SpillAura/SpillAura/UI/SettingsView.swift
git commit -m "feat: add auto-start and launch-hidden toggles to Settings"
```

---

## Verification

1. Open Settings → App → enable "Start streaming automatically on launch"
2. Quit the app (no vibe started yet — this is effectively first launch)
3. Relaunch → Disco should start automatically within ~200ms
4. Stop → switch to a different vibe → quit → relaunch → that vibe resumes
5. Switch to Screen Sync → quit → relaunch → Screen Sync resumes
6. Enable "Launch with window hidden" → quit → relaunch → no main window appears (menu bar icon only)
7. Disable "Launch with window hidden" → quit → relaunch → main window appears as expected
