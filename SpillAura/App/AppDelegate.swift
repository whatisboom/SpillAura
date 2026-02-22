import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
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
