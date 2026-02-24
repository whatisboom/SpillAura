import SwiftUI
import SpillAuraCore

struct MainWindow: View {
    @EnvironmentObject var syncController: SyncController
    @EnvironmentObject var auraLibrary: AuraLibrary
    @Environment(\.openWindow) private var openWindow

    @State private var selectedAura: Aura? = nil

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Divider()

            contentArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            controlRows
                .padding(.horizontal, 20)
                .padding(.vertical, 10)

            Divider()

            bottomBar
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        .frame(minWidth: 360, minHeight: 520)
    }

    // MARK: - Top Bar

    @ViewBuilder
    private var topBar: some View {
        HStack {
            Picker("", selection: $syncController.selectedMode) {
                ForEach(SyncMode.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: UIConstants.Size.modePickerMaxWidth)
            .help("Switch between Aura mode (animated color cycles) and Screen Sync (mirrors your display content in real time).")
            .onChange(of: syncController.selectedMode) { _, newMode in
                guard syncController.connectionStatus == .streaming else { return }
                switch newMode {
                case .aura:
                    let aura = selectedAura ?? auraLibrary.auras.first
                    if let aura { syncController.startAura(aura) }
                case .screen:
                    syncController.startScreenSync()
                }
            }

            Spacer()

            StatusBadge(status: syncController.connectionStatus)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentArea: some View {
        switch syncController.selectedMode {
        case .aura:
            AuraControlView(selectedAura: $selectedAura)
        case .screen:
            ScreenSyncView()
        }
    }

    // MARK: - Control Rows (speed + brightness)

    private var controlRows: some View {
        HStack(spacing: 10) {
            if syncController.selectedMode == .aura {
                Image(systemName: "tortoise").foregroundStyle(.secondary)
                Slider(value: $syncController.speedMultiplier, in: 0.25...1.5)
                    .help("How fast the color animation cycles. Slower is ambient; faster is energetic.")
                    .accessibilityLabel("Animation speed")
                Image(systemName: "hare").foregroundStyle(.secondary)

                Divider().frame(height: 16)
            }

            Image(systemName: "sun.min").foregroundStyle(.secondary)
            Slider(value: $syncController.brightness, in: 0...1)
                .help("Master brightness for all lights.")
                .accessibilityLabel("Brightness")
            Image(systemName: "sun.max").foregroundStyle(.secondary)
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            Button {
                openWindow(id: "settings")
            } label: {
                Image(systemName: "gear").imageScale(.large)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Open Settings to configure your bridge, screen zones, and launch behavior.")
            .accessibilityLabel("Settings")

            Spacer()

            if syncController.connectionStatus == .disconnected {
                Button("Start") {
                    switch syncController.selectedMode {
                    case .aura:
                        if let a = selectedAura ?? auraLibrary.auras.first {
                            syncController.startAura(a)
                        }
                    case .screen:
                        syncController.startScreenSync()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(syncController.selectedMode == .aura && auraLibrary.auras.isEmpty)
                .help("Begin streaming to your lights.")
            } else {
                Button("Stop") { syncController.stop() }
                    .buttonStyle(.bordered)
                    .help("Stop streaming. Your lights will return to their previous state.")
            }
        }
        .frame(minHeight: 28)
    }
}
