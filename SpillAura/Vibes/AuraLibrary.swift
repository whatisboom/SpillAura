import Foundation
import Combine

/// Manages the full aura collection: 8 built-ins + user-created custom auras.
///
/// Built-ins are always prepended. Custom auras are persisted as JSON in Application Support.
@MainActor
final class AuraLibrary: ObservableObject {

    @Published private(set) var auras: [Aura] = []

    private let fileURL: URL

    init() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("SpillAura", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        fileURL = appSupport.appendingPathComponent("custom-auras.json")
        load()
    }

    // MARK: - Mutation

    /// Persist a custom aura (insert or update by ID).
    func save(_ aura: Aura) {
        var custom = loadCustom()
        if let idx = custom.firstIndex(where: { $0.id == aura.id }) {
            custom[idx] = aura
        } else {
            custom.append(aura)
        }
        writeCustom(custom)
    }

    /// Delete a custom aura by ID. No-op for built-ins.
    func delete(_ aura: Aura) {
        var custom = loadCustom()
        custom.removeAll { $0.id == aura.id }
        writeCustom(custom)
    }

    // MARK: - Private

    private func load() {
        auras = BuiltinAuras.all + loadCustom()
    }

    private func loadCustom() -> [Aura] {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Aura].self, from: data) else {
            return []
        }
        return decoded
    }

    private func writeCustom(_ custom: [Aura]) {
        if let data = try? JSONEncoder().encode(custom) {
            try? data.write(to: fileURL)
        }
        auras = BuiltinAuras.all + custom
    }
}
