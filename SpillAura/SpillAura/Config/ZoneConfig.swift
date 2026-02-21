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

    /// Normalized CGRect (0.0–1.0) for this region.
    var rect: CGRect {
        switch self {
        case .leftEdge:   return CGRect(x: 0.0,  y: 0.0,  width: 0.2,  height: 1.0)
        case .rightEdge:  return CGRect(x: 0.8,  y: 0.0,  width: 0.2,  height: 1.0)
        case .topEdge:    return CGRect(x: 0.0,  y: 0.0,  width: 1.0,  height: 0.2)
        case .bottomEdge: return CGRect(x: 0.0,  y: 0.8,  width: 1.0,  height: 0.2)
        case .center:     return CGRect(x: 0.25, y: 0.25, width: 0.5,  height: 0.5)
        case .fullScreen: return CGRect(x: 0.0,  y: 0.0,  width: 1.0,  height: 1.0)
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
