import Foundation
import CoreGraphics

/// A single light zone: which channel it drives and where on screen it samples from.
struct Zone: Codable {
    let lightID: String
    let channelID: UInt8
    var region: CGRect  // normalized 0.0–1.0

    // CGRect is not natively Codable — encode as flat keys
    enum CodingKeys: String, CodingKey {
        case lightID, channelID, x, y, width, height
    }

    init(lightID: String, channelID: UInt8, region: CGRect) {
        self.lightID = lightID
        self.channelID = channelID
        self.region = region
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lightID   = try c.decode(String.self, forKey: .lightID)
        channelID = try c.decode(UInt8.self,  forKey: .channelID)
        let x = try c.decode(Double.self, forKey: .x)
        let y = try c.decode(Double.self, forKey: .y)
        let w = try c.decode(Double.self, forKey: .width)
        let h = try c.decode(Double.self, forKey: .height)
        region = CGRect(x: x, y: y, width: w, height: h)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(lightID,           forKey: .lightID)
        try c.encode(channelID,         forKey: .channelID)
        try c.encode(region.origin.x,   forKey: .x)
        try c.encode(region.origin.y,   forKey: .y)
        try c.encode(region.size.width,  forKey: .width)
        try c.encode(region.size.height, forKey: .height)
    }
}

/// Manages the mapping of screen regions to Hue channel IDs.
struct ZoneConfig {
    var zones: [Zone]

    /// N equal vertical strips, left-to-right, channelID 0..N-1.
    /// Used as the default until the user configures drag-to-assign.
    static func defaultConfig(channelCount: Int) -> ZoneConfig {
        let count = max(1, channelCount)
        let zones = (0..<count).map { i in
            Zone(
                lightID: "channel_\(i)",
                channelID: UInt8(i),
                region: CGRect(
                    x: Double(i) / Double(count),
                    y: 0.0,
                    width: 1.0 / Double(count),
                    height: 1.0
                )
            )
        }
        return ZoneConfig(zones: zones)
    }

    /// Load from UserDefaults; fall back to default strips if nothing saved.
    static func load(channelCount: Int) -> ZoneConfig {
        guard let data = UserDefaults.standard.data(forKey: "zoneConfig"),
              let zones = try? JSONDecoder().decode([Zone].self, from: data),
              !zones.isEmpty else {
            return defaultConfig(channelCount: channelCount)
        }
        return ZoneConfig(zones: zones)
    }

    func save() {
        if let data = try? JSONEncoder().encode(zones) {
            UserDefaults.standard.set(data, forKey: "zoneConfig")
        }
    }
}
