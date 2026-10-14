import Foundation
import MCLCore
import Observation

/// What the Statistics window shows for one log revision and one choice of dimensions.
public struct StatisticsSnapshot: Equatable, Sendable {
    public let table: StatisticsTable
    public let chart: HourlyChart
    /// Only computed while the "Rate, přestávky, běhy" view is on.
    public let reports: [ReportSection]
}

/// The Statistics window (`StatisticsWindow.kt`, N1MM Statistics): the pivot table (or its graph) with the hourly
/// chart, or the reports. The snapshot is computed off the main thread when the log's revision or the choice changes,
/// with a generation. The contest's dimensions (points, new multipliers, the exchange fields, the multipliers) and
/// leaving out the dupes come from a replay of the log into a fresh session of the active contest.
@Observable @MainActor
public final class StatisticsModel {

    /// Kotlin `rowDim` (`HOUR` at first).
    public private(set) var rowDimension: StatsDimension = .base(.HOUR)
    /// Kotlin `colDim` (`BAND` at first).
    public private(set) var columnDimension: StatsDimension = .base(.BAND)
    /// N1MM „Include dupes and X-QSOs".
    public private(set) var includeDupes = true
    /// The pivot as a graph instead of the table.
    public private(set) var showGraph = false
    /// The "Rate, přestávky, běhy" view instead of the pivot.
    public private(set) var showReports = false
    public private(set) var snapshot: StatisticsSnapshot?
    public private(set) var isOpen = false

    @ObservationIgnored private let logbook: LogbookModel
    @ObservationIgnored private let language: LanguageModel
    @ObservationIgnored private let contest: ContestModel?
    @ObservationIgnored private var derived: LogDerived<StatisticsSnapshot>?

    init(logbook: LogbookModel, language: LanguageModel, contest: ContestModel? = nil) {
        self.logbook = logbook
        self.language = language
        self.contest = contest
    }

    /// The contest's own dimensions (points, new multiplier, exchange fields, multipliers); none outside a contest.
    public var contestDimensions: [StatsDimension] {
        guard let contest, contest.isActive else { return [] }
        return StatsPivot.contestDimensions(contest.definition)
    }

    /// The row choices of the picker and the column choices (also „—", the totals only).
    public var rowChoices: [StatsDimension] {
        StatsDimension.general + contestDimensions
    }

    public var columnChoices: [StatsDimension] {
        StatsDimension.general + contestDimensions + [.base(.NONE)]
    }

    /// The label of a dimension in the window's language.
    public func label(_ dimension: StatsDimension) -> String {
        switch dimension {
        case .base(let base): return language.tr(base.label)
        case .minutes(let minutes): return language.tr("Po %s minutách", .int(minutes))
        case .modeBand: return language.tr("Pásmo a mód")
        case .points: return language.tr("Body")
        case .newMultiplier: return language.tr("Nový násobič")
        case .station: return language.tr("Stanice")
        case .exchange(let id): return language.tr("Výměna: %s", .string(id))
        case .multiplier(_, let name): return language.tr("Násobič: %s", .string(name))
        }
    }

    public func open() {
        guard !isOpen else { return }
        isOpen = true
        let derived = LogDerived<StatisticsSnapshot>(logbook: logbook, tracked: { [weak self] in
            _ = self?.contest?.activeId
        }, source: { [weak self] in
            self?.job() ?? { _ in Self.emptySnapshot() }
        }, apply: { [weak self] value in
            self?.snapshot = value
        })
        self.derived = derived
        derived.start()
    }

    public func close() {
        isOpen = false
        derived?.stop()
        derived = nil
    }

    public func setRows(_ dimension: StatsDimension) {
        rowDimension = dimension
        derived?.refresh()
    }

    public func setColumns(_ dimension: StatsDimension) {
        columnDimension = dimension
        derived?.refresh()
    }

    public func setRows(_ dimension: LogStatistics.Dimension) {
        setRows(.base(dimension))
    }

    public func setColumns(_ dimension: LogStatistics.Dimension) {
        setColumns(.base(dimension))
    }

    public func setIncludeDupes(_ on: Bool) {
        includeDupes = on
        derived?.refresh()
    }

    public func setShowGraph(_ on: Bool) {
        showGraph = on
    }

    public func setShowReports(_ on: Bool) {
        showReports = on
        derived?.refresh()
    }

    /// The table as tab-separated text (N1MM Copy All; also what Save writes).
    public var tableText: String? {
        snapshot?.table.tabSeparated
    }

    func settle() async {
        await derived?.settle()
    }

    var generation: Int {
        derived?.generation ?? 0
    }

    nonisolated private static func emptySnapshot() -> StatisticsSnapshot {
        StatisticsSnapshot(table: StatsViews.statisticsTable(qsos: [], rowDim: .HOUR, colDim: .BAND),
                           chart: StatsViews.hourlyChart(qsos: []), reports: [])
    }

    private func job() -> LogDerived<StatisticsSnapshot>.Job {
        let rows: StatsDimension = rowDimension
        let columns: StatsDimension = columnDimension
        let includeDupes: Bool = self.includeDupes
        let reports: Bool = showReports
        let translator: Translator = language.translator
        let header: String = label(rows)
        let needsReplay: Bool = rows.needsContest || columns.needsContest || !includeDupes
        // The fresh session is made here, on the main actor; the replay runs in the job.
        let fresh: ContestSession? = needsReplay && (contest?.isActive ?? false) ? contest?.runtime.freshSession() : nil
        return { qsos in
            let facts: [Int64: StatsFact] = fresh.map { StatsPivot.facts($0, qsos) } ?? [:]
            let pivot: LogStatistics.Pivot = StatsPivot.pivot(qsos, rows: rows, columns: columns, facts: facts,
                                                              includeDupes: includeDupes)
            let counted: [Qso] = includeDupes ? qsos : qsos.filter { qso in
                !qso.xqso && !(qso.id.flatMap { facts[$0] }?.dupe ?? false)
            }
            return StatisticsSnapshot(
                table: StatsViews.statisticsTable(pivot: pivot, rowHeader: header),
                chart: StatsViews.hourlyChart(qsos: counted, translate: translator),
                reports: reports ? StatsViews.reports(qsos: counted, translate: translator) : [])
        }
    }
}

/// The Score window (`ScoreWindow.kt`): the breakdown by band and mode, replayed from the log into a fresh session.
/// A series of writes (an import) is computed once: a change waits 300 ms (Kotlin `delay(300)`) on the injected
/// clock, then the replay runs off the main thread.
@Observable @MainActor
public final class ScoreWindowModel {

    /// Kotlin `delay(300)` of the `LaunchedEffect`.
    public static let debounceMilliseconds = 300

    /// The latest breakdown; `nil` = still computing, no contest or a score error (Kotlin `runCatching`).
    public private(set) var breakdown: ScoreBreakdown?
    /// Pásmo × mód (`true`) or just the bands.
    public var byMode = true
    public private(set) var isOpen = false

    @ObservationIgnored private let logbook: LogbookModel
    @ObservationIgnored private let contest: ContestModel
    @ObservationIgnored private let language: LanguageModel
    @ObservationIgnored private let config: ConfigModel
    @ObservationIgnored private let clock: any RescoreClock
    @ObservationIgnored private var derived: LogDerived<ScoreBreakdown?>?

    init(logbook: LogbookModel, contest: ContestModel, language: LanguageModel, config: ConfigModel,
         clock: any RescoreClock) {
        self.logbook = logbook
        self.contest = contest
        self.language = language
        self.config = config
        self.clock = clock
    }

    /// N1MM Score Summary: the station call in the window title (`Skóre — OK1XOE`).
    public var windowTitle: String {
        let call: String = KotlinStrings.trim(config.config.station.call)
        let base: String = language.tr("Skóre")
        return call.isEmpty ? base : base + " — " + call
    }

    /// N1MM „Display Contest Name": the contest's name above the table (`nil` outside a contest).
    public var contestName: String? {
        guard contest.isActive else { return nil }
        return contest.definition?.metadata?.name
    }

    /// N1MM „Copy all" / „Print to file": `<contest> — <call>`, the contest setup and station lines, then the table;
    /// `nil` without a table.
    public var summaryText: String? {
        guard let table else { return nil }
        let name: String = contest.definition?.metadata?.name ?? language.tr(IoTexts.defaultLogName)
        let title: String = PrintLayout.title(definitionName: name, call: config.config.station.call)
        let lines: [String] = ScoreSummaryText.setupLines(setup: contest.activeSetup, station: config.config.station,
                                                          translate: language.translator)
        return ScoreSummaryText.text(title: title, setupLines: lines, table: table)
    }

    public func open() {
        guard !isOpen else { return }
        isOpen = true
        breakdown = nil
        let derived = LogDerived<ScoreBreakdown?>(
            logbook: logbook, debounce: (clock, Self.debounceMilliseconds),
            tracked: { [weak self] in _ = self?.contest.activeId },
            source: { [weak self] in
                // The fresh session is made here, on the main actor; the replay runs in the job.
                guard let fresh = self?.contest.runtime.freshSession() else { return { _ in nil } }
                return { qsos in try? ScoreBreakdown.compute(fresh, qsos) }
            },
            apply: { [weak self] value in
                self?.breakdown = value
            })
        self.derived = derived
        derived.start()
    }

    public func close() {
        isOpen = false
        derived?.stop()
        derived = nil
    }

    func settle() async {
        await derived?.settle()
    }

    var generation: Int {
        derived?.generation ?? 0
    }

    /// Kotlin `state.contest.isActive`.
    public var contestActive: Bool {
        contest.isActive
    }

    /// The text above the table while there is no breakdown (`SC:62-69`).
    public var statusText: String {
        StatsViews.scoreStatusText(isActive: contest.isActive, translate: language.translator)
    }

    /// The table of the current breakdown for the chosen layout; `nil` without a breakdown or outside a contest.
    public var table: ScoreTable? {
        guard contest.isActive, let breakdown else { return nil }
        return StatsViews.scoreTable(breakdown: breakdown, bandOrder: contest.runtime.bandOrder, byMode: byMode,
                                     translate: language.translator)
    }
}

/// The Dupesheet window (`DupesheetWindow.kt`): the worked calls of the shown band (and mode, by the contest's dupe
/// rules) in columns by the digit, with the typed call highlighted. A log of up to 5 000 QSOs is computed inline on the
/// main actor; a larger one off the main thread with a generation.
///
/// N1MM: each VFO / radio has its own sheet. `dupesheet` follows VFO A (the tuned band, the radio's mode, the typed
/// call of the active entry window); `dupesheet2` follows the VFO B entry window (its band, mode and call). The calls
/// of a column are sorted by suffix while `dupesheetSortBySuffix` is on (N1MM), by the whole call otherwise.
@Observable @MainActor
public final class DupesheetModel {

    /// What a sheet shows: the band, the mode and the typed call it follows (read inside the observation, so a
    /// change rebuilds the sheet).
    public struct Sources {
        /// The tuned band; `nil` = the band of the last QSO.
        public var band: @MainActor () -> Band? = { nil }
        /// The radio's mode; `nil` = the mode of the last QSO.
        public var mode: @MainActor () -> Mode? = { nil }
        /// Kotlin `state.typedCall`.
        public var typedCall: @MainActor () -> String = { "" }
        /// Sort the columns by suffix (`dupesheetSortBySuffix`).
        public var sortBySuffix: @MainActor () -> Bool = { false }

        public init() {}
    }

    /// Above this many QSOs the sheet is built off the main thread.
    public static let defaultInlineLimit = 5_000
    /// The limit in use (tests lower it to reach the off-thread path).
    var inlineLimit = DupesheetModel.defaultInlineLimit

    /// 0 = VFO A (`dupesheet`), 1 = VFO B (`dupesheet2`).
    public let vfo: Int
    public private(set) var view: DupesheetView?
    public private(set) var isOpen = false

    @ObservationIgnored private let logbook: LogbookModel
    @ObservationIgnored private let contest: ContestModel
    @ObservationIgnored private let language: LanguageModel
    @ObservationIgnored private var derived: LogDerived<DupesheetView>?
    /// Wired by the app.
    @ObservationIgnored public var sources = Sources()

    init(logbook: LogbookModel, contest: ContestModel, language: LanguageModel, vfo: Int = 0) {
        self.logbook = logbook
        self.contest = contest
        self.language = language
        self.vfo = vfo
    }

    public func open() {
        guard !isOpen else { return }
        isOpen = true
        let derived = LogDerived<DupesheetView>(
            logbook: logbook,
            tracked: { [weak self] in
                guard let self else { return }
                _ = self.contest.activeId
                _ = self.sources.band()
                _ = self.sources.mode()
                _ = self.sources.typedCall()
                _ = self.sources.sortBySuffix()
            },
            source: { [weak self] in
                self?.job() ?? { _ in
                    StatsViews.dupesheet(qsos: [], scope: nil, band: nil, mode: nil, typedCall: "")
                }
            },
            apply: { [weak self] value in
                self?.view = value
            })
        derived.inlineLimit = inlineLimit
        self.derived = derived
        derived.start()
    }

    public func close() {
        isOpen = false
        derived?.stop()
        derived = nil
    }

    func settle() async {
        await derived?.settle()
    }

    var generation: Int {
        derived?.generation ?? 0
    }

    /// What the sheet is built with: the band of the followed VFO or of the last QSO, its mode or the last QSO's,
    /// the contest's dupe scope (none outside a contest), the typed call and the order.
    private func job() -> LogDerived<DupesheetView>.Job {
        let rows: [Qso] = logbook.rows
        let band: String? = StatsViews.dupesheetBand(tuned: sources.band(), qsos: rows)
        let mode: String? = StatsViews.dupesheetMode(radio: sources.mode(), qsos: rows)
        let scope: ContestDefinition.Scope? = contest.isActive ? contest.runtime.dupeScope : nil
        let typed: String = sources.typedCall()
        let order: Dupesheet.Order = sources.sortBySuffix() ? .suffix : .call
        let translator: Translator = language.translator
        return { qsos in
            StatsViews.dupesheet(qsos: qsos, scope: scope, band: band, mode: mode, typedCall: typed,
                                 translate: translator, order: order)
        }
    }
}
