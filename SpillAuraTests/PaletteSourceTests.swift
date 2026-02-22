import XCTest
import SpillAuraCore

final class PaletteSourceTests: XCTestCase {

    // MARK: - Helpers

    private func aura(
        palette: [CodableColor],
        speed: Double = 1.0,
        pattern: AuraPattern = .cycle,
        channelOffset: Double = 0.0
    ) -> Aura {
        Aura(
            id: UUID(),
            name: "Test",
            type: .dynamic,
            palette: palette,
            speed: speed,
            pattern: pattern,
            channelOffset: channelOffset
        )
    }

    private func red()   -> CodableColor { CodableColor(red: 1, green: 0, blue: 0) }
    private func green() -> CodableColor { CodableColor(red: 0, green: 1, blue: 0) }
    private func blue()  -> CodableColor { CodableColor(red: 0, green: 0, blue: 1) }

    private func colors(
        for aura: Aura,
        channelCount: Int = 1,
        at t: Double = 0
    ) -> [(channel: UInt8, r: Float, g: Float, b: Float)] {
        PaletteSource(aura: aura).nextColors(channelCount: channelCount, at: t)
    }

    // MARK: - Empty / single-color edge cases

    func test_emptyPalette_returnsBlack() {
        let result = colors(for: aura(palette: []))
        XCTAssertEqual(result[0].r, 0)
        XCTAssertEqual(result[0].g, 0)
        XCTAssertEqual(result[0].b, 0)
    }

    func test_singleColorPalette_alwaysThatColor() {
        let result = colors(for: aura(palette: [red()]))
        XCTAssertEqual(result[0].r, 1, accuracy: 0.001)
        XCTAssertEqual(result[0].g, 0, accuracy: 0.001)
        XCTAssertEqual(result[0].b, 0, accuracy: 0.001)
    }

    // MARK: - Cycle pattern

    func test_cycle_atOrigin_firstChannel_returnsFirstColor() {
        // t=0, speed=1, offset=0 → rawPhase=0 → palette[0]
        let result = colors(for: aura(palette: [red(), blue()], pattern: .cycle), at: 0)
        XCTAssertEqual(result[0].r, 1, accuracy: 0.001)
        XCTAssertEqual(result[0].b, 0, accuracy: 0.001)
    }

    func test_cycle_atMidpoint_interpolatesHalfway() {
        // palette: red→blue, pos=0.5 of 2 entries → t=0.5 between red and blue
        // With speed=1, at t=0.5 → rawPhase=0.5 → pos = 0.5 * 2 = 1.0 → lower=1, t=0 → blue
        // Wait: pos = 0.5 * 2 = 1.0, Int(1.0) = 1, t = 0, so returns palette[1] = blue
        // Let me test at t=0.25: rawPhase=0.25 → pos=0.5, lower=0, t=0.5 → halfway red+blue
        let result = colors(for: aura(palette: [red(), blue()], pattern: .cycle), at: 0.25)
        XCTAssertEqual(result[0].r, 0.5, accuracy: 0.01)
        XCTAssertEqual(result[0].b, 0.5, accuracy: 0.01)
    }

    func test_cycle_wrapsAroundAtEnd() {
        // t=0.75 → rawPhase=0.75 → pos = 0.75*2 = 1.5 → lower=1 (blue), upper=0 (red), t=0.5
        // result: r=0.5, b=0.5
        let result = colors(for: aura(palette: [red(), blue()], pattern: .cycle), at: 0.75)
        XCTAssertEqual(result[0].r, 0.5, accuracy: 0.01)
        XCTAssertEqual(result[0].b, 0.5, accuracy: 0.01)
    }

    func test_cycle_completeRevolution_returnsFirstColor() {
        // t=1.0, speed=1 → rawPhase=1.0 → pos=0 (wraps) → palette[0]
        let result = colors(for: aura(palette: [red(), blue()], pattern: .cycle), at: 1.0)
        XCTAssertEqual(result[0].r, 1, accuracy: 0.001)
        XCTAssertEqual(result[0].b, 0, accuracy: 0.001)
    }

    // MARK: - Speed multiplier

    func test_cycle_speed2_doublesAnimationRate() {
        // speed=2, t=0.25 → rawPhase = 0.25*2 = 0.5 → same as speed=1 at t=0.5
        // palette: [red, blue], pos=0.5 → pos*2=1.0 → lower=1 (blue), t=0 → blue
        let result = colors(for: aura(palette: [red(), blue()], speed: 2.0, pattern: .cycle), at: 0.25)
        XCTAssertEqual(result[0].r, 0, accuracy: 0.001)
        XCTAssertEqual(result[0].b, 1, accuracy: 0.001)
    }

    func test_cycle_speed0_5_halvesAnimationRate() {
        // speed=0.5, t=1.0 → rawPhase = 1.0*0.5 = 0.5 → same as speed=1 at t=0.5
        // palette: [red, blue], pos=0.5 → pos*2=1.0 → lower=1 (blue), t=0 → blue
        let result = colors(for: aura(palette: [red(), blue()], speed: 0.5, pattern: .cycle), at: 1.0)
        XCTAssertEqual(result[0].r, 0, accuracy: 0.001)
        XCTAssertEqual(result[0].b, 1, accuracy: 0.001)
    }

    // MARK: - Bounce pattern

    func test_bounce_atOrigin_returnsFirstColor() {
        let result = colors(for: aura(palette: [red(), blue()], pattern: .bounce), at: 0)
        XCTAssertEqual(result[0].r, 1, accuracy: 0.001)
        XCTAssertEqual(result[0].b, 0, accuracy: 0.001)
    }

    func test_bounce_atHalfCycle_returnsLastColor() {
        // speed=1, t=1.0 → rawPhase=1.0, pos=1.0 % 2.0 = 1.0 (not > 1) → interpolate at pos=1.0*(2-1)=1
        // palette[1] = blue
        let result = colors(for: aura(palette: [red(), blue()], pattern: .bounce), at: 1.0)
        XCTAssertEqual(result[0].r, 0, accuracy: 0.001)
        XCTAssertEqual(result[0].b, 1, accuracy: 0.001)
    }

    func test_bounce_returnsToFirstColorAtFullCycle() {
        // speed=1, t=2.0 → rawPhase=2.0 → pos=2.0%2.0=0.0 → palette[0] = red
        let result = colors(for: aura(palette: [red(), blue()], pattern: .bounce), at: 2.0)
        XCTAssertEqual(result[0].r, 1, accuracy: 0.001)
        XCTAssertEqual(result[0].b, 0, accuracy: 0.001)
    }

    func test_bounce_doesNotWrap_atSecondHalf() {
        // At t=1.5 → rawPhase=1.5 → pos=1.5, pos>1 → pos=2-1.5=0.5 → halfway red/blue
        let result = colors(for: aura(palette: [red(), blue()], pattern: .bounce), at: 1.5)
        XCTAssertEqual(result[0].r, 0.5, accuracy: 0.01)
        XCTAssertEqual(result[0].b, 0.5, accuracy: 0.01)
    }

    // MARK: - Channel offset

    func test_channelOffset_phasesChannelsApart() {
        // channelOffset=0.5, speed=1, t=0
        // channel 0: rawPhase = 0 + 0.5*0 = 0 → red
        // channel 1: rawPhase = 0 + 0.5*1 = 0.5 → halfway → interpolated
        let source = PaletteSource(aura: aura(
            palette: [red(), blue()],
            speed: 1.0,
            pattern: .cycle,
            channelOffset: 0.5
        ))
        let result = source.nextColors(channelCount: 2, at: 0)
        // Channel 0: pos=0 → red
        XCTAssertEqual(result[0].r, 1, accuracy: 0.001)
        // Channel 1: pos=0.5 → 0.25*2=0.5 position... wait
        // rawPhase for ch1 = 0 + 0.5*1 = 0.5
        // pos = 0.5 % 1.0 = 0.5 → pos * count = 0.5*2=1.0 → lower=1 (blue), t=0 → blue
        // Actually: rawPhase=0.5, pos = 0.5%1.0=0.5, pos*2=1.0, Int(1.0)=1, lower=1, upper=(1+1)%2=0, t=0
        // returns palette[1] = blue
        XCTAssertEqual(result[1].b, 1, accuracy: 0.001)
        XCTAssertEqual(result[1].r, 0, accuracy: 0.001)
    }

    func test_zeroChannelOffset_allChannelsSamePhase() {
        let source = PaletteSource(aura: aura(
            palette: [red(), blue()],
            speed: 1.0,
            pattern: .cycle,
            channelOffset: 0.0
        ))
        let result = source.nextColors(channelCount: 3, at: 0.25)
        // All channels at same phase
        XCTAssertEqual(result[0].r, result[1].r, accuracy: 0.001)
        XCTAssertEqual(result[0].r, result[2].r, accuracy: 0.001)
    }

    // MARK: - Channel count

    func test_returnsCorrectNumberOfChannelEntries() {
        let result = PaletteSource(aura: aura(palette: [red(), blue()]))
            .nextColors(channelCount: 5, at: 0)
        XCTAssertEqual(result.count, 5)
    }

    func test_channelIDsMatchIndex() {
        let result = PaletteSource(aura: aura(palette: [red(), blue()]))
            .nextColors(channelCount: 3, at: 0)
        XCTAssertEqual(result[0].channel, 0)
        XCTAssertEqual(result[1].channel, 1)
        XCTAssertEqual(result[2].channel, 2)
    }
}
