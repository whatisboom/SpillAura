import Foundation
import Combine

@MainActor
final class HueBridgeDiscovery: NSObject, ObservableObject {
    @Published var discoveredBridges: [DiscoveredBridge] = []
    @Published var isSearching = false

    private var netBrowser: NetServiceBrowser?
    private var resolvingServices: [NetService] = []
    private var discoveryStartDate: Date?

    struct DiscoveredBridge: Identifiable, Equatable {
        let id = UUID()
        let name: String
        let host: String  // hostname (e.g. "Living-Room.local") or IP
    }

    func startDiscovery() {
        isSearching = true
        discoveryStartDate = Date()
        discoveredBridges = []
        resolvingServices = []

        netBrowser = NetServiceBrowser()
        netBrowser?.delegate = self
        netBrowser?.searchForServices(ofType: "_hue._tcp.", inDomain: "local.")

        // Stop the spinner after 4 seconds — browser continues running silently
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            self.isSearching = false
        }
    }

    func stopDiscovery() {
        netBrowser?.stop()
        netBrowser = nil
        for service in resolvingServices { service.stop() }
        resolvingServices = []
        isSearching = false
    }
}

extension HueBridgeDiscovery: NetServiceBrowserDelegate {
    nonisolated func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        service.delegate = self
        service.resolve(withTimeout: 5)
        Task { @MainActor in
            self.resolvingServices.append(service)
        }
    }

    nonisolated func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        Task { @MainActor in
            self.isSearching = false
        }
    }
}

extension HueBridgeDiscovery: NetServiceDelegate {
    nonisolated func netServiceDidResolveAddress(_ sender: NetService) {
        guard let hostName = sender.hostName else { return }
        // Strip trailing dot from hostname (e.g. "Living-Room.local." → "Living-Room.local")
        let cleanHost = hostName.hasSuffix(".") ? String(hostName.dropLast()) : hostName
        let name = sender.name
        sender.stop()
        Task { @MainActor in
            self.resolvingServices.removeAll { $0 === sender }
            let bridge = DiscoveredBridge(name: name, host: cleanHost)
            if !self.discoveredBridges.contains(bridge) {
                self.discoveredBridges.append(bridge)
                let elapsed = self.discoveryStartDate.map { Int(Date().timeIntervalSince($0) * 1000) } ?? 0
                Analytics.send(.bridgeDiscoveryCompleted(method: "mdns", durationMs: elapsed))
            }
        }
    }

    nonisolated func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        print("Failed to resolve \(sender.name): \(errorDict)")
        Task { @MainActor in
            self.resolvingServices.removeAll { $0 === sender }
        }
    }
}
