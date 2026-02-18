import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var syncController: SyncController

    var body: some View {
        VStack(spacing: 12) {
            Text("SpillAura")
                .font(.headline)
            Text("M1 — Setup only")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 260)
    }
}
