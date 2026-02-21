import Foundation

/// Builds Entertainment API v2 UDP packets.
///
/// This type is stateless. The caller is responsible for tracking and
/// incrementing the sequence number (wraps at 255 back to 0).
public enum ColorPacketBuilder {

    /// Builds a single Entertainment API v2 packet that sets all provided
    /// channels to the same RGB color.
    public static func buildPacket(
        r: Float,
        g: Float,
        b: Float,
        channels: [UInt16],
        sequence: UInt8,
        groupID: String
    ) -> Data {
        var data = Data()

        // Header (16 bytes)
        data.append(contentsOf: [0x48, 0x75, 0x65, 0x53, 0x74, 0x72, 0x65, 0x61, 0x6D])
        data.append(contentsOf: [0x02, 0x00])
        data.append(sequence)
        data.append(contentsOf: [0x00, 0x00])
        data.append(0x00) // RGB colorspace
        data.append(0x00) // reserved

        // Entertainment area UUID (36 bytes ASCII)
        data.append(contentsOf: groupID.utf8)

        // Channel entries (7 bytes each)
        let rScaled = UInt16(min(max(r, 0.0), 1.0) * 65535)
        let gScaled = UInt16(min(max(g, 0.0), 1.0) * 65535)
        let bScaled = UInt16(min(max(b, 0.0), 1.0) * 65535)

        for channelID in channels {
            data.append(UInt8(channelID & 0xFF))
            data.append(UInt8(rScaled >> 8)); data.append(UInt8(rScaled & 0xFF))
            data.append(UInt8(gScaled >> 8)); data.append(UInt8(gScaled & 0xFF))
            data.append(UInt8(bScaled >> 8)); data.append(UInt8(bScaled & 0xFF))
        }

        return data
    }

    /// Builds an Entertainment API v2 packet where each channel can have a distinct RGB color.
    public static func buildPacket(
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
