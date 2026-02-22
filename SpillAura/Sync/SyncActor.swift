import Foundation
import SpillAuraCore

typealias ColorEntry = (channel: UInt8, r: Float, g: Float, b: Float)

actor SyncActor {

    private var source: (any LightSource)?
    private var sender: HueSender?
    private var brightness: Float = 1.0
    private var speedMultiplier: Double = 1.0
    private var pulsedIdentify: [ColorEntry]?
    private var streamingTask: Task<Void, Never>?
    private var accumulatedTime: TimeInterval = 0
    private var lastTickTime: TimeInterval = 0

    func setSource(_ source: (any LightSource)?)  { self.source = source }
    func setSender(_ sender: HueSender?)          { self.sender = sender }
    func setBrightness(_ v: Float)                { brightness = v }
    func setSpeedMultiplier(_ v: Double)          { speedMultiplier = v }
    func setPulsedIdentify(_ entries: [ColorEntry]?) { pulsedIdentify = entries }

    func startStreaming(
        channelCount: Int,
        onPreview: @escaping @Sendable ([ColorEntry]) -> Void
    ) {
        streamingTask?.cancel()
        accumulatedTime = 0
        lastTickTime = Date.timeIntervalSinceReferenceDate
        streamingTask = Task { [self] in   // inherits actor isolation
            var tick: UInt8 = 0
            while !Task.isCancelled {
                let now = Date.timeIntervalSinceReferenceDate
                let delta = now - lastTickTime
                lastTickTime = now
                accumulatedTime += delta * speedMultiplier
                if let src = source, let sndr = sender {
                    var colors = src.nextColors(channelCount: channelCount,
                                                at: accumulatedTime)
                    if let ids = pulsedIdentify {
                        for id in ids {
                            if let idx = colors.firstIndex(where: { $0.channel == id.channel }) {
                                colors[idx] = id
                            }
                        }
                    }
                    let scale = brightness
                    colors = colors.map { ($0.channel, $0.r * scale, $0.g * scale, $0.b * scale) }
                    sndr.send(colors)
                    tick &+= 1
                    if tick % 4 == 0 { onPreview(colors) }  // ~2.5 Hz to main
                }
                try? await Task.sleep(for: .milliseconds(40))  // frees actor during sleep
            }
        }
    }

    func stopStreaming() {
        streamingTask?.cancel()
        streamingTask = nil
    }
}
