import Foundation
import SwiftUI

struct Aura: Codable, Identifiable {
    let id: UUID
    var name: String
    var type: AuraType
    var palette: [CodableColor]
    var speed: Double
    var pattern: AuraPattern
    var channelOffset: Double
}

enum AuraType: String, Codable { case `static`, dynamic }
enum AuraPattern: String, Codable { case cycle, bounce, random }

// SwiftUI Color is not Codable — use this wrapper
struct CodableColor: Codable {
    var red: Double
    var green: Double
    var blue: Double
}
