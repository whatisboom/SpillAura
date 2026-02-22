import SwiftUI
import SpillAuraCore

/// Scrollable aura browser for the main window's Aura mode.
/// While stopped: tapping a card updates `selectedAura` binding for the Start button.
/// While streaming: tapping a card hot-swaps immediately.
struct AuraControlView: View {
    @EnvironmentObject var syncController: SyncController
    @EnvironmentObject var auraLibrary: AuraLibrary
    @Binding var selectedAura: Aura?

    @State private var editingAura: Aura? = nil
    @State private var isCreating = false

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
                    .contextMenu {
                        Button("Edit") {
                            editingAura = aura
                        }

                        if auraLibrary.isBuiltin(aura) {
                            Button("Reset to Default") {
                                auraLibrary.reset(aura)
                                // If the streaming aura was reset, hot-swap the reverted version
                                if syncController.connectionStatus == .streaming,
                                   syncController.activeAura?.id == aura.id,
                                   let reverted = auraLibrary.auras.first(where: { $0.id == aura.id }) {
                                    syncController.startAura(reverted)
                                }
                            }
                        } else {
                            Button("Delete", role: .destructive) {
                                auraLibrary.delete(aura)
                            }
                        }
                    }
                }

                // "New Aura" footer button
                Button {
                    isCreating = true
                } label: {
                    Label("New Aura", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .padding(.top, 4)
                .help("Create a new custom aura")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .onAppear {
            if selectedAura == nil { selectedAura = auraLibrary.auras.first }
        }
        .sheet(item: $editingAura) { aura in
            AuraEditorSheet(aura: aura)
                .environmentObject(auraLibrary)
                .onDisappear {
                    // Hot-swap if this aura is currently streaming
                    if syncController.connectionStatus == .streaming,
                       syncController.activeAura?.id == aura.id,
                       let updated = auraLibrary.auras.first(where: { $0.id == aura.id }) {
                        syncController.startAura(updated)
                    }
                }
        }
        .sheet(isPresented: $isCreating) {
            AuraEditorSheet()
                .environmentObject(auraLibrary)
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
            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.card)
                .stroke(
                    isSelected ? Color.accentColor : Color.secondary.opacity(0.2),
                    lineWidth: isSelected ? 1.5 : 0.5
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: UIConstants.CornerRadius.card))
        .contentShape(Rectangle())
        .help("Select this aura. While streaming, swapping takes effect immediately — no need to stop.")
    }

    private var swatchStrip: some View {
        HStack(spacing: 2) {
            ForEach(Array(aura.palette.enumerated()), id: \.offset) { _, c in
                Rectangle()
                    .fill(Color(red: c.red, green: c.green, blue: c.blue))
            }
        }
        .frame(width: UIConstants.Size.swatchStripWidth, height: UIConstants.Size.swatchStripHeight)
        .clipShape(RoundedRectangle(cornerRadius: UIConstants.CornerRadius.swatch))
        .help("Color palette for this aura. These colors cycle or bounce through your lights during playback.")
        .accessibilityLabel("\(aura.palette.count) colors")
    }
}
