import Foundation

/// CLIP v2 envelope: `{"data": [...]}`.
struct HueResponse<T: Decodable>: Decodable {
    let data: [T]
}

/// A single entertainment configuration resource from CLIP v2.
struct EntertainmentConfigResource: Decodable {
    let id: String
    let metadata: Metadata
    let channels: [Channel]
    let status: String?

    struct Metadata: Decodable {
        let name: String
    }

    struct Channel: Decodable {}
}

// MARK: - Pairing (v1 API)

/// Request body for `POST /api` pairing.
struct PairRequestBody: Encodable {
    let devicetype = "SpillAura#mac"
    let generateclientkey = true
}

/// One entry in the `[{...}]` array returned by `POST /api`.
struct PairResponseEntry: Decodable {
    let success: PairSuccess?
    let error: PairError?
}

struct PairSuccess: Decodable {
    let username: String
    let clientkey: String
}

struct PairError: Decodable {
    let type: Int
    let description: String
}

// MARK: - Entertainment Action (PUT body)

struct EntertainmentAction: Encodable {
    let action: String
}
