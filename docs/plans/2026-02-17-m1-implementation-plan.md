# SpillAura M1 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Set up the Xcode project, create all file stubs, implement bridge discovery and pairing, and verify you can read the entertainment configuration from the Hue bridge.

**Architecture:** MenuBar + main window SwiftUI app with no App Sandbox. Bridge discovery uses mDNS (NWBrowser) with a manual IP fallback. Credentials (bridgeIP, username, clientKey) are stored in Keychain. After pairing, the app fetches the entertainment configuration and stores the group ID for M2.

**Tech Stack:** Swift 5.9+, SwiftUI, Network.framework (NWBrowser), URLSession, Security.framework (Keychain)

---

## Task 0: Xcode First-Run Setup

This is a manual step — no code yet.

**Step 1: Launch Xcode**

Open Xcode from `/Applications/Xcode.app`. Accept the license agreement when prompted.

**Step 2: Install additional components**

Xcode will prompt to install additional components (simulators, command line tools). Click Install and wait for it to finish. This can take several minutes.

**Step 3: Verify command line tools**

```bash
xcode-select --print-path
```
Expected output: `/Applications/Xcode.app/Contents/Developer`

If it prints something else, run:
```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

**Step 4: Accept the license via command line (if needed)**

```bash
sudo xcodebuild -license accept
```

---

## Task 1: Create the Xcode Project

**Step 1: Create a new project in Xcode**

1. Open Xcode → File → New → Project
2. Choose **macOS** → **App**
3. Fill in:
   - Product Name: `SpillAura`
   - Team: your Apple ID (or None for now)
   - Organization Identifier: `com.yourname` (anything works for now)
   - Interface: **SwiftUI**
   - Language: **Swift**
   - ☐ Uncheck "Include Tests" (we'll add them manually)
4. Save to: `/Users/brandon/projects/SpillAura/`

**Step 2: Remove App Sandbox entitlement**

In the Project Navigator, find `SpillAura.entitlements`. Select it. Remove the `App Sandbox` key (set it to NO or delete the row entirely).

Alternatively, open the file and make sure it looks like this:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
</dict>
</plist>
```

**Step 3: Set deployment target**

In Project settings → General → Minimum Deployments → set to **macOS 14.0**.

**Step 4: Initialize git**

```bash
cd /Users/brandon/projects/SpillAura
git init
echo "*.DS_Store\n.build/\nDerivedData/\n*.xcuserstate\n*.xcbkptlist" > .gitignore
git add .
git commit -m "init: create Xcode project"
```

---

## Task 2: Create the Project File Structure

Xcode creates a flat structure by default. We need to reorganize into the folder groups defined in the design.

**Step 1: Create folder groups in Xcode**

In the Project Navigator, right-click the `SpillAura` folder → New Group. Create these groups:
- `App`
- `Sync`
- `Sources` (rename if Xcode uses this name already — use `LightSources`)
- `Hue`
- `Vibes`
- `Config`
- `UI`

**Step 2: Move the generated files**

Move `SpillAuraApp.swift` and `ContentView.swift` into the `App` group.

**Step 3: Create stub files**

For each file below, right-click the group → New File → Swift File. Name it exactly as shown. Replace the contents with the stub shown.

---

### App/SpillAuraApp.swift

```swift
import SwiftUI

@main
struct SpillAuraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var syncController = SyncController()

    var body: some Scene {
        MenuBarExtra("SpillAura", systemImage: "light.max") {
            MenuBarView()
                .environmentObject(syncController)
        }
        .menuBarExtraStyle(.window)

        Window("SpillAura", id: "main") {
            MainWindow()
                .environmentObject(syncController)
        }
    }
}
```

---

### App/AppDelegate.swift

```swift
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Sleep/wake observers added in M5
    }
}
```

---

### Sync/SyncController.swift

```swift
import Foundation

@MainActor
class SyncController: ObservableObject {
    @Published var isRunning = false
    @Published var connectionStatus: ConnectionStatus = .disconnected

    enum ConnectionStatus {
        case disconnected, connecting, streaming, error(String)
    }
}
```

---

### Sync/SyncActor.swift

```swift
import Foundation

// Stub — implemented in M2
actor SyncActor {
}
```

---

### Sync/LightSource.swift

```swift
import Foundation

// Stub — implemented in M3
protocol LightSource {
}
```

---

### LightSources/StaticColorSource.swift

```swift
import Foundation

// Stub — implemented in M3
```

---

### LightSources/PaletteSource.swift

```swift
import Foundation

// Stub — implemented in M3
```

---

### Hue/HueBridgeDiscovery.swift

```swift
import Foundation
import Network

// Implemented in Task 3
```

---

### Hue/HueBridgeAuth.swift

```swift
import Foundation

// Implemented in Task 4
```

---

### Hue/EntertainmentSession.swift

```swift
import Foundation

// Stub — implemented in M2
```

---

### Hue/ColorPacketBuilder.swift

```swift
import Foundation

// Stub — implemented in M2
```

---

### Vibes/Vibe.swift

```swift
import Foundation
import SwiftUI

struct Vibe: Codable, Identifiable {
    let id: UUID
    var name: String
    var type: VibeType
    var palette: [CodableColor]
    var speed: Double
    var pattern: VibePattern
    var channelOffset: Double
}

enum VibeType: String, Codable { case `static`, dynamic }
enum VibePattern: String, Codable { case cycle, bounce, random }

// SwiftUI Color is not Codable — use this wrapper
struct CodableColor: Codable {
    var red: Double
    var green: Double
    var blue: Double
}
```

---

### Vibes/VibeLibrary.swift

```swift
import Foundation

// Stub — implemented in M3
class VibeLibrary: ObservableObject {
    @Published var vibes: [Vibe] = []
}
```

---

### Vibes/BuiltinVibes.swift

```swift
import Foundation

// Stub — implemented in M3
```

---

### Config/ZoneConfig.swift

```swift
import Foundation
import CoreGraphics

struct Zone {
    let lightID: String
    let channelID: UInt8
    let region: CGRect  // normalized 0.0–1.0
}
```

---

### Config/AppSettings.swift

```swift
import Foundation

class AppSettings: ObservableObject {
    @Published var showMenuBarIcon: Bool {
        didSet { UserDefaults.standard.set(showMenuBarIcon, forKey: "showMenuBarIcon") }
    }
    @Published var showDockIcon: Bool {
        didSet { UserDefaults.standard.set(showDockIcon, forKey: "showDockIcon") }
    }

    init() {
        self.showMenuBarIcon = UserDefaults.standard.object(forKey: "showMenuBarIcon") as? Bool ?? true
        self.showDockIcon = UserDefaults.standard.object(forKey: "showDockIcon") as? Bool ?? true
    }
}
```

---

### UI/MenuBarView.swift

```swift
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var syncController: SyncController

    var body: some View {
        VStack(spacing: 12) {
            Text("SpillAura")
                .font(.headline)
            Text("M1 — Setup only")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 260)
    }
}
```

---

### UI/MainWindow.swift

```swift
import SwiftUI

struct MainWindow: View {
    @EnvironmentObject var syncController: SyncController

    var body: some View {
        SetupView()
    }
}
```

---

### UI/SetupView.swift

```swift
import SwiftUI

// Implemented in Task 4
struct SetupView: View {
    var body: some View {
        Text("Setup — coming in Task 4")
            .frame(width: 500, height: 400)
    }
}
```

---

### UI/VibeEditor.swift

```swift
import SwiftUI

// Stub — implemented in M3
struct VibeEditor: View {
    var body: some View {
        Text("Vibe Editor — coming in M3")
    }
}
```

---

**Step 4: Build and verify it compiles**

Press `Cmd+B` in Xcode. Expected: Build Succeeded with 0 errors.

**Step 5: Commit**

```bash
cd /Users/brandon/projects/SpillAura
git add -A
git commit -m "feat: add project skeleton with file stubs"
```

---

## Task 3: Bridge Discovery

**Files:**
- Modify: `Hue/HueBridgeDiscovery.swift`

**What this does:** Uses mDNS to find the bridge IP automatically. If mDNS fails (some networks block it), the user can type the IP manually. The discovered/entered IP is stored so auth can use it.

**Step 1: Implement HueBridgeDiscovery.swift**

```swift
import Foundation
import Network
import Combine

@MainActor
class HueBridgeDiscovery: ObservableObject {
    @Published var discoveredBridges: [DiscoveredBridge] = []
    @Published var isSearching = false

    private var browser: NWBrowser?

    struct DiscoveredBridge: Identifiable, Equatable {
        let id = UUID()
        let name: String
        let host: String
    }

    func startDiscovery() {
        isSearching = true
        discoveredBridges = []

        let params = NWParameters()
        params.includePeerToPeer = false

        browser = NWBrowser(
            for: .bonjourWithTXTRecord(type: "_hue._tcp", domain: "local."),
            using: params
        )

        browser?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed(let error):
                print("mDNS browser failed: \(error)")
                Task { @MainActor [weak self] in
                    self?.isSearching = false
                }
            default:
                break
            }
        }

        browser?.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor [weak self] in
                self?.handleResults(results)
            }
        }

        browser?.start(queue: .main)
    }

    func stopDiscovery() {
        browser?.cancel()
        browser = nil
        isSearching = false
    }

    private func handleResults(_ results: Set<NWBrowser.Result>) {
        var bridges: [DiscoveredBridge] = []
        for result in results {
            if case let .service(name, _, _, _) = result.endpoint {
                // Resolve the service to get the IP address
                let endpoint = result.endpoint
                resolveEndpoint(endpoint, name: name) { [weak self] host in
                    if let host {
                        Task { @MainActor [weak self] in
                            self?.discoveredBridges.append(
                                DiscoveredBridge(name: name, host: host)
                            )
                        }
                    }
                }
            }
        }
        _ = bridges // suppress warning
    }

    private func resolveEndpoint(_ endpoint: NWEndpoint, name: String, completion: @escaping (String?) -> Void) {
        let connection = NWConnection(to: endpoint, using: .tcp)
        connection.stateUpdateHandler = { state in
            if case .ready = state {
                // Extract IP from the remote endpoint
                if let remote = connection.currentPath?.remoteEndpoint,
                   case let .hostPort(host, _) = remote {
                    let hostString = "\(host)"
                    // Strip the interface suffix if present (e.g. "192.168.1.1%en0")
                    let cleanHost = hostString.components(separatedBy: "%").first ?? hostString
                    completion(cleanHost)
                } else {
                    completion(nil)
                }
                connection.cancel()
            } else if case .failed = state {
                completion(nil)
                connection.cancel()
            }
        }
        connection.start(queue: .global())
    }
}
```

**Step 2: Build and verify it compiles**

Press `Cmd+B`. Expected: Build Succeeded.

**Step 3: Commit**

```bash
git add Hue/HueBridgeDiscovery.swift
git commit -m "feat: add mDNS bridge discovery"
```

---

## Task 4: Bridge Auth + Keychain Storage

**Files:**
- Modify: `Hue/HueBridgeAuth.swift`

**What this does:** POSTs to the bridge with the link button pressed to get `username` and `clientKey`. Stores them in Keychain. Also includes a helper to read them back.

**Step 1: Implement HueBridgeAuth.swift**

```swift
import Foundation
import Security

struct BridgeCredentials {
    let bridgeIP: String
    let username: String    // used as REST API header: hue-application-key
    let clientKey: String   // hex string, PSK for DTLS in M2
}

enum AuthError: LocalizedError {
    case linkButtonNotPressed
    case networkError(Error)
    case unexpectedResponse(String)

    var errorDescription: String? {
        switch self {
        case .linkButtonNotPressed:
            return "Press the link button on your Hue bridge, then try again."
        case .networkError(let err):
            return "Network error: \(err.localizedDescription)"
        case .unexpectedResponse(let detail):
            return "Unexpected response: \(detail)"
        }
    }
}

class HueBridgeAuth {

    // MARK: - Pairing

    func pair(bridgeIP: String) async throws -> BridgeCredentials {
        let url = URL(string: "http://\(bridgeIP)/api")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "devicetype": "SpillAura#mac",
            "generateclientkey": true
        ] as [String: AnyEncodable])

        let (data, _): (Data, URLResponse)
        do {
            (data, _) = try await URLSession.shared.data(for: request)
        } catch {
            throw AuthError.networkError(error)
        }

        // Response is an array: [{"success": {"username": "...", "clientkey": "..."}}]
        // or [{"error": {"type": 101, "description": "link button not pressed"}}]
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = json.first else {
            throw AuthError.unexpectedResponse(String(data: data, encoding: .utf8) ?? "empty")
        }

        if let error = first["error"] as? [String: Any],
           let type_ = error["type"] as? Int, type_ == 101 {
            throw AuthError.linkButtonNotPressed
        }

        guard let success = first["success"] as? [String: Any],
              let username = success["username"] as? String,
              let clientKey = success["clientkey"] as? String else {
            throw AuthError.unexpectedResponse(String(data: data, encoding: .utf8) ?? "empty")
        }

        let credentials = BridgeCredentials(
            bridgeIP: bridgeIP,
            username: username,
            clientKey: clientKey
        )

        try saveToKeychain(credentials)
        return credentials
    }

    // MARK: - Keychain

    func saveToKeychain(_ credentials: BridgeCredentials) throws {
        let value = "\(credentials.bridgeIP)|\(credentials.username)|\(credentials.clientKey)"
        let data = value.data(using: .utf8)!

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "com.spillaura.bridge",
            kSecAttrAccount: "credentials",
            kSecValueData: data
        ]

        SecItemDelete(query as CFDictionary)  // remove old entry if exists
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    func loadFromKeychain() -> BridgeCredentials? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "com.spillaura.bridge",
            kSecAttrAccount: "credentials",
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else { return nil }

        let parts = value.components(separatedBy: "|")
        guard parts.count == 3 else { return nil }
        return BridgeCredentials(bridgeIP: parts[0], username: parts[1], clientKey: parts[2])
    }
}

// Helper to encode mixed-type dictionaries
struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void
    init<T: Encodable>(_ value: T) { _encode = value.encode }
    func encode(to encoder: Encoder) throws { try _encode(encoder) }
}

extension Dictionary: Encodable where Key == String, Value == AnyEncodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)
        for (key, value) in self {
            try container.encode(value, forKey: StringCodingKey(key))
        }
    }
}

struct StringCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
```

**Note:** The `AnyEncodable` workaround is needed because Swift can't encode `[String: Any]` directly with `JSONEncoder`. The above handles encoding a mix of `String` and `Bool` values.

**Step 2: Build and verify it compiles**

Press `Cmd+B`. Expected: Build Succeeded.

**Step 3: Commit**

```bash
git add Hue/HueBridgeAuth.swift
git commit -m "feat: add bridge pairing and keychain storage"
```

---

## Task 5: Setup UI (Bridge Pairing Flow)

**Files:**
- Modify: `UI/SetupView.swift`

**What this does:** Guides the user through: (1) discovering or entering the bridge IP, (2) pressing the link button and pairing, (3) showing success with the bridge IP and username.

**Step 1: Implement SetupView.swift**

```swift
import SwiftUI

struct SetupView: View {
    @StateObject private var discovery = HueBridgeDiscovery()
    @State private var auth = HueBridgeAuth()

    @State private var selectedBridgeIP: String = ""
    @State private var manualIP: String = ""
    @State private var pairingState: PairingState = .idle
    @State private var credentials: BridgeCredentials? = nil
    @State private var errorMessage: String? = nil

    enum PairingState {
        case idle, waitingForButton, pairing, success, failed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Connect to Hue Bridge")
                .font(.title2)
                .bold()

            // Discovery section
            GroupBox("Step 1: Find Your Bridge") {
                VStack(alignment: .leading, spacing: 8) {
                    if discovery.isSearching {
                        HStack {
                            ProgressView().scaleEffect(0.7)
                            Text("Searching for bridges…")
                                .foregroundStyle(.secondary)
                        }
                    }

                    ForEach(discovery.discoveredBridges) { bridge in
                        Button(action: { selectedBridgeIP = bridge.host }) {
                            HStack {
                                Image(systemName: selectedBridgeIP == bridge.host ? "checkmark.circle.fill" : "circle")
                                VStack(alignment: .leading) {
                                    Text(bridge.name).bold()
                                    Text(bridge.host).foregroundStyle(.secondary).font(.caption)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    Divider()

                    HStack {
                        TextField("Manual IP (e.g. 192.168.1.100)", text: $manualIP)
                            .textFieldStyle(.roundedBorder)
                        Button("Use") {
                            selectedBridgeIP = manualIP
                        }
                        .disabled(manualIP.isEmpty)
                    }

                    Button(discovery.isSearching ? "Searching…" : "Search Again") {
                        discovery.startDiscovery()
                    }
                    .disabled(discovery.isSearching)
                }
                .padding(4)
            }

            // Pairing section
            GroupBox("Step 2: Pair") {
                VStack(alignment: .leading, spacing: 8) {
                    if selectedBridgeIP.isEmpty {
                        Text("Select a bridge above first.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Bridge: \(selectedBridgeIP)")
                            .foregroundStyle(.secondary)

                        switch pairingState {
                        case .idle:
                            Button("Start Pairing") {
                                pairingState = .waitingForButton
                            }
                        case .waitingForButton:
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Press the physical button on your Hue bridge now, then tap Pair.")
                                    .foregroundStyle(.primary)
                                HStack {
                                    Button("Pair") {
                                        Task { await pairWithBridge() }
                                    }
                                    Button("Cancel") { pairingState = .idle }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        case .pairing:
                            HStack {
                                ProgressView().scaleEffect(0.7)
                                Text("Pairing…")
                            }
                        case .success:
                            if let creds = credentials {
                                Label("Paired successfully!", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("Username: \(creds.username.prefix(12))…")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        case .failed:
                            VStack(alignment: .leading, spacing: 4) {
                                Label(errorMessage ?? "Pairing failed.", systemImage: "xmark.circle.fill")
                                    .foregroundStyle(.red)
                                Button("Try Again") { pairingState = .idle }
                            }
                        }
                    }
                }
                .padding(4)
            }

            Spacer()
        }
        .padding(24)
        .frame(width: 480, height: 460)
        .onAppear {
            discovery.startDiscovery()
            // Pre-populate if already paired
            credentials = auth.loadFromKeychain()
            if credentials != nil { pairingState = .success }
        }
        .onDisappear {
            discovery.stopDiscovery()
        }
    }

    private func pairWithBridge() async {
        pairingState = .pairing
        do {
            credentials = try await auth.pair(bridgeIP: selectedBridgeIP)
            pairingState = .success
        } catch let error as AuthError {
            errorMessage = error.errorDescription
            pairingState = .failed
        } catch {
            errorMessage = error.localizedDescription
            pairingState = .failed
        }
    }
}
```

**Step 2: Build and verify it compiles**

Press `Cmd+B`. Expected: Build Succeeded.

**Step 3: Test it manually**

Run the app (`Cmd+R`). The main window should appear with the setup UI. It will immediately start searching for bridges. You should see your bridge appear (or enter the IP manually). Press the link button on the bridge then tap Pair. Expected: "Paired successfully!" with your username prefix shown.

**Step 4: Commit**

```bash
git add UI/SetupView.swift
git commit -m "feat: add bridge pairing UI with mDNS discovery"
```

---

## Task 6: Fetch and Store Entertainment Configuration

**What this does:** After pairing, fetch the entertainment configuration from the bridge to get the group ID. This group ID is needed in M2 to activate the entertainment session. Store it in `AppSettings`.

**Step 1: Add entertainment config fetch to HueBridgeAuth.swift**

Add this struct and method to `HueBridgeAuth`:

```swift
struct EntertainmentGroup: Identifiable {
    let id: String       // group resource ID (UUID string)
    let name: String
    let channelCount: Int
}

extension HueBridgeAuth {
    func fetchEntertainmentGroups(credentials: BridgeCredentials) async throws -> [EntertainmentGroup] {
        let url = URL(string: "https://\(credentials.bridgeIP)/clip/v2/resource/entertainment_configuration")!
        var request = URLRequest(url: url)
        request.setValue(credentials.username, forHTTPHeaderField: "hue-application-key")

        // The bridge uses a self-signed cert — we need to bypass cert validation for local connections
        let session = URLSession(configuration: .default, delegate: SelfSignedCertDelegate(), delegateQueue: nil)
        let (data, _) = try await session.data(for: request)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let resources = json["data"] as? [[String: Any]] else {
            throw AuthError.unexpectedResponse(String(data: data, encoding: .utf8) ?? "empty")
        }

        return resources.compactMap { resource in
            guard let id = resource["id"] as? String,
                  let metadata = resource["metadata"] as? [String: Any],
                  let name = metadata["name"] as? String,
                  let channels = resource["channels"] as? [[String: Any]] else { return nil }
            return EntertainmentGroup(id: id, name: name, channelCount: channels.count)
        }
    }
}

// Bypasses certificate validation for the Hue bridge's self-signed cert
private class SelfSignedCertDelegate: NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
```

**Step 2: Add entertainmentGroupID to AppSettings.swift**

```swift
@Published var entertainmentGroupID: String? {
    didSet { UserDefaults.standard.set(entertainmentGroupID, forKey: "entertainmentGroupID") }
}
```

In `init()`:
```swift
self.entertainmentGroupID = UserDefaults.standard.string(forKey: "entertainmentGroupID")
```

**Step 3: Add entertainment group selection to SetupView.swift**

After the pairing `GroupBox`, add a third section that appears once pairing succeeds:

```swift
if pairingState == .success, let creds = credentials {
    GroupBox("Step 3: Select Entertainment Group") {
        EntertainmentGroupPicker(credentials: creds, auth: auth)
            .padding(4)
    }
}
```

Create a small subview:

```swift
struct EntertainmentGroupPicker: View {
    let credentials: BridgeCredentials
    let auth: HueBridgeAuth
    @State private var groups: [HueBridgeAuth.EntertainmentGroup] = []
    @State private var selectedGroupID: String? = nil
    @State private var isLoading = true
    @State private var errorMessage: String? = nil
    @AppStorage("entertainmentGroupID") private var storedGroupID: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isLoading {
                HStack {
                    ProgressView().scaleEffect(0.7)
                    Text("Fetching entertainment groups…")
                        .foregroundStyle(.secondary)
                }
            } else if let error = errorMessage {
                Text(error).foregroundStyle(.red)
            } else if groups.isEmpty {
                Text("No entertainment groups found. Create one in the Hue app.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(groups) { group in
                    Button(action: {
                        selectedGroupID = group.id
                        storedGroupID = group.id
                    }) {
                        HStack {
                            Image(systemName: selectedGroupID == group.id ? "checkmark.circle.fill" : "circle")
                            VStack(alignment: .leading) {
                                Text(group.name).bold()
                                Text("\(group.channelCount) channels · ID: \(group.id.prefix(8))…")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .task {
            do {
                groups = try await auth.fetchEntertainmentGroups(credentials: credentials)
                selectedGroupID = storedGroupID.isEmpty ? groups.first?.id : storedGroupID
                isLoading = false
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
}
```

**Step 4: Build and test manually**

Press `Cmd+B`. Then `Cmd+R`. After pairing, the third section should appear and load your entertainment groups from the bridge.

**Verification:** In Xcode console you should see no errors. In the UI you should see your entertainment group name and channel count.

**Step 5: Commit**

```bash
git add Hue/HueBridgeAuth.swift Config/AppSettings.swift UI/SetupView.swift
git commit -m "feat: fetch and store entertainment configuration from bridge"
```

---

## M1 Complete

At the end of M1 you have:
- ✓ Compiling Xcode project with full file structure
- ✓ mDNS bridge discovery + manual IP fallback
- ✓ Bridge pairing with link button flow
- ✓ Credentials stored in Keychain
- ✓ Entertainment group fetched and stored (group ID ready for M2)

Next: **M2 — DTLS proof-of-concept, send a static color to all lights**
