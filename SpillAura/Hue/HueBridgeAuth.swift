import Foundation
import Security

struct BridgeCredentials {
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

class HueBridgeAuth {

    // MARK: - Pairing

    func pair(bridgeIP: String) async throws -> BridgeCredentials {
        let url = URL(string: "http://\(bridgeIP)/api")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "devicetype": "SpillAura#mac",
            "generateclientkey": true
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _): (Data, URLResponse)
        do {
            (data, _) = try await URLSession.shared.data(for: request)
        } catch {
            throw AuthError.networkError(error)
        }

        // Response is an array: [{"success": {"username": "...", "clientkey": "..."}}]
        // or [{"error": {"type": 101, "description": "link button not pressed"}}]
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = json.first else {
            throw AuthError.unexpectedResponse(String(data: data, encoding: .utf8) ?? "empty")
        }

        if let error = first["error"] as? [String: Any],
           let type_ = error["type"] as? Int, type_ == 101 {
            throw AuthError.linkButtonNotPressed
        }

        guard let success = first["success"] as? [String: Any],
              let username = success["username"] as? String,
              let clientKey = success["clientkey"] as? String else {
            throw AuthError.unexpectedResponse(String(data: data, encoding: .utf8) ?? "empty")
        }

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
        let value = "\(credentials.bridgeIP)|\(credentials.username)|\(credentials.clientKey)"
        let data = value.data(using: .utf8)!

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "com.spillaura.bridge",
            kSecAttrAccount: "credentials",
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
            kSecAttrService: "com.spillaura.bridge",
            kSecAttrAccount: "credentials",
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else { return nil }

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
        let url = URL(string: "https://\(credentials.bridgeIP)/clip/v2/resource/entertainment_configuration")!
        var request = URLRequest(url: url)
        request.setValue(credentials.username, forHTTPHeaderField: "hue-application-key")

        // The bridge uses a self-signed cert — bypass validation for local connections
        let session = URLSession(configuration: .default, delegate: SelfSignedCertDelegate(), delegateQueue: nil)
        let (data, _) = try await session.data(for: request)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let resources = json["data"] as? [[String: Any]] else {
            throw AuthError.unexpectedResponse(String(data: data, encoding: .utf8) ?? "empty")
        }

        return resources.compactMap { resource in
            guard let id = resource["id"] as? String,
                  let metadata = resource["metadata"] as? [String: Any],
                  let name = metadata["name"] as? String,
                  let channels = resource["channels"] as? [[String: Any]] else { return nil }
            return EntertainmentGroup(id: id, name: name, channelCount: channels.count)
        }
    }
}

// Bypasses certificate validation for the Hue bridge's self-signed cert
private class SelfSignedCertDelegate: NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
