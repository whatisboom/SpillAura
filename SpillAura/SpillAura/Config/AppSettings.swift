import Foundation
import Combine

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
