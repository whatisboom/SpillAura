import Foundation
import SpillAuraCore

typealias ColorEntry = (channel: UInt8, r: Float, g: Float, b: Float)

actor SyncActor {

    private var source: (any LightSource)?
    private var sender: HueSender?
    private var brightness: Float = 1.0
    private var speedMultiplier: Double = 1.0
    private var pulsedChannel: UInt8?
    private var streamingTask: Task<Void, Never>?

    func setSource(_ source: (any LightSource)?)  { self.source = source }
    func setSender(_ sender: HueSender?)          { self.sender = sender }
    func setBrightness(_ v: Float)                { brightness = v }
    func setSpeedMultiplier(_ v: Double)          { speedMultiplier = v }
    func setPulsedChannel(_ ch: UInt8?)           { pulsedChannel = ch }

    func startStreaming(
        channelCount: Int,
        startTime: TimeInterval,
        onPreview: @escaping @Sendable ([ColorEntry]) -> Void
    ) {
        streamingTask?.cancel()
        streamingTask = Task { [self] in   // inherits actor isolation
            var tick: UInt8 = 0
            while !Task.isCancelled {
                let elapsed = Date.timeIntervalSinceReferenceDate - startTime
                if let src = source, let sndr = sender {
                    var colors = src.nextColors(channelCount: channelCount,
                                                at: elapsed * speedMultiplier)
                    if let ch = pulsedChannel,
                       let idx = colors.firstIndex(where: { $0.channel == ch }) {
                        let pulse = Float(0.5 + 0.5 * sin(elapsed * .pi))
                        colors[idx] = (channel: ch, r: pulse, g: pulse, b: pulse)
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
