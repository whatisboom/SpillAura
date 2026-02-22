import Foundation
import Security

struct BridgeCredentials: Codable {
    let bridgeIP: String
    let username: String    // used as REST API header: hue-application-key
    let clientKey: String   // hex string, PSK for DTLS in M2
}

enum AuthError: LocalizedError {
    case linkButtonNotPressed
    case networkError(Error)
    case unexpectedResponse(String)

    var errorDescription: String? {
        switch self {
        case .linkButtonNotPressed:
            return "Press the link button on your Hue bridge, then try again."
        case .networkError(let err):
            return "Network error: \(err.localizedDescription)"
        case .unexpectedResponse(let detail):
            return "Unexpected response: \(detail)"
        }
    }
}

final class HueBridgeAuth {

    private static let keychainService = "com.spillaura.bridge"
    private static let keychainAccount = "credentials"

    // MARK: - Pairing

    func pair(bridgeIP: String) async throws -> BridgeCredentials {
        guard let url = URL(string: "http://\(bridgeIP)/api") else {
            throw AuthError.unexpectedResponse("Invalid bridge IP: \(bridgeIP)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        request.httpBody = try JSONEncoder().encode(PairRequestBody())

        let (data, _): (Data, URLResponse)
        do {
            (data, _) = try await URLSession.shared.data(for: request)
        } catch {
            throw AuthError.networkError(error)
        }

        // Response is an array: [{"success": {"username": "...", "clientkey": "..."}}]
        // or [{"error": {"type": 101, "description": "link button not pressed"}}]
        let entries: [PairResponseEntry]
        do {
            entries = try JSONDecoder().decode([PairResponseEntry].self, from: data)
        } catch {
            throw AuthError.unexpectedResponse(String(data: data, encoding: .utf8) ?? "empty")
        }

        guard let first = entries.first else {
            throw AuthError.unexpectedResponse("Empty response array")
        }

        if let pairError = first.error, pairError.type == 101 {
            throw AuthError.linkButtonNotPressed
        }

        guard let success = first.success else {
            let detail = first.error?.description ?? "no success or error in response"
            throw AuthError.unexpectedResponse(detail)
        }

        let username = success.username
        let clientKey = success.clientkey

        let credentials = BridgeCredentials(
            bridgeIP: bridgeIP,
            username: username,
            clientKey: clientKey
        )

        try saveToKeychain(credentials)
        return credentials
    }

    // MARK: - Keychain

    func saveToKeychain(_ credentials: BridgeCredentials) throws {
        let data = try JSONEncoder().encode(credentials)

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.keychainService,
            kSecAttrAccount: Self.keychainAccount,
            kSecValueData: data
        ]

        SecItemDelete(query as CFDictionary)  // remove old entry if it exists
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    func loadFromKeychain() -> BridgeCredentials? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.keychainService,
            kSecAttrAccount: Self.keychainAccount,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data else { return nil }

        // Try JSON format first (new), then fall back to legacy pipe-separated format
        if let credentials = try? JSONDecoder().decode(BridgeCredentials.self, from: data) {
            return credentials
        }

        // Legacy format: "bridgeIP|username|clientKey"
        guard let value = String(data: data, encoding: .utf8) else { return nil }
        let parts = value.components(separatedBy: "|")
        guard parts.count == 3 else { return nil }
        return BridgeCredentials(bridgeIP: parts[0], username: parts[1], clientKey: parts[2])
    }

    // MARK: - Entertainment Configuration

    struct EntertainmentGroup: Identifiable {
        let id: String       // group resource ID (UUID string)
        let name: String
        let channelCount: Int
    }

    func fetchEntertainmentGroups(credentials: BridgeCredentials) async throws -> [EntertainmentGroup] {
        guard let url = URL(string: "https://\(credentials.bridgeIP)/clip/v2/resource/entertainment_configuration") else {
            throw AuthError.unexpectedResponse("Invalid bridge IP: \(credentials.bridgeIP)")
        }
        var request = URLRequest(url: url)
        request.setValue(credentials.username, forHTTPHeaderField: HueHeader.applicationKey)

        // The bridge uses a self-signed cert — bypass validation for local connections
        let session = URLSession(configuration: .default, delegate: HueBridgeCertDelegate(), delegateQueue: nil)
        let (data, _) = try await session.data(for: request)

        let response: HueResponse<EntertainmentConfigResource>
        do {
            response = try JSONDecoder().decode(HueResponse<EntertainmentConfigResource>.self, from: data)
        } catch {
            throw AuthError.unexpectedResponse(String(data: data, encoding: .utf8) ?? "empty")
        }

        return response.data.map { resource in
            EntertainmentGroup(id: resource.id, name: resource.metadata.name, channelCount: resource.channels.count)
        }
    }
}