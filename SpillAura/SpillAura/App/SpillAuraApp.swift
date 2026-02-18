import SwiftUI

@main
struct SpillAuraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var syncController = SyncController()

    var body: some Scene {
        MenuBarExtra("SpillAura", systemImage: "light.max") {
            MenuBarView()
                .environmentObject(syncController)
        }
        .menuBarExtraStyle(.window)

        Window("SpillAura", id: "main") {
            MainWindow()
                .environmentObject(syncController)
        }
    }
}
