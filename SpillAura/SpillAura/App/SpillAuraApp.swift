import SwiftUI

@main
struct SpillAuraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var syncController = SyncController()
    @StateObject private var vibeLibrary = VibeLibrary()

    var body: some Scene {
        MenuBarExtra("SpillAura", systemImage: "sun.max") {
            MenuBarView()
                .environmentObject(syncController)
                .environmentObject(vibeLibrary)
        }
        .menuBarExtraStyle(.window)

        WindowGroup("SpillAura", id: "main") {
            MainWindow()
                .environmentObject(syncController)
                .environmentObject(vibeLibrary)
        }
    }
}
