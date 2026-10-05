import Foundation
import Testing
@testable import MCLCore

/// Replays the `ViewsMeasured` cases (maintainer-only probe) through
/// the Swift `ScoreBreakdown`, `QsoMarks`, `MoveMultipliers` and `MultiplierKind` and compares with Java
/// row by row — including the order of every list that goes to the UI (review 5 focus).
/// Generated logs (3 × 300 QSOs) are taken from `ReplayMeasured.cases` like the probe takes them from `generated.txt`.
@Suite struct ViewsMeasuredTests {

    /// Rows where Swift knowingly differs: key → Swift row.
    /// Except `javaRowsWithoutCrash`, Java crashes on all of them (`EXC NullPointerException`).
    static let divergent: [String: String] = [
        // `nil` band in the move list (definition `bands: [40m, 20m, ~]`): Java NPE, Swift skips it (a deliberate divergence from Java v1.1.1)
        "V\tlabels\t0\tdef": "[40m:[c]:2]",
        "V\tlabels\t2\tdef": "[]",
        "V\tlabels\t3\tdef": "[40m:[c]:2]",
        "V\tmove-java\t2\t80m;~;15m": "[80m:[zones;countries]:3|15m:[zones;countries]:3]",
        // `nil` binding: Java NPE in `ScoreBreakdown.compute`; Swift skips it (a deliberate divergence from Java v1.1.1).
        "B\tnil-binding": "multIds=[c] labels=[c] bands=[20m] bandsNull=[20m] bandsRev=~ modes=[CW] "
            + "rows=[20m/CW:1,0,1,{c=1},1] byBand=[20m:1,0,1,{c=1},1] byMode=[CW:1,0,1,{c=1},1] "
            + "total=1,0,1,{c=1},1 unknown=0,0,0,{c=0},0,0,0,0,{c=0},0 score=1,1,1,1 skipped=0",
        // the same `nil` binding in a session: Java NPE on write → QSO skipped, no mark;
        // Swift skips the binding already in the engine (a deliberate divergence from Java v1.1.1) → the QSO has a mark.
        "M\tnil-binding": "size=1 [0:1,false,true,[DL],DL]",
        // definition without `bands`: Java NPE (`for (String band : bands)`), Swift `nil` list = no band (a deliberate divergence from Java v1.1.1)
        "V\tnil-binding\t0\tdef": "[]",
        // (`M kelvin` used to be here: `FixedMultiplierSet` merged `K` and KELVIN SIGN; it now
        // keeps keys by UTF-16 like Java and the row matches.)
        // received field without a type / `nil` field / set without an id: Java NPE in `classify`, Swift type or id "does not fit" (a deliberate divergence from Java v1.1.1)
        "K\tkind-no-type": "a=other;b=districts;c=other",
        "K\tkind-nil-field": "a=districts;b=cq",
        "K\tkind-nil-set-id": "a=districts;b=other",
    ]

    /// Known divergences where Java does not crash (explanation at `divergent`).
    static let javaRowsWithoutCrash: Set<String> = ["M\tnil-binding"]

    // MARK: - text like the probe

    static let esc = SessionMeasuredTests.esc

    static func list(_ xs: [String?]?) -> String {
        guard let xs else { return "~" }
        return "[" + xs.map { esc($0) }.joined(separator: ";") + "]"
    }

    static func cell(_ b: ScoreBreakdown, _ c: ScoreBreakdown.Cell) -> String {
        let mults = b.multIds.map { esc($0) + "=\(c.mults($0))" }.joined(separator: ";")
        return "\(c.qsos),\(c.dupes),\(c.points),{" + mults + "},\(c.multTotal)"
    }

    static func breakdown(_ fresh: () throws -> ContestSession, _ qsos: [Qso]) throws -> String {
        let b: ScoreBreakdown
        do {
            b = try ScoreBreakdown.compute(try fresh(), qsos)
        } catch let error as ExpressionError {
            return SessionMeasuredTests.exception(error)
        }
        let order = try fresh().definition.bands
        let rows = b.rows(order).map { esc($0.band) + "/" + esc($0.mode) + ":" + cell(b, $0.cell) }
        let byBand = b.bands(nil).map { esc($0) + ":" + cell(b, b.band($0)) }
        let byMode = b.modes.map { esc($0) + ":" + cell(b, b.mode($0)) }
        let sc = b.score
        var out = "multIds=" + list(b.multIds) + " labels=" + list(b.multIds.map { b.multLabel($0) })
        out += " bands=" + list(b.bands(order)) + " bandsNull=" + list(b.bands(nil))
        out += " bandsRev=" + list(order.map { b.bands(Array($0.reversed())) }) + " modes=" + list(b.modes)
        out += " rows=[" + rows.joined(separator: "|") + "] byBand=[" + byBand.joined(separator: "|")
        out += "] byMode=[" + byMode.joined(separator: "|") + "] total=" + cell(b, b.total)
        out += " unknown=" + cell(b, b.cell("20m", "XX")) + "," + cell(b, b.band("2m"))
        out += " score=\(sc.qsoCount),\(sc.qsoPoints),\(sc.multTotal),\(sc.total) skipped=\(b.skipped)"
        return out
    }

    static func marks(_ fresh: ContestSession, _ qsos: [Qso]) -> String {
        let m = QsoMarks.compute(fresh, qsos)
        let rows = m.keys.sorted().map { id -> String in
            let k = m[id]!
            return "\(id):\(k.points),\(k.dupe),\(k.isMultiplier)," + list(k.newMults) + "," + esc(k.multText)
        }
        return "size=\(m.count) [" + rows.joined(separator: "|") + "]"
    }

    static func move(_ fresh: ContestSession, _ qsos: [(Qso, String)], _ index: Int, _ bands: [String?]?) -> String {
        let log = qsos.filter { !$0.1.contains("p") }.map(\.0)
        let session = ContestReplay.replay(fresh, log).session
        do {
            let c = try MoveMultipliers.candidates(session, qsos[index].0, bands: bands)
            return "[" + c.map { esc($0.band) + ":" + list($0.newMults) + ":\($0.points)" }.joined(separator: "|") + "]"
        } catch {
            return SessionMeasuredTests.exception(error)
        }
    }

    static func kinds(_ def: ContestDefinition, _ registry: MultiplierSetRegistry) -> String {
        guard let bindings = def.multipliers else { return "-" }
        return bindings.map { binding -> String in
            guard let binding else { return "EXC NullPointerException" }
            do {
                let set = try registry.get(binding.set)
                return esc(binding.id) + "=" + MultiplierKind.classify(def, binding, set).key
            } catch {
                return "EXC MultiplierException"
            }
        }.joined(separator: ";")
    }

    // MARK: - run

    /// Definition like the probe: `@file` from `contest-data/contests`, otherwise YAML after `unesc`.
    static func definition(_ spec: String) throws -> ContestDefinition {
        try SessionFixture.definition(spec.hasPrefix("@") ? spec : SessionMeasuredTests.unesc(spec) ?? "")
    }

    /// Manual cases + generated logs from `ReplayMeasured.cases` (from the first `gen-` scenario).
    static func lines() -> [Substring] {
        let own = ViewsMeasured.cases.split(separator: "\n", omittingEmptySubsequences: true)
        let replay = ReplayMeasured.cases.split(separator: "\n", omittingEmptySubsequences: true)
        let start = replay.firstIndex { $0.hasPrefix("S ¦ gen-") } ?? replay.endIndex
        return own + replay[start...]
    }

    /// Replays all cases; returns (key, row) in probe order.
    static func runAll() throws -> [(String, String)] {
        let unesc = SessionMeasuredTests.unesc
        let all = lines()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        var setIndex = 0
        for line in all where line.hasPrefix("Y ") {
            let f = SessionMeasuredTests.columns(line)
            let name = "s" + String(repeating: "0", count: 3 - String(setIndex).count) + String(setIndex) + ".yaml"
            try Data((unesc(f[1]) ?? "").utf8).write(to: dir.appendingPathComponent(name))
            setIndex += 1
        }
        let dxcc = try SessionFixture.dxcc()
        let registry = try SessionFixture.registry(dxcc).loadDir(dir)

        var out: [(String, String)] = []
        var name = ""
        var scenario: [String] = []
        var tour: Tour?
        var qsos: [(Qso, String)] = []
        let fresh = { () throws -> ContestSession in
            let s = ContestSession(definition: try definition(scenario[2]), dxcc: dxcc,
                                   registry: registry, myCall: unesc(scenario[3]), myGrid: unesc(scenario[4]),
                                   myItuZone: unesc(scenario[5]))
            if let tour { s.setTour(tour) }
            return s
        }
        for line in all {
            let f = SessionMeasuredTests.columns(line)
            switch f[0] {
            case "Y":
                break
            case "S":
                name = f[1]
                scenario = f
                tour = nil
                qsos = []
            case "T":
                tour = Tour.parse(unesc(f[1]))
                try #require(tour != nil, "tour \(f[1])")
            case "Q":
                var q = ReplayMeasuredTests.qso(f, id: Int64(qsos.count))
                q.id = f[8].contains("n") ? nil : f[8].contains("z") ? 0 : Int64(qsos.count)
                qsos.append((q, f[8]))
            case "X":
                let logged = qsos.filter { !$0.1.contains("p") }.map(\.0)
                out.append(("B\t" + name, try breakdown(fresh, logged)))
                out.append(("M\t" + name, marks(try fresh(), logged)))
                var indices: [Int] = []
                for i in qsos.isEmpty ? [] : [0, qsos.count / 2, qsos.count - 1] where !indices.contains(i) {
                    indices.append(i)
                }
                for i in indices {
                    let bands = try fresh().definition.bands
                    out.append(("V\t\(name)\t\(i)\tdef", move(try fresh(), qsos, i, bands)))
                }
            case "V":
                let bands = f[2] == "-" ? [] : SessionMeasuredTests.list(f[2])
                out.append(("V\t\(name)\t\(f[1])\t\(f[2])", move(try fresh(), qsos, Int(f[1])!, bands)))
            case "A":
                let contests = try SessionFixture.contestData().appendingPathComponent("contests")
                let files = try FileManager.default.contentsOfDirectory(atPath: contests.path)
                    .filter { $0.hasSuffix(".yaml") }.sorted { $0.utf16.lexicographicallyPrecedes($1.utf16) }
                for file in files {
                    let def = try SessionFixture.definition("@" + file)
                    out.append(("K\t" + (def.id ?? "~"), kinds(def, registry)))
                }
            case "C":
                out.append(("K\t" + f[1], kinds(try definition(f[2]), registry)))
            default:
                preconditionFailure("unknown row \(line)")
            }
        }
        return out
    }

    /// Expected probe rows: (key, row) in run order.
    static func expectedRows() throws -> [(String, String)] {
        try ViewsMeasured.expected.split(separator: "\n", omittingEmptySubsequences: true).map { line in
            let p = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            let keyCount = p[0] == "V" ? 4 : 2
            try #require(p.count == keyCount + 1, "table row: \(line)")
            return (p[..<keyCount].joined(separator: "\t"), p[keyCount])
        }
    }

    @Test func everyViewMatchesJava() throws {
        let expected = try Self.expectedRows()
        let actual = try Self.runAll()
        #expect(actual.map(\.0) == expected.map(\.0), "keys and row order")
        let byKey = Dictionary(uniqueKeysWithValues: expected)
        for (key, row) in actual {
            if let pinned = Self.divergent[key] {
                #expect(row == pinned, "\(key) (known divergence): \(row)")
                #expect(byKey[key] != pinned, "\(key): Java really differs")
                if !Self.javaRowsWithoutCrash.contains(key) {
                    #expect(byKey[key]?.hasPrefix("EXC NullPointerException") == true, "\(key): Java crashes")
                }
                continue
            }
            #expect(row == byKey[key], "\(key): \(row)")
        }
    }

    /// The table covers all 22 supplied contests and the generated logs.
    @Test func tableCoversShippedContestsAndGeneratedLogs() throws {
        let keys = try Self.expectedRows().map(\.0)
        let shipped = try FileManager.default.contentsOfDirectory(
            atPath: SessionFixture.contestData().appendingPathComponent("contests").path).filter { $0.hasSuffix(".yaml") }
        #expect(shipped.count == 22)
        #expect(keys.filter { $0.hasPrefix("K\t") }.count == 22 + 8)
        for gen in ["gen-cq-ww-cw", "gen-iaru-hf", "gen-cq-wpx-cw"] {
            #expect(keys.contains("B\t" + gen))
            #expect(keys.contains("M\t" + gen))
        }
    }
}
