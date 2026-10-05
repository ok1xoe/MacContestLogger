import Foundation
import Testing
@testable import MCLCore

/// Parity suite against Java over the whole `io/`. The references are produced by
/// the **Java** application v1.1.1 (maintainer-only probe, procedure kept with the probe) and are
/// committed gzipped — the tests do not need a JDK.
///
/// - **Write arm** (`io-export-java.json.gz`): 22 definitions from `contest-data/contests/` + 2
///   synthetic ones (`io-gate-synthetic/`: Cabrillo without `sentOrder`/`receivedOrder`, a definition without
///   `cabrillo:`) × a log of 80 QSOs with edge values (frequency `…050`/`…500`/0/negative/outside a
///   segment/VHF, modes outside the contest and `nil`, equal and missing times, `00:00:59.999`, callsigns
///   `ok1žá`/combining character/emoji/`""`, exchange complete/missing/extra/`ß`/NBSP/tab, flags…).
///   Score via `ContestReplay` into a fresh `ContestSession` (= the application's `freshScore`),
///   `receivedFields` = `activeReceivedFields` of the same session. Outputs as **whole texts, tolerance 0**:
///   Cabrillo (3 setup variants × 4 stations across definitions; text, `qsoCount`, warnings or
///   `EXC`), ADIF (without a station whole, with 4 stations the header + SHA-256 of the whole, `record` of all QSOs),
///   CSV, text, summary (score from the session and `nil`; the whole log and only QSOs with time), EDI by band
///   (`iaru-r1-vhf/uhf`, `marconi-memorial`, `cq-ww-cw`). Plus `toAscii` over all code points.
/// - **Read arm** (`io-import-java.json.gz`): edge files `io-edge/`, own exports
///   of the write arm (Java texts from the reference), hand-made cases (IE1–IE5 research, Cabrillo dates,
///   numbers), a seeded fuzzer of 2,000 ADIF/Cabrillo mutations and `ImportedExchange.toFlat` over
///   the sample. Per file the decoding, `read` (a QSO tuple or `EXC class: message` — for
///   `NumberFormatException` and `StringIndexOutOfBounds` the text is compared too), `readRecords`
///   (sorted keys), `toFlat` QSO × definition.
///
/// The item checksum covers the bytes of the definition (for the read arm a fingerprint of all of them), the registry and the rows
/// `in` — Swift assembles them **from its own inputs** (files on disk, Java export texts from the reference).
/// If it does not match, it is "REGENERATE REFERENCE", otherwise a difference = "MISMATCH".
///
/// `null` × `""`: Java tuples carry `null` in text as `~`, before comparison it is
/// converted to `""` and the **number** of cases where Java returned `""` (not `null`) is pinned (the counts are
/// in the assertion message; the gate does not write to stdout).
@Suite struct JavaIoParityTests {

    typealias Entry = JavaYamlParityTests.ReferenceFile
    typealias Fx = JavaIoParityFixture

    static let regenerate = " — the reference is generated from Java v1.1.1 by a maintainer-only generator (not in this repository)."

    /// "Now" for a QSO without time when replaying the score (`IoRefGen.REPLAY_NOW_MS`; without a TOUR
    /// session time does not matter, but Swift must not take the system clock).
    static let replayNow = Date(timeIntervalSince1970: 4_102_444_800)

    static let ediDefinitions: Set<String> = [
        "contests/iaru-r1-vhf.yaml", "contests/iaru-r1-uhf.yaml", "contests/marconi-memorial.yaml",
        "contests/cq-ww-cw.yaml",
    ]

    // MARK: - Write arm

    /// Inputs of one item of the write arm by path (and in Java order).
    struct ExportInputs {
        var byPath: [String: String] = [:]
        var qsoPaths: [String] = []
        var qtcPaths: [Int: [String]] = [:]

        init(_ lines: [String]) {
            for line in lines {
                let path = JavaYamlParityTests.pathOf(line)
                byPath[path] = line
                if path.hasPrefix("/q/") { qsoPaths.append(path) }
                if path.hasPrefix("/setup/"), path.contains("/qtc/"), let k = Int(path.split(separator: "/")[1]) {
                    qtcPaths[k, default: []].append(path)
                }
            }
        }

        func fields(_ path: String) throws -> [String] {
            Fx.inputs(try #require(byPath[path], Comment(rawValue: "missing input \(path)")))
        }
    }

    struct Setup {
        var category: JavaLinkedMap<String>
        var sent: JavaLinkedMap<String>
        var operators: String
        var soapbox: String
        var claimed: String
        var createdBy: String?
        var qtcs: [QtcRecord]
    }

    /// Executes one item of the write arm in the order of `IoRefGen.exportArm`.
    static func exportArm(_ name: String, _ def: ContestDefinition, _ inputLines: [String],
                          _ env: JavaEngineParityTests.Environment) throws -> [String] {
        let input = ExportInputs(inputLines)
        var lines: [String] = []
        func emit(_ path: String) throws { lines.append(try #require(input.byPath[path])) }

        let session = try input.fields("/session")
        try emit("/session")
        var qsos: [Qso] = []
        for path in input.qsoPaths {
            try emit(path)
            qsos.append(try Fx.qso(try input.fields(path)))
        }
        var stations: [StationConfig] = []
        for s in 0..<4 {
            try emit("/station/\(s)")
            stations.append(Fx.station(try input.fields("/station/\(s)")))
        }
        var setups: [Setup] = []
        for k in 0..<3 {
            try emit("/setup/\(k)")
            let f = try input.fields("/setup/\(k)")
            var qtcs: [QtcRecord] = []
            for path in input.qtcPaths[k] ?? [] {
                try emit(path)
                qtcs.append(try Fx.qtc(try input.fields(path)))
            }
            setups.append(Setup(category: JavaEngineParityTests.map(f[0]) ?? JavaLinkedMap(),
                                sent: JavaEngineParityTests.map(f[1]) ?? JavaLinkedMap(),
                                operators: Fx.untx(f[2]) ?? "", soapbox: Fx.untx(f[3]) ?? "", claimed: f[4],
                                createdBy: Fx.untx(f[5]), qtcs: qtcs))
        }

        // Score like the application: replay into a fresh session.
        let fresh = ContestSession(definition: def, dxcc: env.dxcc, registry: env.registry,
                                   myCall: Fx.untx(session[0]), myGrid: Fx.untx(session[1]))
        fresh.setQtcCount(try #require(Int32(session[2])))
        let outcome = ContestReplay.replay(fresh, qsos, now: { replayNow })
        var score: ScoreState?
        do {
            let s = try fresh.score()
            score = s
            let text = "replayed=\(outcome.replayed) skipped=\(outcome.skipped) qso=\(s.qsoCount) pts=\(s.qsoPoints)"
                + " mult=\(s.multTotal) qtc=\(s.qtcPoints) total=\(s.total)"
            lines.append(Fx.out("/score", text))
        } catch {
            lines.append(Fx.out("/score", Fx.exc(error)))
        }
        let received: (String) throws -> [ContestDefinition.ExchangeField] = {
            try fresh.activeReceivedFields(call: $0)
        }

        // ADIF
        let adif = AdifWriter(contestId: def.cabrillo?.contestName)
        Fx.text(&lines, "/adif/plain", adif.toAdif(qsos))
        let records = qsos.map(adif.record).joined()
        lines.append(Fx.out("/adif/records", JavaYamlParityTests.sha256Hex(Data(records.utf8))))
        for (s, station) in stations.enumerated() {
            let full = adif.toAdif(qsos, station: station.toStation())
            let head = try #require(full.range(of: "<EOH>\n"))
            Fx.text(&lines, "/adif/st/\(s)/head", String(full[..<head.upperBound]))
            lines.append(Fx.out("/adif/st/\(s)/sha", JavaYamlParityTests.sha256Hex(Data(full.utf8))))
        }

        // Cabrillo
        for k in 0..<3 {
            let p = "/cab/\(k)"
            try emit(p)
            let f = try input.fields(p)
            let station = stations[try #require(Int(f[0]))]
            let setup = setups[try #require(Int(f[1]))]
            var cab = CabrilloExporter.Input(definition: def, station: station, qsos: qsos, receivedFields: received)
            cab.category = setup.category
            cab.sentExchange = setup.sent
            cab.operators = setup.operators
            cab.soapbox = setup.soapbox
            cab.qtcs = setup.qtcs
            switch setup.claimed {
            case "~": cab.claimedScore = nil
            case "score": cab.claimedScore = score?.total
            default:
                let claimed: Int64 = try #require(Int64(setup.claimed))
                cab.claimedScore = claimed
            }
            if let createdBy = setup.createdBy { cab.createdBy = createdBy }
            do {
                let result = try CabrilloExporter.export(cab)
                lines.append(Fx.out(p + "/count", String(result.qsoCount)))
                for (w, warning) in result.warnings.enumerated() {
                    lines.append(Fx.out(p + "/warn/" + Fx.pad(w, 3), Fx.tx(warning)))
                }
                Fx.text(&lines, p + "/text", result.text)
            } catch {
                lines.append(Fx.out(p + "/exc", Fx.exc(error)))
            }
        }

        // CSV, text, summary
        try emit("/title")
        let title = try input.fields("/title")
        let contestName = Fx.untx(title[0]) ?? ""
        let call = Fx.untx(title[1]) ?? ""
        Fx.text(&lines, "/csv", LogExports.csv(qsos))
        Fx.text(&lines, "/text", LogExports.text(contestName + " \u{2014} " + call, qsos))
        let timed = qsos.filter { $0.timestampUtc != nil }
        summary(&lines, "/sum/score/all", contestName, call, score, qsos)
        summary(&lines, "/sum/null/all", contestName, call, nil, qsos)
        summary(&lines, "/sum/score/timed", contestName, call, score, timed)
        summary(&lines, "/sum/null/timed", contestName, call, nil, timed)

        // EDI
        if ediDefinitions.contains(name) {
            try emit("/edi")
            let f = try input.fields("/edi")
            let station = stations[try #require(Int(f[0]))]
            let header = EdiExporter.Header(section: Fx.untx(f[2]), power: Fx.untx(f[3]), antenna: Fx.untx(f[4]),
                                            operators: Fx.untx(f[5]), remarks: Fx.untx(f[6]))
            var used: [Band] = []
            for q in qsos { if let band = q.band, !used.contains(band) { used.append(band) } }
            used.sort { $0.lowHz < $1.lowHz }
            for band in used {
                let p = "/edi/" + band.adif
                do {
                    Fx.text(&lines, p, try EdiExporter.export(def, station, header, qsos, band, Fx.untx(f[1]), received))
                } catch {
                    lines.append(Fx.out(p + "/exc", Fx.exc(error)))
                }
            }
        }
        return lines
    }

    static func summary(_ lines: inout [String], _ path: String, _ name: String, _ call: String,
                        _ score: ScoreState?, _ qsos: [Qso]) {
        do {
            Fx.text(&lines, path, try LogExports.summary(name, call, score, qsos))
        } catch {
            lines.append(Fx.out(path + "/exc", Fx.exc(error)))
        }
    }

    /// The whole write arm: definition items (in parallel) and the `toAscii` pass.
    static func runExportArm(_ reference: [Entry]) async throws -> (entries: [Entry], asciiNewer: Int) {
        let env = try JavaEngineParityTests.environment()
        let byName = Dictionary(reference.map { ($0.relative, $0) }, uniquingKeysWith: { first, _ in first })
        let files = try Fx.definitionFiles()
        let jobs: [(index: Int, name: String, data: Data, inputs: [String])] = try files.enumerated().map {
            ($0.offset, $0.element.name, try Data(contentsOf: $0.element.url),
             byName[$0.element.name]?.lines.filter(JavaEngineParityTests.isInput) ?? [])
        }
        let results = try await withThrowingTaskGroup(of: (Int, Entry).self) { group in
            for job in jobs {
                group.addTask {
                    let def = try ContestDefinitionLoader.load(job.data)
                    // A definition the reference does not know (new in `contest-data/`) has no inputs: an empty
                    // item, so `differences` reports "REGENERATE REFERENCE" (the set of items), not a missing input.
                    let lines = job.inputs.isEmpty ? [] : try exportArm(job.name, def, job.inputs, env)
                    let sha = Fx.checksum(definition: JavaYamlParityTests.sha256Hex(job.data),
                                          registry: env.registryDigest, lines: job.inputs)
                    return (job.index, Entry(relative: job.name, sha256: sha, lines: lines))
                }
            }
            var out: [(Int, Entry)] = []
            for try await result in group { out.append(result) }
            return out.sorted { $0.0 < $1.0 }.map(\.1)
        }
        let ascii = try await toAsciiArm(byName["toascii"]?.lines.filter(JavaEngineParityTests.isInput) ?? [])
        return (results + [ascii.entry], ascii.newer)
    }

    @Test func writeArmMatchesJava() async throws {
        try await JavaV111Gate.run {
            let reference = try Fx.reference("io-export-java")
            let (mine, newer) = try await Self.runExportArm(reference)
            let diff = Fx.differences(reference: reference, mine: mine, arm: "io-export",
                                                         regenerate: Self.regenerate)
            let lines = mine.reduce(0) { $0 + $1.lines.count }
            let unicode = Unicode.Scalar(0x1FAE9).flatMap { $0.properties.age }.map { "\($0.major).\($0.minor)" } ?? "< 15.0"
            let info = "\(mine.count) items, \(lines) rows; toAscii: \(newer) points after Unicode 15.0 compared as ? "
                + "(U+1FAE9 is in the system's Unicode: \(unicode))"
            #expect(diff == nil, Comment(rawValue: (diff ?? "") + "\n" + info))
            #expect(reference.count == 25, "22 definitions + 2 synthetic + toascii")
            // Non-emptiness of the reference (a broken generator would give a match over empty inputs).
            for entry in reference where entry.relative != "toascii" {
                let qsos = entry.lines.filter { JavaEngineParityTests.isInput($0) && JavaYamlParityTests.pathOf($0).hasPrefix("/q/") }
                #expect(qsos.count == 80, "\(entry.relative): the gate log has 80 QSOs")
            }
        }
    }

    // MARK: - toAscii over all code points

    /// A code point added after Unicode 15.0 (JDK 21) or unknown to the system: Java does not know it (`Cn`)
    /// and gives `?`; Swift (stdlib/the system's ICU) may know more. A recorded divergence, counted.
    static func newerThanJava(_ scalar: Unicode.Scalar) -> Bool {
        guard let age = scalar.properties.age else { return true }
        return age.major > 15 || (age.major == 15 && age.minor > 0)
    }

    /// Guard: a new one is an input scalar, or some scalar of its canonical decomposition (that does not change for
    /// characters ≤ 15.0, but on another system the gate must not assume it).
    static func newerThanJava(decomposing scalar: Unicode.Scalar) -> Bool {
        if newerThanJava(scalar) { return true }
        let nfd = String(Character(scalar)).decomposedStringWithCanonicalMapping
        return nfd.unicodeScalars.contains { newerThanJava($0) }
    }

    static func hex6(_ value: UInt32) -> String {
        let text = String(value, radix: 16, uppercase: true)
        return String(repeating: "0", count: max(0, 6 - text.count)) + text
    }

    struct AsciiChunk: Sendable {
        var outputs: [(UInt32, String)] = []
        var newer = 0
    }

    static func toAsciiArm(_ inputs: [String]) async throws -> (entry: Entry, newer: Int) {
        let ranges: [ClosedRange<UInt32>] = stride(from: UInt32(0x80), through: 0x10FFFF, by: 0x10000).map {
            $0...min($0 + 0xFFFF, 0x10FFFF)
        }
        let chunks = await withTaskGroup(of: (Int, AsciiChunk).self) { group in
            for (i, range) in ranges.enumerated() {
                group.addTask {
                    var chunk = AsciiChunk()
                    for value in range {
                        guard let scalar = Unicode.Scalar(value) else { continue }
                        var out = CabrilloExporter.toAscii(String(Character(scalar)))
                        if out != "?", newerThanJava(decomposing: scalar) {
                            chunk.newer += 1
                            out = "?"
                        }
                        chunk.outputs.append((value, out))
                    }
                    return (i, chunk)
                }
            }
            var all: [(Int, AsciiChunk)] = []
            for await chunk in group { all.append(chunk) }
            return all.sorted { $0.0 < $1.0 }.map(\.1)
        }
        var lines = inputs
        var hashed = Data()
        var kept = 0
        var run: (start: UInt32, end: UInt32, out: String)?
        func flush() {
            if let r = run {
                lines.append(Fx.out("/keep/" + hex6(r.start), hex6(r.end), Fx.tx(r.out)))
            }
        }
        for chunk in chunks {
            for (value, out) in chunk.outputs {
                hashed.append(contentsOf: (out + "\n").utf8)
                let keep = out != "?"
                if keep { kept += 1 }
                if keep, let r = run, r.out == out, value == r.end + 1 {
                    run = (r.start, value, out)
                    continue
                }
                flush()
                run = keep ? (value, value, out) : nil
            }
        }
        flush()
        lines.append(Fx.out("/kept", String(kept)))
        lines.append(Fx.out("/sha", JavaYamlParityTests.sha256Hex(hashed)))
        let newer = chunks.reduce(0) { $0 + $1.newer }
        let entry = Entry(relative: "toascii", sha256: Fx.checksum(definition: nil, registry: "", lines: inputs),
                          lines: lines)
        return (entry, newer)
    }
}
