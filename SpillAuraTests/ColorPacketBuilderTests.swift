import XCTest
import SpillAuraCore

final class ColorPacketBuilderTests: XCTestCase {

    private let groupID = "f1027f82-05b2-4a94-b498-4867602ff21f"

    // MARK: - Packet size

    func test_singleChannel_packetIs59Bytes() {
        // 16 header + 36 UUID + 1×7 channel = 59
        let data = ColorPacketBuilder.buildPacket(
            r: 1, g: 0, b: 0, channels: [0], sequence: 0, groupID: groupID
        )
        XCTAssertEqual(data.count, 59)
    }

    func test_threeChannels_packetIs73Bytes() {
        // 16 + 36 + 3×7 = 73
        let data = ColorPacketBuilder.buildPacket(
            r: 1, g: 0, b: 0, channels: [0, 1, 2], sequence: 0, groupID: groupID
        )
        XCTAssertEqual(data.count, 73)
    }

    // MARK: - Header layout

    func test_header_startsWithHueStream() {
        let data = ColorPacketBuilder.buildPacket(
            r: 0, g: 0, b: 0, channels: [0], sequence: 0, groupID: groupID
        )
        let magic = [UInt8](data[0..<9])
        XCTAssertEqual(magic, [0x48, 0x75, 0x65, 0x53, 0x74, 0x72, 0x65, 0x61, 0x6D])
    }

    func test_header_version2_0() {
        let data = ColorPacketBuilder.buildPacket(
            r: 0, g: 0, b: 0, channels: [0], sequence: 0, groupID: groupID
        )
        XCTAssertEqual(data[9], 0x02)
        XCTAssertEqual(data[10], 0x00)
    }

    func test_header_sequenceAtOffset11() {
        let data = ColorPacketBuilder.buildPacket(
            r: 0, g: 0, b: 0, channels: [0], sequence: 42, groupID: groupID
        )
        XCTAssertEqual(data[11], 42)
    }

    func test_header_colorspaceRGBAtOffset14() {
        let data = ColorPacketBuilder.buildPacket(
            r: 0, g: 0, b: 0, channels: [0], sequence: 0, groupID: groupID
        )
        XCTAssertEqual(data[14], 0x00) // RGB colorspace
    }

    func test_header_uuidEmbeddedAsASCII() {
        let data = ColorPacketBuilder.buildPacket(
            r: 0, g: 0, b: 0, channels: [0], sequence: 0, groupID: groupID
        )
        let uuidBytes = [UInt8](data[16..<52])
        XCTAssertEqual(String(bytes: uuidBytes, encoding: .utf8), groupID)
    }

    // MARK: - Channel encoding

    func test_fullRed_encodedBigEndianAtFirstChannel() {
        // r=1.0 → 0xFFFF
        let data = ColorPacketBuilder.buildPacket(
            r: 1, g: 0, b: 0, channels: [0], sequence: 0, groupID: groupID
        )
        // Channel entry starts at byte 52 (16 header + 36 UUID)
        XCTAssertEqual(data[52], 0)    // channel ID
        XCTAssertEqual(data[53], 0xFF) // R high
        XCTAssertEqual(data[54], 0xFF) // R low
        XCTAssertEqual(data[55], 0x00) // G high
        XCTAssertEqual(data[56], 0x00) // G low
        XCTAssertEqual(data[57], 0x00) // B high
        XCTAssertEqual(data[58], 0x00) // B low
    }

    func test_channelIDs_encodedCorrectly() {
        let data = ColorPacketBuilder.buildPacket(
            r: 0, g: 0, b: 0, channels: [3, 7], sequence: 0, groupID: groupID
        )
        XCTAssertEqual(data[52], 3)
        XCTAssertEqual(data[59], 7)
    }

    func test_outOfRange_clampsToValid() {
        let data = ColorPacketBuilder.buildPacket(
            r: 2.0, g: -0.5, b: 0, channels: [0], sequence: 0, groupID: groupID
        )
        // r clamped to 1.0 → 0xFFFF
        XCTAssertEqual(data[53], 0xFF)
        XCTAssertEqual(data[54], 0xFF)
        // g clamped to 0.0 → 0x0000
        XCTAssertEqual(data[55], 0x00)
        XCTAssertEqual(data[56], 0x00)
    }

    // MARK: - Per-channel variant

    func test_perChannelVariant_correctSize() {
        let entries: [(channel: UInt8, r: Float, g: Float, b: Float)] = [
            (0, 1, 0, 0), (1, 0, 1, 0),
        ]
        let data = ColorPacketBuilder.buildPacket(
            channelColors: entries, sequence: 0, groupID: groupID
        )
        XCTAssertEqual(data.count, 16 + 36 + 2 * 7)
    }

    func test_perChannelVariant_distinctColors() {
        let entries: [(channel: UInt8, r: Float, g: Float, b: Float)] = [
            (0, 1, 0, 0), // red
            (1, 0, 1, 0), // green
        ]
        let data = ColorPacketBuilder.buildPacket(
            channelColors: entries, sequence: 0, groupID: groupID
        )
        // Channel 0: R=0xFFFF, G=0x0000
        XCTAssertEqual(data[53], 0xFF); XCTAssertEqual(data[54], 0xFF)
        XCTAssertEqual(data[55], 0x00); XCTAssertEqual(data[56], 0x00)
        // Channel 1: R=0x0000, G=0xFFFF
        XCTAssertEqual(data[60], 0x00); XCTAssertEqual(data[61], 0x00)
        XCTAssertEqual(data[62], 0xFF); XCTAssertEqual(data[63], 0xFF)
    }
}
