# SpillAura — Swift Implementation Blueprint

A native macOS app that captures screen regions, extracts dominant colors per zone, and pushes updates to Philips Hue Play lights via the Entertainment API at up to 60fps.

**Platform:** macOS 14+
**Distribution:** Notarized DMG (no App Sandbox required)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                      App Entry Point                    │
│                  (SwiftUI MenuBar App)                  │
└───────────────────────┬─────────────────────────────────┘
                        │
          ┌─────────────▼─────────────┐
          │      SyncController       │  ← @MainActor for UI state only
          │  (orchestrates actors)    │
          └──────┬──────────┬─────────┘
                 │          │
    ┌────────────▼──┐   ┌───▼──────────────┐
    │ ScreenCapture │   │  HueBridge       │
    │   Manager     │   │  Client          │
    │(ScreenCapture │   │(Entertainment    │
    │    Kit)       │   │  API / UDP+DTLS) │
    └────────────┬──┘   └───▲──────────────┘
                 │          │
    ┌────────────▼──┐   ┌───┴──────────────┐
    │  ZoneAnalyzer │──▶│  ColorPacket     │
    │ (Metal/vImage)│   │  Builder         │
    └───────────────┘   └──────────────────┘
```

### Actor Isolation

| Component | Isolation | Reason |
|---|---|---|
| `SyncController.isRunning` | `@MainActor` | SwiftUI state only |
| Frame processing loop | `SyncActor` (dedicated background actor) | CPU-bound color math must not block main thread |
| `NWConnection` send | `SyncActor` | Stays on same background actor — no hops |
| Sleep/wake handling | `@MainActor` | `NSWorkspace` notifications fire on main |

> **Rule:** Never `await` inside the tick loop body. The loop runs fully on `SyncActor` with no actor boundary crossings per frame.

---

## Project Structure

```
SpillAura/
├── SpillAuraApp.swift             # App entry, MenuBarExtra
├── SyncController.swift           # Orchestration, @MainActor UI state
├── SyncActor.swift                # Dedicated background actor for the 60fps loop
├── Capture/
│   ├── ScreenCaptureManager.swift # ScreenCaptureKit setup & streaming
│   └── ZoneAnalyzer.swift         # Crop zones, extract dominant color
├── Hue/
│   ├── HueBridgeDiscovery.swift   # mDNS discovery (_hue._tcp.local) + manual IP fallback
│   ├── HueBridgeAuth.swift        # Link button pairing, token storage
│   ├── EntertainmentSession.swift # DTLS handshake, UDP stream, reconnect logic
│   └── ColorPacketBuilder.swift   # Build Hue Entertainment protocol packets
├── Config/
│   ├── ZoneConfig.swift           # Maps screen regions to light IDs
│   └── AppSettings.swift          # UserDefaults-backed settings
└── UI/
    ├── MenuBarView.swift           # Start/stop, status indicator
    └── SetupView.swift             # First-run bridge pairing + zone mapping
```

---

## Key Dependencies

| Concern | Framework/Tool | Notes |
|---|---|---|
| Screen capture | `ScreenCaptureKit` | macOS 14 APIs available |
| Color analysis | `vImage` (Accelerate) | Vectorized, runs on CPU fast |
| DTLS/UDP | `Network.framework` + `CryptoKit` | DTLS 1.2 required by Hue Entertainment API |
| Bridge REST | `URLSession` | Setup/auth only, not the sync loop |
| UI | `SwiftUI` + `MenuBarExtra` | macOS 14+ |
| Persistence | `UserDefaults` / `Keychain` | Store bridge IP, username, app key |
| Display sync | `CADisplayLink` | macOS 14+ only — do not use on earlier targets |

> **Note on DTLS:** The Hue Entertainment API requires DTLS 1.2 over UDP. `Network.framework` supports this natively via `NWProtocolTLS` with a custom PSK. PSK identity must be the `username` string as UTF-8 `Data` (no null terminator). PSK value is the `clientKey` hex string decoded to raw `Data`.

---

## Phase 1 — Bridge Auth & Discovery

### Discovery

Use mDNS (`_hue._tcp.local`) as the primary discovery method. The cloud endpoint `https://discovery.meethue.com` is deprecated and unreliable — do not depend on it. Provide a manual IP entry fallback in the UI for networks where mDNS is blocked.

```swift
// HueBridgeDiscovery.swift
// 1. Browse _hue._tcp.local via NWBrowser
// 2. Resolve the first result to get bridge IP
// 3. Fallback: let user type IP directly in SetupView
```

### Auth

```swift
// HueBridgeAuth.swift
// 1. POST to http://<bridge-ip>/api with devicetype
// 2. User presses link button → 200 response returns username + clientkey
// 3. Store both in Keychain — username for REST, clientkey for Entertainment DTLS PSK

struct BridgeCredentials {
    let bridgeIP: String
    let username: String       // used as REST API header
    let clientKey: String      // PSK for DTLS handshake (hex string → Data)
}
```

**Entertainment group setup** (must be done in the Hue app or via REST before first run):
```
GET /clip/v2/resource/entertainment_configuration
→ grab the group ID and the list of light IDs with their positions
```

---

## Phase 2 — Zone Mapping

Each Hue Play light gets assigned a screen zone. For 4 lights behind a monitor, a typical layout:

```
┌──────────────────────────────────────┐
│  Zone 0 (Top-Left)  Zone 1 (Top-Right)│  ← lights 0 and 1
│                                       │
│                                       │
│  Zone 2 (Bot-Left)  Zone 3 (Bot-Right)│  ← lights 2 and 3
└──────────────────────────────────────┘
```

```swift
// ZoneConfig.swift
struct Zone {
    let lightID: String          // Hue light resource ID
    let channelID: UInt8         // Entertainment channel index (0-based)
    let region: CGRect           // normalized 0.0–1.0 relative to screen bounds
}

// Default config for 4 Play bars behind monitor
let defaultZones: [Zone] = [
    Zone(lightID: "...", channelID: 0, region: CGRect(x: 0,   y: 0,   width: 0.5, height: 0.5)),
    Zone(lightID: "...", channelID: 1, region: CGRect(x: 0.5, y: 0,   width: 0.5, height: 0.5)),
    Zone(lightID: "...", channelID: 2, region: CGRect(x: 0,   y: 0.5, width: 0.5, height: 0.5)),
    Zone(lightID: "...", channelID: 3, region: CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)),
]
```

---

## Phase 3 — Screen Capture Loop

```swift
// ScreenCaptureManager.swift
import ScreenCaptureKit

// 1. Request screen recording permission (Info.plist: NSScreenCaptureUsageDescription)
// 2. SCShareableContent.getExcludingDesktopWindows to pick display
// 3. SCStreamConfiguration — set pixelFormat to BGRA, low resolution (e.g. 128×72)
//    Lower res = faster color averaging, 60fps is very achievable at 128×72
// 4. Conform to SCStreamOutput — each frame arrives as CMSampleBuffer

class ScreenCaptureManager: NSObject, SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(buffer) else { return }
        // hand off to ZoneAnalyzer on SyncActor
    }
}
```

**Resolution tip:** Capture at 128×72. You're averaging colors per zone — you don't need full resolution. This dramatically reduces memory bandwidth and keeps the loop fast.

---

## Phase 4 — Color Analysis

```swift
// ZoneAnalyzer.swift
import Accelerate

func averageColor(in pixelBuffer: CVPixelBuffer, region: CGRect) -> (r: Float, g: Float, b: Float) {
    // 1. Lock pixel buffer
    // 2. Crop to zone using vImageBuffer_InitWithCVPixelBuffer or manual pointer math
    // 3. Use vImageBoxConvolve_ARGB8888 or simple mean via vDSP_meanv
    // 4. Return normalized 0.0–1.0 floats
    // 5. Optional: apply gamma correction or saturation boost for more vivid colors
}
```

**Color smoothing** (prevents flickering):
```swift
// Exponential moving average per zone
let smoothingFactor: Float = 0.3  // 0 = no change, 1 = instant snap
smoothedColor = previousColor * (1 - smoothingFactor) + newColor * smoothingFactor
```

---

## Phase 5 — Entertainment API Streaming

### Activate the entertainment session (REST)
```
PUT /clip/v2/resource/entertainment_configuration/<group-id>
Body: { "action": "start" }
```
Must be called before opening the UDP stream. Call `stop` on app exit or sleep.

> **Session keepalive:** The bridge auto-terminates the entertainment session after **10 seconds of no packets**. Since the loop runs at 60fps unconditionally (always sending the last known color even when nothing changes), this is never an issue — the loop is the keepalive.

### DTLS Handshake
```swift
// EntertainmentSession.swift
import Network

// PSK identity = username (as UTF-8 Data, no null terminator)
// PSK         = clientKey (hex string decoded to raw Data)

let tlsOptions = NWProtocolTLS.Options()
sec_protocol_options_set_min_tls_protocol_version(tlsOptions.securityProtocolOptions, .DTLSv12)
sec_protocol_options_add_pre_shared_key(
    tlsOptions.securityProtocolOptions,
    pskData as dispatch_data_t,
    pskIdentity as dispatch_data_t
)

let params = NWParameters(dtls: tlsOptions, udp: .init())
let connection = NWConnection(host: bridgeHost, port: 2100, using: params)
```

### Packet format (Entertainment API v2)
```
Header: "HueStream" (9 bytes) + version (2 bytes) + sequence (1 byte) + reserved (2 bytes)
        + colorspace (1 byte, 0x00=RGB) + reserved (1 byte)
Per channel: type (1 byte, 0x00=light) + channel_id (2 bytes)
             + R (2 bytes) + G (2 bytes) + B (2 bytes)   ← 16-bit values, 0–65535
```

```swift
// ColorPacketBuilder.swift
func buildPacket(sequence: UInt8, channels: [(id: UInt16, r: Float, g: Float, b: Float)]) -> Data {
    var data = Data()
    data.append(contentsOf: Array("HueStream".utf8))
    data.append(contentsOf: [0x02, 0x00])   // version 2.0
    data.append(sequence)
    data.append(contentsOf: [0x00, 0x00])   // reserved
    data.append(0x00)                        // RGB colorspace
    data.append(0x00)                        // reserved
    for ch in channels {
        data.append(0x00)                    // type: light
        data.append(contentsOf: ch.id.bigEndianBytes)
        data.append(contentsOf: UInt16(ch.r * 65535).bigEndianBytes)
        data.append(contentsOf: UInt16(ch.g * 65535).bigEndianBytes)
        data.append(contentsOf: UInt16(ch.b * 65535).bigEndianBytes)
    }
    return data
}
```

---

## Phase 6 — The Main Loop

```swift
// SyncActor.swift — dedicated background actor for the 60fps loop
actor SyncActor {
    private var captureManager: ScreenCaptureManager
    private var entertainmentSession: EntertainmentSession
    private var zones: [Zone]
    private var smoothed: [(r: Float, g: Float, b: Float)]
    private var displayLink: CADisplayLink?

    func start() async throws {
        try await entertainmentSession.activate()   // PUT start
        try await captureManager.startCapture()
        startDisplayLink()
    }

    func stop() async {
        stopDisplayLink()
        await captureManager.stopCapture()
        await entertainmentSession.deactivate()     // PUT stop
    }

    // Called by CADisplayLink — no await inside, runs fully on this actor
    func tick() {
        guard let frame = captureManager.latestFrame else { return }
        var channels: [(id: UInt16, r: Float, g: Float, b: Float)] = []
        for (i, zone) in zones.enumerated() {
            let raw = ZoneAnalyzer.averageColor(in: frame, region: zone.region)
            smoothed[i] = smooth(smoothed[i], toward: raw)
            channels.append((id: UInt16(zone.channelID), r: smoothed[i].r, g: smoothed[i].g, b: smoothed[i].b))
        }
        let packet = ColorPacketBuilder.buildPacket(sequence: nextSequence(), channels: channels)
        entertainmentSession.send(packet)  // non-async NWConnection.send
    }
}

// SyncController.swift — @MainActor, owns UI state only
@MainActor
class SyncController: ObservableObject {
    @Published var isRunning = false
    private let syncActor = SyncActor()

    func start() async throws {
        try await syncActor.start()
        isRunning = true
    }

    func stop() async {
        await syncActor.stop()
        isRunning = false
    }
}
```

---

## Phase 7 — Sleep/Wake Handling

The DTLS connection and entertainment session are destroyed when the Mac sleeps. Listen for system notifications and reconnect on wake.

```swift
// In SyncController or AppDelegate
import AppKit

func registerSleepWakeObservers() {
    NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.willSleepNotification,
        object: nil, queue: .main
    ) { [weak self] _ in
        Task { await self?.syncActor.stop() }
    }

    NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.didWakeNotification,
        object: nil, queue: .main
    ) { [weak self] _ in
        Task { try? await self?.syncActor.start() }
    }
}
```

---

## Suggested Build Order

1. **Bridge auth + REST calls** — get pairing working via mDNS discovery, verify you can read entertainment groups
2. **Zone config UI** — hardcode zones first, make them configurable later
3. **Screen capture** — get frames flowing, log color values to console
4. **DTLS connection** — get the handshake working (expect to spend time here), send a static color to verify
5. **Wire it together** — full loop on `SyncActor`, tune smoothing factor
6. **Sleep/wake handling** — add reconnect logic
7. **MenuBar UI** — start/stop, status, quick brightness control

---

## Info.plist Requirements

```xml
<key>NSScreenCaptureUsageDescription</key>
<string>SpillAura needs screen access to match your lights to on-screen colors.</string>
```

Screen recording permission must be granted by the user in **System Settings → Privacy & Security → Screen Recording**.

No App Sandbox entitlements required (distributed as notarized DMG).

---

## Tuning Parameters (expose in settings)

| Parameter | Default | Effect |
|---|---|---|
| Capture resolution | 128×72 | Lower = faster, rarely matters for color avg |
| Smoothing factor | 0.25 | Higher = snappier, lower = smoother transitions |
| Target FPS | 60 | Bridge hard cap, 30fps is fine for most content |
| Saturation boost | 1.2× | Makes colors more vivid on lights vs screen |
| Zone edge inset | 10% | Ignore center, bias toward screen edges |

---

## References

- [Hue Entertainment API Docs](https://developers.meethue.com/develop/hue-entertainment/hue-entertainment-api/)
- [ScreenCaptureKit WWDC22 Session](https://developer.apple.com/videos/play/wwdc2022/10156/)
- [Accelerate vImage Overview](https://developer.apple.com/documentation/accelerate/vimage)
- [NWProtocolTLS with PSK (Network.framework)](https://developer.apple.com/documentation/network/nwprotocoltls)
