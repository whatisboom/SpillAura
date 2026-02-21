import Foundation
import CoreGraphics
import SwiftUI

enum ScreenRegion: String, CaseIterable, Codable, Identifiable {
    case topTriangle, bottomTriangle, leftTriangle, rightTriangle, center, fullScreen

    var id: String { rawValue }

    var label: String {
        switch self {
        case .topTriangle:    return "Top Triangle"
        case .bottomTriangle: return "Bottom Triangle"
        case .leftTriangle:   return "Left Triangle"
        case .rightTriangle:  return "Right Triangle"
        case .center:         return "Center"
        case .fullScreen:     return "Full Screen"
        }
    }

    /// Tight bounding box for pixel iteration (normalized 0–1).
    func boundingRect() -> CGRect {
        switch self {
        case .topTriangle:    return CGRect(x: 0,    y: 0,    width: 1,   height: 0.5)
        case .bottomTriangle: return CGRect(x: 0,    y: 0.5,  width: 1,   height: 0.5)
        case .leftTriangle:   return CGRect(x: 0,    y: 0,    width: 0.5, height: 1)
        case .rightTriangle:  return CGRect(x: 0.5,  y: 0,    width: 0.5, height: 1)
        case .center:         return CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        case .fullScreen:     return CGRect(x: 0,    y: 0,    width: 1,   height: 1)
        }
    }

    /// Whether the normalized pixel coordinate (nx, ny) falls inside this region.
    func contains(nx: Double, ny: Double) -> Bool {
        switch self {
        case .topTriangle:    return ny < nx && ny < (1 - nx)
        case .bottomTriangle: return ny > nx && ny > (1 - nx)
        case .leftTriangle:   return ny > nx && ny < (1 - nx)
        case .rightTriangle:  return ny < nx && ny > (1 - nx)
        case .center:         return nx >= 0.25 && nx <= 0.75 && ny >= 0.25 && ny <= 0.75
        case .fullScreen:     return true
        }
    }

    /// Whether this pixel is in the edge band closest to the physical light position.
    /// The band width is fixed at 25% of the relevant screen dimension.
    func isEdge(nx: Double, ny: Double) -> Bool {
        let d = 0.25
        switch self {
        case .topTriangle:    return ny < d
        case .bottomTriangle: return ny > 1 - d
        case .leftTriangle:   return nx < d
        case .rightTriangle:  return nx > 1 - d
        case .center:         return nx < 0.3 || nx > 0.7 || ny < 0.3 || ny > 0.7
        case .fullScreen:     return false
        }
    }

    /// Normalized centroid for label placement (computed as average of vertices).
    var centroid: CGPoint {
        switch self {
        case .topTriangle:    return CGPoint(x: 0.5,   y: 0.167)
        case .bottomTriangle: return CGPoint(x: 0.5,   y: 0.833)
        case .leftTriangle:   return CGPoint(x: 0.167, y: 0.5)
        case .rightTriangle:  return CGPoint(x: 0.833, y: 0.5)
        case .center:         return CGPoint(x: 0.5,   y: 0.5)
        case .fullScreen:     return CGPoint(x: 0.5,   y: 0.5)
        }
    }

    /// SwiftUI path for the live zone preview, mapped into `rect`.
    func previewPath(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let ox = rect.minX, oy = rect.minY

        func pt(_ nx: Double, _ ny: Double) -> CGPoint {
            CGPoint(x: ox + nx * w, y: oy + ny * h)
        }

        switch self {
        case .topTriangle:
            var p = Path()
            p.move(to: pt(0, 0)); p.addLine(to: pt(1, 0)); p.addLine(to: pt(0.5, 0.5))
            p.closeSubpath()
            return p
        case .bottomTriangle:
            var p = Path()
            p.move(to: pt(0, 1)); p.addLine(to: pt(1, 1)); p.addLine(to: pt(0.5, 0.5))
            p.closeSubpath()
            return p
        case .leftTriangle:
            var p = Path()
            p.move(to: pt(0, 0)); p.addLine(to: pt(0, 1)); p.addLine(to: pt(0.5, 0.5))
            p.closeSubpath()
            return p
        case .rightTriangle:
            var p = Path()
            p.move(to: pt(1, 0)); p.addLine(to: pt(1, 1)); p.addLine(to: pt(0.5, 0.5))
            p.closeSubpath()
            return p
        case .center:
            return Path(CGRect(x: ox + 0.25 * w, y: oy + 0.25 * h,
                               width: 0.5 * w, height: 0.5 * h))
        case .fullScreen:
            return Path(rect)
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
    /// 0 = uniform sampling across the triangle, 1 = pixels at the screen edge dominate.
    /// Maps to a weight multiplier of 1× (bias=0) to 5× (bias=1). Default 0.5 → 3×.
    var edgeBias: Double

    private enum CodingKeys: String, CodingKey {
        case displayID, zones, edgeBias
    }

    init(displayID: UInt32, zones: [Zone], edgeBias: Double = 0.5) {
        self.displayID = displayID
        self.zones = zones
        self.edgeBias = edgeBias
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        displayID = try c.decode(UInt32.self, forKey: .displayID)
        zones     = try c.decode([Zone].self, forKey: .zones)
        edgeBias  = try c.decodeIfPresent(Double.self, forKey: .edgeBias) ?? 0.5
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
