import Foundation
import SwiftUI

struct Vibe: Codable, Identifiable {
    let id: UUID
    var name: String
    var type: VibeType
    var palette: [CodableColor]
    var speed: Double
    var pattern: VibePattern
    var channelOffset: Double
}

enum VibeType: String, Codable { case `static`, dynamic }
enum VibePattern: String, Codable { case cycle, bounce, random }

// SwiftUI Color is not Codable — use this wrapper
struct CodableColor: Codable {
    var red: Double
    var green: Double
    var blue: Double
}
