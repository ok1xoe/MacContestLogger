import Foundation
import MCLCore
import Observation

/// The N1MM+ Check window (`window.check`): the calls of the log, `master.scp`, the spotted stations (from three
/// spots) and the call history that could be the call typed in the active entry window, with their characters
/// marked; the exchange pane; the reverse call history lookup; Alt+Y's cycle over the panes; the ✓ / ? mark of the
/// call field.
///
/// The panes are computed off the main thread with a generation (a late result for an older input is dropped) while
/// the window is open; Alt+Y computes them on the spot when it is not.
@Observable @MainActor
public final class CheckModel {

    /// One pane's content.
    public struct Pane: Equatable, Sendable {
        public let pane: CheckPane
        public let matches: [CheckMatcher.Match]
        /// The source's size (N1MM shows the totals of its files).
        public let total: Int

        public init(pane: CheckPane, matches: [CheckMatcher.Match], total: Int) {
            self.pane = pane
            self.matches = matches
            self.total = total
        }
    }

    /// The ✓ / ? at the end of the call field (N1MM: a check coloured by the multiplier status when a Check source
    /// has the exact call, a `?` when none has it).
    public enum CallMark: Equatable, Sendable {
        case none
        case matched(SpotColorClassifier.SpotColorKey)
        case unmatched
    }

    public private(set) var isOpen = false
    /// The call panes (log, master.scp, telnet, call history) in the window's order.
    public private(set) var panes: [Pane] = []
    /// The reverse lookup's calls.
    public private(set) var reverse: [String] = []
    /// The exchange field the exchange pane shows (`nil` = none).
    public private(set) var exchangeField: String?
    public private(set) var exchangeValues: [CheckExchange.Value] = []
    /// The typed call the panes belong to.
    public private(set) var query: String = ""

    /// The entry window the Check follows (the active one; wired by the app).
    @ObservationIgnored public var target: @MainActor () -> EntryModel? = { nil }
    /// The spotted calls with their spot counts (wired by the app).
    @ObservationIgnored public var spotCounts: @MainActor () -> [String: Int] = { [:] }
    /// The multiplier status of a call on an entry window's band and mode (wired by the app).
    @ObservationIgnored public var callStatus: @MainActor (String, EntryModel) -> SpotColorClassifier.SpotColorKey = {
        _, _ in .good
    }

    /// Test seam: runs before a background result is compared with the generation.
    @ObservationIgnored var beforeAdopt: (@MainActor (Int) async -> Void)?

    @ObservationIgnored private let config: ConfigModel
    @ObservationIgnored private let callData: CallDataModel
    @ObservationIgnored private let logbook: LogbookModel
    @ObservationIgnored private let contest: ContestModel
    @ObservationIgnored private var key: Key?
    @ObservationIgnored private(set) var generation: Int = 0
    @ObservationIgnored private var yank = CheckYank()
    @ObservationIgnored private var logCallCache: (revision: Int64, count: Int, calls: [String], set: Set<String>)?
    @ObservationIgnored private var tasks: [Int: Task<Void, Never>] = [:]
    @ObservationIgnored private var nextTaskId: Int = 0
    @ObservationIgnored private var observing = false

    private struct Key: Equatable {
        let call: String
        let exchange: JavaLinkedMap<String>
        let field: String?
        let scpRevision: Int
        let callHistoryRevision: Int
        let logRevision: Int64
        let logCount: Int
        let contestId: String?
        let settings: CheckSettings
    }

    public init(config: ConfigModel, callData: CallDataModel, logbook: LogbookModel, contest: ContestModel) {
        self.config = config
        self.callData = callData
        self.logbook = logbook
        self.contest = contest
    }

    // MARK: - settings (the right-click menu)

    public var settings: CheckSettings {
        CheckSettings(config.config)
    }

    /// Changes the settings and saves them at once.
    public func update(_ change: (inout CheckSettings) -> Void) {
        var next: CheckSettings = settings
        change(&next)
        next.apply(to: &config.config)
        config.saveSilently()
    }

    /// The visible panes in order (the reverse pane only while the lookup is on, the exchange pane only in a
    /// contest).
    public var visiblePanes: [CheckPane] {
        let settings: CheckSettings = settings
        return CheckPane.allCases.filter { pane in
            if settings.hidden.contains(pane) { return false }
            switch pane {
            case .reverse: return settings.reverseEnabled
            case .exchange: return contest.isActive
            default: return true
            }
        }
    }

    /// N1MM View → "Show ? on Unmatched Calls".
    public var showsUnmatchedMark: Bool {
        config.config.showUnmatchedCallMark
    }

    public func setShowsUnmatchedMark(_ on: Bool) {
        config.config.showUnmatchedCallMark = on
        config.saveSilently()
    }

    // MARK: - window

    public func open() {
        guard !isOpen else { return }
        isOpen = true
        key = nil
        if !observing {
            observing = true
            observe()
        }
    }

    public func close() {
        isOpen = false
        generation += 1
    }

    /// Recomputes the panes when an input changed (only while the window is open).
    public func refresh() {
        guard isOpen, let entry = target() else { return }
        let next = Key(call: entry.form.call, exchange: entry.form.contestExchange, field: entry.lastEditedField,
                       scpRevision: callData.scpRevision, callHistoryRevision: callData.callHistoryRevision,
                       logRevision: logbook.revision, logCount: logbook.rows.count, contestId: contest.activeId,
                       settings: settings)
        guard next != key else { return }
        key = next
        generation += 1
        let current: Int = generation
        let input: Input = makeInput(entry)
        track { [weak self] in
            let computed: Output = await Task.detached(priority: .userInitiated) {
                Self.compute(input)
            }.value
            guard let self else { return }
            await self.beforeAdopt?(current)
            guard current == self.generation, self.isOpen else { return }
            self.adopt(computed)
        }
    }

    private func observe() {
        withObservationTracking {
            refresh()
        } onChange: { [weak self] in
            MainHop.post {
                guard let self else { return }
                if self.isOpen {
                    self.observe()
                } else {
                    self.observing = false
                }
            }
        }
    }

    private func adopt(_ output: Output) {
        if panes != output.panes { panes = output.panes }
        if reverse != output.reverse { reverse = output.reverse }
        if exchangeField != output.exchangeField { exchangeField = output.exchangeField }
        if exchangeValues != output.exchangeValues { exchangeValues = output.exchangeValues }
        if query != output.query { query = output.query }
    }

    // MARK: - computing

    struct Input: Sendable {
        let call: String
        let exchange: [String: String]
        let field: String?
        let fieldText: String
        let logRows: [Qso]
        let scp: ScpDatabase
        let callHistory: CallHistory
        let spots: [String: Int]
        let settings: CheckSettings
        let fields: [ContestDefinition.ExchangeField]
        let session: ContestSession?
        let exchangeValues: [CheckExchange.Value]
    }

    struct Output: Sendable {
        let query: String
        let panes: [Pane]
        let reverse: [String]
        let exchangeField: String?
        let exchangeValues: [CheckExchange.Value]
    }

    private func makeInput(_ entry: EntryModel) -> Input {
        let active: Bool = contest.isActive
        let fields: [ContestDefinition.ExchangeField] = active ? contest.exchangeFields(call: entry.form.call) : []
        var exchange: [String: String] = [:]
        let searched: Set<String> = CheckReverseLookup.searchedFields(fields)
        for (id, value) in entry.form.contestExchange.entries {
            if let id, let value, searched.contains(id), !KotlinStrings.isBlank(value) {
                exchange[id] = value
            }
        }
        let settings: CheckSettings = settings
        let field: String? = active ? entry.lastEditedField : nil
        let fieldText: String = field.flatMap { entry.form.contestExchange[$0] } ?? ""
        let values: [CheckExchange.Value] = field.map {
            CheckExchange.values(for: $0, definition: contest.definition, registry: contest.environment.registry)
        } ?? []
        let wantsReverse: Bool = active && settings.reverseEnabled && !exchange.isEmpty
        return Input(call: entry.form.call, exchange: exchange, field: field, fieldText: fieldText,
                     logRows: logbook.rows, scp: callData.scp, callHistory: callData.callHistory,
                     spots: spotCounts(), settings: settings, fields: fields,
                     session: wantsReverse ? contest.runtime.freshSession() : nil, exchangeValues: values)
    }

    nonisolated static func compute(_ input: Input) -> Output {
        let favorEnd: Bool = input.settings.favorEnd
        let logCalls: [String] = distinctCalls(input.logRows)
        let telnet: [String] = input.spots.filter { $0.value >= input.settings.telnetMinSpots }.map(\.key).sorted()
        let sources: [(CheckPane, [String])] = [
            (.log, logCalls), (.scp, input.scp.allCalls), (.telnet, telnet), (.callHistory, input.callHistory.calls),
        ]
        let panes: [Pane] = sources.map { pane, calls in
            Pane(pane: pane, matches: CheckMatcher.matches(input.call, candidates: calls, favorEnd: favorEnd),
                 total: calls.count)
        }
        var reverse: [String] = []
        if let session = input.session {
            let records: [CheckReverseLookup.Record] = CheckReverseLookup.records(session, qsos: input.logRows)
                + CheckReverseLookup.records(input.callHistory, fields: input.fields)
            reverse = CheckReverseLookup.search(entered: input.exchange, records: records, partialCall: input.call,
                                                threshold: input.settings.reverseThreshold,
                                                fromStart: input.settings.reverseFromStart)
        }
        let exchangeValues: [CheckExchange.Value] = CheckExchange.matches(input.fieldText, values: input.exchangeValues)
        return Output(query: CheckMatcher.normalized(input.call), panes: panes, reverse: reverse,
                      exchangeField: exchangeValues.isEmpty ? nil : input.field, exchangeValues: exchangeValues)
    }

    nonisolated private static func distinctCalls(_ rows: [Qso]) -> [String] {
        var seen: Set<String> = []
        var out: [String] = []
        for row in rows where !row.deleted {
            let call: String = CheckMatcher.normalized(row.call)
            if !call.isEmpty && seen.insert(call).inserted {
                out.append(call)
            }
        }
        return out
    }

    // MARK: - Alt+Y

    /// N1MM Alt+Y: in the call field the next call of the panes in the yank order (a cycle while the field keeps the
    /// call the last press put in); in an exchange field the first value of the exchange pane. `nil` = nothing.
    public func yank(entry: EntryModel, field: EntryFieldKey?) -> String? {
        if case .contest(let id)? = field, let id {
            let text: String = entry.form.contestExchange[id] ?? ""
            let values: [CheckExchange.Value] = CheckExchange.values(for: id, definition: contest.definition,
                                                                     registry: contest.environment.registry)
            return CheckExchange.matches(text, values: values).first?.key
        }
        let settings: CheckSettings = settings
        return yank.next(typed: entry.form.call) {
            let output: Output = Self.compute(makeInput(entry))
            var byPane: [CheckPane: [String]] = [:]
            for pane in output.panes {
                byPane[pane.pane] = pane.matches.map(\.call)
            }
            byPane[.reverse] = output.reverse
            let band: Band? = entry.band
            return CheckYank.candidates(panes: byPane, order: settings.yankOrder, typed: entry.form.call,
                                        allowDupes: settings.yankAllowsDupes) { [logbook] call in
                logbook.isDupe(call: call, band: band)
            }
        }
    }

    // MARK: - the call field's mark

    /// The ✓ / ? of a call field: from three characters, while a Check is shown (this window or the entry window's
    /// Check partial row).
    public func mark(for entry: EntryModel) -> CallMark {
        let typed: String = CheckMatcher.normalized(entry.form.call)
        guard typed.count >= 3, isOpen || config.config.scpSuggestionsEnabled else { return .none }
        if knows(typed) {
            return .matched(callStatus(typed, entry))
        }
        return config.config.showUnmatchedCallMark ? .unmatched : .none
    }

    /// Does a Check source have the exact call?
    public func knows(_ call: String) -> Bool {
        let typed: String = CheckMatcher.normalized(call)
        if loggedCalls().contains(typed) || callData.scp.contains(typed) || callData.callHistory.lookup(typed) != nil {
            return true
        }
        return (spotCounts()[typed] ?? 0) > 0
    }

    private func loggedCalls() -> Set<String> {
        let rows: [Qso] = logbook.rows
        if let cache = logCallCache, cache.revision == logbook.revision, cache.count == rows.count {
            return cache.set
        }
        let calls: [String] = Self.distinctCalls(rows)
        let set = Set(calls)
        logCallCache = (logbook.revision, rows.count, calls, set)
        return set
    }

    // MARK: - tasks

    private func track(_ body: @escaping @MainActor () async -> Void) {
        let id: Int = nextTaskId
        nextTaskId += 1
        tasks[id] = Task { [weak self] in
            await body()
            self?.tasks[id] = nil
        }
    }

    /// Waits for the computations in flight (tests).
    func settle() async {
        while let task = tasks.values.first {
            await task.value
        }
    }
}
