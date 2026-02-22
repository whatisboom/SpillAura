import Foundation
import CoreGraphics
import SwiftUI

enum ScreenRegion: String, CaseIterable, Codable, Identifiable {
    case top        = "topTriangle"
    case bottom     = "bottomTriangle"
    case left       = "leftTriangle"
    case right      = "rightTriangle"
    case center     = "center"
    case fullScreen = "fullScreen"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .top:        return "Top"
        case .bottom:     return "Bottom"
        case .left:       return "Left"
        case .right:      return "Right"
        case .center:     return "Center"
        case .fullScreen: return "Full Screen"
        }
    }

    /// Tight bounding box for pixel iteration (normalized 0–1).
    func boundingRect() -> CGRect {
        switch self {
        case .top:        return CGRect(x: 0,    y: 0,    width: 1,   height: 0.5)
        case .bottom:     return CGRect(x: 0,    y: 0.5,  width: 1,   height: 0.5)
        case .left:       return CGRect(x: 0,    y: 0,    width: 0.5, height: 1)
        case .right:      return CGRect(x: 0.5,  y: 0,    width: 0.5, height: 1)
        case .center:     return CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        case .fullScreen: return CGRect(x: 0,    y: 0,    width: 1,   height: 1)
        }
    }

    /// Whether the normalized pixel coordinate (nx, ny) falls inside this region.
    func contains(nx: Double, ny: Double) -> Bool {
        switch self {
        case .top:        return ny < nx && ny < (1 - nx)
        case .bottom:     return ny > nx && ny > (1 - nx)
        case .left:       return ny > nx && ny < (1 - nx)
        case .right:      return ny < nx && ny > (1 - nx)
        case .center:     return nx >= 0.25 && nx <= 0.75 && ny >= 0.25 && ny <= 0.75
        case .fullScreen: return true
        }
    }

    /// Whether this pixel is in the edge band closest to the physical light position.
    /// The band width is fixed at 25% of the relevant screen dimension.
    func isEdge(nx: Double, ny: Double) -> Bool {
        let d = 0.25
        switch self {
        case .top:        return ny < d
        case .bottom:     return ny > 1 - d
        case .left:       return nx < d
        case .right:      return nx > 1 - d
        case .center:     return nx < 0.3 || nx > 0.7 || ny < 0.3 || ny > 0.7
        case .fullScreen: return false
        }
    }

    /// Normalized centroid for label placement (computed as average of vertices).
    var centroid: CGPoint {
        switch self {
        case .top:        return CGPoint(x: 0.5,   y: 0.167)
        case .bottom:     return CGPoint(x: 0.5,   y: 0.833)
        case .left:       return CGPoint(x: 0.167, y: 0.5)
        case .right:      return CGPoint(x: 0.833, y: 0.5)
        case .center:     return CGPoint(x: 0.5,   y: 0.5)
        case .fullScreen: return CGPoint(x: 0.5,   y: 0.5)
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
        case .top:
            var p = Path()
            p.move(to: pt(0, 0)); p.addLine(to: pt(1, 0)); p.addLine(to: pt(0.5, 0.5))
            p.closeSubpath()
            return p
        case .bottom:
            var p = Path()
            p.move(to: pt(0, 1)); p.addLine(to: pt(1, 1)); p.addLine(to: pt(0.5, 0.5))
            p.closeSubpath()
            return p
        case .left:
            var p = Path()
            p.move(to: pt(0, 0)); p.addLine(to: pt(0, 1)); p.addLine(to: pt(0.5, 0.5))
            p.closeSubpath()
            return p
        case .right:
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
    /// Maps to a weight multiplier of 1× (bias=0) to 5× (bias=1). Default 0.0 → uniform.
    var edgeBias: Double

    static func defaultConfig(channelCount: Int) -> ZoneConfig {
        let regions: [ScreenRegion]
        switch channelCount {
        case 1:  regions = [.fullScreen]
        case 2:  regions = [.left, .right]
        case 3:  regions = [.top, .left, .right]
        default: regions = [.top, .right, .bottom, .left]
                         + Array(repeating: .fullScreen, count: max(0, channelCount - 4))
        }
        let zones = regions.enumerated().map { Zone(channelID: UInt8($0.offset), region: $0.element) }
        return ZoneConfig(displayID: 0, zones: zones, edgeBias: 0.0)
    }

    static func load(channelCount: Int) -> ZoneConfig {
        guard let data = UserDefaults.standard.data(forKey: StorageKey.zoneConfig) else {
            return defaultConfig(channelCount: channelCount)
        }
        do {
            return try JSONDecoder().decode(ZoneConfig.self, from: data)
        } catch {
            print("[ZoneConfig] Incompatible stored config, resetting: \(error)")
            UserDefaults.standard.removeObject(forKey: StorageKey.zoneConfig)
            return defaultConfig(channelCount: channelCount)
        }
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else {
            print("[ZoneConfig] Failed to encode config, skipping save")
            return
        }
        UserDefaults.standard.set(data, forKey: StorageKey.zoneConfig)
    }
}

struct ChannelColor {
    let name: String
    let r: Float
    let g: Float
    let b: Float

    var swiftUIColor: Color { Color(red: Double(r), green: Double(g), blue: Double(b)) }

    /// Returns a visually distinct color for channel `index` out of `count` total channels.
    /// Hues are evenly spaced around the color wheel (saturation 1, brightness 1).
    static func color(for index: Int, of count: Int) -> ChannelColor {
        let hue = Double(index) / Double(max(count, 1))  // 0.0 ..< 1.0

        // HSB → RGB (6-sector piecewise linear)
        let h6 = hue * 6.0
        let sector = Int(h6) % 6
        let f = Float(h6 - Double(Int(h6)))
        let q: Float = 1.0 - f
        let r, g, b: Float
        switch sector {
        case 0: r = 1; g = f;   b = 0
        case 1: r = q; g = 1;   b = 0
        case 2: r = 0; g = 1;   b = f
        case 3: r = 0; g = q;   b = 1
        case 4: r = f; g = 0;   b = 1
        default: r = 1; g = 0;  b = q
        }

        // Map hue to one of 12 named sectors
        let sectorNames = [
            "Red", "Orange", "Yellow", "Lime", "Green", "Mint",
            "Cyan", "Sky", "Blue", "Purple", "Pink", "Rose"
        ]
        let sectorIndex = Int(round(hue * 12)) % 12
        let baseName = sectorNames[sectorIndex]

        // For count > 12, disambiguate repeated names with ordinals
        var name = baseName
        if count > 12 {
            var usedCounts: [String: Int] = [:]
            for prev in 0..<index {
                let prevHue = Double(prev) / Double(count)
                let prevSector = Int(round(prevHue * 12)) % 12
                let prevName = sectorNames[prevSector]
                usedCounts[prevName, default: 0] += 1
            }
            let timesUsed = usedCounts[baseName, default: 0]
            if timesUsed > 0 {
                name = "\(baseName) \(timesUsed + 1)"
            }
        }

        return ChannelColor(name: name, r: r, g: g, b: b)
    }
}

enum ZoneLayoutPreset {
    case twoBar, threeBar, fourBar

    func regions(for count: Int) -> [ScreenRegion] {
        let all: [ScreenRegion]
        switch self {
        case .twoBar:   all = [.left, .right]
        case .threeBar: all = [.top, .left, .right]
        case .fourBar:  all = [.top, .right, .bottom, .left]
        }
        return (0..<count).map { i in i < all.count ? all[i] : .fullScreen }
    }
}
