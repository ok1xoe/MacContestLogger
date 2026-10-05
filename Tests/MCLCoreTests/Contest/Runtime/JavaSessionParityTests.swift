import Foundation
import Testing
@testable import MCLCore

/// Parity suite against Java for the **contest session**: the final regression net over the measured
/// tables. Three arms, each compares the Swift result with a reference produced by the
/// **Java** application v1.1.1 (maintainer-only probe). The generator is compiled together with the engine parity generator
/// (maintainer-only probe) and takes the QSO stream and the row format from it; here in turn its
/// helpers are used (`JavaEngineParityTests`: `esc`/`unesc`, multiplier results, exchange, exceptions,
/// checksums, the "REGENERATE REFERENCE" × "MISMATCH" comparison).
///
/// - **Live session** (`session-live-java.json`): a real `ContestSession` — 150 steps
///   `log`/`preview`/`setTour(Tour.effective(…))`/`setBonusStations`/`setQtcCount`/`exchangeComplete`,
///   `score()` after every step incl. bonuses and QTC; at the end `multiplierGrid` for every set.
///   An exception in the middle of a write leaves a half-done state (multiplier yes, QSO no) — like Java.
/// - **Replay** (`session-replay-java.json`): a generated log (deleted, X-QSO, no band,
///   no callsign, unsorted and missing times) through `ContestReplay.replay`: the result of each
///   replayed QSO, the counts, the reason for each skip and the final score.
/// - **Views** (`session-views-java.json`): over the same log `ScoreBreakdown`, `QsoMarks`,
///   `MoveMultipliers`, `Dupesheet` and `LogWarnings`.
///
/// Definitions: 22 `contest-data/contests/`, 2 `definition-synthetic/`, `engine-gate-synthetic/overflow.yaml`
/// and 2 synthetic ones just for this gate in `session-gate-synthetic/` (bonuses of all scopes, QTC, session
/// from the definition, exceptions after a partial write) — the real definitions have no bonuses.
///
/// **Preview with a fixed time:** the Java `preview` takes `Instant.now()`. With a TOUR session the generator therefore
/// calls the same procedure over the private fields of the same session with the step time (without a session it calls the real
/// method and verifies the match); Swift calls `preview(…, at:)` with the step time. `MoveMultipliers` runs
/// over a session without a TOUR session.
///
/// **Replay with a fixed "now":** a log QSO without a time is replayed by both Java and Swift at "now". The generator
/// therefore replays them with a fixed `NULL_TIME_NOW` and the gate with the same `nullTimeNow` (see there).
///
/// Recorded divergence: `synthetic/full-b.yaml` has a `nil` points rule, a `nil` bonus and a `nil` binding —
/// Java fails with a `NullPointerException`, Swift skips them. In the live arm nothing is compared from the first NPE step
/// on (like the engine parity suite — for full-b it is already `/000/score`), in replay and views only the inputs
/// of full-b are compared; full-b thus has its outputs not compared at all.
/// Which items these are is pinned by `javaNpeOnlyInFullDefinitionB`.
@Suite struct JavaSessionParityTests {

    typealias Entry = JavaYamlParityTests.ReferenceFile
    typealias Gate = JavaEngineParityTests

    static let regenerate = " — the reference is generated from Java v1.1.1 by a maintainer-only generator (not in this repository)."

    /// Parity definitions: the engine parity definitions + `session-gate-synthetic/*.yaml` (names `session/…`).
    static func definitionFiles() throws -> [(name: String, url: URL)] {
        var out = try Gate.definitionFiles()
        let dir = try #require(Bundle.module.url(forResource: "session-gate-synthetic", withExtension: nil),
                               "directory session-gate-synthetic is not in the bundle — the .copy rule in Package.swift")
        for name in try JavaDefinitionParityTests.sortedNames(in: dir, suffix: ".yaml") {
            out.append(("session/" + name, dir.appendingPathComponent(name)))
        }
        return out
    }

    // MARK: - Row texts

    static func pad(_ number: Int, _ width: Int) -> String {
        let text = String(number)
        return String(repeating: "0", count: max(0, width - text.count)) + text
    }

    /// Java `SessionRefGen.list`: `[a;b;…]`, elements through `esc`.
    static func list(_ items: [String?]) -> String {
        "[" + items.map(Gate.esc).joined(separator: ";") + "]"
    }

    /// Inverse of `list`: `[]` → empty list; `~` → `nil`.
    static func parseList(_ spec: String) -> [String?]? {
        guard spec != "~" else { return nil }
        let body = String(spec.dropFirst().dropLast())
        return body.isEmpty ? [] : body.components(separatedBy: ";").map(Gate.unesc)
    }

    /// Sorting texts like Java `Collections.sort` (by UTF-16 units).
    static func javaSorted(_ items: [String]) -> [String] {
        items.sorted { $0.utf16.lexicographicallyPrecedes($1.utf16) }
    }

    static func scoreText(_ s: ScoreState) -> String {
        let groups = s.multByGroup.entries.map { Gate.esc($0.key) + "=" + ($0.value.map { String($0) } ?? "null") }
        return "qso=\(s.qsoCount) pts=\(s.qsoPoints) mult=\(s.multTotal) groups=[\(groups.joined(separator: ","))] "
            + "bonus=\(s.bonusPoints) qtc=\(s.qtcPoints) total=\(s.total)"
    }

    static func score(_ session: ContestSession) -> String {
        do {
            return scoreText(try session.score())
        } catch {
            return Gate.exc(error)
        }
    }

    static func result(_ r: ContestSession.LogResult) -> String {
        "counted=\(r.counted) dupe=\(r.dupe) pts=\(r.points) mult=" + Gate.results(r.multipliers)
    }

    static func attempt(_ body: () throws -> String) -> String {
        do {
            return try body()
        } catch {
            return Gate.exc(error)
        }
    }

    // MARK: - Session setup

    struct Setup {
        let myCall: String?
        let myGrid: String?
        let myZone: String?
        let tour: String?
        let bonus: [String?]
        let qtc: Int32
    }

    static func setup(_ f: [String]) throws -> Setup {
        try #require(f[0] == "/setup" && f.count == 8, "first row is not /setup")
        return Setup(myCall: Gate.unesc(f[2]), myGrid: Gate.unesc(f[3]), myZone: Gate.unesc(f[4]),
                     tour: Gate.unesc(f[5]), bonus: try #require(parseList(f[6])), qtc: try #require(Int32(f[7])))
    }

    /// Java `SessionRefGen.session`: a TOUR session via `Tour.effective`, bonus stations, QTC.
    static func session(_ definition: ContestDefinition, _ s: Setup, _ environment: Gate.Environment,
                        withTour: Bool) -> ContestSession {
        let session = ContestSession(definition: definition, dxcc: environment.dxcc, registry: environment.registry,
                                     myCall: s.myCall, myGrid: s.myGrid, myItuZone: s.myZone)
        if withTour { session.setTour(Tour.effective(s.tour, definition)) }
        session.setBonusStations(s.bonus)
        session.setQtcCount(s.qtc)
        return session
    }

    // MARK: - Comparison

    /// Items where Java failed with an NPE (recorded Swift leniency): in replay and views
    /// the steps are not numbered, so only the inputs are compared.
    static func onlyInputsWhereJavaNpe(_ reference: [Entry], _ mine: [Entry]) -> ([Entry], [Entry]) {
        let npe = Set(reference.filter { $0.lines.contains { $0.contains(Gate.javaNpe) } }.map(\.relative))
        func cut(_ e: Entry) -> Entry {
            guard npe.contains(e.relative) else { return e }
            return Entry(relative: e.relative, sha256: e.sha256, lines: e.lines.filter(Gate.isInput))
        }
        return (reference.map(cut), mine.map(cut))
    }

    static func check(_ name: String, arm: String, numberedSteps: Bool,
                      _ run: (ContestDefinition, [String], Gate.Environment) throws -> [String]) throws {
        let reference = try Gate.reference(name)
        var mine = try Gate.runOverDefinitions(reference, files: try definitionFiles(), run)
        var compared = reference
        if !numberedSteps { (compared, mine) = onlyInputsWhereJavaNpe(reference, mine) }
        if let report = Gate.differences(reference: compared, mine: mine, arm: arm, regenerate: regenerate) {
            Issue.record(Comment(rawValue: report))
        }
    }

    // MARK: - Live session arm

    /// Performs the steps of one definition in the order of `SessionRefGen.liveArm`. The step score is printed only
    /// after all its rows (the `G` grid has an input for every set).
    static func liveStream(_ definition: ContestDefinition, _ inputs: [String],
                           _ environment: Gate.Environment) throws -> [String] {
        try liveStream(definition, inputs, environment, observe: nil)
    }

    /// `observe` receives each step's path and the session after the step (bonus coverage test).
    static func liveStream(_ definition: ContestDefinition, _ inputs: [String], _ environment: Gate.Environment,
                           observe: ((String, ContestSession) -> Void)?) throws -> [String] {
        var out: [String] = []
        var session: ContestSession?
        var pendingScore: String?
        let bands = (definition.bands ?? []).compactMap { Band.from(adif: $0) }
        func flush() {
            if let step = pendingScore, let session {
                out.append(Gate.line(step + "/score", "out", score(session)))
                observe?(step, session)
            }
            pendingScore = nil
        }
        for input in inputs {
            let f = Gate.fields(input)
            let p = f[0]
            if p == "/setup" {
                out.append(input)
                let s = try setup(f)
                session = ContestSession(definition: definition, dxcc: environment.dxcc, registry: environment.registry,
                                         myCall: s.myCall, myGrid: s.myGrid, myItuZone: s.myZone)
                continue
            }
            if Gate.step(p) != pendingScore { flush() }
            out.append(input)
            let current = try #require(session, "proud bez /setup")
            if p.contains("/grid/") {
                let setId = Gate.unesc(f[2])
                do {
                    let grid = try current.multiplierGrid(bands: bands) { _, set in set.id == setId }
                    out.append(Gate.line(p + "/head", "out", "available=\(grid.available) worked=\(grid.worked) "
                                         + "possible=\(grid.possible) rows=\(grid.rows.count)"))
                    for (k, row) in grid.rows.enumerated() {
                        let text = [Gate.esc(row.key), Gate.esc(row.label), Gate.esc(row.prefix), Gate.esc(row.continent),
                                    list(row.workedBands)].joined(separator: ",")
                        out.append(Gate.line(p + "/" + pad(k, 3), "out", text))
                    }
                } catch {
                    out.append(Gate.line(p + "/exc", "out", Gate.exc(error)))
                }
                continue
            }
            pendingScore = p
            switch f[2] {
            case "T":
                current.setTour(Tour.effective(Gate.unesc(f[3]), definition))
                out.append(Gate.line(p + "/tour", "out", current.tour?.format() ?? "~"))
            case "B":
                current.setBonusStations(parseList(f[3]))
                out.append(Gate.line(p + "/bonus", "out", list(javaSorted(current.bonusStations))))
            case "C":
                current.setQtcCount(try #require(Int32(f[3])))
                out.append(Gate.line(p + "/qtc", "out", String(current.qtcCount)))
            case "G":
                break
            case "Q", "P":
                let preview = f[2] == "P"
                let at = try #require(Int64(f[3]))
                let call = Gate.unesc(f[4]), band = Gate.unesc(f[5]), mode = Gate.unesc(f[6])
                let raw = Gate.map(f[7]), ownQth = Gate.unesc(f[8])
                do {
                    let r = preview
                        ? try current.preview(call: call, band: band, mode: mode, receivedRaw: raw, ownQth: ownQth,
                                              at: Date(timeIntervalSince1970: TimeInterval(at)))
                        : try current.log(call: call, band: band, mode: mode, receivedRaw: raw, atEpochSecond: at,
                                          ownQth: ownQth)
                    out.append(Gate.line(p + "/class", "out", Gate.esc(r.context.workedClass)))
                    out.append(Gate.line(p + "/rcv", "out", Gate.values(r.context.received)))
                    out.append(Gate.line(p + "/result", "out", result(r)))
                } catch {
                    out.append(Gate.line(p + "/exc", "out", Gate.exc(error)))
                }
                if preview {
                    out.append(Gate.line(p + "/complete", "out", attempt {
                        String(try current.exchangeComplete(call: call, receivedRaw: raw))
                    }))
                }
            default:
                // An unknown step kind must not be silently skipped — the generator and the gate would silently diverge.
                Issue.record(Comment(rawValue: "unknown step kind \(input)"))
            }
        }
        flush()
        return out
    }

    @Test func liveSessionMatchesJava() throws {
        try JavaV111Gate.run {
            try Self.check("session-live-java", arm: "live session arm", numberedSteps: true, Self.liveStream)
        }
    }

    // MARK: - Log

    /// Log from the input rows `/log/NNN` (uuid = row order, so that a skipped QSO can be traced).
    static func logbook(_ inputs: [String]) throws -> [Qso] {
        var out: [Qso] = []
        for input in inputs {
            let f = Gate.fields(input)
            guard f[0].hasPrefix("/log/") else { continue }
            try #require(f.count == 11, "log row \(input)")
            var q = Qso()
            q.uuid = String(out.count)
            if f[2] != "~" { q.id = try number(f[2]) }
            q.call = Gate.unesc(f[3]) ?? ""
            if f[4] != "~" {
                let band: Band = try #require(Band.from(adif: f[4]), "unknown band \(f[4])")
                q.band = band
            }
            if f[5] != "~" {
                let mode: Mode = try #require(Mode(rawValue: f[5]), "unknown mode \(f[5])")
                q.mode = mode
            }
            q.exchangeRcvd = Gate.unesc(f[6]) ?? ""
            if f[7] != "~" { q.serialRcvd = Int(try number(f[7])) }
            if f[8] != "~" { q.timestampUtc = Date(timeIntervalSince1970: TimeInterval(try number(f[8]))) }
            q.exchangeSent = Gate.unesc(f[9]) ?? ""
            q.deleted = f[10].contains("d")
            q.xqso = f[10].contains("x")
            out.append(q)
        }
        return out
    }

    /// Integer from a generator row (not user data — that goes through `esc`).
    static func number(_ text: String) throws -> Int64 {
        try #require(Int64(text), "not a number: \(text)")
    }

    static func index(_ q: Qso) -> String {
        pad(Int(q.uuid) ?? -1, 3)
    }

    // MARK: - Replay arm

    /// "Now" for log QSOs **without a time** in replay and in the views over it: 2100-01-01T00:00:00Z,
    /// Java `SessionRefGen.NULL_TIME_NOW`. Both Java and Swift replay a QSO without a time at `Instant.now()`;
    /// with a TOUR session the dupe then depends on which session the real "now" falls into. Sessions are
    /// counted absolutely from 1970 and the log times lie on 2026-10-01, so with the system clock the gate
    /// failed only that day in the windows where "now" shared a session with a QSO of the same callsign/band/mode
    /// (rdxc 06:00–06:30 and 07:30–08:00 UTC, sp-dx, wae-cw, cq-ww-ssb, gate/overflow).
    /// Pinned by `replayWithoutTimeDependsOnClock`.
    static let nullTimeNow = Date(timeIntervalSince1970: 4_102_444_800)

    static func replayRun(_ definition: ContestDefinition, _ inputs: [String],
                          _ environment: Gate.Environment) throws -> [String] {
        try replayRun(definition, inputs, environment, now: nullTimeNow)
    }

    static func replayRun(_ definition: ContestDefinition, _ inputs: [String],
                          _ environment: Gate.Environment, now: Date) throws -> [String] {
        var out = inputs
        let unknown = inputs.filter { !$0.hasPrefix("[\"/setup\"") && !$0.hasPrefix("[\"/log/") }
        for input in unknown { Issue.record(Comment(rawValue: "unknown replay input \(input)")) }
        let s = try setup(Gate.fields(try #require(inputs.first)))
        let qsos = try logbook(inputs)
        let fresh = session(definition, s, environment, withTour: true)
        out.append(Gate.line("/tour", "out", fresh.tour?.format() ?? "~"))
        let outcome = ContestReplay.replay(fresh, qsos, now: { now }) { q, r in
            out.append(Gate.line("/r/" + index(q), "out", result(r)))
        }
        out.append(Gate.line("/outcome", "out", "replayed=\(outcome.replayed) skipped=\(outcome.skipped)"))
        out.append(Gate.line("/score", "out", score(outcome.session)))
        for skip in outcome.skips {
            let reason: String
            switch skip.reason {
            case .missingBand: reason = "band"
            case .missingCall: reason = "call"
            case .error(let error): reason = "error " + Gate.exc(error)
            }
            out.append(Gate.line("/skip/" + index(skip.qso), "out", reason))
        }
        return out
    }

    @Test func replayMatchesJava() throws {
        try JavaV111Gate.run {
            try Self.check("session-replay-java", arm: "replay arm", numberedSteps: false, Self.replayRun)
        }
    }

    /// The gate can turn red and "now" is really wired in: rdxc (session `1200/30`) with "now" =
    /// 2026-10-01T06:15:00Z makes the QSOs without a time `/r/066` (DL1ABC 10m CW, same at 06:09:03) and
    /// `/r/099` (SP9XYZ 20m SSB, same at 06:09:03) dupes — exactly like Java with the same "now"
    /// (verified with a modified generator: `pts=248 … total=9424`). With `nullTimeNow` it matches the reference.
    @Test func replayWithoutTimeDependsOnClock() throws {
        let reference = try Gate.reference("session-replay-java")
        let entry = try #require(reference.first { $0.relative == "contests/rdxc.yaml" })
        let file = try #require(try Self.definitionFiles().first { $0.name == "contests/rdxc.yaml" })
        let definition = try ContestDefinitionLoader.loadFile(file.url)
        let inputs = entry.lines.filter(Gate.isInput)
        let environment = try Gate.environment()

        let pinned = try Self.replayRun(definition, inputs, environment, now: Self.nullTimeNow)
        #expect(pinned == entry.lines)

        let inWindow = try Self.replayRun(definition, inputs, environment,
                                          now: Date(timeIntervalSince1970: 1_790_835_300))
        let changed = inWindow.filter { !entry.lines.contains($0) }
        #expect(changed.count == 3)
        #expect(changed.contains { $0.hasPrefix("[\"/r/066\",\"out\",\"counted=true dupe=true pts=0 ") })
        #expect(changed.contains { $0.hasPrefix("[\"/r/099\",\"out\",\"counted=true dupe=true pts=0 ") })
        #expect(changed.contains { $0.contains("qso=68 pts=248 ") && $0.contains("total=9424") })
    }

    // MARK: - Views arm

    static func cell(_ c: ScoreBreakdown.Cell, _ ids: [String?]) -> String {
        let mults = ids.map { String(c.mults($0)) }.joined(separator: ",")
        return "\(c.qsos),\(c.dupes),\(c.points),[\(mults)],\(c.multTotal)"
    }

    static func breakdown(_ b: ScoreBreakdown, _ order: [String?]?) -> String {
        let ids = b.multIds
        let labels = ids.map { Gate.esc($0) + "=" + Gate.esc(b.multLabel($0)) }.joined(separator: ";")
        let rows = b.rows(order).map { Gate.esc($0.band) + "/" + Gate.esc($0.mode) + ":" + cell($0.cell, ids) }
        let bands = b.bands(order).map { Gate.esc($0) + ":" + cell(b.band($0), ids) }
        let modes = b.modes.map { Gate.esc($0) + ":" + cell(b.mode($0), ids) }
        var text = "ids=[" + labels + "] rows=[" + rows.joined(separator: ";") + "]"
        text += " bands=[" + bands.joined(separator: ";") + "] modes=[" + modes.joined(separator: ";") + "]"
        text += " none=" + cell(b.band("nope"), ids) + "|" + cell(b.mode("nope"), ids) + "|" + cell(b.cell("nope", "CW"), ids)
        text += " total=" + cell(b.total, ids) + " skipped=\(b.skipped) score=" + scoreText(b.score)
        return text
    }

    static func zones(_ environment: Gate.Environment, _ call: String, cq: Bool) -> Set<Int?> {
        guard let entity = environment.dxcc.resolve(call) else { return [] }
        return Set((cq ? entity.cq : entity.itu) ?? [])
    }

    static func viewsRun(_ definition: ContestDefinition, _ inputs: [String],
                         _ environment: Gate.Environment) throws -> [String] {
        try viewsRun(definition, inputs, environment, now: nullTimeNow)
    }

    static func viewsRun(_ definition: ContestDefinition, _ inputs: [String],
                         _ environment: Gate.Environment, now: Date) throws -> [String] {
        var out: [String] = []
        let s = try setup(Gate.fields(try #require(inputs.first)))
        let qsos = try logbook(inputs)
        // MoveMultipliers runs over a session without a TOUR session with the replayed log (the Java preview takes "now";
        // without a TOUR session it does not matter, `now` is just for uniformity).
        var moveSession: ContestSession?
        let fixedTime = Date(timeIntervalSince1970: 1_790_856_000)
        for input in inputs {
            out.append(input)
            let f = Gate.fields(input)
            let p = f[0]
            guard Gate.stepNumber(p) != nil else {
                if p != "/setup" && !p.hasPrefix("/log/") { Issue.record(Comment(rawValue: "unknown input \(input)")) }
                continue
            }
            let result: String
            switch f[2] {
            case "SB":
                let order = parseList(f[3])
                result = attempt {
                    breakdown(try ScoreBreakdown.compute(session(definition, s, environment, withTour: true), qsos,
                                                        now: { now }), order)
                }
            case "M":
                let marks = QsoMarks.compute(session(definition, s, environment, withTour: true), qsos, now: { now })
                result = marks.keys.sorted().map { id in
                    let m = marks[id]!
                    return "\(id):\(m.points):\(m.dupe):" + list(m.newMults) + ":\(m.isMultiplier):" + Gate.esc(m.multText)
                }.joined(separator: ";")
            case "MV":
                if moveSession == nil {
                    let live = session(definition, s, environment, withTour: false)
                    _ = ContestReplay.replay(live, qsos, now: { now })
                    moveSession = live
                }
                let live = try #require(moveSession)
                let q = qsos[try #require(Int(f[3]))]
                let bands = try #require(parseList(f[4]))
                result = attempt {
                    try MoveMultipliers.candidates(live, q, bands: bands, at: fixedTime)
                        .map { Gate.esc($0.band) + ":" + list($0.newMults) + ":\($0.points)" }
                        .joined(separator: ";")
                }
            case "D":
                var scope: ContestDefinition.Scope?
                if f[5] != "~" {
                    let known: ContestDefinition.Scope = try #require(ContestDefinition.Scope(rawValue: f[5]),
                                                                      "unknown scope \(f[5])")
                    scope = known
                }
                let sheet = Dupesheet.build(qsos, band: Gate.unesc(f[3]), mode: Gate.unesc(f[4]), scope: scope)
                result = sheet.columns.map { Gate.esc(String($0.key)) + ":" + list($0.calls) }.joined(separator: ";")
            case "W":
                let scp = parseList(f[3])?.compactMap { $0 }
                let fields = session(definition, s, environment, withTour: true)
                let inScp: ((String) -> Bool)? = scp.map { list in
                    { call in list.contains { $0.utf16.elementsEqual(call.utf16) } }
                }
                result = attempt {
                    let w = try LogWarnings.analyze(qsos, receivedFields: { try fields.activeReceivedFields(call: $0) },
                                                    inScp: inScp,
                                                    cqZones: { zones(environment, $0, cq: true) },
                                                    ituZones: { zones(environment, $0, cq: false) })
                    return w.ids.map { "\($0):" + list(w[$0] ?? []) }.joined(separator: ";")
                }
            default:
                Issue.record(Comment(rawValue: "unknown operation \(input)"))
                result = "?"
            }
            out.append(Gate.line(p + "/out", "out", result))
        }
        return out
    }

    @Test func viewsMatchJava() throws {
        try JavaV111Gate.run {
            try Self.check("session-views-java", arm: "views arm", numberedSteps: false, Self.viewsRun)
        }
    }

    // MARK: - The gate does not pass by mistake

    /// Java NPEs (recorded Swift leniency) are only in `synthetic/full-b` (`nil` points rule,
    /// `nil` binding). Elsewhere an NPE would mean that a part of an item is not compared.
    @Test func javaNpeOnlyInFullDefinitionB() throws {
        for name in ["session-live-java", "session-replay-java", "session-views-java"] {
            let reference = try Gate.reference(name)
            let withNpe = reference.filter { $0.lines.contains { $0.contains(Gate.javaNpe) } }.map(\.relative)
            #expect(withNpe == ["synthetic/full-b.yaml"], "\(name): \(withNpe)")
        }
        // Scope: `score()` of full-b fails on the `nil` binding already in step /000, so nothing from full-b
        // is compared except the inputs (a shift after regeneration is visible here).
        let live = try #require(try Gate.reference("session-live-java").first { $0.relative == "synthetic/full-b.yaml" })
        let firstNpe = live.lines.first { $0.contains(Gate.javaNpe) }.map(JavaYamlParityTests.pathOf)
        #expect(firstNpe == "/000/score")
        let replay = try #require(try Gate.reference("session-replay-java").first { $0.relative == "synthetic/full-b.yaml" })
        #expect(replay.lines.contains(Gate.line("/outcome", "out", "replayed=0 skipped=87")))
        let messages = Set(["session-live-java", "session-replay-java", "session-views-java"].flatMap { name in
            ((try? Gate.reference(name)) ?? []).flatMap(\.lines).filter { $0.contains(Gate.javaNpe) }
                .map { line -> String in
                    let value = JavaYamlParityTests.valueOf(line)
                    return value.contains("PointRule.when()") ? "when" : value.contains("bandWeights()") ? "bandWeights"
                        : value.contains("MultiplierBinding.id()") ? "bindingId" : value
                }
        })
        // `nil` points rule, `nil` binding in the score and in `ScoreBreakdown.multIds` (a deliberate divergence from Java v1.1.1).
        #expect(messages == ["when", "bandWeights", "bindingId"], Comment(rawValue: messages.sorted().joined(separator: "\n")))
    }
    /// Bonus points in the Java reference split by scope. The Java score carries only the sum
    /// `bonus=`; which bonus was awarded in a step is told by the Swift session over the same inputs (new
    /// keys `id|scopeKey`; elsewhere the gate asserts that its score matches Java step by step).
    /// The step increment is credited to bonuses with a fixed value (`fixed`) and the rest to the single new
    /// bonus with a computed value; steps with two or more computed bonuses are skipped.
    static func bonusContributions(_ live: [Entry], _ name: String) throws -> [ContestDefinition.Scope: Int64] {
        let files = try definitionFiles()
        let file = try #require(files.first { $0.name == name })
        let definition = try ContestDefinitionLoader.loadFile(file.url)
        let entry = try #require(live.first { $0.relative == name })
        var javaBonus: [String: Int64] = [:]
        for line in entry.lines where JavaYamlParityTests.pathOf(line).hasSuffix("/score") {
            let score = JavaYamlParityTests.valueOf(line)
            let field = try #require(score.split(separator: " ").first { $0.hasPrefix("bonus=") })
            javaBonus[Gate.step(JavaYamlParityTests.pathOf(line))] = try number(String(field.dropFirst(6)))
        }
        var bonuses: [String: ContestDefinition.Bonus] = [:]
        for case let bonus? in definition.scoring?.bonuses ?? [] {
            bonuses[bonus.id ?? "null"] = bonus
        }
        var seen: Set<String> = []
        var previous: Int64 = 0
        var out: [ContestDefinition.Scope: Int64] = [:]
        var failure: String?
        _ = try liveStream(definition, entry.lines.filter(Gate.isInput), try Gate.environment()) { step, session in
            let keys = session.awardedBonusKeys
            let fresh = keys.subtracting(seen)
            seen = keys
            let total = javaBonus[step] ?? previous
            var delta = total - previous
            previous = total
            var computed: [ContestDefinition.Bonus] = []
            for key in fresh {
                let id = String(key.prefix { $0 != "|" })
                guard let bonus = bonuses[id] else {
                    failure = "key \(key) without a bonus in the definition"
                    return
                }
                if let fixed = bonus.value?.fixed {
                    out[bonus.scope ?? .ONCE, default: 0] += Int64(fixed)
                    delta -= Int64(fixed)
                } else {
                    computed.append(bonus)
                }
            }
            if computed.count == 1 {
                out[computed[0].scope ?? .ONCE, default: 0] += delta
            } else if computed.isEmpty && delta != 0 {
                failure = "\(step): increment \(delta) without a new bonus"
            }
        }
        if let failure { Issue.record(Comment(rawValue: failure)) }
        return out
    }

    /// The references carry what the gate stands on: bonuses and QTC in the score, session on and off,
    /// exceptions after a partial write, all three skip reasons, deleted/X-QSO/no-time in the log
    /// and non-empty outputs of every view. Counts measured on the reference (regeneration shifts them).
    @Test func referencesCarryCheckpoints() throws {
        let live = try Gate.reference("session-live-java")
        #expect(live.count == 27)
        let liveText = try Gate.referenceText("session-live-java")
        for kind in ["Q", "P", "T", "B", "C", "G"] {
            #expect(liveText.contains("\",\"in\",\"\(kind)\""), "step \(kind) missing")
        }
        #expect(liveText.contains("/tour\",\"out\",\"~\"") && liveText.contains("/tour\",\"out\",\"2330/90\""))
        #expect(liveText.contains("/complete\",\"out\",\"true\"") && liveText.contains("/complete\",\"out\",\"false\""))
        #expect(liveText.contains("available=true") && liveText.contains("available=false"))
        // Bonuses and QTC: non-zero in the gate's session synthetics.
        let byName = Dictionary(live.map { ($0.relative, $0.lines) }, uniquingKeysWith: { first, _ in first })
        for name in ["session/bonus.yaml", "session/qtc-tour.yaml"] {
            let lines = try #require(byName[name])
            #expect(lines.contains { $0.contains("/score\",") && !$0.contains(" bonus=0 ") }, "\(name): bonus")
            #expect(lines.contains { $0.contains("/score\",") && !$0.contains(" qtc=0 ") }, "\(name): qtc")
        }
        // Partial state: an exception in a step after which the multipliers or bonuses changed, but not the QSO count.
        var partial = 0
        for entry in live where entry.relative != "synthetic/full-b.yaml" {
            var previous = ""
            var excStep = ""
            for line in entry.lines {
                let path = JavaYamlParityTests.pathOf(line)
                if path.hasSuffix("/exc") { excStep = Gate.step(path) }
                guard path.hasSuffix("/score") else { continue }
                let score = JavaYamlParityTests.valueOf(line)
                if excStep == Gate.step(path), score != previous,
                   score.split(separator: " ").first == previous.split(separator: " ").first {
                    partial += 1
                }
                previous = score
            }
        }
        #expect(partial >= 15, "partial states only \(partial)")

        // Each bonus scope shows up in the Java reference with non-zero points at least once
        // (missing scope = ONCE: `station`; explicit ONCE `boom` always throws).
        let contributions = try Self.bonusContributions(live, "session/bonus.yaml")
        for scope in [ContestDefinition.Scope.ONCE, .PER_BAND, .PER_MODE, .PER_BAND_MODE] {
            #expect((contributions[scope] ?? 0) > 0, "bonus with scope \(scope) contributed nothing in the reference: \(contributions)")
        }

        let replay = try Gate.referenceText("session-replay-java")
        for reason in ["band", "call", "error EXC MultiplierException", "error EXC NumberFormatException",
                       "error EXC PatternSyntaxException"] {
            #expect(replay.contains("\",\"out\",\"\(reason)"), "reason \(reason) missing")
        }
        for flags in ["d", "x", "dx"] {
            #expect(replay.contains("\",\"\(flags)\"]"), "flag \(flags) missing")
        }
        #expect(replay.components(separatedBy: "\"/r/").count > 1500)

        let views = try Gate.referenceText("session-views-java")
        for kind in ["SB", "M", "MV", "D", "W"] {
            #expect(views.contains("\"in\",\"\(kind)\""), "operation \(kind) missing")
        }
        #expect(views.contains(#"v\\u00FDm\\u011Bna"#), "LogWarnings without an exchange warning")
        #expect(views.contains("master.scp") && views.contains(#"nesed\\u00ED\\u0020k\\u0020zemi"#))
    }
}
