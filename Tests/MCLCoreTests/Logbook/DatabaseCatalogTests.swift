import Foundation
import Testing
@testable import MCLCore

/// Port of `DatabaseCatalogTest.java` — `DatabaseCatalog` manages a directory
/// of named database files (`{name}.sqlite`) from which the
/// operator picks a logbook.
@Suite struct DatabaseCatalogTests {

    @Test func createListPathFor() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }

        let catalog = try DatabaseCatalog(databasesDir: dir)
        #expect(try catalog.list().isEmpty)
        try catalog.create("radioklub")
        try catalog.create("soukroma")
        #expect(try catalog.list() == ["radioklub", "soukroma"])
        #expect(catalog.pathFor("radioklub") == dir.appendingPathComponent("radioklub.sqlite"))
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("radioklub.sqlite").path))
    }

    @Test func ensureDefaultCreatesDefaultLogbookOnceAndIsIdempotent() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }

        let catalog = try DatabaseCatalog(databasesDir: dir)
        #expect(try catalog.ensureDefault() == "Deník")
        #expect(try catalog.list() == ["Deník"])
        #expect(try catalog.ensureDefault() == "Deník") // idempotent
        #expect(try catalog.list() == ["Deník"])
    }
}
