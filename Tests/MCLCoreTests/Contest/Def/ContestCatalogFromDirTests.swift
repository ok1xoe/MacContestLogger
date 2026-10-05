import Foundation
import Testing
@testable import MCLCore

/// `ContestCatalog.fromDir`: port of the Java `ContestCatalogFromDirTest`
/// (4 tests) and a scenario table **measured on Java** by the probe `ProbeCat`
/// (maintainer-only probe, `mkcat.py` → `cat-out.txt` → `gen_cat.py`): for
/// each directory the Java list of ids in catalog order and the skipped files
/// (Java `System.Logger` WARNING "Přeskakuji nevalidní definici <p>: <msg>" — skipping an invalid definition).
///
/// Mapping of Java skip reasons to `ContestDefinitionError`:
/// - `ContestDefinitionException("Nelze načíst definici závodu: " + Jackson)`
///   → `.invalidDefinition` (the cause text is Czech, an allowed divergence),
/// - the same with "java.io.IOException: Is a directory" → `.failure("… Is a directory")`,
/// - `ContestDefinitionException("Nelze načíst definici: <p>")` (open
///   error) → `.failure` with the same path,
/// - `NullPointerException` (dokument `~`/`---`) → `.emptyDefinition`,
/// - `checkVersion` → `.newerSchema`.
@Suite struct ContestCatalogFromDirTests {

    static let definition = """
        schemaVersion: 1
        id: test-cw
        metadata:
          name: Test CW
        modes: [CW]
        exchange:
          sent:
            - { id: rst, type: RST, source: AUTO_RST }
          received:
            - { id: rst, type: RST, required: true }

        """

    // MARK: - Java ContestCatalogFromDirTest

    @Test func loadsYamlFromDir() throws {
        let dir = try Self.makeDirectory([("test-cw.yaml", .text(Self.definition))])
        defer { try? FileManager.default.removeItem(at: dir) }
        let definitions = try ContestCatalog.fromDir(dir)
        #expect(definitions.count == 1)
        #expect(definitions.first?.id == "test-cw")
    }

    @Test func emptyDirYieldsEmptyList() throws {
        let dir = try Self.makeDirectory([])
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(try ContestCatalog.fromDir(dir).isEmpty)
    }

    @Test func skipsInvalidYamlButLoadsRest() throws {
        let dir = try Self.makeDirectory([
            ("ok.yaml", .text(Self.definition)),
            ("broken.yaml", .text("this: : not: valid: yaml")),
        ])
        defer { try? FileManager.default.removeItem(at: dir) }
        let definitions = try ContestCatalog.fromDir(dir)
        #expect(definitions.count == 1)
        #expect(definitions.first?.id == "test-cw")
    }

    @Test func missingDirYieldsEmptyList() throws {
        let dir = try Self.makeDirectory([])
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(try ContestCatalog.fromDir(dir.appendingPathComponent("nope")).isEmpty)
    }

    // MARK: - table measured on Java

    @Test(arguments: rows)
    func fromDirMatchesJava(_ row: Row) throws {
        let dir = try Self.makeDirectory(row.files)
        defer { try? FileManager.default.removeItem(at: dir) }
        var skipped: [(String, ContestDefinitionError)] = []
        let definitions = try ContestCatalog.fromDir(dir) { path, error in skipped.append((path, error)) }
        #expect(definitions.map(\.id) == row.ids)
        #expect(skipped.map(\.0) == row.skipped.map { dir.path + "/" + $0.0 })
        for ((path, error), (_, expected)) in zip(skipped, row.skipped) {
            #expect(expected.matches(error, path: path), "\(path): \(error)")
        }
    }

    /// Focus 1: a hidden AppleDouble `._cq-ww-cw.yaml` (FAT/SMB disk) is
    /// skipped and the rest is loaded; so is the directory `d.yaml`. The skip is only
    /// logged (`os.Logger`) — the public `fromDir` does not crash.
    @Test func hiddenAppleDoubleAndDirectoryAreSkipped() throws {
        let dir = try Self.makeDirectory([
            ("._cq-ww-cw.yaml", .bytes([0x00, 0x05, 0x16, 0x07, 0x00, 0x02, 0x00, 0x00, 0xB0])),
            ("cq-ww-cw.yaml", .text("id: cq-ww-cw\n")),
            ("d.yaml", .directory),
        ])
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(try ContestCatalog.fromDir(dir).map(\.id) == ["cq-ww-cw"])
    }

    /// Relative directory: paths of skipped files stay relative, as
    /// Java prints them (`cat/broken/c/broken.yaml`); order as for an absolute path.
    @Test func relativeDirectoryKeepsRelativePaths() throws {
        let dir = try Self.makeDirectory([
            ("broken.yaml", .text("this: : not: valid: yaml")),
            ("ok.yaml", .text("id: ok\n")),
            ("B.yaml", .text("id: B\n")),
        ])
        defer { try? FileManager.default.removeItem(at: dir) }
        let relative = MultiplierSetRegistryLoadDirTests.relativePath(to: dir)
        var skipped: [String] = []
        let definitions = try ContestCatalog.fromDir(URL(fileURLWithPath: relative)) { path, _ in
            skipped.append(path)
        }
        #expect(definitions.map(\.id) == ["B", "ok"])
        #expect(skipped == [relative + "/broken.yaml"])
    }

    /// Warning text as in Java: "Přeskakuji nevalidní definici <p>: <msg>".
    @Test func skipMessageMatchesJava() {
        #expect(ContestCatalog.skipMessage(path: "c/a.yaml", error: .newerSchema(2))
                    == "Přeskakuji nevalidní definici c/a.yaml: Novější formát definice (schemaVersion=2), "
                    + "aktualizuj aplikaci. Podporováno: 1")
    }

    /// `nil`, a nonexistent path and a file instead of a directory → empty list.
    @Test func nonDirectoryYieldsEmptyList() throws {
        let dir = try Self.makeDirectory([("f.yaml", .text("id: f\n"))])
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(try ContestCatalog.fromDir(nil).isEmpty)
        #expect(try ContestCatalog.fromDir(dir.appendingPathComponent("does-not-exist")).isEmpty)
        #expect(try ContestCatalog.fromDir(dir.appendingPathComponent("f.yaml")).isEmpty)
    }

    /// Unreadable directory: `Files.list` throws `AccessDeniedException` →
    /// "Nelze projít adresář závodů: <dir>" (measured by `ProbeCat`).
    @Test func unreadableDirectoryFails() throws {
        let dir = try Self.makeDirectory([("a.yaml", .text("id: a\n"))])
        defer {
            chmod(dir.path, 0o755)
            try? FileManager.default.removeItem(at: dir)
        }
        #expect(chmod(dir.path, 0) == 0)
        #expect(throws: ContestDefinitionError.failure("Nelze projít adresář závodů: " + dir.path)) {
            try ContestCatalog.fromDir(dir)
        }
    }

    // MARK: - helpers

    enum FileContent: Sendable {
        case text(String)
        case bytes([UInt8])
        case directory
        case link(String)
    }

    /// Expected skip reason.
    enum Skip: Sendable {
        case invalid
        case openFailed
        case failure(String)
        case empty
        case newer(Int)

        func matches(_ error: ContestDefinitionError, path: String) -> Bool {
            switch (self, error) {
            case (.invalid, .invalidDefinition): return true
            case (.openFailed, .failure(let message)): return message == "Nelze načíst definici: " + path
            case (.failure(let expected), .failure(let message)): return message == expected
            case (.empty, .emptyDefinition): return true
            case (.newer(let expected), .newerSchema(let version)): return version == expected
            default: return false
            }
        }
    }

    struct Row: Sendable, CustomTestStringConvertible {
        let name: String
        let files: [(String, FileContent)]
        let ids: [String?]
        let skipped: [(String, Skip)]

        init(_ name: String, files: [(String, FileContent)], ids: [String?], skipped: [(String, Skip)]) {
            self.name = name
            self.files = files
            self.ids = ids
            self.skipped = skipped
        }

        var testDescription: String { name }
    }

    /// A directory with files; names are written via POSIX with literal bytes
    /// (NFC stays NFC — `URL` would convert them to NFD).
    static func makeDirectory(_ files: [(String, FileContent)]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ContestCatalogTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, content) in files {
            let path = dir.path + "/" + name
            let parent = (path as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true)
            switch content {
            case .directory:
                guard mkdir(path, 0o755) == 0 else { throw CocoaError(.fileWriteUnknown) }
            case .link(let target):
                guard symlink(target, path) == 0 else { throw CocoaError(.fileWriteUnknown) }
            case .text(let text):
                try writeRaw(Array(text.utf8), path: path)
            case .bytes(let bytes):
                try writeRaw(bytes, path: path)
            }
        }
        return dir
    }

    private static func writeRaw(_ bytes: [UInt8], path: String) throws {
        let descriptor = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
        defer { close(descriptor) }
        let written = bytes.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
        guard written == bytes.count else { throw CocoaError(.fileWriteUnknown) }
    }
}

// MARK: - table measured on Java (generated by `gen_cat.py` from `cat-out.txt`)

extension ContestCatalogFromDirTests {
    static let rows: [Row] = [
        // Java: Nelze na\u{10D}\u{ED}st definici z\u{E1}vodu: java.io.CharConversionException: Invalid UTF-8 start byte 0xb0 (at char #38, byte #-1)
        Row("appledouble",
            files: [("._cq.yaml", .bytes([0x00, 0x05, 0x16, 0x07, 0x00, 0x02, 0x00, 0x00, 0x4D, 0x61, 0x63, 0x20, 0x4F, 0x53, 0x20, 0x58, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x00, 0x02, 0x00, 0x00, 0x00, 0x09, 0x00, 0x00, 0x00, 0x32, 0x00, 0x00, 0x0E, 0xB0, 0x00, 0x00, 0x00, 0x02])), ("cq.yaml", .text("id: cq\n"))],
            ids: ["cq"],
            skipped: [("._cq.yaml", .invalid)]),
        Row("basic",
            files: [("test-cw.yaml", .text("schemaVersion: 1\nid: test-cw\nmetadata:\n  name: Test CW\nmodes: [CW]\n"))],
            ids: ["test-cw"],
            skipped: []),
        // Java: Nelze na\u{10D}\u{ED}st definici z\u{E1}vodu: mapping values are not allowed here
        Row("broken",
            files: [("broken.yaml", .text("this: : not: valid: yaml")), ("ok.yaml", .text("id: ok\n"))],
            ids: ["ok"],
            skipped: [("broken.yaml", .invalid)]),
        // Java: Nelze na\u{10D}\u{ED}st definici z\u{E1}vodu: java.io.IOException: Is a directory
        Row("dirfile",
            files: [("d.yaml", .directory), ("e.yaml", .text("id: e\n"))],
            ids: ["e"],
            skipped: [("d.yaml", .failure("Nelze načíst definici závodu: Is a directory"))]),
        Row("dup",
            files: [("a.yaml", .text("id: same\n")), ("b.yaml", .text("id: same\n"))],
            ids: ["same", "same"],
            skipped: []),
        // Java: Nelze na\u{10D}\u{ED}st definici z\u{E1}vodu: No content to map due to end-of-input
        // Java: Nelze na\u{10D}\u{ED}st definici z\u{E1}vodu: No content to map due to end-of-input
        // Java: Nelze na\u{10D}\u{ED}st definici z\u{E1}vodu: No content to map due to end-of-input
        Row("empty",
            files: [("e.yaml", .text("")), ("f.yaml", .text("# c\n")), ("g.yaml", .bytes([0xEF, 0xBB, 0xBF])), ("h.yaml", .text("id: h\n"))],
            ids: ["h"],
            skipped: [("e.yaml", .invalid), ("f.yaml", .invalid), ("g.yaml", .invalid)]),
        Row("extensions",
            files: [("a.YAML", .text("id: upper\n")), ("b.yml", .text("id: yml\n")), ("c.yaml.bak", .text("id: bak\n")), ("d.yaml", .text("id: d\n")), ("sub/e.yaml", .text("id: nested\n")), (".hidden.yaml", .text("id: hidden\n"))],
            ids: ["hidden", "d"],
            skipped: []),
        // Java: Nov\u{11B}j\u{161}\u{ED} form\u{E1}t definice (schemaVersion=2), aktualizuj aplikaci. Podporov\u{E1}no: 1
        Row("newer",
            files: [("a.yaml", .text("schemaVersion: 2\nid: new\n")), ("b.yaml", .text("schemaVersion: 0\nid: old\n"))],
            ids: ["old"],
            skipped: [("a.yaml", .newer(2))]),
        // Java: Cannot invoke \u{22}cz.ok1xoe.maccontestlogger.contest.def.ContestDefinition.schemaVersion()\u{22} because \u{22}def\u{22} is null
        // Java: Cannot invoke \u{22}cz.ok1xoe.maccontestlogger.contest.def.ContestDefinition.schemaVersion()\u{22} because \u{22}def\u{22} is null
        Row("nulldoc",
            files: [("a.yaml", .text("~\n")), ("b.yaml", .text("---\n")), ("c.yaml", .text("id: c\n"))],
            ids: ["c"],
            skipped: [("a.yaml", .empty), ("b.yaml", .empty)]),
        Row("ordering",
            files: [("f.yaml", .text("id: f\n")), ("B.yaml", .text("id: B\n")), ("a.yaml", .text("id: a\n")), ("_.yaml", .text("id: _\n")), ("\u{E9}.yaml", .text("id: nfc-e\n")), ("e\u{301}x.yaml", .text("id: nfd-e\n")), ("Z.yaml", .text("id: Z\n")), ("0.yaml", .text("id: 0\n"))],
            ids: ["0", "B", "Z", "_", "a", "nfd-e", "f", "nfc-e"],
            skipped: []),
        // Java: Nelze na\u{10D}\u{ED}st definici: cat/symlink/c/ln.yaml
        Row("symlink",
            files: [("ln.yaml", .link("/nonexistent/target.yaml")), ("ok.yaml", .text("id: ok\n"))],
            ids: ["ok"],
            skipped: [("ln.yaml", .openFailed)]),
        // Java: Nelze na\u{10D}\u{ED}st definici z\u{E1}vodu: java.io.CharConversionException: Invalid UTF-8 start byte 0xff (at char #8, byte #-1)
        // Java: Nelze na\u{10D}\u{ED}st definici z\u{E1}vodu: Cannot deserialize value of type `cz.ok1xoe.maccontestlogger.contest.def.ContestDefinition$Scope` from String \u{22}per_band\u{22}: not one of the values accepted for Enum class: [ONCE, PER_BAND_MODE, PER_MODE, PER_BAND]
        Row("textfix",
            files: [("bom.yaml", .bytes([0xEF, 0xBB, 0xBF, 0x69, 0x64, 0x3A, 0x20, 0x62, 0x6F, 0x6D, 0x0A])), ("crlf.yaml", .bytes([0x69, 0x64, 0x3A, 0x20, 0x63, 0x72, 0x6C, 0x66, 0x0D, 0x0A, 0x62, 0x61, 0x6E, 0x64, 0x73, 0x3A, 0x20, 0x5B, 0x32, 0x30, 0x6D, 0x5D, 0x0D, 0x0A])), ("bad.yaml", .bytes([0x69, 0x64, 0x3A, 0x20, 0x62, 0x61, 0x64, 0xFF, 0x0A])), ("type.yaml", .text("id: type\ndupe:\n  scope: per_band\n")), ("zz.yaml", .text("id: zz\n"))],
            ids: ["bom", "crlf", "zz"],
            skipped: [("bad.yaml", .invalid), ("type.yaml", .invalid)]),
    ]
}
