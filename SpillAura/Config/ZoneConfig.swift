import Foundation
import CoreGraphics

enum ScreenRegion: String, CaseIterable, Codable, Identifiable {
    case leftEdge, rightEdge, topEdge, bottomEdge, center, fullScreen

    var id: String { rawValue }

    var label: String {
        switch self {
        case .leftEdge:   return "Left Edge"
        case .rightEdge:  return "Right Edge"
        case .topEdge:    return "Top Edge"
        case .bottomEdge: return "Bottom Edge"
        case .center:     return "Center"
        case .fullScreen: return "Full Screen"
        }
    }

    /// Normalized CGRect (0.0–1.0) for this region, scaled by `depth` for edge regions.
    func rect(depth: Double) -> CGRect {
        switch self {
        case .leftEdge:   return CGRect(x: 0.0,         y: 0.0, width: depth,       height: 1.0)
        case .rightEdge:  return CGRect(x: 1.0 - depth, y: 0.0, width: depth,       height: 1.0)
        case .topEdge:    return CGRect(x: 0.0,         y: 0.0, width: 1.0,         height: depth)
        case .bottomEdge: return CGRect(x: 0.0,         y: 1.0 - depth, width: 1.0, height: depth)
        case .center:     return CGRect(x: 0.25,        y: 0.25, width: 0.5,        height: 0.5)
        case .fullScreen: return CGRect(x: 0.0,         y: 0.0, width: 1.0,         height: 1.0)
        }
    }
}

struct Zone: Codable {
    let channelID: UInt8
    var region: ScreenRegion
}

struct ZoneConfig: Codable {
    var displayID: UInt32   // 0 = CGMainDisplayID()
    var zones: [Zone]
    /// Fraction of screen width/height that edge regions (leftEdge, rightEdge, etc.) cover. Default 0.20.
    var depth: Double
    /// Weight multiplier for edge pixels within a zone (edge vs center). Default 3.0.
    var edgeWeight: Double

    private enum CodingKeys: String, CodingKey {
        case displayID, zones, depth, edgeWeight
    }

    init(displayID: UInt32, zones: [Zone], depth: Double = 0.20, edgeWeight: Double = 3.0) {
        self.displayID = displayID
        self.zones = zones
        self.depth = depth
        self.edgeWeight = edgeWeight
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        displayID  = try c.decode(UInt32.self, forKey: .displayID)
        zones      = try c.decode([Zone].self, forKey: .zones)
        depth      = try c.decodeIfPresent(Double.self, forKey: .depth)      ?? 0.20
        edgeWeight = try c.decodeIfPresent(Double.self, forKey: .edgeWeight) ?? 3.0
    }

    /// Default: all channels sample Full Screen on the main display.
    static func defaultConfig(channelCount: Int) -> ZoneConfig {
        let zones = (0..<max(1, channelCount)).map { i in
            Zone(channelID: UInt8(i), region: .fullScreen)
        }
        return ZoneConfig(displayID: 0, zones: zones)
    }

    /// Load from UserDefaults; fall back to default if nothing saved.
    static func load(channelCount: Int) -> ZoneConfig {
        guard let data = UserDefaults.standard.data(forKey: "zoneConfig"),
              let config = try? JSONDecoder().decode(ZoneConfig.self, from: data),
              !config.zones.isEmpty else {
            return defaultConfig(channelCount: channelCount)
        }
        return config
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: "zoneConfig")
        }
    }
}
