import SwiftUI

/// Scrollable vibe browser for the main window's Vibe mode.
/// While stopped: tapping a card updates `selectedVibe` binding for the Start button.
/// While streaming: tapping a card hot-swaps immediately.
struct VibeControlView: View {
    @EnvironmentObject var syncController: SyncController
    @EnvironmentObject var vibeLibrary: VibeLibrary
    @Binding var selectedVibe: Vibe?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(vibeLibrary.vibes) { vibe in
                    VibeCard(
                        vibe: vibe,
                        isSelected: syncController.connectionStatus == .streaming
                            ? syncController.activeVibe?.id == vibe.id
                            : selectedVibe?.id == vibe.id
                    )
                    .onTapGesture {
                        if syncController.connectionStatus == .streaming {
                            syncController.startVibe(vibe)
                        } else {
                            selectedVibe = vibe
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .onAppear {
            if selectedVibe == nil { selectedVibe = vibeLibrary.vibes.first }
        }
    }
}

// MARK: - VibeCard

private struct VibeCard: View {
    let vibe: Vibe
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            swatchStrip
            Text(vibe.name)
                .fontWeight(.medium)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected
            ? Color.accentColor.opacity(0.12)
            : Color(nsColor: .controlBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    isSelected ? Color.accentColor : Color.secondary.opacity(0.2),
                    lineWidth: isSelected ? 1.5 : 0.5
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
    }

    private var swatchStrip: some View {
        HStack(spacing: 2) {
            ForEach(Array(vibe.palette.enumerated()), id: \.offset) { _, c in
                Rectangle()
                    .fill(Color(red: c.red, green: c.green, blue: c.blue))
            }
        }
        .frame(width: 52, height: 32)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

}
