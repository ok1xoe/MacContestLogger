import Foundation
import Testing
@testable import MCLCore

/// `MultiplierSetRegistry.loadDir` and surroundings.
///
/// The first three tests are a port of the Java `MultiplierSetRegistryLoadDirTest`
/// (`wpxPrefixesIsBuiltInWithoutDir`, `loadsFixedSetFromDir`,
/// `resolvesValuesFileRelativeToDir`). The table `loadDirMatchesJava` is
/// **measured on Java v1.1.1** by the `ProbeReg` probe (maintainer-only probe,
/// generators `gen.py` → `java-out.txt` → `gen_swift.py`): each row is
/// a set directory, the Java dump of the registry **even after a crash** (the registry stays half
/// filled — `loadDir` has no error isolation) and the exception Java threw.
///
/// Mapping of Java exceptions to `MultiplierError`:
/// - `MultiplierException` with a Java text → `.failure(text)`, `<DIR>` = the directory,
/// - `MultiplierException("Nelze načíst definici sady: …")` from Jackson →
///   `.invalidDefinition` with the same position (the text is Czech, an allowed divergence),
/// - `NullPointerException` on the document `~` → `.emptyDefinition`,
///   on the element `values: [~]` → `.failure` with its own text (Java NPE),
/// - `PatternSyntaxException` → `.invalidPattern` with the verbatim Java message.
@Suite struct MultiplierSetRegistryLoadDirTests {

    // MARK: - Java MultiplierSetRegistryLoadDirTest

    static let fixed = """
        id: zones
        kind: FIXED
        keyType: INTEGER
        range:
          min: 1
          max: 40
        """

    static let withCsv = """
        id: districts
        kind: FIXED
        keyType: TEXT
        valuesFile: districts.csv
        """

    @Test func wpxPrefixesIsBuiltInWithoutDir() {
        let registry = MultiplierSetRegistry(dxcc: nil)
        #expect(registry.contains("wpx_prefixes"), "wpx_prefixes should be built in even without a directory")
    }

    @Test func loadsFixedSetFromDir() throws {
        let dir = try Self.makeDirectory([("zones.yaml", .text(Self.fixed))])
        defer { try? FileManager.default.removeItem(at: dir) }
        let registry = try MultiplierSetRegistry(dxcc: nil).loadDir(dir)
        #expect(registry.contains("zones"))
    }

    @Test func resolvesValuesFileRelativeToDir() throws {
        let dir = try Self.makeDirectory([
            ("districts.yaml", .text(Self.withCsv)),
            ("districts.csv", .text("APA,Praha\nABE,Benešov\n")),
        ])
        defer { try? FileManager.default.removeItem(at: dir) }
        let registry = try MultiplierSetRegistry(dxcc: nil).loadDir(dir)
        #expect(registry.contains("districts"))
    }

    // MARK: - measured behaviour (table from Java)

    @Test(arguments: rows)
    func loadDirMatchesJava(_ row: Row) throws {
        let dir = try Self.makeDirectory(row.files)
        defer { try? FileManager.default.removeItem(at: dir) }
        let dxcc: (any DxccLookup)? = row.name.hasPrefix("nodxcc")
            ? nil : try DxccResolver.fromData(DxccTestFixture.data())
        let registry = MultiplierSetRegistry(dxcc: dxcc)
        var thrown: MultiplierError?
        do {
            try registry.loadDir(dir)
        } catch {
            thrown = error
        }
        switch (row.error, thrown) {
        case (nil, nil):
            break
        case (.invalidDefinition(let line, let column)?, .invalidDefinition(let yaml)?):
            #expect(yaml.line == line && yaml.column == column, "\(yaml)")
        case (let expected?, let actual?):
            if case .error = expected {
                #expect(actual == expected.resolving(dir: dir.path))
            } else {
                Issue.record("expected \(expected), thrown \(actual)")
            }
        default:
            Issue.record("expected \(String(describing: row.error)), thrown \(String(describing: thrown))")
        }
        #expect(Self.render(registry) == row.render)
    }

    // MARK: - by hand: paths, get/contains, directory

    /// Review focus 1: a hidden AppleDouble `._cq.yaml` (FAT/SMB disk) next to
    /// a valid `cq.yaml` brings down the **whole** `loadDir` — like Java (the row
    /// `appledouble` of the table). `FileManager.contentsOfDirectory` would silently
    /// skip it (measured), hence the registry reads the directory via `readdir`.
    @Test func appleDoubleFileFailsWholeLoad() throws {
        let dir = try Self.makeDirectory([
            ("._cq.yaml", .bytes([0x00, 0x05, 0x16, 0x07, 0x00, 0x02, 0x00, 0x00, 0xB0])),
            ("cq.yaml", .text("id: cq\nkind: FIXED\n")),
        ])
        defer { try? FileManager.default.removeItem(at: dir) }
        let registry = MultiplierSetRegistry(dxcc: nil)
        #expect(throws: MultiplierError.self) { try registry.loadDir(dir) }
        #expect(registry.ids == ["wpx_prefixes"])
    }

    /// `loadDir(nil)`, a non-existent path and a file instead of a directory → silently nothing.
    @Test func nonDirectoryIsNoOp() throws {
        let dir = try Self.makeDirectory([("f.yaml", .text("id: f\nkind: FIXED\n"))])
        defer { try? FileManager.default.removeItem(at: dir) }
        let registry = MultiplierSetRegistry(dxcc: nil)
        try registry.loadDir(nil)
        try registry.loadDir(dir.appendingPathComponent("does-not-exist"))
        try registry.loadDir(dir.appendingPathComponent("f.yaml"))
        #expect(registry.ids == ["wpx_prefixes"])
    }

    /// Fluent: `loadDir` returns the same registry, a second call adds to the first.
    @Test func loadDirIsFluentAndCumulative() throws {
        let first = try Self.makeDirectory([("a.yaml", .text("id: a\nkind: FIXED\n"))])
        let second = try Self.makeDirectory([("b.yaml", .text("id: b\nkind: FIXED\n"))])
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }
        let registry = MultiplierSetRegistry(dxcc: nil)
        let returned = try registry.loadDir(first).loadDir(second)
        #expect(returned === registry)
        #expect(registry.ids == ["wpx_prefixes", "a", "b"])
    }

    /// Java: `get` of a missing id (even `null` and `""`) → "multiplikátorová sada
    /// '<id>' není v registru"; `contains(null)` is `false` while a set
    /// with `id: null` is not registered.
    @Test func getMissingThrows() {
        let registry = MultiplierSetRegistry(dxcc: nil)
        for (id, shown) in [("nope", "nope"), (nil, "null"), ("", "")] as [(String?, String)] {
            #expect(throws: MultiplierError.failure("multiplikátorová sada '\(shown)' není v registru")) {
                try registry.get(id)
            }
        }
        #expect(!registry.contains(nil))
    }

    @Test func nullIdIsRegisteredAndRetrievable() throws {
        let dir = try Self.makeDirectory([("a.yaml", .text("kind: FIXED\n"))])
        defer { try? FileManager.default.removeItem(at: dir) }
        let registry = try MultiplierSetRegistry(dxcc: nil).loadDir(dir)
        #expect(registry.contains(nil))
        #expect(try registry.get(nil).id == nil)
    }

    /// An unreadable directory: Java `Files.list` throws `AccessDeniedException` →
    /// "Nelze projít adresář sad: <dir>" (measured by `ProbeExtra`).
    @Test func unreadableDirectoryFails() throws {
        let dir = try Self.makeDirectory([])
        defer {
            chmod(dir.path, 0o755)
            try? FileManager.default.removeItem(at: dir)
        }
        #expect(chmod(dir.path, 0) == 0)
        #expect(throws: MultiplierError.failure("Nelze projít adresář sad: " + dir.path)) {
            try MultiplierSetRegistry(dxcc: nil).loadDir(dir)
        }
    }

    /// The path in the message is Java's: the directory as passed, without canonicalisation,
    /// but with doubled `/` merged and without a trailing `/` (`UnixPath`);
    /// `..` stays (measured by `ProbeExtra` and the row `csv-subpath`).
    @Test func valuesFilePathInMessageIsNotCanonicalised() throws {
        let dir = try Self.makeDirectory([("s.yaml", .text("id: s\nkind: FIXED\nvaluesFile: missing.csv\n"))])
        defer { try? FileManager.default.removeItem(at: dir) }
        let doubled = URL(fileURLWithPath: dir.deletingLastPathComponent().path + "//" + dir.lastPathComponent + "/")
        #expect(throws: MultiplierError.failure("Nelze načíst valuesFile: " + dir.path + "/missing.csv")) {
            try MultiplierSetRegistry(dxcc: nil).loadDir(doubled)
        }
    }

    /// A relative directory stays relative in messages, as Java received it
    /// (`Path.of("rel/dir")` is not canonicalised; `URL.path` would return an absolute
    /// path with `..` resolved). The relative path is built from the current directory
    /// via `..` up to the root, so the test does not change the process's current directory.
    @Test func relativeDirectoryStaysRelativeInMessages() throws {
        let dir = try Self.makeDirectory([("s.yaml", .text("id: s\nkind: FIXED\nvaluesFile: missing.csv\n"))])
        defer { try? FileManager.default.removeItem(at: dir) }
        let relative = Self.relativePath(to: dir)
        #expect(!relative.hasPrefix("/"))
        #expect(throws: MultiplierError.failure("Nelze načíst valuesFile: " + relative + "/missing.csv")) {
            try MultiplierSetRegistry(dxcc: nil).loadDir(URL(fileURLWithPath: relative))
        }
    }

    /// The file name goes into `open()` and into the message **in bytes from `readdir`** —
    /// NFC `é.yaml` stays NFC (via `URL(fileURLWithPath:)` it would change
    /// to NFD). A dead symlink is listed in Java and only opening fails.
    /// "Nelze načíst sadu: <dir>/é.yaml".
    @Test func fileNameBytesReachOpenAndMessage() throws {
        let dir = try Self.makeDirectory([])
        defer { try? FileManager.default.removeItem(at: dir) }
        let name = "\u{E9}.yaml"
        #expect(symlink("/nonexistent/target.yaml", dir.path + "/" + name) == 0)
        let relative = Self.relativePath(to: dir)
        do {
            try MultiplierSetRegistry(dxcc: nil).loadDir(URL(fileURLWithPath: relative))
            Issue.record("a dead symlink should have failed")
        } catch {
            guard case .failure(let message) = error else {
                Issue.record("expected .failure, got \(error)")
                return
            }
            #expect(Array(message.utf8) == Array(("Nelze načíst sadu: " + relative + "/").utf8) + [0xC3, 0xA9]
                        + Array(".yaml".utf8))
        }
    }

    /// An absolute `valuesFile` is not joined to the directory (`Path.resolve`).
    @Test func absoluteValuesFileIsUsedAsIs() throws {
        let csvDir = try Self.makeDirectory([("abs.csv", .text("AB,Alpha\n"))])
        let csv = csvDir.appendingPathComponent("abs.csv").path
        let dir = try Self.makeDirectory([("s.yaml", .text("id: s\nkind: FIXED\nvaluesFile: '\(csv)'\n"))])
        defer {
            try? FileManager.default.removeItem(at: dir)
            try? FileManager.default.removeItem(at: csvDir)
        }
        let registry = try MultiplierSetRegistry(dxcc: nil).loadDir(dir)
        #expect(try registry.get("s").values == [MultiplierValue(key: "AB", label: "Alpha")])
    }

    /// A `valuesFile` with a NUL character: Java `InvalidPathException` brings down `loadDir`.
    /// Swift must not silently truncate the path at NUL and open a different file.
    @Test func valuesFileWithNulFails() throws {
        let dir = try Self.makeDirectory([
            ("s.yaml", .text("id: s\nkind: FIXED\nvaluesFile: \"s.csv\\0x\"\n")),
            ("s.csv", .text("AB,Alpha\n")),
        ])
        defer { try? FileManager.default.removeItem(at: dir) }
        let registry = MultiplierSetRegistry(dxcc: nil)
        #expect(throws: MultiplierError.self) { try registry.loadDir(dir) }
        #expect(registry.ids == ["wpx_prefixes"])
    }

    // MARK: - helpers

    enum FileContent: Sendable {
        case text(String)
        case bytes([UInt8])
        case directory
    }

    /// The expected row error; for `failure` the placeholder `<DIR>` = the set directory.
    enum ExpectedError: Sendable, CustomStringConvertible {
        case error(MultiplierError)
        case invalidDefinition(line: Int, column: Int)

        static func failure(_ message: String) -> ExpectedError { .error(.failure(message)) }
        static var emptyDefinition: ExpectedError { .error(.emptyDefinition) }
        static func invalidPattern(_ message: String) -> ExpectedError {
            .error(.invalidPattern(pattern: "[", message: message))
        }

        var description: String {
            switch self {
            case .error(let error): return "\(error)"
            case .invalidDefinition(let line, let column): return "invalidDefinition @\(line):\(column)"
            }
        }
    }

    struct Row: Sendable, CustomTestStringConvertible {
        let name: String
        let files: [(String, FileContent)]
        let error: ExpectedError?
        let render: [String]

        init(_ name: String, files: [(String, FileContent)], error: ExpectedError?, render: [String]) {
            self.name = name
            self.files = files
            self.error = error
            self.render = render
        }

        var testDescription: String { name }
    }

    static func makeDirectory(_ files: [(String, FileContent)]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MultiplierSetRegistryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, content) in files {
            let url = dir.appendingPathComponent(name)
            switch content {
            case .directory:
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            case .text(let text):
                try writeRaw(Array(text.utf8), name: name, in: dir)
            case .bytes(let bytes):
                try writeRaw(bytes, name: name, in: dir)
            }
        }
        return dir
    }

    /// A relative path to `url` from the process's current directory: `../` up to
    /// the root and then the absolute path without the leading `/`. The messages must then
    /// show it verbatim, including `..`.
    static func relativePath(to url: URL) -> String {
        let depth = FileManager.default.currentDirectoryPath.split(separator: "/").count
        return String(repeating: "../", count: depth) + url.path.dropFirst()
    }

    /// Writing via POSIX with the literal bytes of the name: `URL`/`Data.write` converts
    /// the name to NFD (`é.yaml` → `e\u{301}.yaml`) and thereby would change the byte
    /// order compared to the Java probe's files (written in NFC).
    private static func writeRaw(_ bytes: [UInt8], name: String, in dir: URL) throws {
        let path = dir.path + "/" + name
        let parent = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true)
        let descriptor = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
        defer { close(descriptor) }
        let written = bytes.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
        guard written == bytes.count else { throw CocoaError(.fileWriteUnknown) }
    }

    /// Registry dump in the `ProbeReg` probe format: `ids`, then for each set
    /// the class, id, `enumerable` and the first 8 values (key, label, attributes
    /// sorted by UTF-16 units like a Java `TreeMap`).
    static func render(_ registry: MultiplierSetRegistry) -> [String] {
        var lines = ["ids [" + registry.ids.map(escape).joined(separator: ", ") + "]"]
        for id in registry.ids {
            guard let set = try? registry.get(id) else {
                lines.append("  " + escape(id) + " CHYBÍ")
                continue
            }
            var line = "  \(escape(id)) \(type(of: set)) id=\(escape(set.id)) enum=\(set.enumerable) values="
            for value in set.values.prefix(8) {
                let attributes = value.attributes
                    .sorted { $0.key.utf16.lexicographicallyPrecedes($1.key.utf16) }
                    .map { escape($0.key) + ":" + escape($0.value) + "," }
                    .joined()
                line += "(\(escape(value.key)),\(escape(value.label)),[\(attributes)])"
            }
            if set.values.count > 8 { line += "...#\(set.values.count)" }
            lines.append(line)
        }
        return lines
    }

    /// The probe's Java `esc`: outside printable ASCII (and `"`, `\`) → `\u{XX}` by UTF-16 units.
    static func escape(_ text: String?) -> String {
        guard let text else { return "null" }
        var out = "\""
        for unit in text.utf16 {
            if unit < 0x20 || unit > 0x7E || unit == 0x22 || unit == 0x5C {
                out += "\\u{" + String(unit, radix: 16, uppercase: true) + "}"
            } else {
                out += String(UnicodeScalar(UInt8(unit)))
            }
        }
        return out + "\""
    }
}

extension MultiplierSetRegistryLoadDirTests.ExpectedError {
    /// Substitutes the real directory for `<DIR>`.
    func resolving(dir: String) -> MultiplierError {
        guard case .error(let error) = self else { return .emptyDefinition }
        if case .failure(let message) = error {
            return .failure(message.replacingOccurrences(of: "<DIR>", with: dir))
        }
        return error
    }
}

// MARK: - table measured on Java (generated by `gen_swift.py` from `java-out.txt`)

extension MultiplierSetRegistryLoadDirTests {
    static let rows: [Row] = [
        Row("priority-range",
            files: [("s.yaml", .text("id: s\u{A}kind: FIXED\u{A}keyType: TEXT\u{A}range: {min: 1, max: 3}\u{A}values: [{key: X}]\u{A}valuesFile: missing.csv\u{A}"))],
            error: nil,
            render: [
                #"ids ["wpx_prefixes", "s"]"#,
                #"  "wpx_prefixes" WpxMultiplierSet id="wpx_prefixes" enum=false values="#,
                #"  "s" FixedMultiplierSet id="s" enum=true values=("1","1",[])("2","2",[])("3","3",[])"#,
            ]),
        Row("priority-values",
            files: [("s.yaml", .text("id: s\u{A}kind: FIXED\u{A}keyType: TEXT\u{A}values: [{key: X}]\u{A}valuesFile: missing.csv\u{A}"))],
            error: nil,
            render: [
                #"ids ["wpx_prefixes", "s"]"#,
                #"  "wpx_prefixes" WpxMultiplierSet id="wpx_prefixes" enum=false values="#,
                #"  "s" FixedMultiplierSet id="s" enum=true values=("X","X",[])"#,
            ]),
        Row("range-nomax",
            files: [("s.yaml", .text("id: s\u{A}kind: FIXED\u{A}keyType: TEXT\u{A}range: {min: 1}\u{A}values: [{key: X}]\u{A}"))],
            error: nil,
            render: [
                #"ids ["wpx_prefixes", "s"]"#,
                #"  "wpx_prefixes" WpxMultiplierSet id="wpx_prefixes" enum=false values="#,
                #"  "s" FixedMultiplierSet id="s" enum=true values="#,
            ]),
        Row("range-reversed",
            files: [("s.yaml", .text("id: s\u{A}kind: FIXED\u{A}keyType: TEXT\u{A}range: {min: 5, max: 3}\u{A}"))],
            error: nil,
            render: [
                #"ids ["wpx_prefixes", "s"]"#,
                #"  "wpx_prefixes" WpxMultiplierSet id="wpx_prefixes" enum=false values="#,
                #"  "s" FixedMultiplierSet id="s" enum=true values="#,
            ]),
        Row("range-negative",
            files: [("s.yaml", .text("id: s\u{A}kind: FIXED\u{A}keyType: TEXT\u{A}range: {min: -2, max: 1}\u{A}"))],
            error: nil,
            render: [
                #"ids ["wpx_prefixes", "s"]"#,
                #"  "wpx_prefixes" WpxMultiplierSet id="wpx_prefixes" enum=false values="#,
                #"  "s" FixedMultiplierSet id="s" enum=true values=("-2","-2",[])("-1","-1",[])("0","0",[])("1","1",[])"#,
            ]),
        // Java: Java: attribute "c":null — Swift omits nil values
        Row("values-labels",
            files: [("s.yaml", .text("id: s\u{A}kind: FIXED\u{A}keyType: TEXT\u{A}values:\u{A}  - {key: a}\u{A}  - {key: b, label: Bee}\u{A}  - {label: nokey}\u{A}  - {key: ' c ', label: ''}\u{A}  - {key: d, attributes: {n: 1, c: ~, t: x}}\u{A}"))],
            error: nil,
            render: [
                #"ids ["wpx_prefixes", "s"]"#,
                #"  "wpx_prefixes" WpxMultiplierSet id="wpx_prefixes" enum=false values="#,
                #"  "s" FixedMultiplierSet id="s" enum=true values=("a","a",[])("b","Bee",[])(null,"nokey",[])(" c ","",[])("d","d",["n":"1","t":"x",])"#,
            ]),
        // Java: THROW NullPointerException: "Cannot invoke \u{22}cz.ok1xoe.maccontestlogger.multiplier.MultiplierSetDefinition$ValueDef.key()\u{22} because \u{22}v\u{22} is null"
        Row("values-nil",
            files: [("s.yaml", .text("id: s\u{A}kind: FIXED\u{A}keyType: TEXT\u{A}values: [~]\u{A}"))],
            error: .failure("sada 's' má ve values prázdnou položku"),
            render: [
                #"ids ["wpx_prefixes"]"#,
                #"  "wpx_prefixes" WpxMultiplierSet id="wpx_prefixes" enum=false values="#,
            ]),
        // Java: THROW NullPointerException: "Cannot invoke \u{22}cz.ok1xoe.maccontestlogger.multiplier.MultiplierSetDefinition$ValueDef.key()\u{22} because \u{22}v\u{22} is null"
        Row("values-nil-after-good",
            files: [("a.yaml", .text("id: a\u{A}kind: FIXED\u{A}keyType: TEXT\u{A}values: [{key: A}]\u{A}")),
                    ("b.yaml", .text("id: b\u{A}kind: FIXED\u{A}keyType: TEXT\u{A}values: [{key: B}, ~]\u{A}"))],
            error: .failure("sada 'b' má ve values prázdnou položku"),
            render: [
                #"ids ["wpx_prefixes", "a"]"#,
                #"  "wpx_prefixes" WpxMultiplierSet id="wpx_prefixes" enum=false values="#,
                #"  "a" FixedMultiplierSet id="a" enum=true values=("A","A",[])"#,
            ]),
        // Java: THROW NullPointerException: "Cannot invoke \u{22}cz.ok1xoe.maccontestlogger.multiplier.MultiplierSetDefinition.id()\u{22} because \u{22}def\u{22} is null"
        Row("doc-null",
            files: [("a.yaml", .text("id: a\u{A}kind: FIXED\u{A}keyType: TEXT\u{A}")),
                    ("b.yaml", .text("~\u{A}")),
                    ("c.yaml", .text("id: c\u{A}kind: FIXED\u{A}keyType: TEXT\u{A}"))],
            error: .emptyDefinition,
            render: [
                #"ids ["wpx_prefixes", "a"]"#,
                #"  "wpx_prefixes" WpxMultiplierSet id="wpx_prefixes" enum=false values="#,
                #"  "a" FixedMultiplierSet id="a" enum=true values="#,
            ]),
        Row("bad-pattern",
            files: [("a.yaml", .text("id: a\u{A}kind: FIXED\u{A}keyType: TEXT\u{A}")),
                    ("b.yaml", .text("id: b\u{A}kind: FIXED\u{A}keyType: TEXT\u{A}validation: {keyPattern: '['}\u{A}")),
                    ("c.yaml", .text("id: c\u{A}kind: FIXED\u{A}keyType: TEXT\u{A}"))],
            error: .invalidPattern("Unclosed character class near index 0\u{A}[\u{A}^"),
            render: [
                #"ids ["wpx_prefixes", "a"]"#,
                #"  "wpx_prefixes" WpxMultiplierSet id="wpx_prefixes" enum=false values="#,
                #"  "a" FixedMultiplierSet id="a" enum=true values="#,
            ]),
        Row("csv-basic",
            files: [("s.yaml", .text("id: s\u{A}kind: FIXED\u{A}keyType: TEXT\u{A}valuesFile: s.csv\u{A}")),
                    ("s.csv", .text("AB,\u{A},empty\u{A}CD,Label,W1AW;K1\u{A}EF,L,  \u{A}GH,a,b,c\u{A}# comment\u{A}  # indented\u{A}\u{A}   \u{A} ij , x \u{A}kl\u{A}AB,dup\u{A}\u{A0}mn,nbsp\u{A}\u{B}op,vt\u{A}"))],
            error: nil,
            render: [
                #"ids ["wpx_prefixes", "s"]"#,
                #"  "wpx_prefixes" WpxMultiplierSet id="wpx_prefixes" enum=false values="#,
                #"  "s" FixedMultiplierSet id="s" enum=true values=("AB","dup",[])("","empty",[])("CD","Label",["calls":"W1AW;K1",])("EF","L",[])("GH","a",["calls":"b,c",])("IJ","x",[])("KL","KL",[])("\u{A0}MN","nbsp",[])...#9"#,
            ]),
        Row("csv-crlf",
            files: [("s.yaml", .text("id: s\u{A}kind: FIXED\u{A}keyType: TEXT\u{A}valuesFile: s.csv\u{A}")),
                    ("s.csv", .text("AB,Alpha\u{D}\u{A}CD,Charlie\u{D}\u{A}\u{D}\u{A}EF\u{D}\u{A}"))],
            error: nil,
            render: [
                #"ids ["wpx_prefixes", "s"]"#,
                #"  "wpx_prefixes" WpxMultiplierSet id="wpx_prefixes" enum=false values="#,
                #"  "s" FixedMultiplierSet id="s" enum=true values=("AB","Alpha",[])("CD","Charlie",[])("EF","EF",[])"#,
            ]),
        Row("csv-cr",
            files: [("s.yaml", .text("id: s\u{A}kind: FIXED\u{A}keyType: TEXT\u{A}valuesFile: s.csv\u{A}")),
                    ("s.csv", .text("AB,Alpha\u{D}CD,Charlie\u{D}\u{D}EF"))],
            error: nil,
            render: [
                #"ids ["wpx_prefixes", "s"]"#,
                #"  "wpx_prefixes" WpxMultiplierSet id="wpx_prefixes" enum=false values="#,
                #"  "s" FixedMultiplierSet id="s" enum=true values=("AB","Alpha",[])("CD","Charlie",[])("EF","EF",[])"#,
            ]),
        Row("csv-bom",
            files: [("s.yaml", .text("id: s\u{A}kind: FIXED\u{A}keyType: TEXT\u{A}valuesFile: s.csv\u{A}")),
                    ("s.csv", .text("\u{FEFF}ab,Alpha\u{A}CD,Charlie\u{A}"))],
            error: nil,
            render: [
                #"ids ["wpx_prefixes", "s"]"#,
                #"  "wpx_prefixes" WpxMultiplierSet id="wpx_prefixes" enum=false values="#,
                #"  "s" FixedMultiplierSet id="s" enum=true values=("\u{FEFF}AB","Alpha",[])("CD","Charlie",[])"#,
            ]),
        Row("csv-bom-comment",
            files: [("s.yaml", .text("id: s\u{A}kind: FIXED\u{A}keyType: TEXT\u{A}valuesFile: s.csv\u{A}")),
                    ("s.csv", .text("\u{FEFF}# comment\u{A}CD,Charlie\u{A}"))],
            error: nil,
            render: [
                #"ids ["wpx_prefixes", "s"]"#,
                #"  "wpx_prefixes" WpxMultiplierSet id="wpx_prefixes" enum=false values="#,
                #"  "s" FixedMultiplierSet id="s" enum=true values=("\u{FEFF}# COMMENT","\u{FEFF}# COMMENT",[])("CD","Charlie",[])"#,
            ]),
        Row("csv-bad-utf8",
            files: [("s.yaml", .text("id: s\u{A}kind: FIXED\u{A}keyType: TEXT\u{A}valuesFile: s.csv\u{A}")),
                    ("s.csv", .bytes([0x41, 0x42, 0x2C, 0x41, 0x6C, 0x70, 0x68, 0x61, 0x0A, 0x43, 0x44, 0x2C, 0x43, 0x68, 0xE9, 0x72, 0x6C, 0x69, 0x65, 0x0A]))],
            error: .failure("Nelze na\u{10D}\u{ED}st valuesFile: <DIR>/s.csv"),
            render: [
                #"ids ["wpx_prefixes"]"#,
                #"  "wpx_prefixes" WpxMultiplierSet id="wpx_prefixes" enum=false values="#,
            ]),
        Row("csv-bad-utf8-late",
            files: [("s.yaml", .text("id: s\u{A}kind: FIXED\u{A}keyType: TEXT\u{A}valuesFile: s.csv\u{A}")),
                    ("s.csv", .bytes(Array(repeating: Array("AB,Alpha\n".utf8), count: 3000).flatMap { $0 } + [0x43, 0x44, 0x2C, 0x43, 0x68, 0xE9, 0x72, 0x6C, 0x69, 0x65, 0x0A]))],
            error: .failure("Nelze na\u{10D}\u{ED}st valuesFile: <DIR>/s.csv"),
            render: [
                #"ids ["wpx_prefixes"]"#,
                #"  "wpx_prefixes" WpxMultiplierSet id="wpx_prefixes" enum=false values="#,
            ]),
        Row("csv-missing",
            files: [("a.yaml", .text("id: a\u{A}kind: FIXED\u{A}keyType: TEXT\u{A}")),
                    ("s.yaml", .text("id: s\u{A}kind: FIXED\u{A}keyType: TEXT\u{A}valuesFile: missing.csv\u{A}"))],
            error: .failure("Nelze na\u{10D}\u{ED}st valuesFile: <DIR>/missing.csv"),
            render: [
                #"ids ["wpx_prefixes", "a"]"#,
                #"  "wpx_prefixes" WpxMultiplierSet id="wpx_prefixes" enum=false values="#,
                #"  "a" FixedMultiplierSet id="a" enum=true values="#,
            ]),
        Row("csv-empty-name",
            files: [("s.yaml", .text("id: s\u{A}kind: FIXED\u{A}keyType: TEXT\u{A}valuesFile: ''\u{A}"))],
            error: .failure("Nelze na\u{10D}\u{ED}st valuesFile: <DIR>"),
            render: [
                #"ids ["wpx_prefixes"]"#,
                #"  "wpx_prefixes" WpxMultiplierSet id="wpx_prefixes" enum=false values="#,
            ]),
        Row("csv-subpath",
            files: [("s.yaml", .text("id: s\u{A}kind: FIXED\u{A}keyType: TEXT\u{A}valuesFile: sub/../x//y.csv\u{A}"))],
            error: .failure("Nelze na\u{10D}\u{ED}st valuesFile: <DIR>/sub/../x/y.csv"),
            render: [
                #"ids ["wpx_prefixes"]"#,
                #"  "wpx_prefixes" WpxMultiplierSet id="wpx_prefixes" enum=false values="#,
            ]),
        Row("csv-in-subdir",
            files: [("s.yaml", .text("id: s\u{A}kind: FIXED\u{A}keyType: TEXT\u{A}valuesFile: sub/s.csv\u{A}")),
                    ("sub/s.csv", .text("AB,Alpha\u{A}"))],
            error: nil,
            render: [
                #"ids ["wpx_prefixes", "s"]"#,
                #"  "wpx_prefixes" WpxMultiplierSet id="wpx_prefixes" enum=false values="#,
                #"  "s" FixedMultiplierSet id="s" enum=true values=("AB","Alpha",[])"#,
            ]),
        Row("csv-uppercase",
            files: [("s.yaml", .text("id: s\u{A}kind: FIXED\u{A}keyType: TEXT\u{A}valuesFile: s.csv\u{A}")),
                    ("s.csv", .text("stra\u{DF}e,x\u{A}\u{10D}\u{159},y\u{A}\u{FB01},z\u{A}"))],
            error: nil,
            render: [
                #"ids ["wpx_prefixes", "s"]"#,
                #"  "wpx_prefixes" WpxMultiplierSet id="wpx_prefixes" enum=false values="#,
                #"  "s" FixedMultiplierSet id="s" enum=true values=("STRASSE","x",[])("\u{10C}\u{158}","y",[])("FI","z",[])"#,
            ]),
        Row("csv-empty-file",
            files: [("s.yaml", .text("id: s\u{A}kind: FIXED\u{A}keyType: TEXT\u{A}valuesFile: s.csv\u{A}")),
                    ("s.csv", .text(""))],
            error: nil,
            render: [
                #"ids ["wpx_prefixes", "s"]"#,
                #"  "wpx_prefixes" WpxMultiplierSet id="wpx_prefixes" enum=false values="#,
                #"  "s" FixedMultiplierSet id="s" enum=true values="#,
            ]),
        // Java: THROW MultiplierException: "Nelze na\u{10D}\u{ED}st definici sady: java.io.CharConversionException: Invalid UTF-8 start byte 0xb0 (at char #38, byte #-1)\u{A} at [Source: (sun.nio.ch.ChannelInputStream); line: 1, column: 1]"
        Row("appledouble",
            files: [("._cq.yaml", .bytes([0x00, 0x05, 0x16, 0x07, 0x00, 0x02, 0x00, 0x00, 0x4D, 0x61, 0x63, 0x20, 0x4F, 0x53, 0x20, 0x58, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x00, 0x02, 0x00, 0x00, 0x00, 0x09, 0x00, 0x00, 0x00, 0x32, 0x00, 0x00, 0x0E, 0xB0, 0x00, 0x00, 0x00, 0x02])),
                    ("cq.yaml", .text("id: cq\u{A}kind: FIXED\u{A}keyType: TEXT\u{A}"))],
            error: .invalidDefinition(line: 1, column: 1),
            render: [
                #"ids ["wpx_prefixes"]"#,
                #"  "wpx_prefixes" WpxMultiplierSet id="wpx_prefixes" enum=false values="#,
            ]),
        Row("extensions",
            files: [("a.YAML", .text("id: upper\u{A}kind: FIXED\u{A}keyType: TEXT\u{A}")),
                    ("b.yml", .text("id: yml\u{A}kind: FIXED\u{A}keyType: TEXT\u{A}")),
                    ("c.yaml.bak", .text("id: bak\u{A}kind: FIXED\u{A}keyType: TEXT\u{A}")),
                    ("d.yaml", .text("id: d\u{A}kind: FIXED\u{A}keyType: TEXT\u{A}")),
                    ("sub/e.yaml", .text("id: nested\u{A}kind: FIXED\u{A}keyType: TEXT\u{A}"))],
            error: nil,
            render: [
                #"ids ["wpx_prefixes", "d"]"#,
                #"  "wpx_prefixes" WpxMultiplierSet id="wpx_prefixes" enum=false values="#,
                #"  "d" FixedMultiplierSet id="d" enum=true values="#,
            ]),
        Row("ordering",
            files: [("a.yaml", .text("id: a\u{A}kind: FIXED\u{A}keyType: TEXT\u{A}")),
                    ("B.yaml", .text("id: B\u{A}kind: FIXED\u{A}keyType: TEXT\u{A}")),
                    ("_u.yaml", .text("id: _u\u{A}kind: FIXED\u{A}keyType: TEXT\u{A}")),
                    ("z.yaml", .text("id: z\u{A}kind: FIXED\u{A}keyType: TEXT\u{A}")),
                    ("\u{E9}.yaml", .text("id: e-acute\u{A}kind: FIXED\u{A}keyType: TEXT\u{A}")),
                    ("1.yaml", .text("id: one\u{A}kind: FIXED\u{A}keyType: TEXT\u{A}")),
                    ("a b.yaml", .text("id: a-space\u{A}kind: FIXED\u{A}keyType: TEXT\u{A}")),
                    ("a.b.yaml", .text("id: a-dot-b\u{A}kind: FIXED\u{A}keyType: TEXT\u{A}")),
                    ("aa.yaml", .text("id: aa\u{A}kind: FIXED\u{A}keyType: TEXT\u{A}"))],
            error: nil,
            render: [
                #"ids ["wpx_prefixes", "one", "B", "_u", "a-space", "a-dot-b", "a", "aa", "z", "e-acute"]"#,
                #"  "wpx_prefixes" WpxMultiplierSet id="wpx_prefixes" enum=false values="#,
                #"  "one" FixedMultiplierSet id="one" enum=true values="#,
                #"  "B" FixedMultiplierSet id="B" enum=true values="#,
                #"  "_u" FixedMultiplierSet id="_u" enum=true values="#,
                #"  "a-space" FixedMultiplierSet id="a-space" enum=true values="#,
                #"  "a-dot-b" FixedMultiplierSet id="a-dot-b" enum=true values="#,
                #"  "a" FixedMultiplierSet id="a" enum=true values="#,
                #"  "aa" FixedMultiplierSet id="aa" enum=true values="#,
                #"  "z" FixedMultiplierSet id="z" enum=true values="#,
                #"  "e-acute" FixedMultiplierSet id="e-acute" enum=true values="#,
            ]),
        Row("ordering-nfd",
            files: [("e\u{301}x.yaml", .text("id: nfd-e\u{A}kind: FIXED\u{A}keyType: TEXT\u{A}")),
                    ("f.yaml", .text("id: f\u{A}kind: FIXED\u{A}keyType: TEXT\u{A}")),
                    ("\u{E9}.yaml", .text("id: nfc-e\u{A}kind: FIXED\u{A}keyType: TEXT\u{A}"))],
            error: nil,
            render: [
                #"ids ["wpx_prefixes", "nfd-e", "f", "nfc-e"]"#,
                #"  "wpx_prefixes" WpxMultiplierSet id="wpx_prefixes" enum=false values="#,
                #"  "nfd-e" FixedMultiplierSet id="nfd-e" enum=true values="#,
                #"  "f" FixedMultiplierSet id="f" enum=true values="#,
                #"  "nfc-e" FixedMultiplierSet id="nfc-e" enum=true values="#,
            ]),
        Row("override-wpx",
            files: [("x.yaml", .text("id: wpx_prefixes\u{A}kind: FIXED\u{A}keyType: TEXT\u{A}values: [{key: A}]\u{A}")),
                    ("a.yaml", .text("id: a\u{A}kind: FIXED\u{A}keyType: TEXT\u{A}"))],
            error: nil,
            render: [
                #"ids ["wpx_prefixes", "a"]"#,
                #"  "wpx_prefixes" FixedMultiplierSet id="wpx_prefixes" enum=true values=("A","A",[])"#,
                #"  "a" FixedMultiplierSet id="a" enum=true values="#,
            ]),
        Row("override-dup",
            files: [("a.yaml", .text("id: z\u{A}kind: FIXED\u{A}keyType: TEXT\u{A}values: [{key: A}]\u{A}")),
                    ("b.yaml", .text("id: y\u{A}kind: FIXED\u{A}keyType: TEXT\u{A}")),
                    ("c.yaml", .text("id: z\u{A}kind: FIXED\u{A}keyType: TEXT\u{A}values: [{key: C}]\u{A}"))],
            error: nil,
            render: [
                #"ids ["wpx_prefixes", "z", "y"]"#,
                #"  "wpx_prefixes" WpxMultiplierSet id="wpx_prefixes" enum=false values="#,
                #"  "z" FixedMultiplierSet id="z" enum=true values=("C","C",[])"#,
                #"  "y" FixedMultiplierSet id="y" enum=true values="#,
            ]),
        Row("id-null",
            files: [("a.yaml", .text("kind: FIXED\u{A}keyType: TEXT\u{A}"))],
            error: nil,
            render: [
                #"ids ["wpx_prefixes", null]"#,
                #"  "wpx_prefixes" WpxMultiplierSet id="wpx_prefixes" enum=false values="#,
                #"  null FixedMultiplierSet id=null enum=true values="#,
            ]),
        Row("kind-missing",
            files: [("a.yaml", .text("id: a\u{A}kind: FIXED\u{A}keyType: TEXT\u{A}")),
                    ("b.yaml", .text("id: b\u{A}"))],
            error: .failure("sada 'b' nem\u{E1} kind"),
            render: [
                #"ids ["wpx_prefixes", "a"]"#,
                #"  "wpx_prefixes" WpxMultiplierSet id="wpx_prefixes" enum=false values="#,
                #"  "a" FixedMultiplierSet id="a" enum=true values="#,
            ]),
        Row("kind-missing-noid",
            files: [("b.yaml", .text("keyType: TEXT\u{A}"))],
            error: .failure("sada 'null' nem\u{E1} kind"),
            render: [
                #"ids ["wpx_prefixes"]"#,
                #"  "wpx_prefixes" WpxMultiplierSet id="wpx_prefixes" enum=false values="#,
            ]),
        Row("provider-null",
            files: [("a.yaml", .text("id: a\u{A}kind: EXTERNAL_DATA\u{A}")),
                    ("b.yaml", .text("id: b\u{A}kind: EXTERNAL_DATA\u{A}provider: {data: x}\u{A}")),
                    ("c.yaml", .text("id: c\u{A}kind: EXTERNAL_DATA\u{A}provider: {type: CTY}\u{A}")),
                    ("d.yaml", .text("id: d\u{A}kind: EXTERNAL_DATA\u{A}provider: {type: Dxcc-Json}\u{A}"))],
            error: nil,
            render: [
                #"ids ["wpx_prefixes", "a", "b", "c", "d"]"#,
                #"  "wpx_prefixes" WpxMultiplierSet id="wpx_prefixes" enum=false values="#,
                #"  "a" DxccMultiplierSet id="a" enum=true values=("503","Czech Republic",["continent":"EU","countryCode":"CZ","prefix":"OK",])("291","United States",["continent":"NA","countryCode":"US","prefix":"K",])("1","Canada",["continent":"NA","countryCode":"CA","prefix":"VE",])("230","Germany",["continent":"EU","countryCode":"DE","prefix":"DL",])"#,
                #"  "b" DxccMultiplierSet id="b" enum=true values=("503","Czech Republic",["continent":"EU","countryCode":"CZ","prefix":"OK",])("291","United States",["continent":"NA","countryCode":"US","prefix":"K",])("1","Canada",["continent":"NA","countryCode":"CA","prefix":"VE",])("230","Germany",["continent":"EU","countryCode":"DE","prefix":"DL",])"#,
                #"  "c" DxccMultiplierSet id="c" enum=true values=("503","Czech Republic",["continent":"EU","countryCode":"CZ","prefix":"OK",])("291","United States",["continent":"NA","countryCode":"US","prefix":"K",])("1","Canada",["continent":"NA","countryCode":"CA","prefix":"VE",])("230","Germany",["continent":"EU","countryCode":"DE","prefix":"DL",])"#,
                #"  "d" DxccMultiplierSet id="d" enum=true values=("503","Czech Republic",["continent":"EU","countryCode":"CZ","prefix":"OK",])("291","United States",["continent":"NA","countryCode":"US","prefix":"K",])("1","Canada",["continent":"NA","countryCode":"CA","prefix":"VE",])("230","Germany",["continent":"EU","countryCode":"DE","prefix":"DL",])"#,
            ]),
        Row("provider-empty",
            files: [("a.yaml", .text("id: a\u{A}kind: EXTERNAL_DATA\u{A}provider: {type: ''}\u{A}"))],
            error: .failure("nezn\u{E1}m\u{FD} provider '' u sady 'a'"),
            render: [
                #"ids ["wpx_prefixes"]"#,
                #"  "wpx_prefixes" WpxMultiplierSet id="wpx_prefixes" enum=false values="#,
            ]),
        Row("provider-other",
            files: [("a.yaml", .text("id: a\u{A}kind: EXTERNAL_DATA\u{A}provider: {type: clublog}\u{A}"))],
            error: .failure("nezn\u{E1}m\u{FD} provider 'clublog' u sady 'a'"),
            render: [
                #"ids ["wpx_prefixes"]"#,
                #"  "wpx_prefixes" WpxMultiplierSet id="wpx_prefixes" enum=false values="#,
            ]),
        Row("nodxcc-external",
            files: [("a.yaml", .text("id: a\u{A}kind: FIXED\u{A}keyType: TEXT\u{A}")),
                    ("b.yaml", .text("id: b\u{A}kind: EXTERNAL_DATA\u{A}"))],
            error: .failure("sada 'b' vy\u{17E}aduje DXCC data, ale resolver chyb\u{ED}"),
            render: [
                #"ids ["wpx_prefixes", "a"]"#,
                #"  "wpx_prefixes" WpxMultiplierSet id="wpx_prefixes" enum=false values="#,
                #"  "a" FixedMultiplierSet id="a" enum=true values="#,
            ]),
        Row("nodxcc-other-provider",
            files: [("b.yaml", .text("id: b\u{A}kind: EXTERNAL_DATA\u{A}provider: {type: x}\u{A}"))],
            error: .failure("nezn\u{E1}m\u{FD} provider 'x' u sady 'b'"),
            render: [
                #"ids ["wpx_prefixes"]"#,
                #"  "wpx_prefixes" WpxMultiplierSet id="wpx_prefixes" enum=false values="#,
            ]),
        Row("algorithm",
            files: [("a.yaml", .text("id: a\u{A}kind: ALGORITHM\u{A}algorithm: {type: WPX}\u{A}"))],
            error: nil,
            render: [
                #"ids ["wpx_prefixes", "a"]"#,
                #"  "wpx_prefixes" WpxMultiplierSet id="wpx_prefixes" enum=false values="#,
                #"  "a" WpxMultiplierSet id="a" enum=false values="#,
            ]),
        Row("algorithm-null",
            files: [("a.yaml", .text("id: a\u{A}kind: ALGORITHM\u{A}"))],
            error: .failure("nezn\u{E1}m\u{FD} algoritmus 'null' u sady 'a'"),
            render: [
                #"ids ["wpx_prefixes"]"#,
                #"  "wpx_prefixes" WpxMultiplierSet id="wpx_prefixes" enum=false values="#,
            ]),
        Row("algorithm-empty",
            files: [("a.yaml", .text("id: a\u{A}kind: ALGORITHM\u{A}algorithm: {type: ''}\u{A}"))],
            error: .failure("nezn\u{E1}m\u{FD} algoritmus '' u sady 'a'"),
            render: [
                #"ids ["wpx_prefixes"]"#,
                #"  "wpx_prefixes" WpxMultiplierSet id="wpx_prefixes" enum=false values="#,
            ]),
        Row("algorithm-other",
            files: [("a.yaml", .text("id: a\u{A}kind: ALGORITHM\u{A}algorithm: {type: dxcc}\u{A}"))],
            error: .failure("nezn\u{E1}m\u{FD} algoritmus 'dxcc' u sady 'a'"),
            render: [
                #"ids ["wpx_prefixes"]"#,
                #"  "wpx_prefixes" WpxMultiplierSet id="wpx_prefixes" enum=false values="#,
            ]),
        Row("yaml-bom",
            files: [("a.yaml", .text("\u{FEFF}id: a\u{A}kind: FIXED\u{A}values: [{key: A}]\u{A}"))],
            error: nil,
            render: [
                #"ids ["wpx_prefixes", "a"]"#,
                #"  "wpx_prefixes" WpxMultiplierSet id="wpx_prefixes" enum=false values="#,
                #"  "a" FixedMultiplierSet id="a" enum=true values=("A","A",[])"#,
            ]),
        // Java: THROW MultiplierException: "Nelze na\u{10D}\u{ED}st definici sady: Cannot deserialize value of type `cz.ok1xoe.maccontestlogger.multiplier.MultiplierSetDefinition$SetKind` from String \u{22}fixed\u{22}: not one of the values accepted for Enum class: [FIXED, EXTERNAL_DATA, ALGORITHM]\u{A} at [Source:
        Row("yaml-bom-error",
            files: [("a.yaml", .text("\u{FEFF}id: a\u{A}kind: fixed\u{A}"))],
            error: .invalidDefinition(line: 2, column: 7),
            render: [
                #"ids ["wpx_prefixes"]"#,
                #"  "wpx_prefixes" WpxMultiplierSet id="wpx_prefixes" enum=false values="#,
            ]),
        // Java: THROW MultiplierException: "Nelze na\u{10D}\u{ED}st definici sady: Cannot deserialize value of type `cz.ok1xoe.maccontestlogger.multiplier.MultiplierSetDefinition$SetKind` from String \u{22}fixed\u{22}: not one of the values accepted for Enum class: [FIXED, EXTERNAL_DATA, ALGORITHM]\u{A} at [Source:
        Row("yaml-syntax-error",
            files: [("a.yaml", .text("id: a\u{A}kind: FIXED\u{A}keyType: TEXT\u{A}")),
                    ("b.yaml", .text("id: b\u{A}kind: fixed\u{A}")),
                    ("c.yaml", .text("id: c\u{A}kind: FIXED\u{A}keyType: TEXT\u{A}"))],
            error: .invalidDefinition(line: 2, column: 7),
            render: [
                #"ids ["wpx_prefixes", "a"]"#,
                #"  "wpx_prefixes" WpxMultiplierSet id="wpx_prefixes" enum=false values="#,
                #"  "a" FixedMultiplierSet id="a" enum=true values="#,
            ]),
        // Java: THROW MultiplierException: "Nelze na\u{10D}\u{ED}st definici sady: java.io.IOException: Is a directory\u{A} at [Source: (sun.nio.ch.ChannelInputStream); line: 1, column: 1]"
        Row("yaml-dir",
            files: [("a.yaml", .directory),
                    ("b.yaml", .text("id: b\u{A}kind: FIXED\u{A}keyType: TEXT\u{A}"))],
            error: .failure("Nelze načíst definici sady: Is a directory"),
            render: [
                #"ids ["wpx_prefixes"]"#,
                #"  "wpx_prefixes" WpxMultiplierSet id="wpx_prefixes" enum=false values="#,
            ]),
        Row("empty-dir",
            files: [],
            error: nil,
            render: [
                #"ids ["wpx_prefixes"]"#,
                #"  "wpx_prefixes" WpxMultiplierSet id="wpx_prefixes" enum=false values="#,
            ]),
        Row("keylength",
            files: [("a.yaml", .text("id: a\u{A}kind: FIXED\u{A}keyType: TEXT\u{A}keyLength: 2\u{A}validation: {keyPattern: '[A-R]{2}[0-9]{2}'}\u{A}"))],
            error: nil,
            render: [
                #"ids ["wpx_prefixes", "a"]"#,
                #"  "wpx_prefixes" WpxMultiplierSet id="wpx_prefixes" enum=false values="#,
                #"  "a" FixedMultiplierSet id="a" enum=true values="#,
            ]),
    ]
}
