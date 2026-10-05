import Foundation
import Testing
@testable import MCLCore

/// Swift side of the Java parity suite (maintainer-only probe, fixture `h`): replays the input rows of `ui-h-java.json.gz` against the
/// info, statistics and tool core (the product code):
///
/// - `info.TIMERS` — `InfoTimers` (the formatters, the five off time modes, the time on band, the band change counter);
/// - `info.LINES` — `InfoLines`, `GoalStatus`, `RatePanel` (the country, sun and day lines, the callsign info, the WWV and
///   spot lines, the header, the short-term rates, the trend);
/// - `goals.EDIT` — `GoalEditing` (hour labels and keys, the draft, the filter, save, bulk fill, import, fixed texts);
/// - `stats.VIEWS` — `StatsViews`, `ContestRuntime.breakdown`, `InfoTimers.rules`, the score table and the dupesheet;
/// - `sked.WATCH` — `SkedEditing`, `SkedWatch`, `TourWatch`;
/// - `qtc.SESSION` — `QtcSession`, `BandNotesEditing`, `MoveRequest`, `ContestRuntime.moveCandidates`;
/// - `map.WORLD` — `WorldMapModel`, `MapPalette`, `PropagationRows`, `MultGridLayout`;
/// - `sim.SESSION` — `SimulatorSession` over `PileupSimulator` with `java.util.Random`.
///
/// The logs, rules, goal sets, spots and the map file come from the synthetic corpus `Fixtures/ui-gate/tools-h.txt`
/// of the bundle (the generator writes it): the `defs` and `corpus` rows are Swift's own, so an edited corpus or
/// definition changes the input checksum and the gate asks for regeneration instead of reporting a mismatch. Every
/// other input row (the scenario) is taken from the reference; its single output is computed here. The texts are
/// the raw ones: the reference holds them as `tx` writes them. No audio device, key, socket or URL: the simulator is
/// a model over a seeded random, the CW of a move request is only a text, the map a synthetic geometry.
enum UiParityHSections {

    typealias Entry = JavaYamlParityTests.ReferenceFile
    typealias F = JavaIoParityFixture
    typealias X = JavaCoreParityFixture
    typealias U = UiParitySections
    typealias P = ToolsParity
    typealias T = InfoProbeTable

    static let names: [String] = ["info.TIMERS", "info.LINES", "goals.EDIT", "stats.VIEWS", "sked.WATCH", "qtc.SESSION",
                                  "map.WORLD", "sim.SESSION"]

    // MARK: - the corpus

    struct SpotRecord: Sendable {
        let delayMillis: Int64
        let spotter: String
        let freqHz: Int
        let call: String
        let comment: String
    }

    /// The corpus file: lines `KIND TAB field…`, ASCII, the fields as `tx` writes them.
    struct Corpus: Sendable {
        var baseMillis: Int64 = 0
        var contestStartMillis: Int64 = 0
        var logs: [String: [Qso]] = [:]
        var rules: [String: ContestDefinition.Operating?] = [:]
        var goals: [String: [Int32: Int32]] = [:]
        var spots: [SpotRecord] = []
        var geo = ""
        var sha = ""
        var kinds: [(String, Int)] = []

        var counts: String {
            kinds.map { $0.0 + "=" + String($0.1) }.joined(separator: " ")
        }

        var contestStart: JavaInstant {
            T.instant(millis: contestStartMillis)
        }

        static func parse(_ data: Data) throws -> Corpus {
            var corpus = Corpus()
            corpus.sha = JavaYamlParityTests.sha256Hex(data)
            let text = String(decoding: data, as: UTF8.self)
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                let parts: [String] = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                if let index = corpus.kinds.firstIndex(where: { $0.0 == parts[0] }) {
                    corpus.kinds[index].1 += 1
                } else {
                    corpus.kinds.append((parts[0], 1))
                }
                try corpus.add(parts)
            }
            return corpus
        }

        private func untx(_ field: String) -> String {
            F.untx(field) ?? ""
        }

        mutating func add(_ f: [String]) throws {
            switch f[0] {
            case "CONST":
                baseMillis = try X.int64(f[1])
                contestStartMillis = try X.int64(f[2])
            case "LOG":
                let joined: String = untx(f[2])
                logs[f[1]] = joined.isEmpty ? [] : joined.split(separator: ";", omittingEmptySubsequences: false)
                    .map { T.qso(String($0)) }
            case "RULE":
                rules[f[1]] = try Self.operating(f[2])
            case "GOAL":
                var entries: [Int32: Int32] = [:]
                for item in f[2].split(separator: ",") {
                    let pair = item.split(separator: "=").map(String.init)
                    entries[try X.int32(pair[0])] = try X.int32(pair[1])
                }
                goals[f[1]] = entries
            case "SPOT":
                spots.append(SpotRecord(delayMillis: try X.int64(f[1]), spotter: untx(f[2]), freqHz: try X.int(f[3]),
                                        call: untx(f[4]), comment: untx(f[5])))
            case "GEO":
                geo = untx(f[1])
            default:
                throw X.Malformed(text: f[0])
            }
        }

        /// `off=<min>/<required> band=<min>/<perHour>`, `~` = null; `none` = no rules.
        static func operating(_ text: String) throws -> ContestDefinition.Operating? {
            if text == "none" { return nil }
            let parts: [String] = text.split(separator: " ").map(String.init)
            func pair(_ value: Substring) -> (Int?, Int?) {
                let halves = value.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
                return (halves[0] == "~" ? nil : Int(halves[0]), halves[1] == "~" ? nil : Int(halves[1]))
            }
            let off = pair(parts[0].dropFirst(4))
            let band = pair(parts[1].dropFirst(5))
            let offTime: ContestDefinition.OffTime? = off.0 == nil && off.1 == nil
                ? nil : ContestDefinition.OffTime(minimumMinutes: off.0, requiredMinutes: off.1)
            let bandChange: ContestDefinition.BandChange? = band.0 == nil && band.1 == nil
                ? nil : ContestDefinition.BandChange(minimumMinutes: band.0, perHour: band.1)
            return ContestDefinition.Operating(offTime: offTime, bandChange: bandChange)
        }

        func goalSet(_ name: String) -> GoalSet {
            GoalSet.of(goals[name] ?? [:])
        }
    }

    /// The environment shared by all items (read-only after creation).
    struct Environment: @unchecked Sendable {
        let base: U.Environment
        let corpus: Corpus

        static func load() throws -> Environment {
            let base: U.Environment = try U.Environment.load()
            let gate: URL = try #require(Bundle.module.url(forResource: "ui-gate", withExtension: nil))
            let file: Data = try Data(contentsOf: gate.appendingPathComponent("tools-h.txt"))
            return Environment(base: base, corpus: try Corpus.parse(file))
        }

        var defsRow: String {
            base.defsRow(for: "ctl.RUN")
        }

        var corpusRow: String {
            F.line("corpus", "in", [F.tx(corpus.sha), F.tx(corpus.counts)])
        }
    }

    // MARK: - state between the rows of one item

    struct QtcState {
        var records: [QtcRecord] = []
        var nextId: Int64 = 1
    }

    struct SimState {
        let session: SimulatorSession
    }

    final class Ctx {
        let environment: Environment
        private var statsByLog: [String: ContestStats] = [:]
        var spots: SpotBuffer?
        let clock = InfoLinesTests.ClockBox(0)

        // stats.VIEWS: one runtime, activated as the rows ask
        var views: SpotAnalysisFixture.Environment?
        var activeContest: String?

        // sked.WATCH
        var skedFirst: [String] = []
        var skedStatus = ""
        var skedSecond = 0
        var tourMessages: [String: [String]] = [:]
        var tourSessions = ""

        // qtc.SESSION
        var qtcStates: [String: QtcState] = [:]
        var moveEnv: SpotAnalysisFixture.Environment?

        // map.WORLD
        var gridRows: [MultGridRow] = []

        // sim.SESSION
        var sessions: [String: SimulatorSession] = [:]

        init(_ environment: Environment) {
            self.environment = environment
        }

        func stats(_ log: String) -> ContestStats {
            if let cached = statsByLog[log] { return cached }
            let made = ContestStats.of(environment.corpus.logs[log] ?? [])
            statsByLog[log] = made
            return made
        }

        func viewsEnvironment() throws -> SpotAnalysisFixture.Environment {
            if let views { return views }
            let made = try SpotAnalysisFixture.environment()
            views = made
            return made
        }

        /// The runtime of `stats.VIEWS` with `id` active (`nil` = the one without a contest).
        func runtime(_ id: String?) throws -> ContestRuntime {
            let env: SpotAnalysisFixture.Environment = try viewsEnvironment()
            if let id, activeContest != id {
                if let error = env.runtime.activate(id: id) {
                    throw X.Malformed(text: "activation of \(id): \(error.czech)")
                }
                activeContest = id
            }
            return env.runtime
        }
    }

    // MARK: - replay

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
            lines.append(line)
            // `<area>/NNNNN`: the area names the measured function, the number makes the row unique
            let path: String = fields[0]
            let area: String = String(path.prefix { $0 != "/" })
            let input: String = fields.count > 2 ? (F.untx(fields[2]) ?? "") : ""
            do {
                let result: String = try compute(java.relative, area, input, ctx)
                lines.append(F.line(path, "out", [F.tx(result)]))
            } catch {
                lines.append(F.line(path, "out", ["SWIFT ERROR", String(describing: error)]))
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

    static func compute(_ item: String, _ area: String, _ input: String, _ ctx: Ctx) throws -> String {
        switch item {
        case "info.TIMERS": return try timers(area, input, ctx)
        case "info.LINES": return try infoLines(area, input, ctx)
        case "goals.EDIT": return try goals(area, input, ctx)
        case "stats.VIEWS": return try statistics(area, input, ctx)
        case "sked.WATCH": return try sked(area, input, ctx)
        case "qtc.SESSION": return try qtc(area, input, ctx)
        case "map.WORLD": return try world(area, input, ctx)
        case "sim.SESSION": return try sim(area, input, ctx)
        default: throw X.Malformed(text: "unknown item \(item)")
        }
    }

    // MARK: - field helpers

    static func parts(_ input: String, _ separator: Character = "|") -> [String] {
        input.split(separator: separator, omittingEmptySubsequences: false).map(String.init)
    }

    static func field(_ f: [String], _ index: Int) throws -> String {
        guard f.indices.contains(index) else { throw X.Malformed(text: "field \(index) of \(f)") }
        return f[index]
    }

    static func statusName(_ s: GoalStatus) -> String {
        RatePanelTests.statusName(s)
    }

    // MARK: - info.TIMERS

    static func timers(_ area: String, _ input: String, _ ctx: Ctx) throws -> String {
        let corpus: Corpus = ctx.environment.corpus
        switch area {
        case "hm":
            return InfoTimers.hm(try X.int64(input))
        case "hms":
            return InfoTimers.hms(try X.int64(input))
        case "elapsed":
            let p: [Int64] = try parts(input, " ").map { try X.int64($0) }
            guard let since = JavaInstant.ofEpochSecond(p[0]), let now = JavaInstant.ofEpochSecond(p[1]) else {
                throw X.Malformed(text: input)
            }
            return InfoTimers.elapsed(since: since, now: now)
        case "suffix":
            let minutes: Int? = input == "~" ? nil : try X.int(input)
            return "[" + InfoTimers.suffix(minutes) + "]"
        case "offtime":
            let f: [String] = parts(input)
            let now: JavaInstant = T.instant(millis: try X.int64(f[1]))
            let start: JavaInstant? = f[4] == "S" ? corpus.contestStart : nil
            let cell = InfoTimers.offTime(mode: f[2], stats: ctx.stats(f[0]), now: now,
                                          rules: corpus.rules[f[3]] ?? nil, contestStart: start)
            return "label=" + cell.label + ";value=" + (cell.value ?? "~") + ";ok=" + String(cell.state == .ok)
        case "onband":
            let f: [String] = parts(input)
            let now: JavaInstant = T.instant(millis: try X.int64(f[1]))
            let tuned: Band? = f[2] == "-" ? nil : Band.from(adif: f[2])
            let since: Int64 = try X.int64(f[3])
            let tunedSince: JavaInstant? = since < 0 ? nil : JavaInstant.ofEpochSecond(now.epochSecond - since)
            guard let cell = InfoTimers.onBand(band: tuned, stats: ctx.stats(f[0]), tunedSince: tunedSince, now: now,
                                               rules: corpus.rules[f[4]] ?? nil) else { return "none" }
            return "label=" + cell.label + ";value=" + (cell.value ?? "~") + ";ok=" + String(cell.state == .ok)
        case "bandchg":
            let f: [String] = parts(input)
            let now: JavaInstant = T.instant(millis: try X.int64(f[1]))
            guard let cell = InfoTimers.bandChanges(stats: ctx.stats(f[0]), now: now, rules: corpus.rules[f[2]] ?? nil)
            else { return "none" }
            let state: String
            switch cell.state {
            case .over: state = "over"
            case .warn: state = "warn"
            case .ok: state = "ok"
            case .none: state = "none"
            }
            return "label=" + cell.label + ";value=" + (cell.value ?? "~") + ";state=" + state
        default:
            throw X.Malformed(text: "area \(area)")
        }
    }

    // MARK: - info.LINES

    static func infoLines(_ area: String, _ input: String, _ ctx: Ctx) throws -> String {
        let corpus: Corpus = ctx.environment.corpus
        switch area {
        case "country", "sun":
            let value: CallsignInfo? = input == "null" ? nil : InfoLinesTests.info(input)
            let line: String = area == "country" ? InfoLines.country(value) : InfoLines.sun(value)
            return input == "null" ? "[" + line + "]" : line
        case "dayShort":
            if input == "null" { return "[" + InfoLines.dayShort(nil) + "]" }
            let day = CallsignInfo.DayOfWeek.allCases.first { $0.javaName == input }
            return InfoLines.dayShort(day)
        case "callinfo":
            let f: [String] = parts(input)
            let info = try InfoLines.callsignInfo(typedCall: f[0], lookup: SpotAnalysisFixture.dxcc(),
                                                  myLat: try JavaNetParityValues.double(f[1]), myLon: try JavaNetParityValues.double(f[2]),
                                                  now: T.instant(millis: try X.int64(f[3])))
            return InfoLines.country(info) + " // " + InfoLines.sun(info)
        case "wwv":
            if input == "null" { return "[" + InfoLines.wwv(nil) + "]" }
            let f: [String] = parts(input)
            let message = WwvMessage(spotter: f[0], hourUtc: try X.int(f[1]), sfi: try X.int(f[2]),
                                     aIndex: try X.int(f[3]), kIndex: try X.int(f[4]), conditions: f[5])
            return "[" + InfoLines.wwv(message) + "]"
        case "spot":
            let f: [String] = parts(input)
            if ctx.spots == nil {
                let clock = ctx.clock
                let buffer = SpotBuffer(maxAgeMinutes: 30, clock: { clock.date })
                for record in corpus.spots {
                    clock.set(corpus.baseMillis + record.delayMillis)
                    buffer.add(DxSpot(spotter: record.spotter, freqHz: record.freqHz, dxCall: record.call,
                                      comment: record.comment))
                }
                ctx.spots = buffer
            }
            let now: Int64 = try X.int64(f[1])
            ctx.clock.set(now)
            let line = InfoLines.spot(call: f[2], spots: try #require(ctx.spots), now: T.instant(millis: now),
                                      decimalSeparator: f[0] == "cs-CZ" ? "," : ".")
            return "[" + line + "]"
        case "header":
            let f: [String] = parts(input)
            let header = InfoLines.header(stationCall: f[0], sentExchange: f[1], operatorCall: f[2])
            return "[" + header.stationCall + "][" + (header.exchangeText ?? "") + "][" + header.operatorCall + "]"
        case "status":
            let f: [String] = parts(input)
            let goal: Int? = f[1] == "-" ? nil : try X.int(f[1])
            return statusName(GoalStatus.of(value: try X.int(f[0]), goal: goal))
        case "near":
            let f: [String] = parts(input)
            let goal: Int? = f[2] == "-" ? nil : try X.int(f[2])
            let panel = RatePanel.nearTerm(stats: ctx.stats(f[0]), now: T.instant(millis: try X.int64(f[1])), goal: goal)
            return RatePanelTests.nearText(panel)
        case "trend":
            let f: [String] = parts(input)
            let cfg: String = f[3]
            let start: JavaInstant? = cfg == "nostart" ? nil : corpus.contestStart
            let goals: GoalSet = corpus.goalSet(cfg == "off" || cfg == "nostart" ? "a" : cfg)
            let show: Bool = cfg != "off"
            let view = try RatePanel.trend(stats: ctx.stats(f[0]), now: T.instant(millis: try X.int64(f[1])),
                                           minutes: try X.int(f[2])) { at in
                RatePanel.goal(goals: goals, contestStart: start, showGoals: show, at: at)
            }
            return RatePanelTests.trendText(view)
        default:
            throw X.Malformed(text: "area \(area)")
        }
    }

    // MARK: - goals.EDIT

    static func keyText(_ keys: [Int32]) -> String {
        keys.map { String($0) }.joined(separator: ",")
    }

    static func goals(_ area: String, _ input: String, _ ctx: Ctx) throws -> String {
        let corpus: Corpus = ctx.environment.corpus
        switch area {
        case "hourLabel":
            return GoalEditing.hourLabel(try X.int32(input))
        case "hours":
            let f: [String] = parts(input)
            let start: JavaInstant? = f[0] == "~" ? nil : JavaInstant.ofEpochSecond(try X.int64(f[0]))
            return keyText(try GoalSet.hoursOf(start, try X.int32(f[1])))
        case "draft":
            // `hours=<keys> saved={k=v, …}`
            let hoursText: String = String(input.dropFirst("hours=".count).prefix { $0 != " " })
            let hours: [Int32] = try hoursText.split(separator: ",").map { try X.int32(String($0)) }
            guard let open = input.firstIndex(of: "{"), let close = input.lastIndex(of: "}") else {
                throw X.Malformed(text: input)
            }
            var saved: [Int32: Int32] = [:]
            for item in input[input.index(after: open)..<close].split(separator: ",") {
                let pair = item.split(separator: "=").map { String($0).trimmingCharacters(in: .whitespaces) }
                saved[try X.int32(pair[0])] = try X.int32(pair[1])
            }
            let draft = GoalEditing.Draft(goalSet: GoalSet.of(saved), hours: hours)
            return hours.map { String($0) + "=" + draft.text(for: $0) }.joined(separator: ",")
        case "filter":
            return "[" + GoalEditing.digitsOnly(input) + "]"
        case "save":
            var texts: [Int32: String] = [:]
            for item in input.split(separator: ",", omittingEmptySubsequences: false) {
                guard let eq = item.firstIndex(of: "=") else { throw X.Malformed(text: String(item)) }
                texts[try X.int32(String(item[..<eq]))] = String(item[item.index(after: eq)...])
            }
            let draft = GoalEditing.Draft(hours: texts.keys.sorted(), texts: texts)
            let set = draft.goalSet()
            let config = GoalFileWriter.toConfigMap(set)
            let ordered = config.keys.sorted { JavaText.compare($0, $1) < 0 }
            let configText = "{" + ordered.map { $0 + "=" + String(config[$0]!) }.joined(separator: ", ") + "}"
            return "count=" + String(set.entries.count) + ";config=" + configText + ";status="
                + GoalEditing.savedText(hours: draft.goalCount())
        case "bulk":
            let f: [String] = parts(input)
            let hours: [Int32] = try f[0].split(separator: ",").map { try X.int32(String($0)) }
            var texts: [Int32: String] = [:]
            for h in hours { texts[h] = "x" + String(h) }
            var draft = GoalEditing.Draft(hours: hours, texts: texts)
            var bulk = GoalEditing.BulkFill(hours: hours)
            bulk.fromKey = try X.int32(f[1])
            bulk.toKey = try X.int32(f[2])
            bulk.setValue(f[3])
            bulk.apply(to: &draft)
            return draft.hours.map { String($0) + "=" + draft.text(for: $0) }.joined(separator: ",")
        case "import":
            let f: [String] = parts(input)
            let lines: [String] = f[0].isEmpty ? [] : f[0].components(separatedBy: "\\n")
            let band: String? = f[1] == "~" ? nil : f[1]
            let result = GoalFileParser.parse(lines, band)
            return GoalEditing.importStatus(result, band: band) + "|bands=" + T.listText(result.bands)
        case "importMsg":
            let expected: [String: String] = [
                "read": "Cíle se nepodařilo přečíst (x)",
                "saveFail": GoalEditing.saveFailedText("x"),
                "noExport": "Není co exportovat — žádné cíle nejsou načtené.",
                "exported": "Cíle uloženy do /tmp/goals.txt",
                "exportFail": "Export cílů selhal (x)",
                "help1": GoalEditing.helpText(),
                "help2": GoalEditing.noContestText(),
                "fromLogHelp": GoalEditing.fromLogHelpText(),
            ]
            guard let text = expected[input] else { throw X.Malformed(text: input) }
            return text
        case "fromlog":
            let f: [String] = parts(input)
            let band: Band? = f[2] == "~" ? nil : Band.from(adif: f[2])
            return GoalEditing.fromLogStatus(contestName: f[0], hours: try X.int(f[1]), band: band)
        case "bandlabel":
            return GoalEditing.bandLabel(input == "~" ? nil : Band.from(adif: input))
        default:
            _ = corpus
            throw X.Malformed(text: "area \(area)")
        }
    }

    // MARK: - stats.VIEWS

    static func statistics(_ area: String, _ input: String, _ ctx: Ctx) throws -> String {
        let corpus: Corpus = ctx.environment.corpus
        switch area {
        case "dimension":
            return LogStatistics.Dimension(rawValue: input)?.label ?? "null"
        case "pivot":
            let f: [String] = parts(input)
            guard let rowDim = LogStatistics.Dimension(rawValue: f[1]),
                  let colDim = LogStatistics.Dimension(rawValue: f[2]) else { throw X.Malformed(text: input) }
            let table = StatsViews.statisticsTable(qsos: corpus.logs[f[0]] ?? [], rowDim: rowDim, colDim: colDim)
            return StatsViewsTests.tableText(table)
        case "hourly":
            let chart = StatsViews.hourlyChart(qsos: corpus.logs[input] ?? [])
            return "title=" + chart.title + ";values=" + T.listText(chart.values.map { String($0) }) + ";keys="
                + T.listText(chart.hours)
        case "reports":
            let sections = StatsViews.reports(qsos: corpus.logs[input] ?? [])
            var out: [String] = []
            for (i, section) in sections.enumerated() {
                out.append("T" + String(i + 1) + "=" + section.title)
                out.append(contentsOf: section.lines)
            }
            return out.joined(separator: "|")
        case "breakdown":
            let runtime: ContestRuntime = try ctx.runtime(nil)
            let breakdown = try runtime.breakdown(corpus.logs["cqww"] ?? [])
            return (breakdown == nil ? "~" : "x") + " scope=" + (runtime.dupeScope?.rawValue ?? "~") + " order="
                + T.listText(runtime.bandOrder.map { $0 ?? "null" })
        case "resolve":
            let f: [String] = parts(input)
            let runtime: ContestRuntime = try ctx.runtime(f[0])
            var category: [String: String]?
            if f[1] != "~" {
                // Java `Map.toString`: `{A=B, C=D}`.
                category = [:]
                for item in f[1].dropFirst().dropLast().split(separator: ",") {
                    let pair = item.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                    let key: String = pair[0].hasPrefix(" ") ? String(pair[0].dropFirst()) : String(pair[0])
                    category?[key] = String(pair[1])
                }
            }
            guard let op = InfoTimers.rules(definition: runtime.definition, category: category) else { return "none" }
            func pairText(_ a: Int?, _ b: Int?) -> String {
                (a.map { String($0) } ?? "~") + "/" + (b.map { String($0) } ?? "~")
            }
            let off: String = op.offTime.map { "off=" + pairText($0.minimumMinutes, $0.requiredMinutes) } ?? "off=~"
            let band: String = op.bandChange.map { "band=" + pairText($0.minimumMinutes, $0.perHour) } ?? "band=~"
            return off + " " + band
        case "score":
            let f: [String] = parts(input)
            let runtime: ContestRuntime = try ctx.runtime(f[0])
            let breakdown = try #require(try runtime.breakdown(corpus.logs[f[1]] ?? []))
            return StatsViewsTests.scoreText(StatsViews.scoreTable(breakdown: breakdown, bandOrder: runtime.bandOrder,
                                                                   byMode: f[2] == "true"))
        case "scoreEmpty":
            let runtime: ContestRuntime = try ctx.runtime(input)
            let breakdown = try #require(try runtime.breakdown([]))
            return StatsViewsTests.scoreText(StatsViews.scoreTable(breakdown: breakdown, bandOrder: runtime.bandOrder,
                                                                   byMode: true))
        case "dupe":
            // `<contest>|scope` or `scope <contest>`
            let id: String = input.hasPrefix("scope ") ? String(input.dropFirst("scope ".count))
                : String(parts(input)[0])
            return try ctx.runtime(id).dupeScope?.rawValue ?? "~"
        case "dupesheet":
            var f: [String] = parts(input)
            // `tag|log|band|mode|partial`, the tag being `none`, a contest id, or `<contest id>|<score log>`.
            let tail: [String] = Array(f.suffix(3))
            f.removeLast(3)
            let log: String = f.removeLast()
            var scope: ContestDefinition.Scope?
            if f.first != "none" {
                scope = try ctx.runtime(f[0]).dupeScope
            }
            let band: String? = tail[0] == "~" ? nil : tail[0]
            let mode: String? = tail[1] == "~" ? nil : tail[1]
            let view = StatsViews.dupesheet(qsos: corpus.logs[log] ?? [], scope: scope, band: band, mode: mode,
                                            typedCall: tail[2])
            return StatsViewsTests.dupesheetText(view)
        default:
            throw X.Malformed(text: "area \(area)")
        }
    }
}
