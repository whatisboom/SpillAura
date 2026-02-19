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
    ///   - groupID: Entertainment configuration UUID (e.g. "f1027f82-05b2-4a94-b498-4867602ff21f")
    /// - Returns: Raw packet `Data` ready to send over DTLS
    static func buildPacket(
        r: Float,
        g: Float,
        b: Float,
        channels: [UInt16],
        sequence: UInt8,
        groupID: String
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

        // --- Entertainment area UUID (36 bytes ASCII) ---
        // v2.0 requires the group UUID between the header and channel data.
        data.append(contentsOf: groupID.utf8)

        // --- Channel entries (7 bytes each) ---
        // v2.0: channel_id (1 byte) + R (2B BE) + G (2B BE) + B (2B BE)
        let rScaled = UInt16(min(max(r, 0.0), 1.0) * 65535)
        let gScaled = UInt16(min(max(g, 0.0), 1.0) * 65535)
        let bScaled = UInt16(min(max(b, 0.0), 1.0) * 65535)

        for channelID in channels {
            // Channel ID (1 byte)
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

    /// Builds an Entertainment API v2 packet where each channel can have a distinct RGB color.
    ///
    /// - Parameters:
    ///   - channelColors: Array of (channel, r, g, b) tuples, one per channel
    ///   - sequence: Packet sequence number, 0–255
    ///   - groupID: Entertainment configuration UUID
    /// - Returns: Raw packet `Data` ready to send over DTLS
    static func buildPacket(
        channelColors: [(channel: UInt8, r: Float, g: Float, b: Float)],
        sequence: UInt8,
        groupID: String
    ) -> Data {
        var data = Data()

        // Header (16 bytes)
        data.append(contentsOf: [0x48, 0x75, 0x65, 0x53, 0x74, 0x72, 0x65, 0x61, 0x6D])
        data.append(contentsOf: [0x02, 0x00])
        data.append(sequence)
        data.append(contentsOf: [0x00, 0x00])
        data.append(0x00)
        data.append(0x00)

        // Entertainment area UUID (36 bytes ASCII)
        data.append(contentsOf: groupID.utf8)

        // Channel entries (7 bytes each)
        for entry in channelColors {
            let r = UInt16(min(max(entry.r, 0.0), 1.0) * 65535)
            let g = UInt16(min(max(entry.g, 0.0), 1.0) * 65535)
            let b = UInt16(min(max(entry.b, 0.0), 1.0) * 65535)
            data.append(entry.channel)
            data.append(UInt8(r >> 8)); data.append(UInt8(r & 0xFF))
            data.append(UInt8(g >> 8)); data.append(UInt8(g & 0xFF))
            data.append(UInt8(b >> 8)); data.append(UInt8(b & 0xFF))
        }

        return data
    }
}
