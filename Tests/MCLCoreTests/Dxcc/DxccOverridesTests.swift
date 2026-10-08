import Foundation
import Testing
@testable import MCLCore

/// The own call → country list (N1MM „Add call to country") and the lookup that asks it first.
@Suite struct DxccOverridesTests {

    private static func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("mcl-dxcc-ovr-" + UUID().uuidString, isDirectory: true)
            .appendingPathComponent(DxccOverrideStore.fileName)
    }

    private static func base() throws -> any DxccLookup {
        try SessionFixture.dxcc()
    }

    @Test func callsAreNormalisedAndReplaced() {
        let store = DxccOverrideStore(file: nil)
        #expect(store.set(call: "  ok1xyz ", dxcc: 230, name: "Germany") == "OK1XYZ")
        #expect(store.set(call: "OK1XYZ", dxcc: 1, name: "Canada") == "OK1XYZ")
        #expect(store.all == [DxccOverrideStore.Entry(call: "OK1XYZ", dxcc: 1, name: "Canada")])
        #expect(store.set(call: "   ", dxcc: 1, name: "x") == nil)
        #expect(store.number(for: "ok1xyz") == 1)
        #expect(store.number(for: "OK1XYZ/P") == 1)
        #expect(store.number(for: "ok1xyz/m") == 1)
        #expect(store.number(for: "OK1XYZ/QRP") == 1)
        #expect(store.number(for: "OK1XYZ/MM") == nil)
        #expect(store.number(for: "DL/OK1XYZ") == nil)
        #expect(store.number(for: nil) == nil)
        #expect(store.remove(call: " ok1xyz "))
        #expect(!store.remove(call: "OK1XYZ"))
        #expect(store.number(for: "OK1XYZ") == nil)
    }

    @Test func theFileRoundTripsAndDamageIsEmpty() throws {
        let file = Self.tempFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = DxccOverrideStore(file: file)
        store.set(call: "OK1XYZ", dxcc: 230, name: "Germany")
        store.set(call: "W1ABC", dxcc: 503, name: "Czech Republic")
        try store.save()

        let again = DxccOverrideStore(file: file)
        again.load()
        #expect(again.all == store.all)
        #expect(again.number(for: "W1ABC") == 503)

        try Data("not json".utf8).write(to: file)
        again.load()
        #expect(again.all.isEmpty)
        let missing = DxccOverrideStore(file: file.deletingLastPathComponent().appendingPathComponent("none.json"))
        missing.load()
        #expect(missing.all.isEmpty)
    }

    @Test func aFileWithRepeatedOrBlankCallsIsCleaned() throws {
        let file = Self.tempFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let json = #"{"version":1,"overrides":[{"call":"ok1xyz","dxcc":230,"name":"G"},"#
            + #"{"call":" ","dxcc":1,"name":"x"},{"call":"OK1XYZ","dxcc":1,"name":"C"}]}"#
        try Data(json.utf8).write(to: file)
        let store = DxccOverrideStore(file: file)
        store.load()
        #expect(store.all == [DxccOverrideStore.Entry(call: "OK1XYZ", dxcc: 230, name: "G")])
    }

    @Test func anOverrideIsAskedBeforeTheCountryData() throws {
        let base = try Self.base()
        let store = DxccOverrideStore(file: nil)
        let lookup = DxccOverrideLookup(base, store: store)
        #expect(lookup.resolve("OK1XYZ")?.entityCode == 503)
        store.set(call: "OK1XYZ", dxcc: 230, name: "Germany")
        #expect(lookup.resolve("OK1XYZ")?.entityCode == 230)
        #expect(lookup.resolve("OK1XYZ")?.name == "Germany")
        #expect(lookup.resolve("OK1XYZ/P")?.entityCode == 230)
        // The dated lookup too, and other calls are untouched.
        #expect(lookup.resolve("OK1XYZ", at: Date())?.entityCode == 230)
        #expect(lookup.resolve("OK1ABC")?.entityCode == 503)
        #expect(lookup.entities() == base.entities())
        store.remove(call: "OK1XYZ")
        #expect(lookup.resolve("OK1XYZ")?.entityCode == 503)
    }

    @Test func anOverrideNamingAnUnknownEntityIsIgnored() throws {
        let store = DxccOverrideStore(file: nil)
        store.set(call: "OK1XYZ", dxcc: 424_242, name: "Gone")
        let lookup = DxccOverrideLookup(try Self.base(), store: store)
        #expect(lookup.resolve("OK1XYZ")?.entityCode == 503)
    }

    @Test func theEnvironmentAsksTheOverridesFirst() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcl-dxcc-env-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try DxccTestFixture.data().write(to: dir.appendingPathComponent("dxcc.json"))
        let contestData = try SessionFixture.contestData()
        let store = DxccOverrideStore(file: nil)
        store.set(call: "OK1XYZ", dxcc: 291, name: "United States")

        let plain = ContestEnvironment.load(dataRoot: contestData.path, dxccDir: dir.path,
                                            fallbackDataRoot: "/nonexistent")
        let overridden = ContestEnvironment.load(dataRoot: contestData.path, dxccDir: dir.path,
                                                 fallbackDataRoot: "/nonexistent", overrides: store)
        #expect(plain.dxcc?.resolve("OK1XYZ")?.entityCode == 503)
        #expect(overridden.dxcc?.resolve("OK1XYZ")?.entityCode == 291)
        #expect(overridden.engineAvailable)
    }
}
