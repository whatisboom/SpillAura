import SwiftUI

@main
struct SpillAuraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var syncController = SyncController()
    @StateObject private var vibeLibrary = VibeLibrary()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(syncController)
                .environmentObject(vibeLibrary)
        } label: {
            Image(systemName: syncController.menuBarIcon)
                .accessibilityLabel("SpillAura")
        }
        .menuBarExtraStyle(.window)

        WindowGroup("SpillAura", id: "main") {
            MainWindow()
                .environmentObject(syncController)
                .environmentObject(vibeLibrary)
        }
    }
}
