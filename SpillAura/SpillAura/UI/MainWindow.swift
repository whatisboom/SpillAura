import SwiftUI

struct MainWindow: View {
    @EnvironmentObject var syncController: SyncController
    @EnvironmentObject var vibeLibrary: VibeLibrary
    @Environment(\.openWindow) private var openWindow

    @State private var mode: Mode = .vibe
    @State private var selectedVibe: Vibe? = nil

    private enum Mode: String, CaseIterable {
        case vibe = "Vibe"
        case screen = "Screen"
    }

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
        .frame(minWidth: 480, minHeight: 520)
    }

    // MARK: - Top Bar

    @ViewBuilder
    private var topBar: some View {
        HStack {
            Picker("", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 160)
            .onChange(of: mode) { _, _ in
                if syncController.connectionStatus != .disconnected {
                    syncController.stop()
                }
            }

            Spacer()

            statusBadge
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch syncController.connectionStatus {
        case .disconnected:
            Label("Disconnected", systemImage: "circle")
                .foregroundStyle(.secondary)
                .font(.caption)

        case .connecting:
            HStack(spacing: 5) {
                ProgressView().scaleEffect(0.55)
                Text("Connecting…").font(.caption).foregroundStyle(.secondary)
            }

        case .streaming:
            Label("Streaming", systemImage: "circle.fill")
                .foregroundStyle(.green)
                .font(.caption)

        case .error(let msg):
            Label(msg, systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .font(.caption)
                .lineLimit(2)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentArea: some View {
        switch mode {
        case .vibe:
            VibeControlView(selectedVibe: $selectedVibe)
        case .screen:
            ScreenSyncView()
        }
    }

    // MARK: - Control Rows (speed + brightness)

    private var controlRows: some View {
        HStack(spacing: 10) {
            if mode == .vibe {
                Image(systemName: "tortoise").foregroundStyle(.secondary)
                Slider(value: $syncController.speedMultiplier, in: 0.25...3.0)
                    .frame(width: 100)
                Image(systemName: "hare").foregroundStyle(.secondary)

                Divider().frame(height: 16)
            }

            Image(systemName: "sun.min").foregroundStyle(.secondary)
            Slider(value: $syncController.brightness, in: 0...1)
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

            Spacer()

            if syncController.connectionStatus == .disconnected {
                Button("Start") {
                    switch mode {
                    case .vibe:
                        if let v = selectedVibe ?? vibeLibrary.vibes.first {
                            syncController.startVibe(v)
                        }
                    case .screen:
                        syncController.startScreenSync()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(mode == .vibe && vibeLibrary.vibes.isEmpty)
            } else {
                Button("Stop") { syncController.stop() }
                    .buttonStyle(.bordered)
            }
        }
    }
}
