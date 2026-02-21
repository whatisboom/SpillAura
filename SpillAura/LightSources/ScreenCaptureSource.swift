import Foundation
import ScreenCaptureKit
import CoreMedia
import CoreVideo

/// A `LightSource` that samples a specific display and maps zone regions to channel colors.
///
/// SCKit delivers frames on a background serial queue. The delegate processes each frame
/// immediately — weighted edge average + EMA smoothing — then stores the result under
/// `lock`. `nextColors()` reads synchronously: no `await` in the hot path.
final class ScreenCaptureSource: NSObject, LightSource, SCStreamOutput, SCStreamDelegate {

    // MARK: - Private state

    private let config: ZoneConfig
    /// Protected by `lock` so updateResponsiveness can swap it from any actor.
    private var _emaFactor: Float

    private var stream: SCStream?
    private let frameQueue = DispatchQueue(label: "com.spillaura.screencapture", qos: .userInteractive)

    /// Per-zone smoothed colors, only accessed on `frameQueue`.
    private var smoothed: [(channel: UInt8, r: Float, g: Float, b: Float)]

    /// Latest processed colors exposed to the MainActor 60fps loop.
    private let lock = NSLock()
    private var _currentColors: [(channel: UInt8, r: Float, g: Float, b: Float)] = []

    // MARK: - Init / deinit

    private var _initialFrameRate: Int

    init(config: ZoneConfig, responsiveness: SyncResponsiveness) {
        self.config = config
        self._emaFactor = Float(responsiveness.emaFactor)
        self._initialFrameRate = responsiveness.frameRate
        self.smoothed = config.zones.map { (channel: $0.channelID, r: 0, g: 0, b: 0) }
        super.init()
        Task { await startCapture() }
    }

    deinit {
        if let s = stream {
            Task { try? await s.stopCapture() }
        }
    }

    // MARK: - LightSource

    func nextColors(channelCount: Int, at timestamp: TimeInterval) -> [(channel: UInt8, r: Float, g: Float, b: Float)] {
        lock.lock()
        let colors = _currentColors
        lock.unlock()
        if colors.isEmpty {
            return (0..<channelCount).map { (channel: UInt8($0), r: 0, g: 0, b: 0) }
        }
        return colors
    }

    // MARK: - Capture setup

    private func startCapture() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: false
            )

            let targetID: CGDirectDisplayID = config.displayID == 0
                ? CGMainDisplayID()
                : CGDirectDisplayID(config.displayID)
            guard let display = content.displays.first(where: { $0.displayID == targetID })
                             ?? content.displays.first else {
                print("[ScreenCaptureSource] No display found")
                return
            }

            let filter = SCContentFilter(display: display, excludingWindows: [])

            let streamConfig = SCStreamConfiguration()
            streamConfig.width = 160
            streamConfig.height = 90
            streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(_initialFrameRate))
            streamConfig.queueDepth = 3
            streamConfig.pixelFormat = kCVPixelFormatType_32BGRA

            let newStream = SCStream(filter: filter, configuration: streamConfig, delegate: self)
            try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: frameQueue)
            try await newStream.startCapture()
            stream = newStream
        } catch {
            print("[ScreenCaptureSource] Failed to start capture: \(error)")
        }
    }

    // MARK: - SCStreamOutput

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let processed = extractColors(from: pixelBuffer)
        lock.lock()
        _currentColors = processed
        lock.unlock()
    }

    // MARK: - SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("[ScreenCaptureSource] Stream stopped: \(error)")
    }

    // MARK: - Color extraction

    /// Weighted edge RMS average: accumulates squares of pixel values (sRGB → linear-light
    /// approximation), then takes the square root of the mean (linear → display). This ensures
    /// bright pixels contribute their fair share rather than being swamped by dark backgrounds.
    /// Edge pixels (outer 20%) are weighted 3× vs center. Followed by EMA smoothing.
    private func extractColors(
        from pixelBuffer: CVPixelBuffer
    ) -> [(channel: UInt8, r: Float, g: Float, b: Float)] {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let pw = CVPixelBufferGetWidth(pixelBuffer)
        let ph = CVPixelBufferGetHeight(pixelBuffer)
        let bpr = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return [] }
        let buf = base.assumingMemoryBound(to: UInt8.self)

        lock.lock()
        let factor = _emaFactor
        lock.unlock()
        var result: [(channel: UInt8, r: Float, g: Float, b: Float)] = []

        for (i, zone) in config.zones.enumerated() {
            let bRect = zone.region.boundingRect()
            let zx = Int(bRect.minX * Double(pw))
            let zy = Int(bRect.minY * Double(ph))
            let zw = max(1, Int(bRect.width  * Double(pw)))
            let zh = max(1, Int(bRect.height * Double(ph)))

            var sumR = 0.0, sumG = 0.0, sumB = 0.0, sumW = 0.0

            for y in zy..<min(zy + zh, ph) {
                for x in zx..<min(zx + zw, pw) {
                    let nx = Double(x) / Double(pw)
                    let ny = Double(y) / Double(ph)
                    guard zone.region.contains(nx: nx, ny: ny) else { continue }
                    let w = zone.region.isEdge(nx: nx, ny: ny, depth: config.depth)
                        ? config.edgeWeight : 1.0
                    let off = y * bpr + x * 4  // BGRA
                    let b = Double(buf[off])     / 255.0
                    let g = Double(buf[off + 1]) / 255.0
                    let rv = Double(buf[off + 2]) / 255.0
                    sumB += b  * b  * w   // accumulate squares for RMS
                    sumG += g  * g  * w
                    sumR += rv * rv * w
                    sumW += w
                }
            }

            guard sumW > 0 else { result.append(smoothed[i]); continue }

            // RMS (sqrt of mean-of-squares) + gamma boost (^0.6).
            // Combined exponent of 0.3 aggressively lifts dim averages:
            //   rms 0.2 → 0.34,  rms 0.5 → 0.62,  rms 1.0 → 1.0
            let rawR = Float(pow(sqrt(sumR / sumW), 0.6))
            let rawG = Float(pow(sqrt(sumG / sumW), 0.6))
            let rawB = Float(pow(sqrt(sumB / sumW), 0.6))

            let prev = smoothed[i]
            smoothed[i] = (
                channel: zone.channelID,
                r: prev.r * (1 - factor) + rawR * factor,
                g: prev.g * (1 - factor) + rawG * factor,
                b: prev.b * (1 - factor) + rawB * factor
            )
            result.append(smoothed[i])
        }

        return result
    }

    // MARK: - Live responsiveness update

    /// Update EMA factor and stream frame rate in-place — no stream teardown.
    func updateResponsiveness(_ r: SyncResponsiveness) {
        lock.lock()
        _emaFactor = Float(r.emaFactor)
        lock.unlock()

        guard let s = stream else { return }
        let cfg = SCStreamConfiguration()
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(r.frameRate))
        Task { try? await s.updateConfiguration(cfg) }
    }
}
