import Foundation
import Network
import Combine

@MainActor
class HueBridgeDiscovery: ObservableObject {
    @Published var discoveredBridges: [DiscoveredBridge] = []
    @Published var isSearching = false

    private var browser: NWBrowser?

    struct DiscoveredBridge: Identifiable, Equatable {
        let id = UUID()
        let name: String
        let host: String
    }

    func startDiscovery() {
        isSearching = true
        discoveredBridges = []

        let params = NWParameters()
        params.includePeerToPeer = false

        browser = NWBrowser(
            for: .bonjourWithTXTRecord(type: "_hue._tcp", domain: "local."),
            using: params
        )

        browser?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed(let error):
                print("mDNS browser failed: \(error)")
                Task { @MainActor [weak self] in
                    self?.isSearching = false
                }
            default:
                break
            }
        }

        browser?.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor [weak self] in
                self?.handleResults(results)
            }
        }

        browser?.start(queue: .main)
    }

    func stopDiscovery() {
        browser?.cancel()
        browser = nil
        isSearching = false
    }

    private func handleResults(_ results: Set<NWBrowser.Result>) {
        for result in results {
            if case let .service(name, _, _, _) = result.endpoint {
                let endpoint = result.endpoint
                resolveEndpoint(endpoint, name: name) { [weak self] host in
                    guard let host else { return }
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        let bridge = DiscoveredBridge(name: name, host: host)
                        if !self.discoveredBridges.contains(bridge) {
                            self.discoveredBridges.append(bridge)
                        }
                    }
                }
            }
        }
    }

    private func resolveEndpoint(_ endpoint: NWEndpoint, name: String, completion: @escaping (String?) -> Void) {
        let connection = NWConnection(to: endpoint, using: .tcp)
        connection.stateUpdateHandler = { state in
            if case .ready = state {
                if let remote = connection.currentPath?.remoteEndpoint,
                   case let .hostPort(host, _) = remote {
                    let hostString = "\(host)"
                    // Strip interface suffix if present (e.g. "192.168.1.1%en0")
                    let cleanHost = hostString.components(separatedBy: "%").first ?? hostString
                    completion(cleanHost)
                } else {
                    completion(nil)
                }
                connection.cancel()
            } else if case .failed = state {
                completion(nil)
                connection.cancel()
            }
        }
        connection.start(queue: .global())
    }
}
