# UI Redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the tab-based main window with a focused control surface (mode switcher → content area → brightness → bottom bar) and a separate Settings window opened via a gear icon.

**Architecture:** `MainWindow` becomes the primary light-control view; a new `VibeControlView` renders the scrollable vibe browser; a new `SettingsView` handles bridge pairing (reusing `HueBridgeDiscovery` / `HueBridgeAuth` / `EntertainmentGroupPicker`) and app preferences. `SpillAuraApp` gains a `Window("Settings")` scene. `ScreenSyncView` and `MenuBarView` are untouched.

**Tech Stack:** SwiftUI, ServiceManagement (SMAppService for login item), existing `SyncController`, `VibeLibrary`, `HueBridgeAuth`, `HueBridgeDiscovery`, `EntertainmentGroupPicker`.

---

## Task 1: Create `VibeControlView.swift`

**Files:**
- Create: `SpillAura/SpillAura/UI/VibeControlView.swift`

### Step 1: Create the file

```swift
import SwiftUI

/// Scrollable vibe browser for the main window's Vibe mode.
/// While stopped: tapping a card updates `selectedVibe` binding for the Start button.
/// While streaming: tapping a card hot-swaps immediately.
struct VibeControlView: View {
    @EnvironmentObject var syncController: SyncController
    @EnvironmentObject var vibeLibrary: VibeLibrary
    @Binding var selectedVibe: Vibe?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(vibeLibrary.vibes) { vibe in
                    VibeCard(
                        vibe: vibe,
                        isSelected: syncController.connectionStatus == .streaming
                            ? syncController.activeVibe?.id == vibe.id
                            : selectedVibe?.id == vibe.id
                    )
                    .onTapGesture {
                        if syncController.connectionStatus == .streaming {
                            syncController.startVibe(vibe)
                        } else {
                            selectedVibe = vibe
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .onAppear {
            if selectedVibe == nil { selectedVibe = vibeLibrary.vibes.first }
        }
    }
}

// MARK: - VibeCard

private struct VibeCard: View {
    let vibe: Vibe
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            swatchStrip
            VStack(alignment: .leading, spacing: 2) {
                Text(vibe.name)
                    .fontWeight(.medium)
                Text(speedLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected
            ? Color.accentColor.opacity(0.12)
            : Color(nsColor: .controlBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    isSelected ? Color.accentColor : Color.secondary.opacity(0.2),
                    lineWidth: isSelected ? 1.5 : 0.5
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
    }

    private var swatchStrip: some View {
        HStack(spacing: 2) {
            ForEach(Array(vibe.palette.enumerated()), id: \.offset) { _, c in
                Rectangle()
                    .fill(Color(red: c.red, green: c.green, blue: c.blue))
            }
        }
        .frame(width: 52, height: 32)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var speedLabel: String {
        switch vibe.type {
        case .static: return "Static"
        case .dynamic:
            switch vibe.speed {
            case ..<2:  return "Very fast"
            case ..<5:  return "Fast"
            case ..<10: return "Medium"
            case ..<20: return "Slow"
            default:    return "Very slow"
            }
        }
    }
}
```

### Step 2: Build

```bash
xcodebuild -project SpillAura/SpillAura.xcodeproj -scheme SpillAura \
  -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```

Expected: `** BUILD SUCCEEDED **`

### Step 3: Commit

```bash
git add SpillAura/SpillAura/UI/VibeControlView.swift
git commit -m "feat: add VibeControlView with scrollable vibe cards and swatch strips"
```

---

## Task 2: Create `SettingsView.swift`

**Files:**
- Create: `SpillAura/SpillAura/UI/SettingsView.swift`

`EntertainmentGroupPicker` already exists in `SetupView.swift` and is referenced here without changes.

### Step 1: Create the file

```swift
import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @State private var auth = HueBridgeAuth()
    @State private var credentials: BridgeCredentials? = nil
    @State private var showPairingFlow: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Settings")
                    .font(.title2)
                    .fontWeight(.semibold)

                // MARK: Bridge
                GroupBox("Bridge") {
                    VStack(alignment: .leading, spacing: 12) {
                        if let creds = credentials, !showPairingFlow {
                            HStack {
                                Label(creds.bridgeIP, systemImage: "network")
                                Spacer()
                                Button("Re-pair") { showPairingFlow = true }
                                    .buttonStyle(.borderless)
                            }
                            Divider()
                            EntertainmentGroupPicker(credentials: creds, auth: auth)
                        } else {
                            BridgePairingSection(
                                onPaired: { newCreds in
                                    credentials = newCreds
                                    showPairingFlow = false
                                },
                                onCancel: credentials != nil ? { showPairingFlow = false } : nil
                            )
                        }
                    }
                    .padding(4)
                }

                // MARK: App
                GroupBox("App") {
                    LoginItemRow()
                        .padding(4)
                }
            }
            .padding(24)
        }
        .frame(width: 420, minHeight: 400)
        .onAppear { credentials = auth.loadFromKeychain() }
    }
}

// MARK: - BridgePairingSection

private struct BridgePairingSection: View {
    let onPaired: (BridgeCredentials) -> Void
    let onCancel: (() -> Void)?

    @StateObject private var discovery = HueBridgeDiscovery()
    @State private var auth = HueBridgeAuth()
    @State private var selectedIP: String = ""
    @State private var manualIP: String = ""
    @State private var pairingState: PairingState = .idle
    @State private var errorMessage: String? = nil

    enum PairingState { case idle, waitingForButton, pairing, success, failed }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if discovery.isSearching {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.7)
                    Text("Searching for bridges…")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            }

            ForEach(discovery.discoveredBridges) { bridge in
                Button {
                    selectedIP = bridge.host
                } label: {
                    HStack {
                        Image(systemName: selectedIP == bridge.host
                              ? "checkmark.circle.fill" : "circle")
                        VStack(alignment: .leading, spacing: 1) {
                            Text(bridge.name).font(.callout).fontWeight(.medium)
                            Text(bridge.host).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            HStack {
                TextField("Manual IP (e.g. 192.168.1.100)", text: $manualIP)
                    .textFieldStyle(.roundedBorder)
                Button("Use") { selectedIP = manualIP }
                    .disabled(manualIP.isEmpty)
            }

            Button(discovery.isSearching ? "Searching…" : "Search Again") {
                discovery.startDiscovery()
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .disabled(discovery.isSearching)

            Divider()

            switch pairingState {
            case .idle:
                HStack {
                    if !selectedIP.isEmpty {
                        Text(selectedIP).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let cancel = onCancel {
                        Button("Cancel", action: cancel)
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                    }
                    Button("Start Pairing") { pairingState = .waitingForButton }
                        .disabled(selectedIP.isEmpty)
                }

            case .waitingForButton:
                VStack(alignment: .leading, spacing: 8) {
                    Text("Press the button on your Hue bridge, then tap Pair.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Pair") { Task { await pair() } }
                        Button("Cancel") { pairingState = .idle }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                    }
                }

            case .pairing:
                HStack {
                    ProgressView().scaleEffect(0.7)
                    Text("Pairing…").font(.callout)
                }

            case .success:
                Label("Paired successfully!", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)

            case .failed:
                VStack(alignment: .leading, spacing: 4) {
                    Label(errorMessage ?? "Pairing failed.", systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                    Button("Try Again") { pairingState = .idle }
                }
            }
        }
        .onAppear {
            discovery.startDiscovery()
        }
        .onDisappear { discovery.stopDiscovery() }
    }

    private func pair() async {
        pairingState = .pairing
        do {
            let creds = try await auth.pair(bridgeIP: selectedIP)
            onPaired(creds)
        } catch let error as AuthError {
            errorMessage = error.errorDescription
            pairingState = .failed
        } catch {
            errorMessage = error.localizedDescription
            pairingState = .failed
        }
    }
}

// MARK: - LoginItemRow

private struct LoginItemRow: View {
    @State private var isEnabled: Bool = false

    var body: some View {
        Toggle("Launch at login", isOn: $isEnabled)
            .onChange(of: isEnabled) { _, enabled in
                do {
                    if enabled {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    // Revert if registration fails (e.g., unsigned dev build)
                    isEnabled = !enabled
                }
            }
            .onAppear {
                isEnabled = SMAppService.mainApp.status == .enabled
            }
    }
}
```

### Step 2: Build

```bash
xcodebuild -project SpillAura/SpillAura.xcodeproj -scheme SpillAura \
  -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```

Expected: `** BUILD SUCCEEDED **`

### Step 3: Commit

```bash
git add SpillAura/SpillAura/UI/SettingsView.swift
git commit -m "feat: add SettingsView with bridge pairing flow and launch-at-login toggle"
```

---

## Task 3: Rewrite `MainWindow.swift`

**Files:**
- Modify: `SpillAura/SpillAura/UI/MainWindow.swift`

### Step 1: Replace the entire file

```swift
import SwiftUI

struct MainWindow: View {
    @EnvironmentObject var syncController: SyncController
    @EnvironmentObject var vibeLibrary: VibeLibrary
    @Environment(\.openWindow) private var openWindow

    @State private var mode: Mode = .vibe
    @State private var selectedVibe: Vibe? = nil

    private enum Mode: String, CaseIterable {
        case vibe = "Vibe"
        case screen = "Screen"
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Divider()

            contentArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            brightnessRow
                .padding(.horizontal, 20)
                .padding(.vertical, 10)

            Divider()

            bottomBar
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        .frame(minWidth: 480, minHeight: 520)
    }

    // MARK: - Top Bar

    @ViewBuilder
    private var topBar: some View {
        HStack {
            Picker("", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 160)
            .onChange(of: mode) { _, _ in
                if syncController.connectionStatus != .disconnected {
                    syncController.stop()
                }
            }

            Spacer()

            statusBadge
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch syncController.connectionStatus {
        case .disconnected:
            Label("Disconnected", systemImage: "circle")
                .foregroundStyle(.secondary)
                .font(.caption)

        case .connecting:
            HStack(spacing: 5) {
                ProgressView().scaleEffect(0.55)
                Text("Connecting…").font(.caption).foregroundStyle(.secondary)
            }

        case .streaming:
            Label("Streaming", systemImage: "circle.fill")
                .foregroundStyle(.green)
                .font(.caption)

        case .error(let msg):
            Label(msg, systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .font(.caption)
                .lineLimit(2)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentArea: some View {
        switch mode {
        case .vibe:
            VibeControlView(selectedVibe: $selectedVibe)
        case .screen:
            ScreenSyncView()
        }
    }

    // MARK: - Brightness

    private var brightnessRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "sun.min").foregroundStyle(.secondary)
            Slider(value: $syncController.brightness, in: 0...1)
            Image(systemName: "sun.max").foregroundStyle(.secondary)
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            Button {
                openWindow(id: "settings")
            } label: {
                Image(systemName: "gear").imageScale(.large)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()

            if syncController.connectionStatus == .disconnected {
                Button("Start") {
                    switch mode {
                    case .vibe:
                        let vibe = selectedVibe ?? vibeLibrary.vibes.first
                        if let v = vibe { syncController.startVibe(v) }
                    case .screen:
                        syncController.startScreenSync()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(mode == .vibe && vibeLibrary.vibes.isEmpty)
            } else {
                Button("Stop") { syncController.stop() }
                    .buttonStyle(.bordered)
            }
        }
    }
}
```

### Step 2: Build

```bash
xcodebuild -project SpillAura/SpillAura.xcodeproj -scheme SpillAura \
  -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```

Expected: `** BUILD SUCCEEDED **`

### Step 3: Commit

```bash
git add SpillAura/SpillAura/UI/MainWindow.swift
git commit -m "feat: rewrite MainWindow as focused control surface with mode switcher and bottom bar"
```

---

## Task 4: Update `SpillAuraApp.swift`

**Files:**
- Modify: `SpillAura/SpillAura/App/SpillAuraApp.swift`
- Modify: `SpillAura/SpillAura/UI/MenuBarView.swift` (button label only)

### Step 1: Replace `SpillAuraApp.swift`

Add a `Window("Settings", id: "settings")` scene and rename the MenuBar button.

```swift
import SwiftUI

@main
struct SpillAuraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var syncController = SyncController()
    @StateObject private var vibeLibrary = VibeLibrary()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(syncController)
                .environmentObject(vibeLibrary)
        } label: {
            Image(systemName: syncController.menuBarIcon)
                .accessibilityLabel("SpillAura")
        }
        .menuBarExtraStyle(.window)

        WindowGroup("SpillAura", id: "main") {
            MainWindow()
                .environmentObject(syncController)
                .environmentObject(vibeLibrary)
        }

        Window("Settings", id: "settings") {
            SettingsView()
        }
        .windowResizability(.contentSize)
    }
}
```

### Step 2: Update "Open Settings" button label in `MenuBarView.swift`

Find in `MenuBarView.swift`:
```swift
Button("Open Settings") { openWindow(id: "main") }
```

Replace with:
```swift
Button("Open") { openWindow(id: "main") }
```

### Step 3: Build

```bash
xcodebuild -project SpillAura/SpillAura.xcodeproj -scheme SpillAura \
  -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```

Expected: `** BUILD SUCCEEDED **`

### Step 4: Commit

```bash
git add SpillAura/SpillAura/App/SpillAuraApp.swift \
        SpillAura/SpillAura/UI/MenuBarView.swift
git commit -m "feat: add Settings window scene and rename MenuBar open button"
```

---

## Task 5: End-to-end verification

### Step 1: Build and launch

```bash
xcodebuild -project SpillAura/SpillAura.xcodeproj -scheme SpillAura \
  -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
open $(find ~/Library/Developer/Xcode/DerivedData -name "SpillAura.app" \
  -path "*/Debug/*" | head -1)
```

### Step 2: Verify main window layout

- Open the main window (click "Open" in the MenuBar popover)
- Confirm top bar: `[Vibe] [Screen]` segmented control left, status badge right
- Confirm vibe cards list in the content area with color swatches and names
- Confirm brightness slider row above the bottom bar
- Confirm gear icon bottom-left, Start button bottom-right

### Step 3: Verify vibe selection

- Click a vibe card → card gets highlighted with accent border
- Click Start → status changes to Connecting → Streaming
- While streaming: click a different vibe card → lights change immediately (hot-swap)
- Click Stop → status returns to Disconnected

### Step 4: Verify Screen mode

- Switch to Screen tab → ScreenSyncView appears (zone pickers, preview)
- Start/Stop buttons work correctly
- Switching tabs while streaming stops the session

### Step 5: Verify Settings window

- Click the gear icon (bottom-left of main window) → Settings window opens as a separate window
- Bridge section shows current bridge IP + Re-pair button if already paired
- Click Re-pair → pairing flow appears inline (bridge discovery list, manual IP, Start Pairing)
- Cancel → returns to bridge info view
- Launch at login toggle is present

### Step 6: Verify MenuBar still works

- MenuBar popover: Vibe/Screen tabs, Start/Stop, brightness slider, "Open" button
- "Open" button brings the main window to front

### Step 7: Vibe mode regression

- Confirm all 8 built-in vibes appear in the list
- Confirm color swatches match each vibe's palette colors
