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

/// The Statistics window (`StatisticsWindow.kt`): the pivot table with the hourly chart, or the reports. The snapshot
/// is computed off the main thread when the log's revision or the choice changes, with a generation.
@Observable @MainActor
public final class StatisticsModel {

    /// Kotlin `rowDim` (`HOUR` at first).
    public private(set) var rowDimension: LogStatistics.Dimension = .HOUR
    /// Kotlin `colDim` (`BAND` at first).
    public private(set) var columnDimension: LogStatistics.Dimension = .BAND
    /// The "Rate, přestávky, běhy" view instead of the pivot.
    public private(set) var showReports = false
    public private(set) var snapshot: StatisticsSnapshot?
    public private(set) var isOpen = false

    @ObservationIgnored private let logbook: LogbookModel
    @ObservationIgnored private let language: LanguageModel
    @ObservationIgnored private var derived: LogDerived<StatisticsSnapshot>?

    init(logbook: LogbookModel, language: LanguageModel) {
        self.logbook = logbook
        self.language = language
    }

    /// The row choices of the picker (every dimension but `NONE`) and the column choices.
    public var rowChoices: [LogStatistics.Dimension] {
        StatsViews.rowDimensions
    }

    public var columnChoices: [LogStatistics.Dimension] {
        StatsViews.columnDimensions
    }

    public func open() {
        guard !isOpen else { return }
        isOpen = true
        let derived = LogDerived<StatisticsSnapshot>(logbook: logbook, source: { [weak self] in
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

    public func setRows(_ dimension: LogStatistics.Dimension) {
        rowDimension = dimension
        derived?.refresh()
    }

    public func setColumns(_ dimension: LogStatistics.Dimension) {
        columnDimension = dimension
        derived?.refresh()
    }

    public func setShowReports(_ on: Bool) {
        showReports = on
        derived?.refresh()
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
        let rows: LogStatistics.Dimension = rowDimension
        let columns: LogStatistics.Dimension = columnDimension
        let reports: Bool = showReports
        let translator: Translator = language.translator
        return { qsos in
            StatisticsSnapshot(
                table: StatsViews.statisticsTable(qsos: qsos, rowDim: rows, colDim: columns),
                chart: StatsViews.hourlyChart(qsos: qsos, translate: translator),
                reports: reports ? StatsViews.reports(qsos: qsos, translate: translator) : [])
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
    @ObservationIgnored private let clock: any RescoreClock
    @ObservationIgnored private var derived: LogDerived<ScoreBreakdown?>?

    init(logbook: LogbookModel, contest: ContestModel, language: LanguageModel, clock: any RescoreClock) {
        self.logbook = logbook
        self.contest = contest
        self.language = language
        self.clock = clock
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
@Observable @MainActor
public final class DupesheetModel {

    /// Above this many QSOs the sheet is built off the main thread.
    public static let defaultInlineLimit = 5_000
    /// The limit in use (tests lower it to reach the off-thread path).
    var inlineLimit = DupesheetModel.defaultInlineLimit

    public private(set) var view: DupesheetView?
    public private(set) var isOpen = false

    @ObservationIgnored private let logbook: LogbookModel
    @ObservationIgnored private let contest: ContestModel
    @ObservationIgnored private let rig: RigModel
    @ObservationIgnored private let language: LanguageModel
    @ObservationIgnored private var derived: LogDerived<DupesheetView>?
    /// Kotlin `state.typedCall` (wired by the app).
    @ObservationIgnored public var typedCall: @MainActor () -> String = { "" }

    init(logbook: LogbookModel, contest: ContestModel, rig: RigModel, language: LanguageModel) {
        self.logbook = logbook
        self.contest = contest
        self.rig = rig
        self.language = language
    }

    public func open() {
        guard !isOpen else { return }
        isOpen = true
        let derived = LogDerived<DupesheetView>(
            logbook: logbook,
            tracked: { [weak self] in
                guard let self else { return }
                _ = self.contest.activeId
                _ = self.rig.currentBand
                _ = self.rig.activeState
                _ = self.typedCall()
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

    /// What the sheet is built with: the band of the tuned frequency or of the last QSO, the radio's mode or the last
    /// QSO's, the contest's dupe scope (none outside a contest), the typed call.
    private func job() -> LogDerived<DupesheetView>.Job {
        let rows: [Qso] = logbook.rows
        let band: String? = StatsViews.dupesheetBand(tuned: rig.currentBand, qsos: rows)
        let mode: String? = StatsViews.dupesheetMode(radio: rig.activeState?.mode, qsos: rows)
        let scope: ContestDefinition.Scope? = contest.isActive ? contest.runtime.dupeScope : nil
        let typed: String = typedCall()
        let translator: Translator = language.translator
        return { qsos in
            StatsViews.dupesheet(qsos: qsos, scope: scope, band: band, mode: mode, typedCall: typed,
                                 translate: translator)
        }
    }
}
