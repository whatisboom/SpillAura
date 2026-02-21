import Foundation
import Combine

enum SyncMode: String {
    case aura, screen
}

enum SyncResponsiveness: String, CaseIterable, Identifiable {
    case instant, snappy, balanced, smooth, cinematic

    var id: String { rawValue }

    var label: String {
        switch self {
        case .instant:   return "Instant"
        case .snappy:    return "Snappy"
        case .balanced:  return "Balanced"
        case .smooth:    return "Smooth"
        case .cinematic: return "Cinematic"
        }
    }

    /// EMA blend factor: smoothed = smoothed * (1 - factor) + raw * factor
    var emaFactor: Double {
        switch self {
        case .instant:   return 1.0
        case .snappy:    return 0.4
        case .balanced:  return 0.2
        case .smooth:    return 0.1
        case .cinematic: return 0.05
        }
    }

    /// SCStream target frame rate
    var frameRate: Int {
        switch self {
        case .instant:   return 60
        case .snappy:    return 30
        case .balanced:  return 20
        case .smooth:    return 10
        case .cinematic: return 5
        }
    }
}

class AppSettings: ObservableObject {
    @Published var showMenuBarIcon: Bool {
        didSet { UserDefaults.standard.set(showMenuBarIcon, forKey: "showMenuBarIcon") }
    }
    @Published var showDockIcon: Bool {
        didSet { UserDefaults.standard.set(showDockIcon, forKey: "showDockIcon") }
    }
    @Published var entertainmentGroupID: String? {
        didSet { UserDefaults.standard.set(entertainmentGroupID, forKey: "entertainmentGroupID") }
    }
    @Published var entertainmentChannelCount: Int {
        didSet { UserDefaults.standard.set(entertainmentChannelCount, forKey: "entertainmentChannelCount") }
    }

    init() {
        self.showMenuBarIcon = UserDefaults.standard.object(forKey: "showMenuBarIcon") as? Bool ?? true
        self.showDockIcon = UserDefaults.standard.object(forKey: "showDockIcon") as? Bool ?? true
        self.entertainmentGroupID = UserDefaults.standard.string(forKey: "entertainmentGroupID")
        self.entertainmentChannelCount = UserDefaults.standard.object(forKey: "entertainmentChannelCount") as? Int ?? 1
    }
}
