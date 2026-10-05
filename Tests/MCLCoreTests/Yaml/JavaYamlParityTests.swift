import CryptoKit
import Foundation
import Testing
@testable import MCLCore

/// A gate against Java for the YAML reader: the Swift `YamlParser` must produce over the whole
/// `contest-data/` corpus the **same tree** that Java Jackson produces
/// over the same files (`YamlObjectMapper.create()`, i.e. the mapper of the production
/// Java application v1.1.1).
///
/// The canonical dump is compared **byte for byte**. The reference is produced by
/// a maintainer-only probe and is **committed** as the fixture
/// `contest-data-jackson.json` — so the tests need neither a JDK nor Jackson (and above all
/// cannot silently degrade to "Swift against Swift" when Java is not available).
/// How to regenerate the reference is in a maintainer-only probe.
///
/// ## Canonical format
///
/// It must be identical to what `YamlRefGen` writes — the format is described in the doc
/// comment of that file. One node per line, a depth-first walk
/// **in document order** (not sorted by key, so that the gate also covers the order of
/// keys, which `YamlMapping` keeps the same as Jackson's `LinkedHashMap`).
///
/// A scalar carries both the **computed value** and the **literal spelling from the file**
/// (`YamlValue.raw`). Jackson's tree does not keep the original spelling, but
/// `JsonParser.getText()` does and Java puts it literally into `String` fields — in
/// `contests/ww-digi.yaml` the difference is visible: the value is `3.333333333E-4`
/// (Java `Double.toString`), the spelling in the file `0.0003333333333`. The gate thus
/// guards both, not just the value.
///
/// Decimal numbers are printed via `JavaDouble.toString` from `Sources/MCLCore/Yaml/`
/// (verified against Java) — a second implementation of the same
/// rule is deliberately not written. Swift `String(Double)` would give different text for the same
/// value (`0.0003333333333` vs `3.333333333E-4`) and the gate would
/// turn red on a difference that is not a reader defect.
@Suite struct JavaYamlParityTests {

    // MARK: - Canonical dump

    /// The nodes of one document as lines of the canonical dump.
    static func canonicalLines(_ value: YamlValue) -> [String] {
        var lines: [String] = []
        emit(value, path: "", into: &lines)
        return lines
    }

    private static func emit(_ value: YamlValue, path: String, into lines: inout [String]) {
        switch value {
        case .mapping(let mapping):
            lines.append(line(path, "map"))
            for pair in mapping.pairs {
                emit(pair.value, path: path + "/" + pointer(pair.key), into: &lines)
            }
        case .sequence(let items):
            lines.append(line(path, "seq"))
            for (index, item) in items.enumerated() {
                emit(item, path: path + "/[\(index)]", into: &lines)
            }
        case .null:
            // Without `raw`: `YamlValue.null` does not keep the original spelling (`null`/`~`/empty),
            // so there would be nothing to compare. `YamlRefGen` does not write it for `null` either.
            lines.append(line(path, "null"))
        case .bool(let flag, let raw):
            lines.append(line(path, "bool", flag ? "true" : "false", raw))
        case .int(let number, let raw):
            lines.append(line(path, "int", String(number), raw))
        case .double(let number, let raw):
            lines.append(line(path, "double", JavaDouble.toString(number), raw))
        case .string(let text):
            // For text the literal spelling is identical to the content (quotes and escapes are
            // already unfolded), so one field is enough — same as in `YamlRefGen`.
            lines.append(line(path, "str", text))
        }
    }

    private static func line(_ path: String, _ fields: String...) -> String {
        var out = "[" + jsonString(path)
        for field in fields { out += "," + jsonString(field) }
        return out + "]"
    }

    /// Escaping a key into a JSON Pointer (RFC 6901).
    private static func pointer(_ key: String) -> String {
        key.replacingOccurrences(of: "~", with: "~0").replacingOccurrences(of: "/", with: "~1")
    }

    /// A JSON string by the **same hand-implemented rule** as
    /// `YamlRefGen.jsonString`: only `"`, the backslash and control
    /// characters below 0x20 are escaped. Nothing else — non-ASCII goes to the output as UTF-8.
    /// The Foundation writer is deliberately not used: the gate compares bytes, so
    /// both sides must escape identically, not "also correctly".
    static func jsonString(_ value: String) -> String {
        var out = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\u{08}": out += "\\b"
            case "\t": out += "\\t"
            case "\n": out += "\\n"
            case "\u{0C}": out += "\\f"
            case "\r": out += "\\r"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }

    /// Assembles the whole reference document from per-file data — byte for byte
    /// as `YamlRefGen.main` assembles it.
    static func canonicalDocument(_ files: [ReferenceFile]) -> String {
        var out = "{\n"
        for (fileIndex, file) in files.enumerated() {
            out += jsonString(file.relative) + ": {\n"
            out += "\"sha256\": " + jsonString(file.sha256) + ",\n"
            out += "\"nodes\": [\n"
            for (lineIndex, line) in file.lines.enumerated() {
                out += line + (lineIndex + 1 < file.lines.count ? "," : "") + "\n"
            }
            out += "]\n"
            out += "}" + (fileIndex + 1 < files.count ? "," : "") + "\n"
        }
        return out + "}\n"
    }

    // MARK: - Reading the reference

    /// One file in the reference: the checksum of the input bytes and the tree nodes.
    struct ReferenceFile {
        let relative: String
        let sha256: String
        let lines: [String]
    }

    /// The reference document taken apart by files. No JSON parser is used:
    /// the format is line-based and a string cannot contain a literal line break
    /// (it is escaped as `\n`), so splitting by lines is safe.
    static func parseReference(_ text: String) throws -> [ReferenceFile] {
        var files: [ReferenceFile] = []
        var relative: String?
        var sha: String?
        var lines: [String] = []
        var inNodes = false

        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if line.isEmpty || line == "{" { continue }
            if line == "]" || line == "]," { inNodes = false; continue }
            if line == "}" || line == "}," {
                // A bare `}` closes either a file object or the whole document — it is told
                // apart by whether a file is open. If it were
                // told apart by position, the last file would be lost (after its
                // `}` comes right after the document's `}`).
                guard let name = relative else { continue }
                files.append(ReferenceFile(relative: name,
                                           sha256: try #require(sha, Comment(rawValue: "\(name): missing sha256")),
                                           lines: lines))
                relative = nil; sha = nil; lines = []
                continue
            }
            if line.hasSuffix(": {") {
                relative = try unquote(String(line.dropLast(3)))
                continue
            }
            if line.hasPrefix("\"sha256\": ") {
                let value = String(line.dropFirst("\"sha256\": ".count))
                sha = try unquote(value.hasSuffix(",") ? String(value.dropLast()) : value)
                continue
            }
            if line == "\"nodes\": [" { inNodes = true; continue }
            guard inNodes else { continue }
            lines.append(line.hasSuffix(",") ? String(line.dropLast()) : line)
        }
        return files
    }

    /// SHA-256 of the file bytes, lowercase — by the same rule as
    /// `YamlRefGen.sha256`. `CryptoKit` is a system framework from the SDK, not an
    /// external dependency.
    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Unfolds a JSON string in quotes. It handles only the escapes that
    /// `YamlRefGen.jsonString` can write — file paths contain nothing else.
    private static func unquote(_ quoted: String) throws -> String {
        try #require(quoted.hasPrefix("\"") && quoted.hasSuffix("\"") && quoted.count >= 2,
                     "'\(quoted)' is not a JSON string")
        var out = ""
        var iterator = quoted.dropFirst().dropLast().makeIterator()
        while let character = iterator.next() {
            guard character == "\\" else { out.append(character); continue }
            guard let escaped = iterator.next() else { break }
            switch escaped {
            case "\"": out.append("\"")
            case "\\": out.append("\\")
            case "n": out.append("\n")
            case "t": out.append("\t")
            case "r": out.append("\r")
            case "b": out.append("\u{08}")
            case "f": out.append("\u{0C}")
            default: out.append(escaped)
            }
        }
        return out
    }

    /// The path of a node from a canonical line — only for reporting a difference.
    static func pathOf(_ line: String) -> String {
        guard line.hasPrefix("[\"") else { return line }
        let rest = line.dropFirst(2)
        guard let end = rest.range(of: "\",") else { return line }
        return String(rest[rest.startIndex..<end.lowerBound])
    }

    /// The path for the report: the root is shown as `<root>` so that it is not empty.
    static func display(_ path: String) -> String {
        path.isEmpty ? "<root>" : path
    }

    /// The value part of a canonical line (type and values without the path) — for the report.
    static func valueOf(_ line: String) -> String {
        guard line.hasPrefix("[\"") else { return line }
        let rest = line.dropFirst(2)
        guard let end = rest.range(of: "\",") else { return line }
        return String(rest[end.upperBound...].dropLast())
    }

    // MARK: - Corpus

    static func yamlFiles() throws -> [String] {
        let root = try ContestDataLayoutTests.contestDataRoot()
        return try ContestDataLayoutTests.relativeFiles(under: root).filter { $0.hasSuffix(".yaml") }
    }

    /// Reads the corpus from the bundle: for every `.yaml` the checksum of the bytes and the nodes
    /// from the **Swift** reader.
    static func readCorpus() throws -> [ReferenceFile] {
        let root = try ContestDataLayoutTests.contestDataRoot()
        var out: [ReferenceFile] = []
        for relative in try yamlFiles() {
            let data = try Data(contentsOf: root.appendingPathComponent(relative))
            let text = try #require(String(data: data, encoding: .utf8),
                                    Comment(rawValue: "\(relative): is not valid UTF-8"))
            out.append(ReferenceFile(relative: relative,
                                     sha256: sha256Hex(data),
                                     lines: canonicalLines(try YamlParser.parse(text))))
        }
        return out
    }

    /// Files whose bytes diverged from what the reference was made from.
    /// A non-empty result means a **stale reference**, not a reader defect.
    static func staleFiles(corpus: [ReferenceFile], reference: [ReferenceFile]) -> [String] {
        let referenceDigests = Dictionary(uniqueKeysWithValues: reference.map { ($0.relative, $0.sha256) })
        return corpus.compactMap { file in
            guard let expected = referenceDigests[file.relative] else { return nil }
            return expected == file.sha256 ? nil : file.relative
        }
    }

    static func referenceText() throws -> String {
        let url = try #require(
            Bundle.module.url(forResource: "contest-data-jackson", withExtension: "json"),
            "the bundle has no contest-data-jackson.json reference"
        )
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - Tests

    /// The reference covers exactly those `.yaml` files that are in the bundle. This is a
    /// cross-check to `ContestDataLayoutTests`: the reference was made over the source
    /// directory in the repository, so when a file does not get into the bundle (or
    /// conversely is added without regenerating the reference), the key sets diverge.
    /// The count is thus taken from data, not from a number copied from the assignment.
    @Test func referenceCoversSameFilesAsBundle() throws {
        let bundleFiles = try Self.yamlFiles()
        let referenceFiles = try Self.parseReference(Self.referenceText()).map(\.relative)

        #expect(!bundleFiles.isEmpty, "there are no .yaml files in the bundle")

        let extraInBundle: [String] = Set(bundleFiles).subtracting(referenceFiles).sorted()
        let extraInReference: [String] = Set(referenceFiles).subtracting(bundleFiles).sorted()
        let message: String = "the corpus and the reference diverged — extra in the bundle: "
            + extraInBundle.joined(separator: ", ")
            + " | extra in the reference: "
            + extraInReference.joined(separator: ", ")
            + " — the reference is generated from Java v1.1.1 by a maintainer-only generator (not in this repository)."
        #expect(bundleFiles == referenceFiles, Comment(rawValue: message))
    }

    /// Every corpus file is read without an error. If the reader crashed on some,
    /// the byte comparison below would report only a nonsensically large difference.
    @Test func wholeCorpusIsReadWithoutError() throws {
        let root = try ContestDataLayoutTests.contestDataRoot()
        for relative in try Self.yamlFiles() {
            let text = try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
            #expect(throws: Never.self, "\(relative): the reader crashed") {
                _ = try YamlParser.parse(text)
            }
        }
    }

    /// The checksums in the reference must match the corpus bytes in the bundle.
    ///
    /// This tells a **stale reference** from a **reader defect**: when somebody changes
    /// a file in `contest-data/` and forgets to regenerate the reference, this
    /// test turns red with clear advice "regenerate", instead of the gate pointing at a reader that
    /// is fine.
    @Test func checksumsMatchCorpusBytes() throws {
        let corpus = try Self.readCorpus()
        let reference = try Self.parseReference(Self.referenceText())
        let stale = Self.staleFiles(corpus: corpus, reference: reference)

        #expect(
            stale.isEmpty,
            Comment(rawValue: "REGENERATE REFERENCE — the bytes of these files diverged from the reference: "
                              + stale.joined(separator: ", ")
                              + " — the reference is generated from Java v1.1.1 by a maintainer-only generator (not in this repository).")
        )
    }

    /// **The gate proper.** The canonical dump of the Swift reader must equal
    /// the reference from Java Jackson byte for byte.
    @Test func canonicalDumpMatchesJacksonByteForByte() throws {
        let reference = try Self.referenceText()
        let referenceFiles = try Self.parseReference(reference)
        let mine = try Self.readCorpus()

        let document = Self.canonicalDocument(mine)
        guard Array(document.utf8) != Array(reference.utf8) else { return }

        // First it is decided **whose defect it is**. When the input bytes diverged,
        // the reference is stale and node differences would point at a reader that
        // is fine — so they are not printed at all.
        let stale = Self.staleFiles(corpus: mine, reference: referenceFiles)
        if !stale.isEmpty {
            Issue.record(Comment(rawValue:
                "REGENERATE REFERENCE — the reader did not diverge, the input bytes did. "
                + "Checksum mismatch at: " + stale.joined(separator: ", ")
                + " — the reference is generated from Java v1.1.1 by a maintainer-only generator (not in this repository)."))
            return
        }

        // The sums match and yet the tree differs — that is a reader defect. The report
        // is paired **by key path**, not by line index: on a structural
        // change (a sequence becomes a scalar) the indexes shift and pairing by
        // them would print nonsensical triples like `/bands: java="int","1","1"
        // swift="seq"`, where two unrelated nodes face each other.
        var report: [String] = []
        let byName = Dictionary(uniqueKeysWithValues: referenceFiles.map { ($0.relative, $0.lines) })

        for file in mine where report.count < 20 {
            guard let javaLines = byName[file.relative] else {
                report.append("\(file.relative): missing in the reference")
                continue
            }
            let javaByPath = Dictionary(javaLines.map { (Self.pathOf($0), Self.valueOf($0)) },
                                        uniquingKeysWith: { first, _ in first })
            let swiftByPath = Dictionary(file.lines.map { (Self.pathOf($0), Self.valueOf($0)) },
                                         uniquingKeysWith: { first, _ in first })

            // First the nodes in the order in which the Swift reader sees them, then
            // what Java has and Swift did not produce at all.
            var seen = Set<String>()
            for path in file.lines.map(Self.pathOf) where report.count < 20 {
                guard seen.insert(path).inserted else { continue }
                let swiftText = swiftByPath[path] ?? "<node missing>"
                let javaText = javaByPath[path] ?? "<node missing>"
                guard javaText != swiftText else { continue }
                report.append("\(file.relative): \(Self.display(path)): java=\(javaText) swift=\(swiftText)")
            }
            for path in javaLines.map(Self.pathOf) where report.count < 20 {
                guard !seen.contains(path) else { continue }
                seen.insert(path)
                report.append("\(file.relative): \(Self.display(path)): "
                              + "java=\(javaByPath[path] ?? "<node missing>") swift=<node missing>")
            }

            // The path sets may be identical and differ only in the **order** of keys; the
            // path pairing alone would not show that, so it is reported separately.
            if report.isEmpty {
                let javaPaths = javaLines.map(Self.pathOf)
                let swiftPaths = file.lines.map(Self.pathOf)
                if javaPaths != swiftPaths, Set(javaPaths) == Set(swiftPaths),
                   let index = (0..<min(javaPaths.count, swiftPaths.count))
                       .first(where: { javaPaths[$0] != swiftPaths[$0] }) {
                    report.append("\(file.relative): key order: "
                                  + "java=\(Self.display(javaPaths[index])) "
                                  + "swift=\(Self.display(swiftPaths[index]))")
                }
            }
        }
        if report.isEmpty {
            // Nodes match, but bytes do not — the difference is in the document
            // composition (separators, file order), not in the nodes.
            report.append("nodes match, but the document differs byte-wise "
                          + "(swift \(document.utf8.count) B vs java \(reference.utf8.count) B)")
        }
        Issue.record(Comment(rawValue: "READER MISMATCH — the corpus checksums match, "
                             + "but the tree diverged from Jackson:\n" + report.joined(separator: "\n")))
    }

    /// `parse(write(parse(f))) == parse(f)` for **every** corpus file.
    ///
    /// The suite once **assumed this property but
    /// did not test it** — it was verified only by hand and on synthetic values
    /// (`YamlWriterTests.roundTripThroughWriterCoversEveryValueKind`). The definition editor
    /// stands on it (read → edit → write), so it is better
    /// if a test guards it than a note.
    @Test func corpusPassesRoundTripThroughWriter() throws {
        let root = try ContestDataLayoutTests.contestDataRoot()
        var checked = 0
        for relative in try Self.yamlFiles() {
            let text = try String(contentsOf: root.appendingPathComponent(relative),
                                  encoding: .utf8)
            let parsed = try YamlParser.parse(text)
            let again = try YamlParser.parse(YamlWriter.write(parsed))
            #expect(again == parsed,
                    Comment(rawValue: "\(relative): the round trip through the writer diverged"))
            checked += 1
        }
        #expect(checked > 20, Comment(rawValue: "the round trip covered only \(checked) files"))
    }

    /// Verifies that the gate cannot pass by accident: if the corpus or the reference
    /// were emptied, `canonicalDumpMatchesJacksonByteForByte` would pass trivially.
    /// This test insists that a non-trivial number of nodes is compared and that
    /// the reference contains the specific value for which `JavaDouble` is needed.
    @Test func gateComparesNontrivialCorpus() throws {
        let reference = try Self.referenceText()
        let files = try Self.parseReference(reference)
        let nodes = files.reduce(0) { $0 + $1.lines.count }

        #expect(files.count > 20, Comment(rawValue: "the reference carries only \(files.count) files"))
        #expect(nodes > 2000, Comment(rawValue: "the reference carries only \(nodes) nodes"))
        // A checkpoint of Java `Double.toString`: the value is exponential,
        // the spelling in the file is not. If the canonical dump switched to `String(Double)`,
        // this line would not arise in the Swift dump and the gate would turn red.
        #expect(
            reference.contains("\"double\",\"3.333333333E-4\",\"0.0003333333333\""),
            "the reference has no checkpoint value from contests/ww-digi.yaml"
        )
    }
}
