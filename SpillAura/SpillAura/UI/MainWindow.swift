import SwiftUI

struct MainWindow: View {
    @EnvironmentObject var syncController: SyncController

    var body: some View {
        SetupView()
    }
}
