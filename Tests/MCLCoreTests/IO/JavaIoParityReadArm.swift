import Foundation
import Testing
@testable import MCLCore

/// Read arm of the `JavaIoParityTests` gate (`io-import-java.json.gz`) — described
/// in the header of `JavaIoParityTests`. The order of rows and items is that of `IoRefGen` (`edgeArm`,
/// `exportsReadArm`, `manualArm`, `fuzzArm`, `sampleArm`).
extension JavaIoParityTests {

    /// `ImportedExchange.toFlat` for QSO × definition: one session per definition (like `IoRefGen`)
    /// and a cache of active fields by callsign (the result depends only on the definition, DXCC and callsign).
    /// One instance per job — not shared between threads.
    final class FlatResolver {
        let definitions: [ContestDefinition]
        let sessions: [ContestSession]
        private var cache: [Int: [String: Result<[ContestDefinition.ExchangeField], ExpressionError>]] = [:]

        init(_ definitions: [ContestDefinition], _ env: JavaEngineParityTests.Environment) {
            self.definitions = definitions
            sessions = definitions.map {
                ContestSession(definition: $0, dxcc: env.dxcc, registry: env.registry, myCall: "OK1XOE", myGrid: "JO70FC")
            }
        }

        func active(_ index: Int, _ call: String) -> Result<[ContestDefinition.ExchangeField], ExpressionError> {
            if let hit = cache[index]?[call] { return hit }
            let result = Result { () throws(ExpressionError) in try sessions[index].activeReceivedFields(call: call) }
            cache[index, default: [:]][call] = result
            return result
        }

        func flat(_ index: Int, _ q: Qso) -> String {
            switch active(index, q.call) {
            case .success(let fields): return Fx.tx(ImportedExchange.toFlat(definitions[index], fields, q))
            case .failure(let error): return Fx.exc(error)
            }
        }
    }

    /// QSO tuples in the columns of `IoRefGen.readOutputs` (text `""` = Java `null` after normalisation).
    static func tuple(_ q: Qso) -> [String] {
        let head: [String] = [Fx.tx(q.call), String(q.freqHz), q.band?.adif ?? "~", q.mode?.rawValue ?? "~",
                              Fx.millis(q.timestampUtc), Fx.tx(q.rstSent), Fx.tx(q.rstRcvd)]
        let serials: [String] = [q.serialSent.map { String($0) } ?? "~", q.serialRcvd.map { String($0) } ?? "~"]
        let tail: [String] = [Fx.tx(q.exchangeSent), Fx.tx(q.exchangeRcvd), Fx.tx(q.operator), Fx.tx(q.comment),
                              q.xqso ? "true" : "false"]
        return head + serials + tail
    }

    static func defList(_ spec: String) -> [Int] {
        spec.split(separator: ",").compactMap { Int($0) }
    }

    /// Java `IoRefGen.readOutputs`.
    static func readOutputs(_ p: String, _ content: String, adif: Bool, defs: String, _ lines: inout [String],
                            _ resolver: FlatResolver) {
        let indexes = defList(defs)
        do {
            let qsos: [Qso] = adif ? try AdifReader().read(content) : try CabrilloReader().read(content)
            lines.append(Fx.out(p + "/read", "QSO " + String(qsos.count)))
            for (i, q) in qsos.enumerated() {
                let qp = p + "/q/" + Fx.pad(i, 3)
                lines.append(Fx.line(qp, "out", tuple(q)))
                lines.append(Fx.line(qp + "/flat", "out", indexes.map { resolver.flat($0, q) }))
            }
        } catch {
            lines.append(Fx.out(p + "/read", Fx.exc(error)))
        }
        guard adif else { return }
        do {
            let records = try AdifReader().readRecords(content)
            lines.append(Fx.out(p + "/rec", "REC " + String(records.count)))
            for (i, record) in records.enumerated() {
                let keys = record.keys.sorted { $0.utf16.lexicographicallyPrecedes($1.utf16) }
                let pairs = keys.map { Fx.tx($0) + "=" + Fx.tx(record[$0]) }
                lines.append(Fx.out(p + "/r/" + Fx.pad(i, 3), pairs.joined(separator: ";")))
            }
        } catch {
            lines.append(Fx.out(p + "/rec", Fx.exc(error)))
        }
    }

    static func allDefs(_ count: Int) -> String {
        (0..<count).map(String.init).joined(separator: ",")
    }

    static func decodingLabel(_ text: String?) -> String {
        guard let text else { return "UNREADABLE java.nio.charset.MalformedInputException" }
        return text.unicodeScalars.first == "\u{FEFF}" ? "UTF8+BOM" : "UTF8"
    }

    static func sortedFiles(_ dir: URL, directories: Bool) throws -> [String] {
        let urls = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey])
        return try urls.filter { try $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == directories }
            .map(\.lastPathComponent)
            .sorted { $0.utf16.lexicographicallyPrecedes($1.utf16) }
    }

    // MARK: - items

    static func edgeArm(_ resolver: FlatResolver) throws -> [String] {
        let dir = try IoEdgeFixture.inputURL("")
        let defs = allDefs(resolver.definitions.count)
        var lines: [String] = []
        for name in try sortedFiles(dir, directories: false) {
            let adif = name.hasSuffix(".adi")
            let data = try Data(contentsOf: dir.appendingPathComponent(name))
            let p = "/f/" + name
            let fields = [JavaEngineParityTests.esc(name), adif ? "adif" : "cabrillo",
                          JavaYamlParityTests.sha256Hex(data), defs]
            lines.append(Fx.line(p, "in", fields))
            let text = Utf8Text.decodeKeepingBom(data)
            lines.append(Fx.out(p + "/dec", decodingLabel(text)))
            guard let text else { continue }
            readOutputs(p, text, adif: adif, defs: defs, &lines, resolver)
        }
        return lines
    }

    /// Java export texts from the reference of the write arm (`/adif/plain`, `/cab/0/text`) back.
    static func exportsReadArm(_ exportReference: [Entry], _ resolver: FlatResolver) -> [String] {
        let defs = allDefs(resolver.definitions.count)
        var lines: [String] = []
        for entry in exportReference where entry.relative != "toascii" {
            let texts: [(String, String?)] = [("adif", Fx.joinedText(entry, prefix: "/adif/plain/")),
                                              ("cabrillo", Fx.joinedText(entry, prefix: "/cab/0/text/"))]
            for (kind, text) in texts {
                guard let text else { continue }
                let p = "/x/" + entry.relative + "/" + kind
                let fields = [JavaEngineParityTests.esc(entry.relative), kind,
                              JavaYamlParityTests.sha256Hex(Data(text.utf8)), defs]
                lines.append(Fx.line(p, "in", fields))
                readOutputs(p, text, adif: kind == "adif", defs: defs, &lines, resolver)
            }
        }
        return lines
    }

    /// Hand-made cases and the fuzzer: the content is directly in the input row (`manual`: kind, definition, text;
    /// `fuzz-*`: kind, base, definition, text).
    static func inlineArm(_ inputs: [String], contentAt: Int, defsAt: Int, _ resolver: FlatResolver) throws -> [String] {
        var lines: [String] = []
        for raw in inputs {
            lines.append(raw)
            let f = Fx.inputs(raw)
            let content = try #require(Fx.untx(f[contentAt]))
            readOutputs(JavaYamlParityTests.pathOf(raw), content, adif: f[0] == "adif", defs: f[defsAt], &lines,
                        resolver)
        }
        return lines
    }

    /// The sample: `read` and the `toFlat` fingerprint of every QSO with a set definition (`null` count separately).
    /// The set definition is taken from the reference input (the path and bytes of the log are verified by the sum). The logs are
    /// read from `ScoreCheckSampleCorpus.directory` (not distributed with the sources).
    static func sampleArm(_ javaInputs: [String], _ resolver: FlatResolver) throws -> [String] {
        let root = ScoreCheckSampleCorpus.directory
        var defOf: [String: String] = [:]
        for raw in javaInputs { defOf[JavaYamlParityTests.pathOf(raw)] = Fx.inputs(raw)[2] }
        var lines: [String] = []
        // hidden files (Finder's `.DS_Store`) may appear in a local corpus directory
        for set in try sortedFiles(root, directories: true) where !set.hasPrefix(".") {
            let dir = root.appendingPathComponent(set)
            for log in try sortedFiles(dir, directories: false) where !log.hasPrefix(".") {
                let rel = set + "/" + log
                let p = "/s/" + rel
                let data = try Data(contentsOf: dir.appendingPathComponent(log))
                let def = defOf[p] ?? "?"
                lines.append(Fx.line(p, "in", [JavaEngineParityTests.esc(rel), JavaYamlParityTests.sha256Hex(data), def]))
                guard let text = Utf8Text.decodeKeepingBom(data) else {
                    lines.append(Fx.out(p + "/read", decodingLabel(nil)))
                    continue
                }
                let qsos: [Qso]
                do {
                    qsos = try CabrilloReader().read(text)
                } catch {
                    lines.append(Fx.out(p + "/read", Fx.exc(error)))
                    continue
                }
                guard let index = Int(def) else { continue }
                var all = ""
                var nulls = 0
                for q in qsos {
                    let flat = resolver.flat(index, q)
                    if flat == "~" { nulls += 1 }
                    all += flat + "\n"
                }
                lines.append(Fx.out(p + "/read", "QSO " + String(qsos.count)))
                lines.append(Fx.out(p + "/flat", JavaYamlParityTests.sha256Hex(Data(all.utf8)), "null=" + String(nulls)))
            }
        }
        return lines
    }

    /// Read-arm items for which the committed data suffice (everything except `sample`).
    static let committedImportEntries = ["edge", "exports", "manual", "fuzz-adif", "fuzz-cabrillo"]

    /// The read arm (the given items); items run in parallel (each has its own `FlatResolver`).
    static func runImportArm(_ reference: [Entry], _ exportReference: [Entry], names: [String]) async throws -> [Entry] {
        let env = try JavaEngineParityTests.environment()
        let files = try Fx.definitionFiles()
        var digest = ""
        var definitions: [ContestDefinition] = []
        for file in files {
            let data = try Data(contentsOf: file.url)
            digest += file.name + "\t" + JavaYamlParityTests.sha256Hex(data) + "\n"
            definitions.append(try ContestDefinitionLoader.load(data))
        }
        let defsDigest = JavaYamlParityTests.sha256Hex(Data(digest.utf8))
        let byName = Dictionary(reference.map { ($0.relative, $0) }, uniquingKeysWith: { first, _ in first })
        let defs = definitions
        return try await withThrowingTaskGroup(of: (Int, Entry).self) { group in
            for (index, name) in names.enumerated() {
                let javaInputs = byName[name]?.lines.filter(JavaEngineParityTests.isInput) ?? []
                group.addTask {
                    let resolver = FlatResolver(defs, env)
                    let lines: [String]
                    switch name {
                    case "edge": lines = try edgeArm(resolver)
                    case "exports": lines = exportsReadArm(exportReference, resolver)
                    case "manual": lines = try inlineArm(javaInputs, contentAt: 2, defsAt: 1, resolver)
                    case "sample": lines = try sampleArm(javaInputs, resolver)
                    default: lines = try inlineArm(javaInputs, contentAt: 3, defsAt: 2, resolver)
                    }
                    let sha = Fx.checksum(definition: defsDigest, registry: env.registryDigest,
                                          lines: lines.filter(JavaEngineParityTests.isInput))
                    return (index, Entry(relative: name, sha256: sha, lines: lines))
                }
            }
            var out: [(Int, Entry)] = []
            for try await result in group { out.append(result) }
            return out.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    /// Everything except the `sample` entry (which needs the corpus logs, see
    /// `sampleReadArmMatchesJava`); the reference counts below cover all entries.
    @Test func readArmMatchesJava() async throws {
        try await JavaV111Gate.run {
            let reference = try Fx.reference("io-import-java")
            let exportReference = try Fx.reference("io-export-java")
            let mine = try await Self.runImportArm(reference, exportReference, names: Self.committedImportEntries)

            var stats = Fx.Normalization()
            let java = reference.map { Fx.normalized($0, &stats) }.filter { Self.committedImportEntries.contains($0.relative) }
            let all = mine.flatMap(\.lines)
            let excs = all.filter { $0.contains("\",\"out\",\"EXC ") }.count
            let info = "\(mine.count) items, \(all.count) rows, \(excs) exceptions; null≡\"\" (Java returned \"\", "
                + "not null): \(stats.javaEmptyNotNull)×; lone surrogate → U+FFFD: \(stats.surrogates)×"
            let diff = Fx.differences(reference: java, mine: mine, arm: "io-import",
                                                         regenerate: Self.regenerate)
            #expect(diff == nil, Comment(rawValue: (diff ?? "") + "\n" + info))
            #expect(reference.map(\.relative) == Self.committedImportEntries + ["sample"])
            #expect(mine.map(\.relative) == Self.committedImportEntries)
            // Java returned `""`, not `null`: the edge `comment`, `rstRcvd`,
            // `rstSent` and `comment` and five fuzzer ADIF values (`operator` ×2, `rstSent`,
            // `rstRcvd` ×2 — an empty value after mutation).
            #expect(stats.javaEmptyNotNull == 9, Comment(rawValue: info))
            // `comment` in the tuple and in the raw map of `readRecords` (a deliberate divergence from Java v1.1.1).
            #expect(stats.surrogates == 2, Comment(rawValue: info))

            // Non-emptiness of the reference: a broken generator (empty fuzzer, missing sample…) would give a match
            // over inputs taken from the reference. Counts from the Java side.
            let byName = Dictionary(reference.map { ($0.relative, $0) }, uniquingKeysWith: { first, _ in first })
            func inputs(_ name: String) -> Int {
                byName[name]?.lines.filter(JavaEngineParityTests.isInput).count ?? 0
            }
            #expect(inputs("edge") == 73, "edge files io-edge/")
            #expect(inputs("fuzz-adif") == 1000, "ADIF fuzzer")
            #expect(inputs("fuzz-cabrillo") == 1000, "Cabrillo fuzzer")
            #expect(inputs("sample") == 424, "sample logs")
            let javaLines = reference.flatMap(\.lines)
            let tuples = javaLines.filter { Fx.isTuple(JavaYamlParityTests.pathOf($0)) }.count
            let flats = javaLines.filter { JavaYamlParityTests.pathOf($0).hasSuffix("/flat") }.count
            #expect(tuples == 8093, "QSO tuples in the reference")
            #expect(flats == 8513, "toFlat rows in the reference (tuples + sample fingerprints)")
        }
    }

    /// The `sample` entry: `read` and `toFlat` over the 424 sample logs, which are not in the
    /// repository (`ScoreCheckSampleCorpus`). The entry checksum covers the SHA-256 of every log,
    /// so a different corpus is reported as "REGENERATE REFERENCE", not as a pass.
    @Test(.enabled(if: ScoreCheckSampleCorpus.available, ScoreCheckSampleCorpus.skipReason))
    func sampleReadArmMatchesJava() async throws {
        try await JavaV111Gate.run {
            let reference = try Fx.reference("io-import-java")
            let exportReference = try Fx.reference("io-export-java")
            let mine = try await Self.runImportArm(reference, exportReference, names: ["sample"])

            var stats = Fx.Normalization()
            let java = reference.filter { $0.relative == "sample" }.map { Fx.normalized($0, &stats) }
            let all = mine.flatMap(\.lines)
            let info = "\(all.count) rows; null≡\"\" (Java returned \"\", not null): \(stats.javaEmptyNotNull)×"
            let diff = Fx.differences(reference: java, mine: mine, arm: "io-import",
                                                         regenerate: Self.regenerate)
            #expect(diff == nil, Comment(rawValue: (diff ?? "") + "\n" + info))
            #expect(mine.map(\.relative) == ["sample"])
            let inputs = mine.flatMap(\.lines).filter(JavaEngineParityTests.isInput).count
            #expect(inputs == 424, "sample logs")
        }
    }
}
