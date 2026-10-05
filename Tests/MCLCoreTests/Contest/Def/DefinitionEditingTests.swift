import Foundation
import Testing
@testable import MCLCore

/// Port of the Java `DefinitionEditingTest` (7 tests) and cases measured by the probe
/// `ProbeEdit.java` / `ProbeSum.java` (maintainer-only probe, JDK 21). The editor is **text-based**: `withId` is a regex
/// replacement of one line, `save` writes the user's text, `template` is a fixed
/// text template — nothing is re-serialised.
@Suite struct DefinitionEditingTests {

    /// Java `Set.of("dxcc_entities", "cq_zones")`; in Swift a sorted array
    /// (the set message lists in iteration order, `TreeSet` in production).
    static let sets = ["cq_zones", "dxcc_entities"]

    static let tx = DefinitionEditing.template("x", "X")

    static func lines(_ check: DefinitionEditing.Check) -> [String] {
        check.issues.map { "[\($0.severity)] \($0.message)" }
    }

    // MARK: - Java DefinitionEditingTest

    @Test func templateIsValid() throws {
        let check = DefinitionEditing.check(DefinitionEditing.template("my-test", "Můj závod"),
                                            fileId: "my-test", knownSets: Self.sets)
        #expect(!check.hasErrors, "\(check.issues)")
        #expect(check.definition?.id == "my-test")
        let definition = try #require(check.definition)
        #expect(DefinitionEditing.summary(definition).contains("Název: Můj závod"))
        // Beyond Java: the whole summary measured on JDK 21.
        #expect(DefinitionEditing.summary(definition) == [
            "Název: Můj závod",
            "Pásma: 160m 80m 40m 20m 15m 10m",
            "Módy: CW SSB",
            "Délka: 24 h",
            "Výměna odeslaná: rst:RST nr:SERIAL",
            "Výměna přijatá: rst:RST nr:SERIAL",
            "Násobiče: countries (dxcc_entities, PER_BAND)",
            "Skóre: qsoPoints * multTotal",
            "Dupe: PER_BAND_MODE",
            "Cabrillo: MY-TEST",
        ])
    }

    /// In Java this is a **type** error (string instead of a list) at 8:8, not a
    /// syntax one — Swift must report the same line and column.
    @Test func parseErrorReportsLine() {
        let yaml = Self.tx.replacingOccurrences(of: "bands: [160m", with: "bands: 160m, [")
        let check = DefinitionEditing.check(yaml, fileId: "x", knownSets: Self.sets)
        #expect(check.definition == nil)
        #expect(check.hasErrors)
        #expect(check.issues[0].message.contains("řádek"), "\(check.issues[0].message)")
        // Java: "Cannot construct instance of `java.util.ArrayList` … (řádek 8, sloupec 8)".
        #expect(check.issues.count == 1)
        #expect(check.issues[0].severity == .error)
        #expect(check.issues[0].message.hasSuffix(" (řádek 8, sloupec 8)"), "\(check.issues[0].message)")
    }

    /// Java name `unknownFieldIsParseError` — in fact the loader silently ignores the unknown key
    /// `modez` and the error comes only from the validator ("chybí modes").
    @Test func missingModesIsValidationError() {
        let yaml = Self.tx.replacingOccurrences(of: "modes:", with: "modez:")
        let check = DefinitionEditing.check(yaml, fileId: "x", knownSets: Self.sets)
        #expect(check.hasErrors)
        #expect(check.definition != nil)
        #expect(Self.lines(check) == ["[ERROR] chybí modes"])
    }

    @Test func validatorAndSetReferencesAreChecked() {
        let yaml = Self.tx.replacingOccurrences(of: "set: dxcc_entities", with: "set: nonexistent")
        let check = DefinitionEditing.check(yaml, fileId: "y", knownSets: Self.sets)
        #expect(check.definition != nil)
        #expect(check.hasErrors)
        let messages = check.issues.map(\.message)
        #expect(messages.contains { $0.contains("nonexistent") }, "\(messages)")
        #expect(messages.contains { $0.contains("liší od názvu souboru") }, "\(messages)")
        #expect(Self.lines(check) == [
            "[WARNING] id 'x' se liší od názvu souboru 'y.yaml'",
            "[ERROR] multiplier 'countries' odkazuje na neexistující sadu 'nonexistent' (dostupné: cq_zones, dxcc_entities)",
        ])
    }

    @Test func withIdReplacesIdLine() {
        let copy = DefinitionEditing.withId(DefinitionEditing.template("a", "A"), "b-copy")
        #expect(DefinitionEditing.check(copy, fileId: "b-copy", knownSets: Self.sets).definition?.id == "b-copy")
        #expect(!DefinitionEditing.isValidId("Bad Id"))
        #expect(DefinitionEditing.isValidId("cq-ww_2"))
    }

    @Test func saveAndList() throws {
        let dir = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try DefinitionEditing.save(dir, id: "abc", yaml: "schemaVersion: 1")
        #expect(try Self.read(dir, "abc.yaml") == "schemaVersion: 1\n")
        try DefinitionEditing.save(dir, id: "abc", yaml: "id: abc\n")
        #expect(try Self.read(dir, "abc.yaml") == "id: abc\n")
        #expect(DefinitionEditing.listIds(dir) == ["abc"])
        #expect(throws: DefinitionEditingError.self) {
            try DefinitionEditing.save(dir, id: "../evil", yaml: "x")
        }
    }

    @Test func shippedDefinitionsPass() throws {
        let root = try #require(Bundle.module.url(forResource: "contest-data", withExtension: nil))
        let sets = DefinitionEditing.knownSets(root.appendingPathComponent("multipliers"))
        let ids = DefinitionEditing.listIds(root.appendingPathComponent("contests"))
        #expect(ids.count == 22)
        #expect(!sets.isEmpty)
        for id in ids {
            let yaml = try String(contentsOf: root.appendingPathComponent("contests/\(id).yaml"), encoding: .utf8)
            let check = DefinitionEditing.check(yaml, fileId: id, knownSets: sets)
            #expect(!check.hasErrors, "\(id): \(check.issues)")
        }
    }

    // MARK: - template: byte for byte against Java

    @Test(arguments: [
        ("tpl-my-test.yaml", "my-test", "Můj závod"),
        ("tpl-quote.yaml", "q-1", "Závod \"Velký\" 'x'"),
        // Invalid id and name with `\` — the template checks and escapes nothing;
        // `ß` expands to `SS` in upper case (Locale.ROOT).
        ("tpl-weird.yaml", "abcß-i", "a\\b"),
    ])
    func templateMatchesJavaBytes(_ fixture: String, _ id: String, _ name: String) throws {
        let dir = try #require(Bundle.module.url(forResource: "definition-editing-java", withExtension: nil))
        let expected = try Data(contentsOf: dir.appendingPathComponent(fixture))
        #expect(Data(DefinitionEditing.template(id, name).utf8) == expected)
    }

    /// A quote with a combining character is a different grapheme for Swift comparison;
    /// Java replaces by UTF-16 units, so it is replaced here too.
    @Test func templateReplacesQuoteBeforeCombiningMark() {
        let text = DefinitionEditing.template("a", "x\"\u{301}y")
        #expect(text.contains("  name: \"x'\u{301}y\"\n"))
    }

    // MARK: - withId (source 3.7, measured)

    @Test(arguments: [
        ("metadata:\n  id: a\nid: b\n", "n", "metadata:\n  id: a\nid: n\n"),
        // indented `  id:` is skipped → nothing found → the line is prepended
        ("  id: a\n", "n", "id: n\n  id: a\n"),
        // `\s*` also skips the line break: it eats two lines (a Java flaw, copied)
        ("id:\nid: 2\n", "n", "id: n\n"),
        ("id:   \n\n  \nfoo: 1\n", "n", "id: n\n"),
        // the comment after id disappears
        ("id: old # c\nx: 1\n", "n", "id: n\nx: 1\n"),
        // CRLF: `\r` stays (Focus 2)
        ("id: a\r\nx: 1\r\n", "n", "id: n\r\nx: 1\r\n"),
        ("x: 1\rid: a\r", "n", "x: 1\rid: n\r"),
        ("x: 1\u{85}id: a\u{85}y: 2", "n", "x: 1\u{85}id: n\u{85}y: 2"),
        ("x: 1\u{2028}id: a\u{2028}y: 2", "n", "x: 1\u{2028}id: n\u{2028}y: 2"),
        // `.` takes `\u{0B}` (not a Java line break), `\s` takes it too
        ("id: a\u{0B}b\nc\n", "n", "id: n\nc\n"),
        ("id:\u{0B}\u{0C}z\n", "n", "id: n\n"),
        ("id:a\n", "n", "id: n\n"),
        ("ids: a\nid: b\n", "n", "ids: a\nid: n\n"),
        ("x: 1\n", "n", "id: n\nx: 1\n"),
        ("", "n", "id: n\n"),
        // `$1` and `\` are inserted verbatim (quoteReplacement) in both branches
        ("id: a\n", "$1\\x$0", "id: $1\\x$0\n"),
        ("x: 1\n", "$1\\x", "id: $1\\x\nx: 1\n"),
    ])
    func withIdMatchesJava(_ yaml: String, _ newId: String, _ expected: String) {
        let result = DefinitionEditing.withId(yaml, newId)
        #expect(Array(result.utf16) == Array(expected.utf16), "\(result.debugDescription)")
    }

    @Test func withIdKeepsRestOfTemplateByteForByte() {
        let result = DefinitionEditing.withId(Self.tx, "b-copy")
        #expect(result == Self.tx.replacingOccurrences(of: "\nid: x\n", with: "\nid: b-copy\n"))
    }

    // MARK: - isValidId

    @Test func isValidIdMatchesJava() {
        let valid = ["a", "0", "a-", "a_b-c", "cq-ww_2"]
        let invalid: [String?] = [nil, "", "-a", "_a", "A", "á", "a b", "a.b", "../evil", "a\n", "a\u{301}"]
        for id in valid { #expect(DefinitionEditing.isValidId(id), "\(id)") }
        for id in invalid { #expect(!DefinitionEditing.isValidId(id), "\(String(describing: id))") }
    }

    // MARK: - check (source 3.7, 7.4)

    @Test(arguments: [
        // null and "" → empty input (Java "No content to map due to end-of-input (řádek 1, sloupec 1)")
        (nil as String?, " (řádek 1, sloupec 1)"),
        ("", " (řádek 1, sloupec 1)"),
        // Java "while parsing a flow node (řádek 1, sloupec 5)" — the end of the last
        // event (`[`); once a divergence, now fixed.
        ("a: [\n", " (řádek 1, sloupec 5)"),
    ])
    func parseFailuresCarryJavaPosition(_ yaml: String?, _ suffix: String) {
        let check = DefinitionEditing.check(yaml, fileId: nil, knownSets: Self.sets)
        #expect(check.definition == nil)
        #expect(check.hasErrors)
        #expect(check.issues.count == 1)
        #expect(check.issues.first?.severity == .error)
        #expect(check.issues.first?.message.hasSuffix(suffix) == true, "\(check.issues)")
    }

    /// Type errors deep in the definition (Focus 4) — positions from Java.
    @Test(arguments: [
        ("scope: PER_BAND }", "scope: per_band }", " (řádek 24, sloupec 65)"),
        ("required: true }\n    - { id: nr", "required: ano }\n    - { id: nr", " (řádek 16, sloupec 39)"),
        ("bands: [160m, 80m, 40m, 20m, 15m, 10m]", "bands: 20m", " (řádek 8, sloupec 8)"),
    ])
    func typeErrorsCarryJavaPosition(_ from: String, _ to: String, _ suffix: String) {
        let yaml = Self.tx.replacingOccurrences(of: from, with: to)
        #expect(yaml != Self.tx)
        let check = DefinitionEditing.check(yaml, fileId: "x", knownSets: Self.sets)
        #expect(check.definition == nil)
        #expect(check.issues.count == 1)
        #expect(check.issues.first?.message.hasSuffix(suffix) == true, "\(check.issues)")
    }

    /// Decision 3: root `~`/`---` → ERROR "definice je prázdná" (Java shows
    /// the NPE text `Cannot invoke "…schemaVersion()" because "def" is null`).
    @Test(arguments: ["~\n", "---\n"])
    func nullRootIsEmptyDefinition(_ yaml: String) {
        let check = DefinitionEditing.check(yaml, fileId: nil, knownSets: Self.sets)
        #expect(check.definition == nil)
        #expect(check.hasErrors)
        #expect(Self.lines(check) == ["[ERROR] definice je prázdná"])
    }

    @Test func newerSchemaMessageIsJavas() {
        let yaml = Self.tx.replacingOccurrences(of: "schemaVersion: 1", with: "schemaVersion: 2")
        let check = DefinitionEditing.check(yaml, fileId: "x", knownSets: Self.sets)
        #expect(check.definition == nil)
        #expect(Self.lines(check) == [
            "[ERROR] Novější formát definice (schemaVersion=2), aktualizuj aplikaci. Podporováno: 1",
        ])
    }

    @Test(arguments: [
        // id: "" → additionally a shape error and a warning (source 7.4)
        ("id: x", "id: \"\"", "x" as String?, sets, [
            "[ERROR] chybí id závodu",
            "[ERROR] id '' smí obsahovat jen malá písmena, číslice, - a _",
            "[WARNING] id '' se liší od názvu souboru 'x.yaml'",
        ]),
        ("id: x", "id: ~", "x", sets, ["[ERROR] chybí id závodu"]),
        ("id: x", "id: Bad_X", nil, sets, [
            "[ERROR] id 'Bad_X' smí obsahovat jen malá písmena, číslice, - a _",
        ]),
        // set: "" → besides the validator's "nemá set" also a nonexistent set ''
        ("set: dxcc_entities", "set: \"\"", "x", sets, [
            "[ERROR] multiplier 'countries' nemá set",
            "[ERROR] multiplier 'countries' odkazuje na neexistující sadu '' (dostupné: cq_zones, dxcc_entities)",
        ]),
        ("set: dxcc_entities", "set: ~", "x", sets, ["[ERROR] multiplier 'countries' nemá set"]),
        // empty knownSets = do not check
        ("set: dxcc_entities", "set: \"\"", "x", [], ["[ERROR] multiplier 'countries' nemá set"]),
        ("set: dxcc_entities", "set: nonexistent", "x", [], []),
        ("  - { id: countries, set: dxcc_entities, from: callsign, scope: PER_BAND }",
         "  - { id: a, set: zz, from: callsign, scope: PER_BAND }\n  - { id: b, set: aa, from: callsign }",
         "x", sets, [
            "[ERROR] multiplier 'b' nemá scope",
            "[ERROR] multiplier 'a' odkazuje na neexistující sadu 'zz' (dostupné: cq_zones, dxcc_entities)",
            "[ERROR] multiplier 'b' odkazuje na neexistující sadu 'aa' (dostupné: cq_zones, dxcc_entities)",
        ]),
        ("multipliers:\n  - { id: countries, set: dxcc_entities, from: callsign, scope: PER_BAND }",
         "multipliers: []", "x", sets, []),
    ] as [(String, String, String?, [String], [String])])
    func checkFindingsMatchJava(_ from: String, _ to: String, _ fileId: String?, _ sets: [String],
                                _ expected: [String]) {
        let yaml = Self.tx.replacingOccurrences(of: from, with: to)
        #expect(yaml != Self.tx)
        let check = DefinitionEditing.check(yaml, fileId: fileId, knownSets: sets)
        #expect(check.definition != nil)
        #expect(Self.lines(check) == expected)
        #expect(check.hasErrors == expected.contains { $0.hasPrefix("[ERROR]") })
    }

    /// Comparing the id with the file is Java `equals` (UTF-16), not Swift's canonical
    /// equality: an NFD file name against an NFC id **differs**.
    @Test func fileIdComparisonIsByUtf16Units() {
        let check = DefinitionEditing.check(Self.tx, fileId: "x\u{301}", knownSets: [])
        let nfc = DefinitionEditing.check(Self.tx.replacingOccurrences(of: "id: x\n", with: "id: \u{E9}\n"),
                                          fileId: "e\u{301}", knownSets: [])
        #expect(Self.lines(check) == ["[WARNING] id 'x' se liší od názvu souboru 'x\u{301}.yaml'"])
        #expect(nfc.issues.map(\.message).contains("id '\u{E9}' se liší od názvu souboru 'e\u{301}.yaml'"))
    }

    /// The set is looked up with Java `contains` (UTF-16), not canonically.
    @Test func knownSetLookupIsByUtf16Units() {
        let yaml = Self.tx.replacingOccurrences(of: "set: dxcc_entities", with: "set: \u{E9}")
        let check = DefinitionEditing.check(yaml, fileId: "x", knownSets: ["e\u{301}"])
        #expect(Self.lines(check) == [
            "[ERROR] multiplier 'countries' odkazuje na neexistující sadu '\u{E9}' (dostupné: e\u{301})",
        ])
    }

    /// Focus 2 and 3: CRLF and BOM are both loaded as LF.
    @Test func crlfAndBomAreAccepted() {
        for yaml in [Self.tx.replacingOccurrences(of: "\n", with: "\r\n"), "\u{FEFF}" + Self.tx] {
            let check = DefinitionEditing.check(yaml, fileId: "x", knownSets: Self.sets)
            #expect(!check.hasErrors, "\(check.issues)")
            #expect(check.definition?.id == "x")
        }
    }

    /// Known divergence: `multipliers: [~]` with non-empty
    /// `knownSets` — Java crashes with an NPE **out of `check`** (`m.set()`), Swift skips the `nil`
    /// element and returns the validator error "multiplier bez id" (Java
    /// returns that too with empty `knownSets`).
    @Test func nilMultiplierElementIsSkipped() {
        let yaml = Self.tx.replacingOccurrences(
            of: "  - { id: countries, set: dxcc_entities, from: callsign, scope: PER_BAND }", with: "  - ~")
        for sets in [Self.sets, []] {
            let check = DefinitionEditing.check(yaml, fileId: "x", knownSets: sets)
            #expect(check.definition != nil)
            #expect(check.hasErrors)
            #expect(Self.lines(check) == ["[ERROR] multiplier bez id"])
        }
    }

    // MARK: - summary (source 3.7: `null` is printed verbatim)

    @Test(arguments: [
        ("schemaVersion: 1\nid: s\nexchange: {}\nscoring: {}\n", [
            "Název: —", "Pásma: —", "Módy: —", "Výměna odeslaná: —", "Výměna přijatá: —",
            "Násobiče: žádné", "Skóre: null",
        ]),
        ("schemaVersion: 1\nid: s\nmultipliers: [ { id: m } ]\n", [
            "Název: —", "Pásma: —", "Módy: —", "Násobiče: m (null, null)",
        ]),
        ("schemaVersion: 1\n", ["Název: —", "Pásma: —", "Módy: —", "Násobiče: žádné"]),
        ("schemaVersion: 1\nid: s\nmetadata: {}\nperiod: { durationHours: -3 }\nexchange: { sent: [], received: ~ }\n"
            + "multipliers: []\ndupe: { scope: ONCE }\ncabrillo: { contestName: \"\" }\nscoring: { total: \"\" }\n", [
            "Název: —", "Pásma: —", "Módy: —", "Délka: -3 h", "Výměna odeslaná: —", "Výměna přijatá: —",
            "Násobiče: žádné", "Skóre: ", "Dupe: ONCE", "Cabrillo: ",
        ]),
        ("schemaVersion: 1\nid: s\nperiod: 12\n", ["Název: —", "Pásma: —", "Módy: —", "Délka: 12 h", "Násobiče: žádné"]),
    ])
    func summaryMatchesJava(_ yaml: String, _ expected: [String]) throws {
        let definition = try #require(DefinitionEditing.check(yaml, fileId: "s", knownSets: []).definition)
        #expect(DefinitionEditing.summary(definition) == expected)
    }

    /// `nil` list elements: `bands`/`modes` Java prints as `null` too
    /// (`String.join`); a `nil` exchange field and a `nil` multiplier make Java crash with an NPE
    /// (`f.id()`, `m.id()`), Swift prints them as `null` — a known divergence.
    @Test func summaryPrintsNilElementsAsNull() throws {
        let yaml = "schemaVersion: 1\nid: s\nmetadata: { name: \"\" }\nbands: [20m, ~, \"\"]\nmodes: [~]\nperiod: {}\n"
            + "exchange: { sent: [ { type: RST } ], received: [ { id: r }, {}, ~ ] }\nscoring: {}\ndupe: {}\n"
            + "cabrillo: {}\nmultipliers: [ {}, ~ ]\n"
        let definition = try #require(DefinitionEditing.check(yaml, fileId: "s", knownSets: []).definition)
        #expect(DefinitionEditing.summary(definition) == [
            "Název: ",
            "Pásma: 20m null ",
            "Módy: null",
            "Výměna odeslaná: null:RST",
            "Výměna přijatá: r:null null:null null",   // last `null` = Java NPE
            "Násobiče: null (null, null), null",        // last `null` = Java NPE
            "Skóre: null",
            "Dupe: null",
            "Cabrillo: null",
        ])
    }

    // MARK: - listIds / knownSets

    /// Java: `Files.list` + `endsWith(".yaml")` + `sorted()` by UTF-16 units.
    /// `😀` (D83D…) is **before** `ａ` (FF41) in UTF-16, **after** it by UTF-8 bytes.
    @Test func listIdsSortsByUtf16Units() throws {
        let dir = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        for name in ["b.yaml", "a.yaml", "_x.yaml", "\u{E9}.yaml", "\u{1F600}.yaml", "\u{FF41}.yaml",
                     "z.YAML", "c.yml", ".yaml", "._a.yaml", "noext"] {
            try Self.touch(dir, name)
        }
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("sub.yaml"),
                                                withIntermediateDirectories: false)
        let expected = ["", "._a", "_x", "a", "b", "sub", "\u{E9}", "\u{1F600}", "\u{FF41}"]
        #expect(DefinitionEditing.listIds(dir).map { Array($0.utf16) } == expected.map { Array($0.utf16) })
        #expect(DefinitionEditing.knownSets(dir).map { Array($0.utf16) } == expected.map { Array($0.utf16) })
    }

    /// Java does not normalise names (measured by `ProbeNfd`: an NFD file `e\u{301}x.yaml`
    /// is returned as NFD and sorted before `f`); Swift `<` would canonically place it
    /// like `éx` after `f`.
    @Test func listIdsKeepsNfdNamesAndSortsThemByUtf16() throws {
        let dir = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        for name in ["e\u{301}x.yaml", "f.yaml", "\u{E9}a.yaml"] {
            try Self.touch(dir, name)
        }
        let expected = ["e\u{301}x", "f", "\u{E9}a"]
        #expect(DefinitionEditing.listIds(dir).map { Array($0.utf16) } == expected.map { Array($0.utf16) })
    }

    @Test func listIdsOfMissingDirectoryIsEmpty() throws {
        let dir = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Self.touch(dir, "b.yaml")
        #expect(DefinitionEditing.listIds(dir.appendingPathComponent("nope")) == [])
        #expect(DefinitionEditing.listIds(nil) == [])
        #expect(DefinitionEditing.listIds(dir.appendingPathComponent("b.yaml")) == [])
        #expect(DefinitionEditing.knownSets(nil) == [])
    }

    // MARK: - save

    @Test func saveAppendsNewlineAndCreatesDirectories() throws {
        let root = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let dir = root.appendingPathComponent("save/nested")
        let target = try DefinitionEditing.save(dir, id: "abc", yaml: "schemaVersion: 1")
        #expect(target.lastPathComponent == "abc.yaml")
        #expect(try Self.read(dir, "abc.yaml") == "schemaVersion: 1\n")
        try DefinitionEditing.save(dir, id: "abc", yaml: "x\r")
        #expect(try Self.read(dir, "abc.yaml") == "x\r\n")
        try DefinitionEditing.save(dir, id: "abc", yaml: "")
        #expect(try Self.read(dir, "abc.yaml") == "\n")
        // Java: `Files.createTempFile` → permissions 0600, carried over by the move.
        let attributes = try FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent("abc.yaml").path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["abc.yaml"])
    }

    /// Text ending in CRLF no longer gets `\n` (Java `endsWith("\n")`
    /// by units; Swift `hasSuffix` treats `"\r\n"` as one grapheme).
    @Test(arguments: [
        ("a\r\n", Array("a\r\n".utf8)),
        ("\r\n", Array("\r\n".utf8)),
        ("a\n\r", Array("a\n\r\n".utf8)),
    ])
    func saveKeepsCrlfEnding(_ yaml: String, _ expected: [UInt8]) throws {
        let dir = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try DefinitionEditing.save(dir, id: "abc", yaml: yaml)
        #expect(Array(try Data(contentsOf: dir.appendingPathComponent("abc.yaml"))) == expected)
    }

    @Test(arguments: ["../evil", "", "A"])
    func saveRejectsInvalidId(_ id: String) throws {
        let dir = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(throws: DefinitionEditingError(message: "Neplatné id souboru: " + id)) {
            try DefinitionEditing.save(dir, id: id, yaml: "x")
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == [])
    }

    /// The target is a directory: the move fails (Java "Is a directory") and the temporary file
    /// does not remain.
    @Test func failedMoveLeavesNoTemporaryFile() throws {
        let dir = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("dirid.yaml"),
                                                withIntermediateDirectories: false)
        #expect(throws: DefinitionEditingError.self) {
            try DefinitionEditing.save(dir, id: "dirid", yaml: "x")
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["dirid.yaml"])
    }

    /// The contest directory is actually a file (Java `FileAlreadyExistsException`).
    @Test func saveIntoFileFails() throws {
        let dir = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Self.touch(dir, "b.yaml")
        #expect(throws: DefinitionEditingError.self) {
            try DefinitionEditing.save(dir.appendingPathComponent("b.yaml"), id: "abc", yaml: "x")
        }
    }

    // MARK: - helpers

    static func temporaryDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DefinitionEditingTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func read(_ dir: URL, _ name: String) throws -> String {
        try String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)
    }

    /// Creates a file via POSIX so the name reaches the disk as bytes as given
    /// (`URL(fileURLWithPath:)` would convert it to NFD).
    static func touch(_ dir: URL, _ name: String) throws {
        let descriptor = open(dir.path + "/" + name, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        try #require(descriptor >= 0)
        close(descriptor)
    }
}
