import Foundation
import Combine

/// Manages the full aura collection: 8 built-ins + user-created custom auras.
///
/// Built-ins are always prepended. Custom auras are persisted as JSON in Application Support.
@MainActor
public final class AuraLibrary: ObservableObject {

    @Published public private(set) var auras: [Aura] = []

    private let fileURL: URL

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let appSupport = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("SpillAura", isDirectory: true)
            try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
            self.fileURL = appSupport.appendingPathComponent("custom-auras.json")
        }
        load()
    }

    // MARK: - Mutation

    /// Persist a custom aura (insert or update by ID).
    public func save(_ aura: Aura) {
        var custom = loadCustom()
        if let idx = custom.firstIndex(where: { $0.id == aura.id }) {
            custom[idx] = aura
        } else {
            custom.append(aura)
        }
        writeCustom(custom)
    }

    /// Delete a custom aura by ID. No-op for built-ins.
    public func delete(_ aura: Aura) {
        guard !isBuiltin(aura) else { return }
        var custom = loadCustom()
        custom.removeAll { $0.id == aura.id }
        writeCustom(custom)
    }

    // MARK: - Builtin helpers

    public func isBuiltin(_ aura: Aura) -> Bool {
        BuiltinAuras.all.contains { $0.id == aura.id }
    }

    /// Removes any custom override for a built-in aura, reverting it to its default. No-op for custom auras.
    public func reset(_ aura: Aura) {
        guard isBuiltin(aura) else { return }
        var custom = loadCustom()
        custom.removeAll { $0.id == aura.id }
        writeCustom(custom)
    }

    // MARK: - Private

    private func load() {
        let custom = loadCustom()
        let customByID = Dictionary(custom.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        let merged = BuiltinAuras.all.map { builtin in customByID[builtin.id] ?? builtin }
        let builtinIDs = Set(BuiltinAuras.all.map(\.id))
        let customOnly = custom.filter { !builtinIDs.contains($0.id) }
        auras = merged + customOnly
    }

    private func loadCustom() -> [Aura] {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Aura].self, from: data) else {
            return []
        }
        return decoded
    }

    private func writeCustom(_ custom: [Aura]) {
        do {
            let data = try JSONEncoder().encode(custom)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[AuraLibrary] Failed to write custom auras: \(error)")
        }
        load()
    }
}
