import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Guard: if both icons were hidden (e.g. manual defaults edit), force dock visible
        if !UserDefaults.standard.bool(forKey: "showDockIcon"),
           !UserDefaults.standard.bool(forKey: "showMenuBarIcon"),
           UserDefaults.standard.object(forKey: "showDockIcon") != nil,
           UserDefaults.standard.object(forKey: "showMenuBarIcon") != nil {
            UserDefaults.standard.set(true, forKey: "showDockIcon")
        }

        if !UserDefaults.standard.bool(forKey: "showDockIcon"),
           UserDefaults.standard.object(forKey: "showDockIcon") != nil {
            NSApp.setActivationPolicy(.accessory)
        }

        guard UserDefaults.standard.bool(forKey: "launchWindowHidden") else { return }
        // SwiftUI restores windows before this fires, so close them async.
        DispatchQueue.main.async {
            NSApp.windows
                .filter { $0.title == "SpillAura" }
                .forEach { $0.close() }
        }
    }
}
