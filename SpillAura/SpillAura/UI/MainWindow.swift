import SwiftUI

struct MainWindow: View {
    @EnvironmentObject var syncController: SyncController

    var body: some View {
        TabView {
            SetupView()
                .tabItem { Label("Setup", systemImage: "gear") }

            ScreenSyncView()
                .tabItem { Label("Screen Sync", systemImage: "display") }
        }
        .frame(minWidth: 520, minHeight: 400)
    }
}
