# SpillAura M2 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Establish DTLS connection to Hue bridge and send a static color to all lights.

**Architecture:** EntertainmentSession manages the REST activation + DTLS state machine. ColorPacketBuilder produces UDP packets. SyncActor sends them. MenuBarView provides a test button.

**Tech Stack:** Network.framework (NWConnection with DTLS), URLSession (REST activation), Security.framework

---

## Prerequisites

Before starting, confirm all of the following are true:

- M1 is complete and the app builds cleanly
- You can run the app, pair with the bridge, and see the entertainment group in Setup
- The following values are persisted from M1:
  - `bridgeIP`, `username`, `clientKey` — in Keychain via `HueBridgeAuth.loadFromKeychain()`
  - `entertainmentGroupID` — in `UserDefaults` key `"entertainmentGroupID"` (set via `@AppStorage`)
- Xcode 26 is your build tool; it requires explicit `import Combine` for `@Published` / `ObservableObject`

If any of these are not true, complete M1 first.

---

## M2 File Map

```
SpillAura/SpillAura/
├── Config/
│   └── AppSettings.swift          ← Task 0: add entertainmentChannelCount
├── Hue/
│   ├── ColorPacketBuilder.swift   ← Task 1: implement packet builder
│   └── EntertainmentSession.swift ← Task 2: implement DTLS state machine
├── Sync/
│   ├── SyncActor.swift            ← Task 3: add sendStaticColor
│   └── SyncController.swift       ← Task 4: add startStaticColor/stop
└── UI/
    └── MenuBarView.swift          ← Task 5: add "Send Red" / "Stop" buttons
```

All absolute paths below are rooted at:
`/Users/brandon/projects/SpillAura/SpillAura/SpillAura/`

---

## Task 0: Store Channel Count in AppSettings

**File:** `Config/AppSettings.swift`

**Why:** The Entertainment API packet must include one channel entry per channel in the group. The channel count was fetched and displayed in M1 via `HueBridgeAuth.EntertainmentGroup.channelCount`, but it was never persisted. We need it available at runtime without re-fetching. We also need to update `EntertainmentGroupPicker` in `SetupView.swift` to save it when a group is selected.

**Step 1: Add `entertainmentChannelCount` to AppSettings**

Open `/Users/brandon/projects/SpillAura/SpillAura/SpillAura/Config/AppSettings.swift`.

Replace the entire file with:

```swift
import Foundation
import Combine

class AppSettings: ObservableObject {
    @Published var showMenuBarIcon: Bool {
        didSet { UserDefaults.standard.set(showMenuBarIcon, forKey: "showMenuBarIcon") }
    }
    @Published var showDockIcon: Bool {
        didSet { UserDefaults.standard.set(showDockIcon, forKey: "showDockIcon") }
    }
    @Published var entertainmentGroupID: String? {
        didSet { UserDefaults.standard.set(entertainmentGroupID, forKey: "entertainmentGroupID") }
    }
    @Published var entertainmentChannelCount: Int {
        didSet { UserDefaults.standard.set(entertainmentChannelCount, forKey: "entertainmentChannelCount") }
    }

    init() {
        self.showMenuBarIcon = UserDefaults.standard.object(forKey: "showMenuBarIcon") as? Bool ?? true
        self.showDockIcon = UserDefaults.standard.object(forKey: "showDockIcon") as? Bool ?? true
        self.entertainmentGroupID = UserDefaults.standard.string(forKey: "entertainmentGroupID")
        self.entertainmentChannelCount = UserDefaults.standard.object(forKey: "entertainmentChannelCount") as? Int ?? 1
    }
}
```

**Step 2: Persist channel count when a group is selected in SetupView**

Open `/Users/brandon/projects/SpillAura/SpillAura/SpillAura/UI/SetupView.swift`.

Locate the `EntertainmentGroupPicker` struct. It currently has:

```swift
@AppStorage("entertainmentGroupID") private var storedGroupID: String = ""
```

Add a second `@AppStorage` line directly below it:

```swift
@AppStorage("entertainmentChannelCount") private var storedChannelCount: Int = 1
```

Then locate the button action inside `ForEach(groups)`:

```swift
Button(action: {
    selectedGroupID = group.id
    storedGroupID = group.id
}) {
```

Add `storedChannelCount = group.channelCount` so it becomes:

```swift
Button(action: {
    selectedGroupID = group.id
    storedGroupID = group.id
    storedChannelCount = group.channelCount
}) {
```

Also find the `.task` block where the first group is auto-selected:

```swift
if let first = groups.first, storedGroupID.isEmpty {
    storedGroupID = first.id
}
```

Add channel count persistence here too:

```swift
if let first = groups.first, storedGroupID.isEmpty {
    storedGroupID = first.id
    storedChannelCount = first.channelCount
}
```

**Step 3: Build and verify**

Press `Cmd+B` in Xcode. Expected: Build Succeeded with 0 errors.

**Step 4: Commit**

```bash
cd /Users/brandon/projects/SpillAura
git add SpillAura/SpillAura/Config/AppSettings.swift SpillAura/SpillAura/UI/SetupView.swift
git commit -m "feat: persist entertainment channel count to UserDefaults"
```

---

## Task 1: ColorPacketBuilder

**File:** `Hue/ColorPacketBuilder.swift`

**What this does:** Builds the raw UDP payload for the Hue Entertainment API v2 protocol. This is a pure function with no state — it takes a color and a list of channel IDs and returns a `Data` blob ready to send over DTLS.

### Packet format reference

```
Header (16 bytes total):
  Bytes 0–8:   "HueStream" (9 bytes ASCII, no null terminator)
  Bytes 9–10:  0x02 0x00  (protocol version 2.0)
  Byte  11:    sequence   (0–255, caller increments each packet, wraps)
  Bytes 12–13: 0x00 0x00  (reserved)
  Byte  14:    0x00       (colorspace: RGB=0, XY=1 — we always use RGB)
  Byte  15:    0x00       (reserved)

Per channel (9 bytes each, immediately after header):
  Byte  0:     0x00       (type: light=0)
  Bytes 1–2:   channel_id (UInt16 big-endian, e.g. channel 0 = 0x00 0x00)
  Bytes 3–4:   R          (UInt16 big-endian, range 0–65535)
  Bytes 5–6:   G          (UInt16 big-endian, range 0–65535)
  Bytes 7–8:   B          (UInt16 big-endian, range 0–65535)

Total packet size: 16 + (9 × channelCount) bytes
```

### Color scaling

The API accepts 16-bit color values (0–65535). Input `Float` values are in the 0.0–1.0 range. Scale: `UInt16(clamp(component, 0, 1) × 65535)`.

**Step 1: Implement ColorPacketBuilder.swift**

Replace the entire contents of `/Users/brandon/projects/SpillAura/SpillAura/SpillAura/Hue/ColorPacketBuilder.swift` with:

```swift
import Foundation

/// Builds Entertainment API v2 UDP packets.
///
/// This type is stateless. The caller is responsible for tracking and
/// incrementing the sequence number (wraps at 255 back to 0).
enum ColorPacketBuilder {

    /// Builds a single Entertainment API v2 packet that sets all provided
    /// channels to the same RGB color.
    ///
    /// - Parameters:
    ///   - r: Red component, 0.0–1.0
    ///   - g: Green component, 0.0–1.0
    ///   - b: Blue component, 0.0–1.0
    ///   - channels: Channel IDs to include (e.g. [0, 1, 2, 3])
    ///   - sequence: Packet sequence number, 0–255
    /// - Returns: Raw packet `Data` ready to send over DTLS
    static func buildPacket(
        r: Float,
        g: Float,
        b: Float,
        channels: [UInt16],
        sequence: UInt8
    ) -> Data {
        var data = Data()

        // --- Header (16 bytes) ---
        // "HueStream" in ASCII (9 bytes)
        data.append(contentsOf: [0x48, 0x75, 0x65, 0x53, 0x74, 0x72, 0x65, 0x61, 0x6D])
        // Version 2.0
        data.append(contentsOf: [0x02, 0x00])
        // Sequence number
        data.append(sequence)
        // Reserved
        data.append(contentsOf: [0x00, 0x00])
        // Colorspace: RGB = 0
        data.append(0x00)
        // Reserved
        data.append(0x00)

        // --- Channel entries (9 bytes each) ---
        let rScaled = UInt16(min(max(r, 0.0), 1.0) * 65535)
        let gScaled = UInt16(min(max(g, 0.0), 1.0) * 65535)
        let bScaled = UInt16(min(max(b, 0.0), 1.0) * 65535)

        for channelID in channels {
            // Type: light = 0x00
            data.append(0x00)
            // Channel ID (big-endian UInt16)
            data.append(UInt8(channelID >> 8))
            data.append(UInt8(channelID & 0xFF))
            // R (big-endian UInt16)
            data.append(UInt8(rScaled >> 8))
            data.append(UInt8(rScaled & 0xFF))
            // G (big-endian UInt16)
            data.append(UInt8(gScaled >> 8))
            data.append(UInt8(gScaled & 0xFF))
            // B (big-endian UInt16)
            data.append(UInt8(bScaled >> 8))
            data.append(UInt8(bScaled & 0xFF))
        }

        return data
    }
}
```

**Step 2: Build and verify**

Press `Cmd+B`. Expected: Build Succeeded with 0 errors.

**Step 3: Commit**

```bash
cd /Users/brandon/projects/SpillAura
git add SpillAura/SpillAura/Hue/ColorPacketBuilder.swift
git commit -m "feat: implement Entertainment API v2 packet builder"
```

---

## Task 2: EntertainmentSession

**File:** `Hue/EntertainmentSession.swift`

**What this does:** Manages the full lifecycle of a Hue entertainment session:
1. Activates the session via REST (`PUT .../action = "start"`)
2. Opens a DTLS 1.2 UDP connection to the bridge on port 2100
3. Sends Entertainment API packets
4. Tears everything down cleanly on stop

### State machine

```
idle → activating → connecting → streaming → reconnecting → deactivating → idle
```

- `idle`: nothing happening
- `activating`: REST PUT "start" in flight
- `connecting`: DTLS handshake in progress (NWConnection not yet `.ready`)
- `streaming`: DTLS ready, packets can be sent
- `reconnecting`: connection dropped unexpectedly; waits 2 s then retries (max 3 attempts)
- `deactivating`: REST PUT "stop" in flight, then transitions to `idle`

### DTLS notes

- Port: `2100` (UDP)
- Protocol: DTLS 1.2 (set both min and max to `.DTLSv12`)
- Auth: PSK (pre-shared key)
  - Identity: `username` encoded as UTF-8 `Data` (no null terminator)
  - Key: `clientKey` is a hex string — decode it to raw bytes (e.g., `"AABB"` → `Data([0xAA, 0xBB])`)
- The `NWProtocolTLS.Options` API uses `dispatch_data_t`; Swift's `Data` bridges to this automatically via `as dispatch_data_t`

### REST activation notes

- URL: `https://<bridgeIP>/clip/v2/resource/entertainment_configuration/<groupID>`
- Method: PUT
- Header: `hue-application-key: <username>`
- Body: `{"action": "start"}` (or `"stop"`)
- The bridge uses a self-signed TLS certificate — use `SelfSignedCertDelegate` already defined in `HueBridgeAuth.swift`. Because it is `private` there, we need our own identical copy here.

**Step 1: Implement EntertainmentSession.swift**

Replace the entire contents of `/Users/brandon/projects/SpillAura/SpillAura/SpillAura/Hue/EntertainmentSession.swift` with:

```swift
import Foundation
import Network
import Combine

/// Manages one Hue entertainment session: REST activation → DTLS → streaming → teardown.
@MainActor
final class EntertainmentSession: ObservableObject {

    // MARK: - State

    enum State: Equatable {
        case idle
        case activating
        case connecting
        case streaming
        case reconnecting(attempt: Int)
        case deactivating
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var lastError: String? = nil

    // MARK: - Private

    private let credentials: BridgeCredentials
    private let groupID: String
    private let channelCount: Int

    private var connection: NWConnection?
    private var sequenceNumber: UInt8 = 0
    private var reconnectAttempts: Int = 0
    private static let maxReconnectAttempts = 3

    // MARK: - Init

    /// - Parameters:
    ///   - credentials: Bridge credentials loaded from Keychain
    ///   - groupID: Entertainment configuration group UUID from UserDefaults
    ///   - channelCount: Number of channels in the selected group
    init(credentials: BridgeCredentials, groupID: String, channelCount: Int) {
        self.credentials = credentials
        self.groupID = groupID
        self.channelCount = channelCount
    }

    // MARK: - Public API

    /// Start the session: activate via REST, then open DTLS connection.
    func start() {
        guard state == .idle else { return }
        lastError = nil
        reconnectAttempts = 0
        activate()
    }

    /// Stop the session: close DTLS, then deactivate via REST.
    func stop() {
        guard state != .idle && state != .deactivating else { return }
        teardown()
    }

    /// Send a packet setting all channels to the given RGB color.
    /// Only valid when `state == .streaming`.
    func sendColor(r: Float, g: Float, b: Float) {
        guard state == .streaming, let connection else { return }

        let channels = (0..<channelCount).map { UInt16($0) }
        let packet = ColorPacketBuilder.buildPacket(
            r: r,
            g: g,
            b: b,
            channels: channels,
            sequence: sequenceNumber
        )
        sequenceNumber = sequenceNumber == 255 ? 0 : sequenceNumber + 1

        connection.send(content: packet, completion: .idempotent)
    }

    // MARK: - REST Activation

    private func activate() {
        state = .activating
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.putAction("start")
                self.openDTLS()
            } catch {
                self.lastError = "Activation failed: \(error.localizedDescription)"
                self.state = .idle
            }
        }
    }

    private func deactivateREST() {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.putAction("stop")
            } catch {
                // Log but don't surface — we're already tearing down
                print("[EntertainmentSession] deactivation REST call failed: \(error)")
            }
            self.state = .idle
        }
    }

    private func putAction(_ action: String) async throws {
        let urlString = "https://\(credentials.bridgeIP)/clip/v2/resource/entertainment_configuration/\(groupID)"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(credentials.username, forHTTPHeaderField: "hue-application-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["action": action])

        let session = URLSession(
            configuration: .default,
            delegate: SessionSelfSignedCertDelegate(),
            delegateQueue: nil
        )
        let (_, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw URLError(.badServerResponse, userInfo: [
                NSLocalizedDescriptionKey: "PUT \(action) returned HTTP \(code)"
            ])
        }
    }

    // MARK: - DTLS Connection

    private func openDTLS() {
        state = .connecting

        let pskIdentity = credentials.username.data(using: .utf8)!
        let pskData = hexToData(credentials.clientKey)

        let tlsOptions = NWProtocolTLS.Options()
        sec_protocol_options_set_min_tls_protocol_version(
            tlsOptions.securityProtocolOptions, .DTLSv12
        )
        sec_protocol_options_set_max_tls_protocol_version(
            tlsOptions.securityProtocolOptions, .DTLSv12
        )
        sec_protocol_options_add_pre_shared_key(
            tlsOptions.securityProtocolOptions,
            pskData as dispatch_data_t,
            pskIdentity as dispatch_data_t
        )

        let params = NWParameters(dtls: tlsOptions, udp: NWProtocolUDP.Options())
        params.allowLocalEndpointReuse = true

        let conn = NWConnection(
            host: NWEndpoint.Host(credentials.bridgeIP),
            port: 2100,
            using: params
        )
        connection = conn

        conn.stateUpdateHandler = { [weak self] newState in
            Task { @MainActor [weak self] in
                self?.handleConnectionState(newState)
            }
        }

        conn.start(queue: .global(qos: .userInteractive))
    }

    private func handleConnectionState(_ newState: NWConnection.State) {
        switch newState {
        case .ready:
            reconnectAttempts = 0
            state = .streaming

        case .failed(let error):
            connection?.cancel()
            connection = nil

            if reconnectAttempts < Self.maxReconnectAttempts && state != .deactivating {
                reconnectAttempts += 1
                state = .reconnecting(attempt: reconnectAttempts)
                scheduleReconnect()
            } else {
                lastError = "Connection failed: \(error.localizedDescription)"
                state = .deactivating
                deactivateREST()
            }

        case .cancelled:
            // Triggered by our own teardown — don't reconnect
            connection = nil

        case .waiting(let error):
            print("[EntertainmentSession] waiting: \(error)")

        default:
            break
        }
    }

    private func scheduleReconnect() {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let self, case .reconnecting = self.state else { return }
            self.openDTLS()
        }
    }

    // MARK: - Teardown

    private func teardown() {
        state = .deactivating
        connection?.cancel()
        connection = nil
        deactivateREST()
    }

    // MARK: - Helpers

    private func hexToData(_ hex: String) -> Data {
        var data = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            if let byte = UInt8(hex[index..<nextIndex], radix: 16) {
                data.append(byte)
            }
            index = nextIndex
        }
        return data
    }
}

// MARK: - Self-Signed Certificate Delegate

/// Bypasses certificate validation for the Hue bridge's self-signed TLS cert.
/// The bridge is local-network only, so this is acceptable.
private final class SessionSelfSignedCertDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
```

**Step 2: Build and verify**

Press `Cmd+B`. Expected: Build Succeeded with 0 errors.

There should be no warnings. If you see a warning about `dispatch_data_t`, this is a known Swift/Network.framework bridging quirk and can be ignored as long as it builds.

**Step 3: Commit**

```bash
cd /Users/brandon/projects/SpillAura
git add SpillAura/SpillAura/Hue/EntertainmentSession.swift
git commit -m "feat: implement EntertainmentSession DTLS state machine"
```

---

## Task 3: SyncActor

**File:** `Sync/SyncActor.swift`

**What this does:** `SyncActor` is a Swift `actor` (its own concurrency domain) that owns and drives the `EntertainmentSession`. It exposes a `sendStaticColor(r:g:b:)` method for M2 and will grow in M3+ to support animation loops.

Using an `actor` here means all mutation of the session is serialized without needing manual locks — important for safety when a timer loop is added in M3.

**Step 1: Implement SyncActor.swift**

Replace the entire contents of `/Users/brandon/projects/SpillAura/SpillAura/SpillAura/Sync/SyncActor.swift` with:

```swift
import Foundation

/// Owns the EntertainmentSession and serializes all access to it.
///
/// `SyncActor` runs in its own concurrency domain (Swift actor isolation).
/// In M2 it provides a simple one-shot color sender.
/// In M3 it will drive a real-time animation loop.
actor SyncActor {

    private var session: EntertainmentSession?

    // MARK: - Session lifecycle

    /// Attach a session that is already started (or starting).
    /// Call this before `sendStaticColor`.
    func setSession(_ session: EntertainmentSession) {
        self.session = session
    }

    /// Remove and stop the current session.
    func clearSession() {
        session = nil
    }

    // MARK: - Color sending

    /// Send a single static color packet to all channels.
    ///
    /// Does nothing if no session is attached or if the session is not
    /// in the `.streaming` state.
    func sendStaticColor(r: Float, g: Float, b: Float) async {
        await MainActor.run {
            session?.sendColor(r: r, g: g, b: b)
        }
    }
}
```

**Step 2: Build and verify**

Press `Cmd+B`. Expected: Build Succeeded.

**Step 3: Commit**

```bash
cd /Users/brandon/projects/SpillAura
git add SpillAura/SpillAura/Sync/SyncActor.swift
git commit -m "feat: implement SyncActor with sendStaticColor"
```

---

## Task 4: SyncController

**File:** `Sync/SyncController.swift`

**What this does:** `SyncController` is the `@MainActor` `ObservableObject` that the UI binds to. It creates and owns the `SyncActor`, creates and starts the `EntertainmentSession`, and publishes `connectionStatus` so the UI can reflect the current state.

`SyncController` adds two new public methods for M2:
- `startStaticColor(r:g:b:)` — creates and starts the session, then sends the color once the session reaches `.streaming`
- `stop()` — stops the session

**Step 1: Implement SyncController.swift**

Replace the entire contents of `/Users/brandon/projects/SpillAura/SpillAura/SpillAura/Sync/SyncController.swift` with:

```swift
import Foundation
import Combine

@MainActor
class SyncController: ObservableObject {

    // MARK: - Published state

    @Published var isRunning: Bool = false

    /// Mirrors EntertainmentSession.State for the UI.
    enum ConnectionStatus: Equatable {
        case disconnected
        case connecting
        case streaming
        case error(String)
    }

    @Published private(set) var connectionStatus: ConnectionStatus = .disconnected

    // MARK: - Private

    private let syncActor = SyncActor()
    private var session: EntertainmentSession?
    private var sessionStateCancellable: AnyCancellable?

    // Pending color to send once streaming starts
    private var pendingColor: (r: Float, g: Float, b: Float)? = nil

    // MARK: - M2 API

    /// Activate the entertainment session and send a static color to all lights.
    ///
    /// If credentials or group ID are missing from storage, this logs an error
    /// and returns without doing anything.
    ///
    /// - Parameters:
    ///   - r: Red 0.0–1.0
    ///   - g: Green 0.0–1.0
    ///   - b: Blue 0.0–1.0
    func startStaticColor(r: Float, g: Float, b: Float) {
        guard connectionStatus == .disconnected else { return }

        guard let credentials = HueBridgeAuth().loadFromKeychain() else {
            connectionStatus = .error("No bridge credentials found. Complete setup first.")
            return
        }

        let groupID = UserDefaults.standard.string(forKey: "entertainmentGroupID") ?? ""
        guard !groupID.isEmpty else {
            connectionStatus = .error("No entertainment group selected. Complete setup first.")
            return
        }

        let channelCount = UserDefaults.standard.object(forKey: "entertainmentChannelCount") as? Int ?? 1

        let newSession = EntertainmentSession(
            credentials: credentials,
            groupID: groupID,
            channelCount: channelCount
        )
        session = newSession
        pendingColor = (r, g, b)
        isRunning = true

        // Observe state changes and mirror them to connectionStatus
        sessionStateCancellable = newSession.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                self?.handleSessionState(state)
            }

        Task { [weak self] in
            guard let self else { return }
            await self.syncActor.setSession(newSession)
        }

        newSession.start()
    }

    /// Stop the entertainment session.
    func stop() {
        session?.stop()
        pendingColor = nil
    }

    // MARK: - Private

    private func handleSessionState(_ state: EntertainmentSession.State) {
        switch state {
        case .idle:
            connectionStatus = .disconnected
            isRunning = false
            session = nil
            sessionStateCancellable = nil
            Task { [weak self] in
                guard let self else { return }
                await self.syncActor.clearSession()
            }

        case .activating, .connecting:
            connectionStatus = .connecting

        case .reconnecting:
            connectionStatus = .connecting

        case .streaming:
            connectionStatus = .streaming
            // Send the pending color now that DTLS is ready
            if let color = pendingColor {
                pendingColor = nil
                Task { [weak self] in
                    guard let self else { return }
                    await self.syncActor.sendStaticColor(r: color.r, g: color.g, b: color.b)
                }
            }

        case .deactivating:
            connectionStatus = .disconnected
        }

        // Surface session errors
        if let errorMessage = session?.lastError {
            connectionStatus = .error(errorMessage)
        }
    }
}
```

**Step 2: Build and verify**

Press `Cmd+B`. Expected: Build Succeeded with 0 errors.

**Step 3: Commit**

```bash
cd /Users/brandon/projects/SpillAura
git add SpillAura/SpillAura/Sync/SyncController.swift
git commit -m "feat: add startStaticColor and stop to SyncController"
```

---

## Task 5: MenuBarView Test UI

**File:** `UI/MenuBarView.swift`

**What this does:** Adds two buttons to the menu bar popover — "Send Red" and "Stop" — so you can manually trigger the M2 proof-of-concept without writing tests. "Send Red" calls `syncController.startStaticColor(r:1, g:0, b:0)`. "Stop" calls `syncController.stop()`. A status label shows the current `connectionStatus`.

**Step 1: Implement MenuBarView.swift**

Replace the entire contents of `/Users/brandon/projects/SpillAura/SpillAura/SpillAura/UI/MenuBarView.swift` with:

```swift
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var syncController: SyncController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 12) {
            Text("SpillAura")
                .font(.headline)

            Divider()

            // Connection status
            statusRow

            Divider()

            // M2 test controls
            HStack(spacing: 8) {
                Button("Send Red") {
                    syncController.startStaticColor(r: 1.0, g: 0.0, b: 0.0)
                }
                .disabled(syncController.connectionStatus != .disconnected)

                Button("Stop") {
                    syncController.stop()
                }
                .disabled(syncController.connectionStatus == .disconnected)
            }

            Divider()

            Button("Open Settings") {
                openWindow(id: "main")
            }
        }
        .padding()
        .frame(width: 260)
    }

    @ViewBuilder
    private var statusRow: some View {
        switch syncController.connectionStatus {
        case .disconnected:
            Label("Disconnected", systemImage: "circle")
                .foregroundStyle(.secondary)
                .font(.caption)

        case .connecting:
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.6)
                Text("Connecting…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .streaming:
            Label("Streaming", systemImage: "circle.fill")
                .foregroundStyle(.green)
                .font(.caption)

        case .error(let message):
            Label(message, systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .font(.caption)
                .lineLimit(3)
        }
    }
}
```

**Step 2: Build and verify**

Press `Cmd+B`. Expected: Build Succeeded.

**Step 3: Commit**

```bash
cd /Users/brandon/projects/SpillAura
git add SpillAura/SpillAura/UI/MenuBarView.swift
git commit -m "feat: add Send Red / Stop test buttons to menu bar"
```

---

## Manual End-to-End Verification

After all five tasks are complete and built:

**Preconditions:**
- Your Hue bridge is on the same network as your Mac
- You have already completed the M1 setup flow (paired, selected an entertainment group)
- The entertainment group you selected has lights physically reachable

**Steps:**

1. Run the app in Xcode (`Cmd+R`)
2. The SpillAura icon appears in the menu bar
3. Click the menu bar icon — the popover opens showing "Disconnected" and the "Send Red" button enabled
4. Click "Send Red"
5. The status label changes to "Connecting…" briefly
6. Then changes to "Streaming"
7. **Expected result: all lights in the entertainment group turn red**
8. Click "Stop"
9. The status label returns to "Disconnected"
10. The lights return to their previous state (Hue restores state after entertainment session ends)

**If lights don't change:**

- Open the Xcode console (View → Debug Area → Activate Console) and look for `[EntertainmentSession]` log lines
- Check that `entertainmentGroupID` and `entertainmentChannelCount` are non-empty in UserDefaults. You can verify by adding a temporary `print` in `SyncController.startStaticColor` before the session is created
- Confirm the bridge IP stored in Keychain matches the bridge on your current network (especially if on a different network than when you paired)
- Try running `curl -k -X PUT https://<bridgeIP>/clip/v2/resource/entertainment_configuration/<groupID> -H "hue-application-key: <username>" -d '{"action":"start"}'` in Terminal to verify the REST step works independently

---

## M2 Complete

At the end of M2 you have:

- `ColorPacketBuilder` — stateless, tested-by-inspection packet builder
- `EntertainmentSession` — REST activation + DTLS state machine with reconnect
- `SyncActor` — actor-isolated session driver with `sendStaticColor`
- `SyncController` — `@MainActor` coordinator with `startStaticColor` / `stop`
- `MenuBarView` — "Send Red" / "Stop" test buttons with live status indicator
- `AppSettings` — `entertainmentChannelCount` persisted alongside group ID

Next: **M3 — Animation loop, vibe system, real-time screen sampling**
