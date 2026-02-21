import Foundation

public struct Aura: Codable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var type: AuraType
    public var palette: [CodableColor]
    public var speed: Double
    public var pattern: AuraPattern
    public var channelOffset: Double

    public init(id: UUID, name: String, type: AuraType, palette: [CodableColor],
                speed: Double, pattern: AuraPattern, channelOffset: Double) {
        self.id = id; self.name = name; self.type = type; self.palette = palette
        self.speed = speed; self.pattern = pattern; self.channelOffset = channelOffset
    }
}

public enum AuraType: String, Codable, Sendable { case `static`, dynamic }
public enum AuraPattern: String, Codable, CaseIterable, Sendable { case cycle, bounce, random }

/// SwiftUI Color is not Codable — use this wrapper.
public struct CodableColor: Codable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red; self.green = green; self.blue = blue
    }
}
