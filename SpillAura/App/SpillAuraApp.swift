import SwiftUI
import SpillAuraCore

@main
struct SpillAuraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var syncController = SyncController()
    @StateObject private var auraLibrary = AuraLibrary()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(syncController)
                .environmentObject(auraLibrary)
        } label: {
            Image(systemName: syncController.menuBarIcon)
                .accessibilityLabel("SpillAura")
        }
        .menuBarExtraStyle(.window)

        WindowGroup("SpillAura", id: "main") {
            MainWindow()
                .environmentObject(syncController)
                .environmentObject(auraLibrary)
        }

        Window("Settings", id: "settings") {
            SettingsView()
                .environmentObject(syncController)
        }
        .windowResizability(.contentSize)
    }
}
