import Foundation
import CoreGraphics

struct Zone {
    let lightID: String
    let channelID: UInt8
    let region: CGRect  // normalized 0.0–1.0
}
