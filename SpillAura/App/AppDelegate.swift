import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private let appLaunchDate = Date()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Guard: if both icons were hidden (e.g. manual defaults edit), force dock visible
        if !UserDefaults.standard.bool(forKey: StorageKey.showDockIcon),
           !UserDefaults.standard.bool(forKey: StorageKey.showMenuBarIcon),
           UserDefaults.standard.object(forKey: StorageKey.showDockIcon) != nil,
           UserDefaults.standard.object(forKey: StorageKey.showMenuBarIcon) != nil {
            UserDefaults.standard.set(true, forKey: StorageKey.showDockIcon)
        }

        if !UserDefaults.standard.bool(forKey: StorageKey.showDockIcon),
           UserDefaults.standard.object(forKey: StorageKey.showDockIcon) != nil {
            NSApp.setActivationPolicy(.accessory)
        }

        guard UserDefaults.standard.bool(forKey: StorageKey.launchWindowHidden) else { return }
        // SwiftUI restores windows before this fires, so close them async.
        DispatchQueue.main.async {
            NSApp.windows
                .filter { $0.title == "SpillAura" }
                .forEach { $0.close() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        let duration = Int(Date().timeIntervalSince(appLaunchDate))
        Analytics.send(.appTerminated(sessionDurationSeconds: duration))
    }
}
