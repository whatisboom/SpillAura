import Foundation

/// A `LightSource` that animates through a color palette with per-channel phase offsets.
///
/// - **cycle**: Continuously loops through the palette. Channel `i` is offset by
///   `aura.channelOffset * i` (as a fraction of one full cycle).
/// - **bounce**: Sweeps palette forward then backward. Same per-channel offset applies.
/// - **random**: Treated as fast cycle for a stochastic appearance.
struct PaletteSource: LightSource {
    let aura: Aura

    func nextColors(channelCount: Int, at timestamp: TimeInterval) -> [(channel: UInt8, r: Float, g: Float, b: Float)] {
        (0..<channelCount).map { channelIndex in
            let color = paletteColor(channelIndex: channelIndex, at: timestamp)
            return (channel: UInt8(channelIndex), r: Float(color.red), g: Float(color.green), b: Float(color.blue))
        }
    }

    // MARK: - Private

    private func paletteColor(channelIndex: Int, at t: TimeInterval) -> CodableColor {
        let palette = aura.palette
        guard !palette.isEmpty else { return CodableColor(red: 0, green: 0, blue: 0) }
        guard palette.count > 1 else { return palette[0] }

        let rawPhase = t * aura.speed + aura.channelOffset * Double(channelIndex)

        switch aura.pattern {
        case .cycle, .random:
            var pos = rawPhase.truncatingRemainder(dividingBy: 1.0)
            if pos < 0 { pos += 1.0 }
            return interpolate(at: pos * Double(palette.count), in: palette, wrap: true)

        case .bounce:
            var pos = rawPhase.truncatingRemainder(dividingBy: 2.0)
            if pos < 0 { pos += 2.0 }
            if pos > 1.0 { pos = 2.0 - pos }
            return interpolate(at: pos * Double(palette.count - 1), in: palette, wrap: false)
        }
    }

    /// Linearly interpolate between adjacent palette entries.
    ///
    /// - Parameters:
    ///   - position: Float index into palette (e.g. 1.5 = halfway between entries 1 and 2)
    ///   - wrap: If `true`, entry after the last wraps to entry 0 (cycle). If `false`, clamps (bounce).
    private func interpolate(at position: Double, in palette: [CodableColor], wrap: Bool) -> CodableColor {
        let count = palette.count
        let lower = Int(position) % count
        let upper = wrap ? (lower + 1) % count : min(lower + 1, count - 1)
        let t = position - Double(Int(position))
        let a = palette[lower]
        let b = palette[upper]
        return CodableColor(
            red:   a.red   + (b.red   - a.red)   * t,
            green: a.green + (b.green - a.green) * t,
            blue:  a.blue  + (b.blue  - a.blue)  * t
        )
    }
}
