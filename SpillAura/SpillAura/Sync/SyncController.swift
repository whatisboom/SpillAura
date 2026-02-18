import Foundation

@MainActor
class SyncController: ObservableObject {
    @Published var isRunning = false
    @Published var connectionStatus: ConnectionStatus = .disconnected

    enum ConnectionStatus {
        case disconnected, connecting, streaming, error(String)
    }
}
