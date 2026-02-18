import SwiftUI

@main
struct SpillAuraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var syncController = SyncController()

    var body: some Scene {
        MenuBarExtra("SpillAura", systemImage: "sun.max") {
            MenuBarView()
                .environmentObject(syncController)
        }
        .menuBarExtraStyle(.window)

        WindowGroup("SpillAura", id: "main") {
            MainWindow()
                .environmentObject(syncController)
        }
    }
}
