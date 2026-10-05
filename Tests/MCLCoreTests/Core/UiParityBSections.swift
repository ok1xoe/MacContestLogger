import Foundation
import Testing
@testable import MCLCore

/// Swift side of the Java parity suite (maintainer-only probe, fixture `b`): replays the input rows of `ui-b-java.json.gz` against the
/// logbook logic the entry window and the log table moved into the core. Kotlin recomputes everything after a change;
/// Swift follows changes incrementally, so every section drives the Swift technique the app uses:
///
/// - `dupe.IDX` — `LogbookMutations` over an in-memory logbook keeps the reference-counted `DupeIndex` (`didInsert`
///   after an insert, `apply(changes)` after an update, bulk edit, delete, delete-last, tombstone or wipe);
/// - `stats.RULES` — `ContestStats.appending` for an append with `ContestStats.of` as the fallback (an earlier time),
///   `of` after an edit or a delete (as `LogbookModel`), then `OperatingGuard.check` over a probe grid;
/// - `marks.LOG` — one `QsoMarksTracker` per definition, appended for an append, replaced by
///   `QsoMarksTracker.recomputed` when the append is refused and after every edit or delete (as `LogbookModel`);
/// - `edit.CELL` — `LogTableEdit.apply` per column.
///
/// The `defs` input row of `marks.LOG` is not copied from the reference: Swift builds it from its own bundle (the same
/// rule as the Java parity suite), so an added, removed or edited definition asks for regeneration instead of a mismatch.
enum UiParityBSections {

    typealias Entry = JavaYamlParityTests.ReferenceFile
    typealias Rows = [(String, [String])]
    typealias X = JavaCoreParityFixture
    typealias F = JavaIoParityFixture

    static let names: [String] = ["dupe.IDX", "stats.RULES", "marks.LOG", "edit.CELL"]

    /// The fixed `now` of the marks replay (no definition of the gate has a TOUR session, so it reaches no output).
    static let replayNow = Date(timeIntervalSince1970: 1_790_899_200)

    // MARK: - replay

    /// The state of one item between its rows.
    final class Ctx {
        let environment: UiParitySections.Environment
        // dupe.IDX
        var queryCalls: [String] = []
        var queryBands: [Band?] = []
        var service: LogbookService?
        var mutations = LogbookMutations(existing: [])
        var live: [(handle: Int, qso: Qso)] = []
        var nextHandle: Int = 0
        // stats.RULES
        var rules: [ContestDefinition.BandChange] = []
        var probeBands: [Band?] = []
        var statsRows: [(handle: Int, qso: Qso)] = []
        var stats: ContestStats = ContestStats.of([])
        // marks.LOG
        var runtime: ContestRuntime?
        var tracker: QsoMarksTracker?
        var markRows: [Qso] = []

        init(_ environment: UiParitySections.Environment) {
            self.environment = environment
        }
    }

    /// Replays an item: after each input row of the reference the outputs computed by Swift; the `defs` row is
    /// Swift's own. A Swift error at a row = the output row `SWIFT ERROR`, not a crash of the whole gate.
    static func replay(_ java: Entry, _ environment: UiParitySections.Environment) -> Entry {
        let ctx = Ctx(environment)
        var lines: [String] = []
        lines.reserveCapacity(java.lines.count)
        for line in java.lines {
            let fields: [String] = JavaEngineParityTests.fields(line)
            guard fields.count >= 2, fields[1] == "in" else { continue }
            if fields[0] == "defs" {
                lines.append(environment.defsRow(for: java.relative))
                continue
            }
            lines.append(line)
            let inputs: [String] = Array(fields.dropFirst(2))
            do {
                for (outPath, out) in try compute(java.relative, fields[0], inputs, ctx) {
                    lines.append(F.line(outPath, "out", out))
                }
            } catch {
                lines.append(F.line(fields[0], "out", ["SWIFT ERROR", String(describing: error)]))
            }
        }
        let sum: String = F.checksum(definition: nil, registry: "", lines: lines)
        return Entry(relative: java.relative, sha256: sum, lines: lines)
    }

    /// Replays all items, each on its own thread (not in the shared pool). Order of results = order of the reference.
    static func replayAll(_ reference: [Entry]) async throws -> [Entry] {
        let environment = try UiParitySections.Environment.load()
        return try await withThrowingTaskGroup(of: (Int, Entry).self) { group in
            for (index, entry) in reference.enumerated() {
                group.addTask {
                    let replayed = try await JavaNetParityFixture.onGateThread(entry.relative) {
                        replay(entry, environment)
                    }
                    return (index, replayed)
                }
            }
            var results = [Entry?](repeating: nil, count: reference.count)
            for try await (index, entry) in group {
                results[index] = entry
            }
            return results.compactMap { $0 }
        }
    }

    static func compute(_ name: String, _ path: String, _ f: [String], _ ctx: Ctx) throws -> Rows {
        switch name {
        case "dupe.IDX": return try dupe(path, f, ctx)
        case "stats.RULES": return try stats(path, f, ctx)
        case "marks.LOG": return try marks(path, f, ctx)
        case "edit.CELL": return [(path, try edit(f))]
        default: throw X.Malformed(text: "unknown item \(name)")
        }
    }

    // MARK: - shared

    static func band(_ adif: String) -> Band? {
        adif == "~" ? nil : Band.from(adif: adif)
    }

    static func adif(_ band: Band?) -> String {
        band?.adif ?? "~"
    }

    static func date(millis: Int64) -> Date {
        Date(timeIntervalSince1970: Double(millis) / 1000)
    }

    static func instant(millis: Int64) throws -> JavaInstant {
        let seconds: Int64 = millis >= 0 ? millis / 1000 : (millis - 999) / 1000
        let nanos: Int64 = (millis - seconds * 1000) * 1_000_000
        guard let value = JavaInstant.ofEpochSecond(seconds, nanos) else { throw X.Malformed(text: String(millis)) }
        return value
    }

    /// Java `getEpochSecond() + "." + getNano()`.
    static func text(_ instant: JavaInstant?) -> String {
        guard let instant else { return "~" }
        return String(instant.epochSecond) + "." + String(instant.nano)
    }

    // MARK: - dupe.IDX

    static func dupe(_ path: String, _ f: [String], _ ctx: Ctx) throws -> Rows {
        if path == "queries" {
            let (calls, next) = try X.list(f, from: 0)
            ctx.queryCalls = calls
            let count: Int = try X.int(f[next])
            ctx.queryBands = f[(next + 1)...(next + count)].map { band($0) }
            return []
        }
        if !path.contains("/") {
            let service = LogbookService(repository: try LogbookRepository.inMemory())
            service.activeContestId = "gate"
            ctx.service = service
            ctx.mutations = LogbookMutations(existing: [])
            ctx.live = []
            ctx.nextHandle = 0
            return []
        }
        guard let service = ctx.service else { throw X.Malformed(text: "no logbook at \(path)") }
        try dupeStep(f, service, ctx)
        let stored: Int = try service.findAll().count
        return [(path, [String(stored), answers(ctx)])]
    }

    static func dupeStep(_ f: [String], _ service: LogbookService, _ ctx: Ctx) throws {
        switch f[0] {
        case "I":
            try insert(f, service, ctx)
        case "U":
            let index: Int = try liveIndex(f[1], ctx)
            let old: Qso = ctx.live[index].qso
            let new: Qso = try changed(old, kind: f[2], value: f[3])
            let change: LogbookMutations.Change? = try LogbookMutations.update(.init(old: old, new: new), in: service)
            try adopt(change.map { [$0] } ?? [], ctx)
        case "B":
            let count: Int = try X.int(f[3])
            var edits: [LogbookMutations.Edit] = []
            for i in 0..<count {
                let old: Qso = ctx.live[try liveIndex(f[4 + i], ctx)].qso
                var new: Qso = old
                if f[1] == "freq" {
                    new.freqHz = try X.int(f[2])
                } else {
                    new.xqso = !old.xqso
                }
                edits.append(.init(old: old, new: new))
            }
            let (changes, error) = LogbookMutations.bulk(edits, in: service)
            if let error { throw error }
            try adopt(changes, ctx)
        case "D":
            let count: Int = try X.int(f[1])
            var rows: [Qso] = []
            for i in 0..<count {
                rows.append(ctx.live[try liveIndex(f[2 + i], ctx)].qso)
            }
            try adopt(try LogbookMutations.delete(rows, in: service), ctx)
        case "L":
            let (changes, _) = try LogbookMutations.deleteLast(of: ctx.live.map(\.qso), in: service)
            try adopt(changes, ctx)
        case "T":
            let old: Qso = ctx.live[try liveIndex(f[1], ctx)].qso
            var new: Qso = old
            new.deleted = true
            let change: LogbookMutations.Change? = try LogbookMutations.update(.init(old: old, new: new), in: service)
            try adopt(change.map { [$0] } ?? [], ctx)
        case "W":
            let (changes, _) = try LogbookMutations.wipe(ctx.live.map(\.qso), in: service)
            try adopt(changes, ctx)
        default:
            throw X.Malformed(text: "dupe step \(f[0])")
        }
    }

    /// An insert (a county line copy = the same callsign and band twice, the exchange `14`, `15`).
    static func insert(_ f: [String], _ service: LogbookService, _ ctx: Ctx) throws {
        let copies: Int = try X.int(f[1])
        let step: Int64 = Int64(ctx.nextHandle)
        for n in 0..<copies {
            var q = Qso()
            q.call = X.text(f[2]) ?? ""
            q.freqHz = try X.int(f[3])
            q.mode = .cw
            q.exchangeRcvd = String(14 + n)
            q.timestampUtc = date(millis: 1_790_899_200_000 + step * 60_000 + Int64(n))
            let stored: Qso = try LogbookMutations.insert(q, into: service)
            ctx.mutations.didInsert(stored)
            ctx.live.append((ctx.nextHandle, stored))
            ctx.nextHandle += 1
        }
    }

    /// The saved changes into the index and into the live rows (an update's written row replaces the row; a
    /// tombstone or a delete takes it out).
    static func adopt(_ changes: [LogbookMutations.Change], _ ctx: Ctx) throws {
        ctx.mutations.apply(changes)
        for change in changes {
            switch change {
            case .updated(_, let new):
                guard let index = ctx.live.firstIndex(where: { $0.qso.id == new.id }) else { continue }
                if new.deleted {
                    ctx.live.remove(at: index)
                } else {
                    ctx.live[index].qso = new
                }
            case .deleted(let gone):
                ctx.live.removeAll { $0.qso.id == gone.id }
            case .inserted, .reset:
                throw X.Malformed(text: "unexpected change")
            }
        }
    }

    static func liveIndex(_ field: String, _ ctx: Ctx) throws -> Int {
        let handle: Int = try X.int(field)
        guard let index = ctx.live.firstIndex(where: { $0.handle == handle }) else {
            throw X.Malformed(text: "no live row \(handle)")
        }
        return index
    }

    /// One cell change of an edit (`LogSections.change`).
    static func changed(_ old: Qso, kind: String, value: String) throws -> Qso {
        var new: Qso = old
        switch kind {
        case "call": new.call = X.text(value) ?? ""
        case "freq": new.freqHz = try X.int(value)
        case "mode": new.mode = .ft8
        case "xqso": new.xqso = !old.xqso
        case "exch": new.exchangeRcvd = value
        default: throw X.Malformed(text: "edit \(kind)")
        }
        return new
    }

    /// `isDupe` of every query callsign on every query band (`LogSections.answers`).
    static func answers(_ ctx: Ctx) -> String {
        var out = ""
        for call in ctx.queryCalls {
            for band in ctx.queryBands {
                out += ctx.mutations.isDupe(call: call, band: band) ? "1" : "0"
            }
        }
        return out
    }

    // MARK: - stats.RULES

    static func stats(_ path: String, _ f: [String], _ ctx: Ctx) throws -> Rows {
        if path == "grid" {
            let count: Int = try X.int(f[0])
            ctx.rules = []
            for i in 0..<count {
                let minimum: Int? = f[1 + 2 * i] == "~" ? nil : try X.int(f[1 + 2 * i])
                let perHour: Int? = f[2 + 2 * i] == "~" ? nil : try X.int(f[2 + 2 * i])
                ctx.rules.append(ContestDefinition.BandChange(minimumMinutes: minimum, perHour: perHour))
            }
            let start: Int = 1 + 2 * count
            let bands: Int = try X.int(f[start])
            ctx.probeBands = f[(start + 1)...(start + bands)].map { band($0) }
            return []
        }
        if !path.contains("/") {
            ctx.statsRows = []
            ctx.stats = ContestStats.of([])
            return []
        }
        let next: Int = try statsStep(path, f, ctx)
        let now1: JavaInstant = try instant(millis: try X.int64(f[next]))
        let now2: JavaInstant = try instant(millis: try X.int64(f[next + 1]))
        return [(path, statsOut(ctx, now1, now2))]
    }

    /// Applies one step; returns the index of the first `now` field.
    static func statsStep(_ path: String, _ f: [String], _ ctx: Ctx) throws -> Int {
        switch f[0] {
        case "A":
            var q = Qso()
            q.call = "OK1ABC"
            q.band = band(f[2])
            if f[1] != "~" {
                q.timestampUtc = date(millis: try X.int64(f[1]))
            }
            q.deleted = X.bool(f[3])
            let handle: Int = try X.int(String(path.split(separator: "/")[1])) + 1
            ctx.statsRows.append((handle, q))
            // An append at the end of the time line extends the snapshot; anything else is a full recompute
            ctx.stats = ctx.stats.appending(q) ?? ContestStats.of(ctx.statsRows.map(\.qso))
            return 4
        case "E":
            let index: Int = try statsIndex(f[1], ctx)
            if f[2] == "band" {
                ctx.statsRows[index].qso.band = band(f[3])
            } else {
                ctx.statsRows[index].qso.timestampUtc = date(millis: try X.int64(f[3]))
            }
            ctx.stats = ContestStats.of(ctx.statsRows.map(\.qso))
            return 4
        case "D":
            ctx.statsRows.remove(at: try statsIndex(f[1], ctx))
            ctx.stats = ContestStats.of(ctx.statsRows.map(\.qso))
            return 2
        default:
            throw X.Malformed(text: "stats step \(f[0])")
        }
    }

    static func statsIndex(_ field: String, _ ctx: Ctx) throws -> Int {
        let handle: Int = try X.int(field)
        guard let index = ctx.statsRows.firstIndex(where: { $0.handle == handle }) else {
            throw X.Malformed(text: "no stats row \(handle)")
        }
        return index
    }

    /// `LogSections.statsOut`: the snapshot queries, then `OperatingGuard.check` over the grid.
    static func statsOut(_ ctx: Ctx, _ now1: JavaInstant, _ now2: JavaInstant) -> [String] {
        let st: ContestStats = ctx.stats
        let last: Band? = st.lastQsoBand()
        var f: [String] = [adif(last), text(st.firstQsoAt()), text(st.lastQsoAt())]
        f.append(text(st.currentBandRunStart(last)))
        f.append(String(st.bandChangesInClockHour(now1)))
        f.append(String(st.rateForLastQsos(10)))
        f.append(String(st.rateThisClockHour(now2)))
        for now in [now1, now2] {
            for rules in ctx.rules {
                for band in ctx.probeBands {
                    f.append(F.tx(OperatingGuard.check(st, rules, band, now, .none, false)))
                }
            }
        }
        f.append(F.tx(OperatingGuard.check(st, nil, .m20, now1, .mult, false)))
        f.append(F.tx(OperatingGuard.check(st, nil, .m20, now1, .mult, true)))
        return f
    }

    // MARK: - marks.LOG

    static func marks(_ path: String, _ f: [String], _ ctx: Ctx) throws -> Rows {
        let parts: [Substring] = path.split(separator: "/")
        if parts.count == 2 {
            let runtime: ContestRuntime = ctx.environment.runtime(dxcc: ctx.environment.dxcc)
            if let failed = runtime.activate(id: X.text(f[0]) ?? "") {
                throw X.Malformed(text: failed.czech)
            }
            ctx.runtime = runtime
            ctx.markRows = []
            ctx.tracker = QsoMarksTracker(fresh: try fresh(runtime))
            return []
        }
        guard let runtime = ctx.runtime, let tracker = ctx.tracker else {
            throw X.Malformed(text: "no active runtime at \(path)")
        }
        switch f[0] {
        case "A":
            let q: Qso = try markQso(f, from: 1)
            ctx.markRows.append(q)
            // The append is replayed into the tracker; a refused one (an earlier or no time) is a full recompute
            if !tracker.append(q, now: { replayNow }) {
                ctx.tracker = try recomputed(runtime, ctx.markRows)
            }
        case "E":
            let q: Qso = try markQso(f, from: 2)
            guard let index = ctx.markRows.firstIndex(where: { $0.id == q.id }) else {
                throw X.Malformed(text: "no row \(f[1])")
            }
            ctx.markRows[index] = q
            ctx.tracker = try recomputed(runtime, ctx.markRows)
        case "D":
            let id: Int64 = try X.int64(f[1])
            ctx.markRows.removeAll { $0.id == id }
            ctx.tracker = try recomputed(runtime, ctx.markRows)
        default:
            throw X.Malformed(text: "marks step \(f[0])")
        }
        return [(path, markOut(ctx.tracker?.marks ?? [:]))]
    }

    static func fresh(_ runtime: ContestRuntime) throws -> ContestSession {
        guard let session = runtime.freshSession() else { throw X.Malformed(text: "no fresh session") }
        return session
    }

    static func recomputed(_ runtime: ContestRuntime, _ rows: [Qso]) throws -> QsoMarksTracker {
        QsoMarksTracker.recomputed(fresh: try fresh(runtime), qsos: rows, now: { replayNow })
    }

    /// `LogSections.qsoFields` from index `start`.
    static func markQso(_ f: [String], from start: Int) throws -> Qso {
        var q = Qso()
        q.id = try X.int64(f[start])
        q.call = X.text(f[start + 1]) ?? ""
        q.band = band(f[start + 2])
        q.mode = Mode(rawValue: f[start + 3])
        q.exchangeRcvd = X.text(f[start + 4]) ?? ""
        q.serialRcvd = f[start + 5] == "~" ? nil : try X.int(f[start + 5])
        if f[start + 6] != "~" {
            q.timestampUtc = date(millis: try X.int64(f[start + 6]))
        }
        q.xqso = X.bool(f[start + 7])
        q.exchangeSent = X.text(f[start + 8]) ?? ""
        return q
    }

    static func markOut(_ marks: [Int64: QsoMarks.Mark]) -> [String] {
        var out: [String] = [String(marks.count)]
        for id in marks.keys.sorted() {
            guard let mark = marks[id] else { continue }
            out.append(String(id))
            out.append(String(mark.points))
            out.append(X.b(mark.dupe))
            out.append(F.tx(mark.newMults.joined(separator: ",")))
        }
        return out
    }

    // MARK: - edit.CELL

    static func edit(_ f: [String]) throws -> [String] {
        let qso: Qso = try editQso(f)
        guard let column = LogTableEdit.Column(rawValue: try X.int(f[13])) else {
            throw X.Malformed(text: "column \(f[13])")
        }
        let edited: Qso = LogTableEdit.apply(column: column, text: X.text(f[14]) ?? "", to: qso)
        return editFields(edited)
    }

    /// `LogSections.editFields` back into a QSO.
    static func editQso(_ f: [String]) throws -> Qso {
        var q = Qso()
        q.id = try X.int64(f[0])
        if f[1] != "~" {
            let parts: [Substring] = f[1].split(separator: ".")
            guard parts.count == 2, let seconds = Int64(parts[0]), let nanos = Int64(parts[1]),
                  let at = JavaInstant.ofEpochSecond(seconds, nanos) else { throw X.Malformed(text: f[1]) }
            q.timestampUtc = at.date
        }
        q.call = X.text(f[2]) ?? ""
        q.freqHz = try X.int(f[3])
        q.band = band(f[4])
        q.mode = Mode(rawValue: f[5])
        q.rstSent = X.text(f[6]) ?? ""
        q.rstRcvd = X.text(f[7]) ?? ""
        q.serialSent = f[8] == "~" ? nil : try X.int(f[8])
        q.serialRcvd = f[9] == "~" ? nil : try X.int(f[9])
        q.exchangeRcvd = X.text(f[10]) ?? ""
        q.comment = X.text(f[11]) ?? ""
        q.xqso = X.bool(f[12])
        return q
    }

    static func editFields(_ q: Qso) -> [String] {
        var f: [String] = [q.id.map { String($0) } ?? "~"]
        f.append(q.timestampUtc.map { text(JavaInstant(date: $0)) } ?? "~")
        f.append(F.tx(q.call))
        f.append(String(q.freqHz))
        f.append(adif(q.band))
        f.append(q.mode?.rawValue ?? "~")
        f.append(F.tx(q.rstSent))
        f.append(F.tx(q.rstRcvd))
        f.append(q.serialSent.map { String($0) } ?? "~")
        f.append(q.serialRcvd.map { String($0) } ?? "~")
        f.append(F.tx(q.exchangeRcvd))
        f.append(F.tx(q.comment))
        f.append(X.b(q.xqso))
        return f
    }
}
