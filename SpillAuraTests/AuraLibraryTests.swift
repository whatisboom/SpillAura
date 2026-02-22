import XCTest
import SpillAuraCore

@MainActor
final class AuraLibraryTests: XCTestCase {

    // MARK: - Cleanup

    private var tempURLs: [URL] = []

    override func tearDown() {
        for url in tempURLs {
            try? FileManager.default.removeItem(at: url)
        }
        tempURLs.removeAll()
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeLibrary(custom: [Aura] = []) -> AuraLibrary {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json")
        tempURLs.append(url)
        if !custom.isEmpty,
           let data = try? JSONEncoder().encode(custom) {
            try? data.write(to: url)
        }
        return AuraLibrary(fileURL: url)
    }

    private func customAura(
        id: UUID = UUID(),
        name: String = "Custom"
    ) -> Aura {
        Aura(
            id: id,
            name: name,
            type: .dynamic,
            palette: [
                CodableColor(red: 1, green: 0, blue: 0),
                CodableColor(red: 0, green: 0, blue: 1),
            ],
            speed: 0.5,
            pattern: .cycle,
            channelOffset: 0.2
        )
    }

    // MARK: - Initial load

    func test_freshLibrary_contains8Builtins() {
        let lib = makeLibrary()
        XCTAssertEqual(lib.auras.count, 8)
    }

    func test_freshLibrary_builtinsInOrder() {
        let lib = makeLibrary()
        // BuiltinAuras.all = [disco, neon, fire, warmSunset, forest, ocean, galaxy, candy]
        XCTAssertEqual(lib.auras[0].id, BuiltinAuras.disco.id)
        XCTAssertEqual(lib.auras[7].id, BuiltinAuras.candy.id)
    }

    // MARK: - Built-in override merge

    func test_customWithBuiltinID_overridesBuiltin() {
        let override = customAura(id: BuiltinAuras.disco.id, name: "My Disco")
        let lib = makeLibrary(custom: [override])
        let disco = lib.auras.first { $0.id == BuiltinAuras.disco.id }
        XCTAssertEqual(disco?.name, "My Disco")
    }

    func test_builtinOverride_preservesPosition() {
        // Disco is index 0 in BuiltinAuras.all
        let override = customAura(id: BuiltinAuras.disco.id, name: "My Disco")
        let lib = makeLibrary(custom: [override])
        XCTAssertEqual(lib.auras[0].name, "My Disco")
    }

    func test_customOnlyAura_appendedAfterBuiltins() {
        let custom = customAura(name: "New One")
        let lib = makeLibrary(custom: [custom])
        XCTAssertEqual(lib.auras.count, 9)
        XCTAssertEqual(lib.auras.last?.name, "New One")
    }

    func test_mixedCustom_overridesAndNewAuras() {
        let override = customAura(id: BuiltinAuras.fire.id, name: "Hot Fire")
        let brandNew = customAura(name: "Brand New")
        let lib = makeLibrary(custom: [override, brandNew])
        XCTAssertEqual(lib.auras.count, 9)
        XCTAssertEqual(lib.auras.first { $0.id == BuiltinAuras.fire.id }?.name, "Hot Fire")
        XCTAssertEqual(lib.auras.last?.name, "Brand New")
    }

    // MARK: - isBuiltin

    func test_isBuiltin_trueForBuiltinID() {
        let lib = makeLibrary()
        XCTAssertTrue(lib.isBuiltin(BuiltinAuras.disco))
    }

    func test_isBuiltin_falseForCustomID() {
        let lib = makeLibrary()
        XCTAssertFalse(lib.isBuiltin(customAura()))
    }

    func test_isBuiltin_trueForOverriddenBuiltin() {
        // Even if saved with different name, same UUID = still builtin
        let override = customAura(id: BuiltinAuras.neon.id, name: "My Neon")
        XCTAssertTrue(makeLibrary().isBuiltin(override))
    }

    // MARK: - save

    func test_save_newCustomAura_appearsInLibrary() {
        let lib = makeLibrary()
        let aura = customAura(name: "Saved")
        lib.save(aura)
        XCTAssertTrue(lib.auras.contains { $0.name == "Saved" })
    }

    func test_save_builtin_createsOverride() {
        let lib = makeLibrary()
        var modified = BuiltinAuras.ocean
        modified.name = "My Ocean"
        lib.save(modified)
        XCTAssertEqual(lib.auras.first { $0.id == BuiltinAuras.ocean.id }?.name, "My Ocean")
    }

    func test_save_persistsAcrossReinit() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json")
        tempURLs.append(url)
        let lib1 = AuraLibrary(fileURL: url)
        lib1.save(customAura(name: "Persist Me"))

        let lib2 = AuraLibrary(fileURL: url)
        XCTAssertTrue(lib2.auras.contains { $0.name == "Persist Me" })
    }

    func test_save_updatesExistingAura() {
        let id = UUID()
        let lib = makeLibrary(custom: [customAura(id: id, name: "Before")])
        var updated = customAura(id: id, name: "After")
        lib.save(updated)
        let names = lib.auras.filter { $0.id == id }.map(\.name)
        XCTAssertEqual(names, ["After"])
    }

    // MARK: - delete

    func test_delete_removesCustomAura() {
        let aura = customAura(name: "Delete Me")
        let lib = makeLibrary(custom: [aura])
        lib.delete(aura)
        XCTAssertFalse(lib.auras.contains { $0.id == aura.id })
    }

    func test_delete_builtin_doesNothing() {
        let lib = makeLibrary()
        lib.delete(BuiltinAuras.galaxy)
        XCTAssertTrue(lib.auras.contains { $0.id == BuiltinAuras.galaxy.id })
    }

    // MARK: - reset

    func test_reset_revertOverriddenBuiltin() {
        let lib = makeLibrary()
        var modified = BuiltinAuras.candy
        modified.name = "My Candy"
        lib.save(modified)
        XCTAssertEqual(lib.auras.first { $0.id == BuiltinAuras.candy.id }?.name, "My Candy")

        lib.reset(modified)
        XCTAssertEqual(lib.auras.first { $0.id == BuiltinAuras.candy.id }?.name, BuiltinAuras.candy.name)
    }

    func test_reset_customAura_isNoOp() {
        let custom = customAura(name: "Stay")
        let lib = makeLibrary(custom: [custom])
        lib.reset(custom) // should do nothing
        XCTAssertTrue(lib.auras.contains { $0.name == "Stay" })
    }

    func test_reset_doesNotRemoveOtherCustomAuras() {
        let override = customAura(id: BuiltinAuras.forest.id, name: "My Forest")
        let other = customAura(name: "Other")
        let lib = makeLibrary(custom: [override, other])
        lib.reset(override)
        XCTAssertTrue(lib.auras.contains { $0.name == "Other" })
    }

    // MARK: - Write failure

    func test_save_toUnwritablePath_doesNotCrash() {
        // Point the library at a path inside a non-existent directory
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("nested")
            .appendingPathComponent("custom-auras.json")
        let lib = AuraLibrary(fileURL: url)
        // This should log an error but not crash
        lib.save(customAura(name: "Should Not Crash"))
        // Builtins still present — library state is consistent
        XCTAssertEqual(lib.auras.count, 8)
    }

    // MARK: - Corrupt JSON

    func test_corruptJSON_treatedAsNoCustomAuras() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json")
        tempURLs.append(url)
        try? "not json".write(to: url, atomically: true, encoding: .utf8)
        let lib = AuraLibrary(fileURL: url)
        XCTAssertEqual(lib.auras.count, 8) // just the 8 builtins
    }
}
