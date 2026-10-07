import CryptoKit
import Foundation
import Testing
@testable import MCLCore

/// The `i18n/` package against Java v1.1.1 (maintainer-only probe, table `I18nMeasured`):
/// `LanguageCatalog.load` over bytes (hand-made Jackson edges, UTF-16/32, limits, 600 fuzzer files), `list`
/// over directories (names, labels, links, permissions, Unicode), `ensureDir`, the shipped files and the formatting
/// `tr(cs, args)` (`String.format` pod `en_US` a `cs_CZ`).
@Suite struct I18nMeasuredTests {

    private static func rows(_ id: String) -> [[String]] {
        ProbeRows.rawRows(I18nMeasured.rows, id)
    }

    /// The shipped `lang_en.json` / `lang_de.json` intentionally differ from Java v1.1.1: 61 keys were appended for
    /// Kotlin literals the Swift UI translates, the 20 `menu.json` labels Java leaves out
    /// (deliberate divergences from Java v1.1.1), 1 key of the post-port QO-100 spot tooltip line, 2 accessibility labels of the SCP and N+1 rows and 2 Settings labels of their switches and 12 keys of the manual callbook lookups and 1 key of the missing-frequency spot status and 1 accessibility label of the DX Cluster window parallel switch and 1 Settings Apply button and 16 keys of the Club Log DXCC update and 26 keys of the window plugins. The Java measurement stays as it was; these are its cells for the shipped files
    /// with the Swift files' size, hash and map digest.
    static let shippedFileCells: [String: String] = [
        "81929": "90337", "afc6becd4f499483": "64f17d7ea0daea2a",
        "87423": "96416", "d0c67e41ffca0e5d": "02cb9a772122f4f2",
        "1006": "1153",
        "cc0ee26c076bc811dcc8325b5de39f43b89e7c0e8805e23db59cea0b4def8a4f":
            "5574cf24cba2020e9da87c5229b02ce61a55017003cb3b330861e39af8739e88",
        "2c37f524ad0b3da50e3eac30e91daf1f8bbe8353c3f844467c667a8f5f881bdb":
            "49014572cbe885995d828ac5ed1c599bf5801bbd74b8ef64a7b93c03041f929f",
    ]

    /// A Java cell describing a shipped file, adjusted to the Swift files (`shippedFileCells`). Only whole
    /// alphanumeric tokens are replaced (a cell, or `name:hash` inside a listing), so a value that merely contains
    /// one of the numbers is never rewritten.
    static func shipped(_ cell: String) -> String {
        var out: String = ""
        var token: String = ""
        for character in cell {
            if character.isLetter || character.isNumber {
                token.append(character)
            } else {
                out += shippedFileCells[token] ?? token
                token = ""
                out.append(character)
            }
        }
        return out + (shippedFileCells[token] ?? token)
    }

    /// Probe escaping: UTF-16 units < 0x20, > 0x7E and `\` as `\uXXXX`.
    static func esc(_ text: String) -> String {
        var out = ""
        for unit in text.utf16 {
            if unit < 0x20 || unit > 0x7E || unit == 0x5C {
                let hex: String = String(unit, radix: 16).uppercased()
                out += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
            } else {
                out.unicodeScalars.append(Unicode.Scalar(unit)!)
            }
        }
        return out
    }

    /// Java probe text as a Swift `String` can carry it: lone surrogates → `U+FFFD` (`JavaChar.string`).
    static func swiftView(_ javaCell: String) -> String {
        esc(String(decoding: ProbeRows.unescapeUnits(javaCell), as: UTF16.self))
    }

    static func bytes(hex: String) -> [UInt8] {
        let chars: [Character] = Array(hex)
        return stride(from: 0, to: chars.count, by: 2).map { UInt8(String(chars[$0...$0 + 1]), radix: 16)! }
    }

    /// `[k=v, …]` in `TreeMap` order.
    static func render(_ map: LanguageCatalog.Translations) -> String {
        let parts: [String] = map.sortedEntries.map { esc($0.key) + "=" + esc($0.value) }
        return "[" + parts.joined(separator: ", ") + "]"
    }

    static func sha(_ bytes: [UInt8]) -> String {
        SHA256.hash(data: bytes).map { $0 < 16 ? "0" + String($0, radix: 16) : String($0, radix: 16) }.joined()
    }

    // MARK: - load

    /// String items of the map equal to Java; non-string values are omitted by Swift, so the
    /// "String only" column of the probe is compared.
    @Test func loadMatchesJava() {
        let all: [[String]] = Self.rows("L.load")
        #expect(all.count == 767)
        var mismatches: [String] = []
        for row in all {
            let got: String = Self.render(LanguageJsonReader.read(Self.bytes(hex: row[1])).map {
                LanguageCatalog.Translations($0)
            } ?? .empty)
            let want: String = Self.swiftView(row[3])
            if got != want {
                mismatches.append(row[0] + ": " + got + " != " + want)
            }
        }
        #expect(mismatches.isEmpty, "\(mismatches.prefix(10))")
    }

    /// A `null` value discards the whole file, a non-string only its key (Java keeps it in the map — the "all" column).
    @Test func nullDropsFileNonStringDropsKey() {
        let byId: [String: [String]] = Dictionary(uniqueKeysWithValues: Self.rows("L.load").map { ($0[0], $0) })
        #expect(byId["null-other"]?[2] == "NPE")
        #expect(byId["dup-string-then-null"]?[2] == "NPE")
        #expect(byId["dup-null-then-string"]?[3] == "[a=b]")
        #expect(byId["int"]?[4] == "[a=Integer, b=String:c]")
        let read: [JavaStringKey: String]? = LanguageJsonReader.read(Array("{\"a\":1,\"b\":\"c\"}".utf8))
        #expect(read == [JavaStringKey("b"): "c"])
        #expect(LanguageJsonReader.read(Array("{\"x\":\"y\",\"a\":null}".utf8)) == nil)
    }

    /// `StreamReadConstraints` limits (name 50,000 bytes / characters, string 20,000,000 units); input by id.
    /// Row by row as arguments, so that large inputs (up to 40 MB) run concurrently. Strings of 20 M units are expensive in the debug
    /// build (seconds per row), so only the rows that decide the boundary are replayed: ASCII exactly
    /// at the limit and just above it, surrogate pairs exactly at the limit (`pairs-10000000` = 20 M UTF-16 units, but
    /// 40 M UTF-8 bytes — the only row proving that UTF-16 units are counted, not bytes) and just above it
    /// (units, not scalars) and the UTF-16 character path just above it. Omitted: two rows **below** the limit
    /// (`ascii-19999999`, `pairs-9999999`) and `utf16le-20000000` **at** the limit (the character path counts the same as
    /// the byte one with ASCII, which `ascii-20000000` covers).
    static let slowLimitRows: Set<String> = [
        "value-ascii-19999999", "value-pairs-9999999", "value-utf16le-20000000",
    ]

    @Test(arguments: ProbeRows.rawRows(I18nMeasured.rows, "L.limit")
        .filter { !slowLimitRows.contains($0[0]) }.map { $0[0] + "=" + $0[1] })
    func limitsMatchJava(_ row: String) throws {
        let parts: [String] = row.components(separatedBy: "=")
        let input: [UInt8] = try #require(Self.limitInput(parts[0]))
        #expect(String(LanguageJsonReader.read(input)?.count ?? 0) == parts[1], "\(parts[0])")
    }

    @Test func limitRowsArePresent() {
        #expect(Self.rows("L.limit").count == 26)
    }

    private static func limitInput(_ id: String) -> [UInt8]? {
        guard let dash = id.lastIndex(of: "-"), let n = Int(id[id.index(after: dash)...]) else { return nil }
        let kind = String(id[..<dash])
        let tail = "\":\"v\",\"b\":\"c\"}"
        let valueTail = "\",\"b\":\"c\"}"
        switch kind {
        case "key-ascii": return Array(("{\"" + String(repeating: "k", count: n) + tail).utf8)
        case "key-e-acute": return Array(("{\"" + String(repeating: "\u{e9}", count: n) + tail).utf8)
        case "key-3byte": return Array(("{\"" + String(repeating: "\u{20ac}", count: n) + tail).utf8)
        case "key-escaped": return Array(("{\"" + String(repeating: "\\u0041", count: n) + tail).utf8)
        case "key-utf16le": return [0xFF, 0xFE] + utf16le("{\"" + String(repeating: "k", count: n) + tail)
        case "value-ascii", "long-value":
            return Array(("{\"a\":\"" + String(repeating: "x", count: n) + valueTail).utf8)
        case "value-pairs": return Array(("{\"a\":\"" + String(repeating: "\u{1F600}", count: n) + valueTail).utf8)
        case "value-utf16le":
            return [0xFF, 0xFE] + utf16le("{\"a\":\"" + String(repeating: "x", count: n) + valueTail)
        default: return nil
        }
    }

    private static func utf16le(_ text: String) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(text.utf16.count * 2)
        for unit in text.utf16 {
            out.append(UInt8(unit & 0xFF))
            out.append(UInt8(unit >> 8))
        }
        return out
    }

    // MARK: - shipped files

    @Test func bundledFilesAreJavaBytes() throws {
        for row in Self.rows("L.resource") where row[0].hasSuffix(".json") {
            let code = String(row[0].dropLast(5))
            let bytes: [UInt8] = try #require(LanguageCatalog.bundledBytes(code))
            #expect(String(bytes.count) == Self.shipped(row[1]))
            #expect(String(Self.sha(bytes).prefix(16)) == Self.shipped(row[2]))
        }
        for row in Self.rows("L.resource") where row[0].hasSuffix(".load") {
            let code = String(row[0].dropLast(5))
            let bytes: [UInt8] = try #require(LanguageCatalog.bundledBytes(code))
            let map = LanguageCatalog.Translations(try #require(LanguageJsonReader.read(bytes)))
            #expect(String(map.count) == Self.shipped(row[1]))
            #expect(Self.digest(map) == Self.shipped(row[2]))
            #expect(map["_name"] == row[3])
        }
    }

    /// SHA-256 over items in `TreeMap` order: key, NUL, value, NUL (UTF-8).
    private static func digest(_ map: LanguageCatalog.Translations) -> String {
        var data: [UInt8] = []
        for entry in map.sortedEntries {
            data += Array(entry.key.utf8) + [0] + Array(entry.value.utf8) + [0]
        }
        return sha(data)
    }

    // MARK: - list

    private static func listing(_ dir: String?) -> String {
        let parts: [String] = LanguageCatalog.list(dir).map { language in
            let name: String = (language.file ?? "").components(separatedBy: "/").last ?? ""
            return esc(language.code) + "=" + esc(language.label) + "|" + esc(name)
        }
        return "[" + parts.joined(separator: ", ") + "]"
    }

    /// Rows where Java throws `ClassCastException` (`_name` is not text), Swift omits `_name`
    /// and the label is the code in uppercase.
    static let listDivergences: [String: String] = [
        "name-int": "[a=A|lang_a.json, b=B|lang_b.json]",
        "name-array": "[a=A|lang_a.json]",
        "name-object": "[a=A|lang_a.json]",
        "name-bool": "[a=A|lang_a.json]",
    ]

    @Test func listMatchesJava() throws {
        var got: [String: String] = [:]
        try LanguageCatalogTests.withTemporaryDirectory { work in
            try Self.listScenarios(work, &got)
        }
        var mismatches: [String] = []
        for row in Self.rows("L.list") {
            let want: String = row[1].hasPrefix("throws ") ? (Self.listDivergences[row[0]] ?? "?") : row[1]
            if got[row[0]] != want {
                mismatches.append(row[0] + ": " + (got[row[0]] ?? "<missing>") + " != " + want)
            }
        }
        #expect(Self.rows("L.list").count == 14)
        #expect(Set(Self.rows("L.list").filter { $0[1].hasPrefix("throws ") }.map { $0[0] })
            == Set(Self.listDivergences.keys))
        #expect(mismatches.isEmpty, "\(mismatches)")
    }

    private static func fresh(_ work: String, _ name: String) throws -> String {
        let dir: String = work + "/" + name
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func w(_ dir: String, _ name: String, _ json: String) throws {
        try LanguageCatalogTests.write(dir, name, json)
    }

    private static func listScenarios(_ work: String, _ got: inout [String: String]) throws {
        let a: String = try fresh(work, "listA")
        try w(a, "lang_en.json", "{\"_name\": \"English\", \"Skóre\": \"Score\"}")
        try w(a, "lang_de.json", "{\"_name\": \"Deutsch\"}")
        try w(a, "poznamky.txt", "nic")
        try w(a, "en.json", "{}")
        got["test-conventions"] = listing(a)

        let b: String = try fresh(work, "listB")
        let names: [String] = [
            "lang_.json", "lang_ .json", "lang_\t.json", "lang_\u{2003}.json", "lang_\u{a0}.json",
            "lang_\u{3000}.json", "lang_b.JSON", "Lang_c.json", "lang_d.json.bak", "lang_pt_BR.json",
            "lang_lang_.json", "lang_.json.json", ".lang_h.json", "lang_x0.json", "lang_Zz.json",
            "lang_\u{df}.json", "lang_i.json", "lang_\u{1F600}.json", "lang_\u{ff41}.json", "lang_.json ",
        ]
        for name in names {
            try w(b, name, "{}")
        }
        got["names"] = listing(b)

        try labelScenarios(work, &got)

        for (id, json) in [("name-int", "{\"_name\":5}"), ("name-array", "{\"_name\":[\"x\"]}"),
            ("name-object", "{\"_name\":{}}"), ("name-bool", "{\"_name\":true}")]
        {
            let d: String = try fresh(work, "list-" + id)
            try w(d, "lang_a.json", json)
            if id == "name-int" {
                try w(d, "lang_b.json", "{\"_name\":\"B\"}")
            }
            got[id] = listing(d)
        }

        // Unicode names from exact bytes (APFS keeps normalisation, `Å` U+212B collapses with `a` + U+030A).
        let e: String = try fresh(work, "listE")
        try w(e, "lang_\u{f6}.json", "{}")
        try w(e, "lang_u\u{308}.json", "{}")
        try w(e, "lang_a\u{30a}.json", "{\"_name\":\"\u{c5}\"}")
        try w(e, "lang_\u{212b}.json", "{}")
        got["unicode-names"] = listing(e)

        got["missing-dir"] = listing(work + "/chybi")
        try w(work, "soubor.txt", "x")
        got["dir-is-file"] = listing(work + "/soubor.txt")
        got["null-dir"] = listing(nil)
        let g: String = try fresh(work, "listG")
        try w(g, "lang_a.json", "{}")
        chmod(g, 0o300)
        got["unreadable-dir"] = listing(g)
        chmod(g, 0o700)
        symlink(a, work + "/listLink")
        got["symlink-dir"] = listing(work + "/listLink")
        got["empty-dir"] = listing(try fresh(work, "listH"))
    }

    private static func labelScenarios(_ work: String, _ got: inout [String: String]) throws {
        let c: String = try fresh(work, "listC")
        let files: [(String, String)] = [
            ("lang_a.json", "{\"_name\":\"   \"}"), ("lang_b.json", "{\"_name\":\"\"}"),
            ("lang_c.json", "{\"_name\":\"\u{a0}\"}"), ("lang_d.json", "{\"_name\":\"\u{2003}\"}"),
            ("lang_e.json", "{\"_name\":null}"), ("lang_f.json", "{\"_name\":\" Fx \"}"),
            ("lang_g.json", "{tohle není JSON"), ("lang_h.json", "{\"_name\":\"A\",\"_name\":\"B\"}"),
            ("lang_i.json", "{\"_name\":\"Ok\",\"x\":null}"), ("lang_j.json", "{\"_Name\":\"Wrong\"}"),
            ("lang_k.json", "{\"_name\":\"Ok\",\"x\":1}"), ("lang_o.json", ""), ("lang_p.json", "null"),
            ("lang_q.json", "{\"_name\":\"Hidden\"}"),
        ]
        for (name, json) in files {
            try w(c, name, json)
        }
        mkdir(c + "/lang_l.json", 0o755)
        symlink(c + "/lang_a.json", c + "/lang_m.json")
        symlink(c + "/chybi.json", c + "/lang_n.json")
        chmod(c + "/lang_q.json", 0)
        got["labels"] = listing(c)
        chmod(c + "/lang_q.json", 0o644)
    }

    // MARK: - ensureDir

    private static func state(_ dir: String) -> String {
        var info = stat()
        guard lstat(dir, &info) == 0 else { return "<missing>" }
        guard info.st_mode & S_IFMT == S_IFDIR else { return "<not-dir>" }
        let names: [String] = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [])
            .sorted { Array($0.utf8).lexicographicallyPrecedes(Array($1.utf8)) }
        let parts: [String] = names.map { name in
            let path: String = dir + "/" + name
            var entry = stat()
            lstat(path, &entry)
            if entry.st_mode & S_IFMT == S_IFLNK { return esc(name) + ":link" }
            if entry.st_mode & S_IFMT == S_IFDIR { return esc(name) + ":dir" }
            let data: [UInt8] = [UInt8](FileManager.default.contents(atPath: path) ?? Data())
            return esc(name) + ":" + String(sha(data).prefix(16))
        }
        return "[" + parts.joined(separator: ", ") + "]"
    }

    @Test func ensureDirMatchesJava() throws {
        var got: [String: String] = [:]
        var mode: mode_t = 0
        var expectedMode: mode_t = 0
        try LanguageCatalogTests.withTemporaryDirectory { work in
            func ensure(_ id: String, _ dir: String) {
                LanguageCatalog.ensureDir(dir)
                got[id] = Self.state(dir)
            }
            ensure("missing-nested", work + "/ens1/a/b")
            let e2: String = try Self.fresh(work, "ens2")
            try Self.w(e2, "lang_en.json", "{\"_name\":\"Mine\"}")
            ensure("keeps-existing", e2)
            let e3: String = try Self.fresh(work, "ens3")
            mkdir(e3 + "/lang_en.json", 0o755)
            ensure("en-is-dir", e3)
            let e4: String = try Self.fresh(work, "ens4")
            symlink(e4 + "/chybi.json", e4 + "/lang_en.json")
            ensure("dangling-link", e4)
            let e5: String = try Self.fresh(work, "ens5")
            try Self.w(e5, "cil.json", "{}")
            symlink(e5 + "/cil.json", e5 + "/lang_de.json")
            ensure("live-link", e5)
            try Self.w(work, "ens6.txt", "x")
            ensure("dir-is-file", work + "/ens6.txt")
            ensure("parent-is-file", work + "/ens6.txt/sub")
            let e7: String = try Self.fresh(work, "ens7")
            chmod(e7, 0o500)
            ensure("read-only-dir", e7)
            chmod(e7, 0o700)
            let e8: String = try Self.fresh(work, "ens8")
            try Self.w(e8, "lang_de.json", "{}")
            chmod(e8, 0o500)
            ensure("read-only-dir-de-exists", e8)
            chmod(e8, 0o700)
            let e9: String = try Self.fresh(work, "ens9")
            ensure("empty-dir", e9)
            // Permissions of a new file = `0666 & ~umask` like `Files.copy` (Java measured with umask 022 → rw-r--r--).
            var info = stat()
            stat(e9 + "/lang_en.json", &info)
            mode = info.st_mode & 0o777
            let reference: Int32 = open(e9 + "/umask-reference", O_WRONLY | O_CREAT | O_EXCL, 0o666)
            close(reference)
            stat(e9 + "/umask-reference", &info)
            expectedMode = info.st_mode & 0o777
        }
        LanguageCatalog.ensureDir(nil as String?)
        var mismatches: [String] = []
        for row in Self.rows("L.ensure") where row[0] != "null" {
            if got[row[0]] != Self.shipped(row[1]) {
                mismatches.append(row[0] + ": " + (got[row[0]] ?? "<missing>") + " != " + Self.shipped(row[1]))
            }
        }
        #expect(Self.rows("L.ensure").count == 11)
        #expect(mismatches.isEmpty, "\(mismatches)")
        #expect(Self.rows("L.ensure.mode").first?[1] == "rw-r--r--")
        #expect(mode == expectedMode)
    }

    // MARK: - tr(cs, args)

    /// Writes that Java formats but `TranslationFormat` does not (→ `tr` returns the formatted Czech original).
    static let unsupportedFormats: Set<String> = [
        "%x", "%,d", "%b", "%c", "%+d", "%e", "%10.3e", "%g", "%a", "%h", "%o", "%X", "%(d", "% d", "%#x",
        "%,.1f",
    ]

    private static func arg(_ cell: String) -> Translator.Arg {
        let value: String = ProbeRows.unescape(String(cell.dropFirst(2)))
        switch cell.first {
        case "i", "l": return .int(Int(value)!)
        case "d": return .double(Double(value)!)
        case "n": return .string(nil)
        default: return .string(value)
        }
    }

    @Test func formatMatchesJava() {
        var mismatches: [String] = []
        var unsupported: Set<String> = []
        let all: [[String]] = Self.rows("T.format")
        for row in all {
            let pattern: String = ProbeRows.unescape(row[1])
            let args: [Translator.Arg] = row[2].isEmpty ? [] : row[2].components(separatedBy: "|").map(Self.arg)
            let separator: String = row[0] == "cs-CZ" ? "," : "."
            let got: String? = Translator.format(pattern, args, decimalSeparator: separator)
            if row[3].hasPrefix("throws ") {
                if let got {
                    mismatches.append(row[0] + " " + row[1] + ": " + Self.esc(got) + " != " + row[3])
                }
                continue
            }
            guard let got else {
                unsupported.insert(row[1])
                continue
            }
            if Self.esc(got) != Self.swiftView(row[3]) {
                mismatches.append(row[0] + " " + row[1] + ": " + Self.esc(got) + " != " + row[3])
            }
        }
        #expect(all.count == 192)
        #expect(mismatches.isEmpty, "\(mismatches)")
        #expect(unsupported == Self.unsupportedFormats)
    }
}
