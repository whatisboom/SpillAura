import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var syncController: SyncController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 12) {
            Text("SpillAura")
                .font(.headline)
            Text("M1 — Setup only")
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
            Button("Open Settings") {
                openWindow(id: "main")
            }
        }
        .padding()
        .frame(width: 260)
    }
}
