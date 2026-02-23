import Foundation

/// Centralized UserDefaults key constants.
///
/// Using these instead of string literals prevents typos and makes
/// key usage discoverable via Find Usages / callers.
enum StorageKey {
    static let zoneConfig = "zoneConfig"
    static let entertainmentGroupID = "entertainmentGroupID"
    static let entertainmentChannelCount = "entertainmentChannelCount"
    static let selectedMode = "selectedMode"
    static let syncResponsiveness = "syncResponsiveness"
    static let brightness = "brightness"
    static let speedMultiplier = "speedMultiplier"
    static let autoStartOnLaunch = "autoStartOnLaunch"
    static let lastMode = "lastMode"
    static let lastAura = "lastAura"
    static let showDockIcon = "showDockIcon"
    static let showMenuBarIcon = "showMenuBarIcon"
    static let launchWindowHidden = "launchWindowHidden"
    static let analyticsEnabled = "analyticsEnabled"
}
