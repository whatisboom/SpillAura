import Foundation

/// A `LightSource` that sends the same RGB color to every channel.
struct StaticColorSource: LightSource {
    let r: Float
    let g: Float
    let b: Float

    func nextColors(channelCount: Int, at timestamp: TimeInterval) -> [(channel: UInt8, r: Float, g: Float, b: Float)] {
        (0..<channelCount).map { (channel: UInt8($0), r: r, g: g, b: b) }
    }
}
