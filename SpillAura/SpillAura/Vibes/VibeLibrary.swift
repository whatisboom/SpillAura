import Foundation
import Combine

/// Manages the full vibe collection: 8 built-ins + user-created custom vibes.
///
/// Built-ins are always prepended. Custom vibes are persisted as JSON in Application Support.
@MainActor
final class VibeLibrary: ObservableObject {

    @Published private(set) var vibes: [Vibe] = []

    private let fileURL: URL

    init() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("SpillAura", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        fileURL = appSupport.appendingPathComponent("custom-vibes.json")
        load()
    }

    // MARK: - Mutation

    /// Persist a custom vibe (insert or update by ID).
    func save(_ vibe: Vibe) {
        var custom = loadCustom()
        if let idx = custom.firstIndex(where: { $0.id == vibe.id }) {
            custom[idx] = vibe
        } else {
            custom.append(vibe)
        }
        writeCustom(custom)
    }

    /// Delete a custom vibe by ID. No-op for built-ins.
    func delete(_ vibe: Vibe) {
        var custom = loadCustom()
        custom.removeAll { $0.id == vibe.id }
        writeCustom(custom)
    }

    // MARK: - Private

    private func load() {
        vibes = BuiltinVibes.all + loadCustom()
    }

    private func loadCustom() -> [Vibe] {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Vibe].self, from: data) else {
            return []
        }
        return decoded
    }

    private func writeCustom(_ custom: [Vibe]) {
        if let data = try? JSONEncoder().encode(custom) {
            try? data.write(to: fileURL)
        }
        vibes = BuiltinVibes.all + custom
    }
}
