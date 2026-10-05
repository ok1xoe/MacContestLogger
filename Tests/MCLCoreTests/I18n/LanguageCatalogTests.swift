import Foundation
import Testing
@testable import MCLCore

/// Port of the Java `LanguageCatalogTest` (6 tests, same names) — files in a temporary directory.
@Suite struct LanguageCatalogTests {

    static func withTemporaryDirectory(_ body: (String) throws -> Void) throws {
        let dir: String = NSTemporaryDirectory() + "i18n-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        try body(dir)
    }

    /// `Files.writeString(dir.resolve(name), json, UTF_8)` — the name verbatim (without conversion to NFD).
    struct WriteError: Error {
        let path: String
    }

    /// An error is thrown (not `precondition`), so that `defer` in `withTemporaryDirectory` cleans up the directory.
    static func write(_ dir: String, _ name: String, _ json: String) throws {
        try writeBytes(dir + "/" + name, Array(json.utf8))
    }

    static func writeBytes(_ path: String, _ bytes: [UInt8]) throws {
        let descriptor: Int32 = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        guard descriptor >= 0 else { throw WriteError(path: path) }
        defer { close(descriptor) }
        let written: Int = bytes.withUnsafeBytes { Darwin.write(descriptor, $0.baseAddress, $0.count) }
        guard written == bytes.count else { throw WriteError(path: path) }
    }

    @Test func findsFilesByConvention() throws {
        try Self.withTemporaryDirectory { dir in
            try Self.write(dir, "lang_en.json", "{\"_name\": \"English\", \"Skóre\": \"Score\"}")
            try Self.write(dir, "lang_de.json", "{\"_name\": \"Deutsch\"}")
            try Self.write(dir, "poznamky.txt", "nic")
            try Self.write(dir, "en.json", "{}")

            let langs: [LanguageCatalog.Language] = LanguageCatalog.list(dir)
            #expect(langs.map(\.code) == ["de", "en"])
            #expect(langs[0].label == "Deutsch")
            #expect(langs[1].label == "English")
        }
    }

    @Test func withoutOwnNameTheCodeServesAsLabel() throws {
        try Self.withTemporaryDirectory { dir in
            try Self.write(dir, "lang_pl.json", "{\"Skóre\": \"Wynik\"}")
            #expect(LanguageCatalog.list(dir)[0].label == "PL")
        }
    }

    @Test func brokenFileIsListedButTranslationIsEmpty() throws {
        // A broken translation must not bring down the start — it is just not translated.
        try Self.withTemporaryDirectory { dir in
            try Self.write(dir, "lang_xx.json", "{tohle není JSON")
            let langs: [LanguageCatalog.Language] = LanguageCatalog.list(dir)
            #expect(langs.count == 1, "the file is in the menu so the user sees that it is there")
            #expect(LanguageCatalog.load(langs[0].file).isEmpty)
        }
    }

    @Test func loadsKeysAndSkipsMetadata() throws {
        try Self.withTemporaryDirectory { dir in
            try Self.write(dir, "lang_sk.json", "{\"_name\": \"Slovenčina\", \"Skóre\": \"Skóre\", \"Deník\": \"Denník\"}")
            let map: LanguageCatalog.Translations = LanguageCatalog.load(dir + "/lang_sk.json")
            #expect(map["Deník"] == "Denník")
            #expect(map["_name"] != nil, "metadata stays in the map, the translation does not use it")
            #expect(map.count == 3)
        }
    }

    @Test func missingDirectoryIsHarmless() throws {
        try Self.withTemporaryDirectory { dir in
            #expect(LanguageCatalog.list(dir + "/neni").isEmpty)
            #expect(LanguageCatalog.load(dir + "/lang_x.json") == .empty)
            #expect(LanguageCatalog.list(nil as String?).isEmpty)
        }
    }

    @Test func codeIsTakenFromNamingConvention() throws {
        try Self.withTemporaryDirectory { dir in
            try Self.write(dir, "lang_pt_BR.json", "{}")
            try Self.write(dir, "lang_.json", "{}")
            #expect(LanguageCatalog.list(dir).map(\.code) == ["pt_BR"], "an empty code is skipped")
        }
    }
}
