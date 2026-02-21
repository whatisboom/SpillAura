import SwiftUI

/// Scrollable aura browser for the main window's Aura mode.
/// While stopped: tapping a card updates `selectedAura` binding for the Start button.
/// While streaming: tapping a card hot-swaps immediately.
struct AuraControlView: View {
    @EnvironmentObject var syncController: SyncController
    @EnvironmentObject var auraLibrary: AuraLibrary
    @Binding var selectedAura: Aura?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(auraLibrary.auras) { aura in
                    AuraCard(
                        aura: aura,
                        isSelected: syncController.connectionStatus == .streaming
                            ? syncController.activeAura?.id == aura.id
                            : selectedAura?.id == aura.id
                    )
                    .onTapGesture {
                        if syncController.connectionStatus == .streaming {
                            syncController.startAura(aura)
                        } else {
                            selectedAura = aura
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .onAppear {
            if selectedAura == nil { selectedAura = auraLibrary.auras.first }
        }
    }
}

// MARK: - AuraCard

private struct AuraCard: View {
    let aura: Aura
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            swatchStrip
            Text(aura.name)
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
            ForEach(Array(aura.palette.enumerated()), id: \.offset) { _, c in
                Rectangle()
                    .fill(Color(red: c.red, green: c.green, blue: c.blue))
            }
        }
        .frame(width: 52, height: 32)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

}
