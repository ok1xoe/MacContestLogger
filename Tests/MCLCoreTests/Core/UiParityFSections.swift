import Foundation
import Testing
@testable import MCLCore

/// Swift side of the Java parity suite (maintainer-only probe, fixture `f`): replays the input rows of `ui-f-java.json.gz` against the
/// spot and band map core:
///
/// - `spot.STATUS` — `SpotAnalyzer.spotStatus`, `isColorRelevant`, `spotCategory`, `resolveSpotMode` and
///   `bandPlanCategory` over the corpus in seven contexts, each with a seeded log of the generator;
/// - `spot.ROWS` — `spotRows`, `AvailableMults.filter`/`matrix`/`sorted` and `SpotModeCategory.of`;
/// - `mult.GRID` — `multiplierGrid` for every kind;
/// - `spot.TIP` — `spotTooltip` and `predictExchange` with callbook records and without;
/// - `bandmap.LAYOUT` — `BandmapViewport.niceStepHz`, `BandmapLayout.place`/`hitSpot`/`azimuthOf`;
/// - `spot.ACT` — `SpotActions` (mark, remove, spot to the cluster, SPOTME, store), `SpotBuffer` and
///   `SelfSpotTracker`, composed in the order of the entry window's effects.
///
/// The spots come from the synthetic corpus `Fixtures/ui-gate/spots-f.txt` of the bundle (the generator writes it):
/// the rows that carry a corpus spot are rebuilt from Swift's own copy, and the `defs` and `corpus` rows are Swift's
/// own too — an edited corpus or definition changes the input checksum and the gate asks for regeneration instead of
/// reporting a mismatch. No socket, no callbook client, no browser: the cluster of `spot.ACT` is a connected flag.
enum UiParityFSections {

    typealias Entry = JavaYamlParityTests.ReferenceFile
    typealias Rows = [(String, [String])]
    typealias X = JavaCoreParityFixture
    typealias F = JavaIoParityFixture
    typealias U = UiParitySections

    static let names: [String] = ["spot.STATUS", "spot.ROWS", "mult.GRID", "spot.TIP", "bandmap.LAYOUT", "spot.ACT"]

    static let myCall = "OK1XOE"
    static let myGrid = "JN79"
    /// 2026-10-03T12:00:00Z, the instant of the generator's seeded log and of the spot buffer's clock.
    static let atMillis: Int64 = 1_791_028_800_000
    static let kinds: [String] = ["dxcc", "grid", "itu", "cq", "districts", "sections", "other", "bogus"]
    static let matrixBands: [Band] = [.m160, .m80, .m40, .m20, .m15, .m10]

    // MARK: - the DXCC with coordinates

    /// The real resolver plus the generator's deterministic coordinates per entity code (`SpotSections.Located`).
    struct Located: DxccLookup {
        let base: any DxccLookup

        static func lat(_ code: Int) -> Double {
            code == 1 ? Double.nan : Double((code * 37) % 1_400 - 700) / 10.0
        }

        static func lon(_ code: Int) -> Double {
            code == 1 ? Double.nan : Double((code * 91) % 3_400 - 1_700) / 10.0
        }

        static func located(_ e: DxccEntity) -> DxccEntity {
            DxccEntity(entityCode: e.entityCode, name: e.name, countryCode: e.countryCode, continents: e.continents,
                       cq: e.cq, itu: e.itu, lat: lat(e.entityCode), lon: lon(e.entityCode),
                       primaryPrefix: e.primaryPrefix, adifDxcc: e.adifDxcc)
        }

        func resolve(_ callsign: String?) -> DxccEntity? {
            base.resolve(callsign).map(Self.located)
        }

        func entities() -> [DxccEntity] {
            base.entities().map(Self.located)
        }
    }

    // MARK: - the corpus

    struct Spot: Sendable {
        let spotter: String
        let freq: Int
        let call: String
        let comment: String
        let selfSpotted: Bool

        var dx: DxSpot {
            DxSpot(spotter: spotter, freqHz: freq, dxCall: call, comment: comment, selfSpotted: selfSpotted)
        }

        /// The input fields of a row: spotter, frequency, call, comment, self flag.
        var fields: [String] {
            [F.tx(spotter), String(freq), F.tx(call), F.tx(comment), X.b(selfSpotted)]
        }
    }

    /// The corpus file: lines `spotter TAB freq TAB call TAB comment TAB 0|1`, ASCII.
    static func parseCorpus(_ text: String) throws -> [Spot] {
        var spots: [Spot] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let f: [Substring] = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard f.count == 5, let freq = Int(f[1]) else { throw X.Malformed(text: String(line)) }
            spots.append(Spot(spotter: String(f[0]), freq: freq, call: String(f[2]), comment: String(f[3]),
                              selfSpotted: f[4] == "1"))
        }
        return spots
    }

    /// The environment shared by all items (read-only after creation).
    struct Environment: @unchecked Sendable {
        let base: U.Environment
        let dxcc: Located
        let data: URL
        let bandPlan: BandPlan
        let digi: DigiFrequencies
        let gridDb: GridDatabase
        let fieldMap: GridFieldMap
        let spots: [Spot]
        let corpusSha: String

        static func load() throws -> Environment {
            let base: U.Environment = try U.Environment.load()
            let dxcc = Located(base: base.dxcc)
            let data: URL = try ContestDataLayoutTests.contestDataRoot()
            let gate: URL = try #require(Bundle.module.url(forResource: "ui-gate", withExtension: nil))
            let file: Data = try Data(contentsOf: gate.appendingPathComponent("spots-f.txt"))
            let spots: [Spot] = try parseCorpus(String(decoding: file, as: UTF8.self))
            return Environment(base: base, dxcc: dxcc, data: data, bandPlan: BandPlan.fromDir(data),
                               digi: DigiFrequencies.fromDir(data), gridDb: GridDatabase.fromDir(data),
                               fieldMap: GridFieldMap.fromDir(data, dxcc), spots: spots,
                               corpusSha: JavaYamlParityTests.sha256Hex(file))
        }

        var defsRow: String {
            base.defsRow(for: "ctl.RUN")
        }

        var corpusRow: String {
            F.line("corpus", "in", [corpusSha, String(spots.count)])
        }

        func runtime() -> ContestRuntime {
            ContestRuntime(dxcc: dxcc, registry: base.registry, contestsDir: base.contestsDir,
                           myCall: { UiParityFSections.myCall }, myGrid: { UiParityFSections.myGrid })
        }
    }

    // MARK: - replay

    /// The state of one item between its rows.
    final class Ctx {
        let environment: Environment
        var runtime: ContestRuntime?
        var useBook = false
        var book: [String: HamQthRecord] = [:]
        var cached: SpotAnalyzer?
        var rows: [SpotRow] = []
        var act = Act()

        init(_ environment: Environment) {
            self.environment = environment
        }

        func analyzer() throws -> SpotAnalyzer {
            if let cached { return cached }
            guard let runtime else { throw X.Malformed(text: "no context before the row") }
            let records: [String: HamQthRecord] = useBook ? book : [:]
            let callbook: @Sendable (String) -> HamQthRecord? = { call in
                guard let record = records[SpotAnalyzer.callbookKey(call)], !record.isEmpty else { return nil }
                return record
            }
            let made = SpotAnalyzer(runtime: runtime, bandPlan: environment.bandPlan, digiFrequencies: environment.digi,
                                    gridDatabase: environment.gridDb, gridFieldMap: environment.fieldMap,
                                    callbook: callbook, gridLog: SpotGridLog { _ in },
                                    now: { Date(timeIntervalSince1970: Double(UiParityFSections.atMillis) / 1000) })
            cached = made
            return made
        }
    }

    /// One computed row: the input row when Swift rebuilds it (a corpus spot), and the outputs.
    struct Step {
        var input: [String]?
        var rows: Rows
    }

    static func replay(_ java: Entry, _ environment: Environment) -> Entry {
        let ctx = Ctx(environment)
        var lines: [String] = []
        lines.reserveCapacity(java.lines.count)
        for line in java.lines {
            let fields: [String] = JavaEngineParityTests.fields(line)
            guard fields.count >= 2, fields[1] == "in" else { continue }
            if fields[0] == "defs" {
                lines.append(environment.defsRow)
                continue
            }
            if fields[0] == "corpus" {
                lines.append(environment.corpusRow)
                continue
            }
            let inputs: [String] = Array(fields.dropFirst(2))
            do {
                let step: Step = try compute(java.relative, fields[0], inputs, ctx)
                lines.append(step.input.map { F.line(fields[0], "in", $0) } ?? line)
                for (outPath, out) in step.rows {
                    lines.append(F.line(outPath, "out", out))
                }
            } catch {
                lines.append(line)
                lines.append(F.line(fields[0], "out", ["SWIFT ERROR", String(describing: error)]))
            }
        }
        let sum: String = F.checksum(definition: nil, registry: "", lines: lines)
        return Entry(relative: java.relative, sha256: sum, lines: lines)
    }

    static func replayAll(_ reference: [Entry]) async throws -> [Entry] {
        let environment: Environment = try Environment.load()
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

    static func compute(_ name: String, _ path: String, _ f: [String], _ ctx: Ctx) throws -> Step {
        switch name {
        case "spot.STATUS": return try status(path, f, ctx)
        case "spot.ROWS": return try rows(path, f, ctx)
        case "mult.GRID": return try grid(path, f, ctx)
        case "spot.TIP": return try tooltip(path, f, ctx)
        case "bandmap.LAYOUT": return try layout(path, f, ctx)
        case "spot.ACT": return try action(path, f, ctx)
        default: throw X.Malformed(text: "unknown item \(name)")
        }
    }

    static func text(_ field: String) -> String {
        X.text(field) ?? ""
    }

    static func int64(_ field: String) throws -> Int64 {
        guard let value = Int64(field) else { throw X.Malformed(text: field) }
        return value
    }

    static func int(_ field: String) throws -> Int {
        guard let value = Int(field) else { throw X.Malformed(text: field) }
        return value
    }

    static func pad(_ n: Int, _ width: Int) -> String {
        let s = String(n)
        return String(repeating: "0", count: Swift.max(0, width - s.count)) + s
    }

    static func floatFromBits(_ hex: String) throws -> Float {
        guard let bits = UInt32(hex, radix: 16) else { throw X.Malformed(text: hex) }
        return Float(bitPattern: bits)
    }

    static func bits(_ value: Float) -> String {
        String(value.bitPattern, radix: 16)
    }

    static func spot(_ index: Int, _ ctx: Ctx) throws -> Spot {
        guard ctx.environment.spots.indices.contains(index) else { throw X.Malformed(text: "spot \(index)") }
        return ctx.environment.spots[index]
    }

    // MARK: - contexts

    /// Row `c/<id>` (or `c/<id>/cb|nocb`): opens the context and the seeded log `<row>/q/NNN` follows.
    static func isSetup(_ path: String) -> Bool {
        let parts: [Substring] = path.split(separator: "/")
        if parts.count == 2 { return true }
        return parts.count == 3 && (parts[2] == "cb" || parts[2] == "nocb")
    }

    static func setup(_ path: String, _ f: [String], _ ctx: Ctx) throws -> Step {
        let id: String = text(f[0])
        let runtime: ContestRuntime = ctx.environment.runtime()
        ctx.runtime = runtime
        ctx.cached = nil
        ctx.useBook = path.hasSuffix("/cb")
        let activation: String = id == "none" ? "~" : F.tx(runtime.activate(id: id)?.czech)
        let analyzer: SpotAnalyzer = try ctx.analyzer()
        return Step(input: nil, rows: [(path, [activation, X.b(analyzer.needsHamQthLookup),
                                                X.b(analyzer.needsGridLookup)])])
    }

    /// Row `<setup>/q/NNN`: one logged QSO of the seeded log.
    static func logged(_ path: String, _ f: [String], _ ctx: Ctx) throws -> Step {
        guard let runtime = ctx.runtime else { throw X.Malformed(text: "no context at \(path)") }
        let call: String = text(f[0])
        let band: String = text(f[1])
        let mode: String = text(f[2])
        let (exchange, next) = try U.linkedMap(f, from: 3)
        let at = Date(timeIntervalSince1970: Double(try int64(f[next])) / 1000)
        var out: [String] = []
        do {
            let result = try runtime.log(call: call, band: band, mode: mode, exchange: exchange, ownQth: nil, at: at)
            out += U.result(result)
        } catch {
            out.append(F.tx(U.thrown(error)))
        }
        out += U.score(runtime.score)
        return Step(input: nil, rows: [(path, out)])
    }

    static func isLog(_ parts: [Substring]) -> Bool {
        parts.count >= 3 && parts[parts.count - 2] == "q"
    }

    // MARK: - spot.STATUS

    static func status(_ path: String, _ f: [String], _ ctx: Ctx) throws -> Step {
        let parts: [Substring] = path.split(separator: "/")
        if isSetup(path) { return try setup(path, f, ctx) }
        if isLog(parts) { return try logged(path, f, ctx) }
        let index: Int = try int(f[0])
        let sp: Spot = try spot(index, ctx)
        let analyzer: SpotAnalyzer = try ctx.analyzer()
        let dx: DxSpot = sp.dx
        let state = analyzer.spotStatus(dx)
        let plan = analyzer.bandPlanCategory(Int64(sp.freq))
        let out: [String] = [
            X.b(state.dupe), String(state.newMultCount), X.b(state.newMult), X.b(analyzer.isColorRelevant(dx)),
            F.tx(analyzer.spotCategory(dx)),
            F.tx(analyzer.resolveSpotMode(call: sp.call, freqHz: sp.freq, comment: sp.comment)),
            plan?.rawValue ?? "~",
        ]
        return Step(input: [String(index)] + sp.fields, rows: [(path, out)])
    }

    // MARK: - spot.ROWS

    static func rowFields(_ r: SpotRow) -> [String] {
        [F.tx(r.call), String(r.freqHz), r.azimuth.map { String($0) } ?? "~", F.tx(r.mode), String(r.newMultCount),
         X.b(r.dupe), r.snr.map { String($0) } ?? "~", String(r.points), F.tx(r.spotter), X.b(r.isMult)]
    }

    static func ids(_ rows: [SpotRow]) -> String {
        rows.map { $0.call + "@" + String($0.freqHz) }.joined(separator: " ")
    }

    static func rows(_ path: String, _ f: [String], _ ctx: Ctx) throws -> Step {
        if path.hasPrefix("mc/") {
            return Step(input: nil, rows: [(path, [SpotModeCategory.of(text(f[0]))])])
        }
        let parts: [Substring] = path.split(separator: "/")
        if isSetup(path) { return try setup(path, f, ctx) }
        if isLog(parts) { return try logged(path, f, ctx) }
        switch parts[2] {
        case "r":
            let analyzer: SpotAnalyzer = try ctx.analyzer()
            let all: [SpotRow] = analyzer.spotRows(ctx.environment.spots.map(\.dx))
            ctx.rows = all
            var out: Rows = []
            for (i, row) in all.enumerated() {
                out.append((path + "/" + pad(i, 3), rowFields(row)))
            }
            out.append((path, [String(all.count)]))
            return Step(input: [String(ctx.environment.spots.count)], rows: out)
        case "f":
            let bands: Set<Band> = Set(try text(f[1]).split(separator: " ").map { name -> Band in
                guard let band = Band.from(adif: String(name)) else { throw X.Malformed(text: "band \(name)") }
                return band
            })
            let modes = Set(text(f[2]).split(separator: " ").map(String.init))
            let kept: [SpotRow] = AvailableMults.filter(rows: ctx.rows, multsOnly: f[0] == "1", bands: bands,
                                                        modes: modes)
            var out: [String] = [String(kept.count)]
            let matrix: [Band?: AvailableMults.Counts] = AvailableMults.matrix(rows: kept)
            for band in matrixBands {
                let c: AvailableMults.Counts = matrix[band] ?? .zero
                out.append("\(c.mults)/\(c.qs)/\(c.total)")
            }
            for column in AvailableMults.SortColumn.allCases {
                for ascending in [true, false] {
                    out.append(ids(AvailableMults.sorted(kept, by: column, ascending: ascending)))
                }
            }
            return Step(input: nil, rows: [(path, out)])
        default:
            throw X.Malformed(text: "row \(path)")
        }
    }

    // MARK: - mult.GRID

    static func grid(_ path: String, _ f: [String], _ ctx: Ctx) throws -> Step {
        let parts: [Substring] = path.split(separator: "/")
        if isSetup(path) { return try setup(path, f, ctx) }
        if isLog(parts) { return try logged(path, f, ctx) }
        let kind: String = f[0]
        let analyzer: SpotAnalyzer = try ctx.analyzer()
        let g: MultGridView = analyzer.multiplierGrid(kind: kind, spots: ctx.environment.spots.map(\.dx))
        var out: Rows = [(path, [X.b(g.available), String(g.worked), String(g.possible), String(g.rows.count)])]
        for (idx, r) in g.rows.enumerated() {
            var cells = ""
            for band in SpotAnalyzer.multGridBands {
                if let cell = r.cells[band.adif], cell != .empty {
                    cells += band.adif + "=" + cell.rawValue + ","
                }
            }
            if !cells.isEmpty || idx == 0 || idx == g.rows.count - 1 {
                out.append((path + "/" + pad(idx, 4),
                            [F.tx(r.key), F.tx(r.label), F.tx(r.prefix), F.tx(r.continent), F.tx(cells)]))
            }
        }
        var at: [String] = g.spotAt.map { key, spot in
            key.key + "@" + key.band + "=" + spot.dxCall + "@" + String(spot.freqHz)
        }
        at.sort { JavaText.compare($0, $1) < 0 }
        out.append((path + "/at", [String(at.count), F.tx(at.joined(separator: ", "))]))
        return Step(input: [kind, String(ctx.environment.spots.count)], rows: out)
    }

    // MARK: - spot.TIP

    static func tooltip(_ path: String, _ f: [String], _ ctx: Ctx) throws -> Step {
        if path.hasPrefix("cb/") {
            ctx.book[text(f[0])] = HamQthRecord(grid: text(f[1]), name: text(f[2]), cqZone: text(f[3]),
                                                ituZone: text(f[4]))
            return Step(input: nil, rows: [])
        }
        let parts: [Substring] = path.split(separator: "/")
        if isSetup(path) { return try setup(path, f, ctx) }
        if isLog(parts) { return try logged(path, f, ctx) }
        let index: Int = try int(f[0])
        let sp: Spot = try spot(index, ctx)
        let analyzer: SpotAnalyzer = try ctx.analyzer()
        let dx: DxSpot = sp.dx
        let predicted: JavaLinkedMap<String> = analyzer.predictExchange(dx)
        var mapFields: [String] = [String(predicted.count)]
        for key in predicted.keys {
            mapFields.append(F.tx(key))
            mapFields.append(F.tx(predicted[key]))
        }
        return Step(input: [String(index)] + sp.fields,
                    rows: [(path, [F.tx(analyzer.spotTooltip(dx)), mapFields.joined(separator: " ")])])
    }

    // MARK: - bandmap.LAYOUT

    static func layout(_ path: String, _ f: [String], _ ctx: Ctx) throws -> Step {
        if path.hasPrefix("nice/") {
            return Step(input: nil, rows: [(path, [String(BandmapViewport.niceStepHz(try int64(f[0])))])])
        }
        if path.hasPrefix("az/") {
            let grid: String = text(f[0])
            let azimuth: Int? = BandmapLayout.azimuthOf(call: text(f[1]), myLatLon: Maidenhead.centerLatLon(grid),
                                                        dxcc: ctx.environment.dxcc)
            return Step(input: nil, rows: [(path, [azimuth.map { String($0) } ?? "~"])])
        }
        let lo: Int64 = try int64(f[0])
        let hi: Int64 = try int64(f[1])
        let height: Float = try floatFromBits(f[2])
        let rowH: Float = try floatFromBits(f[3])
        let count: Int = try int(f[4])
        var spots: [DxSpot] = []
        for i in 0..<count {
            let call: String = text(f[5 + 2 * i])
            spots.append(DxSpot(spotter: "S", freqHz: try int(f[6 + 2 * i]), dxCall: call, comment: "",
                                selfSpotted: false))
        }
        let start: Int = 5 + 2 * count
        let ysCount: Int = try int(f[start])
        let ys: [Float] = try (0..<ysCount).map { try floatFromBits(f[start + 1 + $0]) }
        let placed: [SpotPlacement] = BandmapLayout.place(spots: spots, viewport: BandmapViewport(loHz: lo, hiHz: hi),
                                                          height: height, rowH: rowH)
        let layout: [String] = placed.map { p in
            F.tx(p.spot.dxCall) + "@" + bits(p.trueY) + ">" + bits(p.labelY)
        }
        let hits: [String] = ys.map { y in
            BandmapLayout.hitSpot(placed, y: y, rowH: rowH).map { F.tx($0.spot.dxCall) } ?? "-"
        }
        return Step(input: nil, rows: [(path, layout), (path + "/hit", hits)])
    }

    // MARK: - spot.ACT

    /// What the entry window and the app keep for one run: the spot buffer, the call field, the tuned frequency,
    /// the tracker and the main cluster's connected flag.
    final class Act {
        let buffer = SpotBuffer(maxAgeMinutes: 90,
                                clock: { Date(timeIntervalSince1970: Double(UiParityFSections.atMillis) / 1000) })
        var connected = false
        var tuned: Int64 = 0
        var lastTuned: Int64 = 0
        var call = ""
        var tracker = SelfSpotTracker()
        var threshold: Int64 = 2_500
        var status = ""

        func nearest(_ freqHz: Int, _ toleranceHz: Int) -> DxSpot? {
            buffer.nearestWithin(freqHz, toleranceHz: toleranceHz)
        }

        func store(call: String, atHz: Int64) {
            if let spot = SpotActions.storeSpot(myCall: UiParityFSections.myCall, call: call, freqHz: atHz) {
                buffer.add(spot)
            }
        }

        /// The two effects after a state change: the anchor effect (`callChanged`), then the tuning effect when the
        /// tuned frequency changed.
        func settle() {
            tracker.callChanged(call, tunedFreqHz: tuned)
            guard tuned != lastTuned else { return }
            lastTuned = tuned
            let action = tracker.tunedChanged(tuned, call: call, thresholdHz: threshold) { nearest($0, $1) }
            switch action {
            case .selfSpot(let spotCall, let atHz)?:
                store(call: spotCall, atHz: atHz)
                call = ""
            case .prefill(let spotCall)?:
                call = spotCall
            case nil:
                break
            }
        }

        func snapshot() -> String {
            let parts: [String] = buffer.snapshot().map { d in
                d.dxCall + "\t" + String(d.freqHz) + "\t" + d.spotter + "\t" + d.comment + "\t"
                    + (d.selfSpotted ? "true" : "false")
            }
            return String(parts.count) + " " + F.tx(parts.joined(separator: "\n"))
        }
    }

    static func action(_ path: String, _ f: [String], _ ctx: Ctx) throws -> Step {
        let act: Act = ctx.act
        if path == "start" {
            return Step(input: nil, rows: [(path, [act.snapshot()])])
        }
        act.status = ""
        var extra: [String] = []
        switch f[0] {
        case "A":
            let spot = Spot(spotter: text(f[1]), freq: try int(f[2]), call: text(f[3]), comment: text(f[4]),
                            selfSpotted: X.bool(f[5]))
            act.buffer.add(spot.dx)
        case "M":
            let freq: Int64 = try int64(f[1])
            if let mark = SpotActions.markSpot(freqHz: freq) {
                act.buffer.add(mark)
                act.status = SpotActions.markStatus(freqHz: freq, translator: .source).czech
            }
        case "R":
            let call: String = text(f[1])
            if let target = SpotActions.removeTarget(call: call, tunedFreqHz: act.tuned, nearest: { act.nearest($0, $1) }) {
                act.buffer.remove(target)
                act.status = SpotActions.removed(target, blacklist: false).czech
            } else {
                act.status = EntryStatus.tr(SpotActions.removeNoSpot).czech
            }
        case "S":
            let outcome = SpotActions.clusterCommand(call: text(f[1]), freqHz: try int64(f[2]), comment: text(f[3]),
                                                     connected: act.connected)
            switch outcome {
            case .accepted(let command):
                act.status = SpotActions.sent(command).czech
                extra = [X.b(true)]
            case .rejected(let status):
                act.status = status.czech
                extra = [X.b(false)]
            }
        case "P":
            let comment: String = SpotActions.spotMeComment(text(f[2]))
            let outcome = SpotActions.clusterCommand(call: myCall, freqHz: try int64(f[1]), comment: comment,
                                                     connected: act.connected)
            switch outcome {
            case .accepted(let command): act.status = SpotActions.spotMeSent(command).czech
            case .rejected(let status): act.status = status.czech
            }
        case "F":
            act.store(call: text(f[1]), atHz: try int64(f[2]))
        case "C":
            act.connected = X.bool(f[1])
        case "X":
            act.buffer.clear()
        case "H":
            act.threshold = try int64(f[1])
        case "Y":
            act.call = text(f[1])
            act.tracker.typed()
            act.settle()
        case "B":
            act.call = text(f[1])
            act.tracker.prefilledFromSpot()
            act.settle()
        case "W":
            act.call = ""
            act.tracker.typed()
            act.settle()
        case "Z":
            act.tuned = try int64(f[1])
            act.settle()
        default:
            throw X.Malformed(text: "op \(f[0])")
        }
        let out: [String] = [F.tx(act.status)] + extra + [
            F.tx(act.call), String(act.tracker.anchorHz), X.b(act.tracker.callFromSpot), act.snapshot(),
        ]
        return Step(input: nil, rows: [(path, out)])
    }
}
