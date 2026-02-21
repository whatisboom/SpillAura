import Foundation

/// A source of per-channel light colors for a given point in time.
public protocol LightSource {
    /// Generate one color per channel.
    ///
    /// - Parameters:
    ///   - channelCount: Number of channels in the entertainment group
    ///   - timestamp: Seconds elapsed since the session started
    /// - Returns: Array of (channel, r, g, b) tuples, one per channel
    func nextColors(channelCount: Int, at timestamp: TimeInterval) -> [(channel: UInt8, r: Float, g: Float, b: Float)]
}
