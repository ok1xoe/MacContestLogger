import Foundation
import MCLCore
import Observation

/// The callsign help under the entry fields (`EP:271-295, 623-669, 1193-1246`): Check partial, N+1, the worked-before
/// strip, the call history prefill and the reverse call history lookup.
///
/// Every part runs when one of its Kotlin keys changes (`refresh()` compares them), so repeated refreshes are cheap:
/// - Check partial and N+1 (`produceState(call, state.scp, logCalls)`): off the main thread with a generation — a late
///   result for an older call is dropped. The log call list follows the QSO **count** only (Kotlin
///   `remember(state.qsos.size)`: a call edited in the table shows up after the next QSO).
/// - Worked-before (`remember(call, qsos.size, qsos.lastOrNull(), order)`): `WorkedBefore.of` takes ~1.6 ms over 20k
///   QSOs (release, `mcl-synthlog`), so it runs off the main thread too, with its own generation.
/// - The call history prefill (`LaunchedEffect(call, state.callHistory, contest.activeId, callbookRec)`): 250 ms
///   after the last key change, `CallbookPrefill.prefill(rec) + CallHistoryFill.fill` (the call history wins) and
///   `apply` over the current form; what it filled (`chFilled`) is taken back when the call changes.
/// - The callbook lookup (`LaunchedEffect(call) { delay(700); if (active) lookupCallbook(call) }`, `EP:276-279`) and
///   the callbook line of the entry window (`callbookLine`, `EP:1186-1192`).
/// - The spot calls of the cluster buffer join Check partial and N+1 (`EP:632, 645`), read when the call changes.
/// - The reverse lookup (`remember(exchSnapshot, state.callHistory, cfields)`): synchronous like Kotlin.
///
/// The entry form comes from `formSource`; the prefilled form goes back through `formSink` (both wired by the app).
@Observable @MainActor
public final class SuggestionsModel {

    /// Check partial (Kotlin `partial`).
    public private(set) var partial: [PartialCheck.Suggestion] = []
    /// N+1 (Kotlin `nPlusOne`).
    public private(set) var nPlusOne: [String] = []
    /// The worked-before strip; `nil` = hidden.
    public private(set) var workedBefore: WorkedBefore.Result?
    /// Calls the filled exchange matches (empty call only).
    public private(set) var reverse: [String] = []
    /// The highlighted suggestion; -1 = none (Enter logs as usual).
    public private(set) var scpPick: Int = -1
    /// What the call history prefilled (Kotlin `chFilled`).
    public private(set) var chFilled = JavaLinkedMap<String>()

    /// Kotlin `callbookRec`: the callbook record of the app (`callbookRecord`) when it belongs to the call typed here
    /// (Kotlin `first == call.trim().uppercase()`).
    public var callbookRecord: HamQthRecord? {
        guard let hit = callbookSource() else { return nil }
        return hit.call == CallbookPolicy.key(formSource().call) ? hit.record : nil
    }

    /// The callbook line under the fields (`"Callbook: " + CallbookPrefill.describe(rec)`, not translated); `nil` =
    /// hidden.
    public var callbookLine: String? {
        callbookRecord.map { "Callbook: " + CallbookPrefill.describe($0) }
    }

    /// The spot calls of the cluster buffer (Kotlin `state.dxCluster.spots.snapshot().map { it.dxCall() }`).
    @ObservationIgnored public var spotCalls: @MainActor () -> [String] = { [] }
    /// The call in this window's call field (the manual lookup button's input).
    public var currentCall: String {
        formSource().call
    }

    /// The failed answer of the manual lookup button for the call typed here (`nil` = none, found or another call).
    public var callbookProblem: ManualLookupResult? {
        guard let result = lookupSource(), result.problem != nil || result.state == .loading,
              result.call == CallbookPolicy.key(formSource().call) else { return nil }
        return result
    }

    /// The app's manual lookup of the entry button (`CallbookModel.entryLookup`).
    @ObservationIgnored public var lookupSource: @MainActor () -> ManualLookupResult? = { nil }
    /// The app's callbook record (`AppState.callbookRecord`).
    @ObservationIgnored public var callbookSource: @MainActor () -> CallbookHit? = { nil }
    /// `state.lookupCallbook(call)` after the 700 ms pause (wired by the app).
    @ObservationIgnored public var callbookLookup: @MainActor (String) -> Void = { _ in }
    /// Kotlin `active` of the panel, read when the pause starts (`LaunchedEffect(call)` captures it at its launch).
    @ObservationIgnored public var callbookActive: @MainActor () -> Bool = { true }

    /// Is the `SCP:` row shown (and Check partial computed)? The Settings switch `scpSuggestionsEnabled`.
    public var showsScpRow: Bool { callData.scpSuggestionsEnabled }
    /// Is the `N+1:` row shown (and N+1 computed)? The Settings switch `nPlusOneEnabled`.
    public var showsNPlusOneRow: Bool { callData.nPlusOneEnabled }

    /// The suggested calls (Kotlin `suggestions = partial.map { it.call() }`).
    public var suggestions: [String] {
        partial.map(\.call)
    }

    /// The current entry form.
    @ObservationIgnored public var formSource: @MainActor () -> EntryForm = { EntryForm() }
    /// Takes the form with the call history prefill.
    @ObservationIgnored public var formSink: @MainActor (EntryForm) -> Void = { _ in }

    /// Which background computation reached the main thread (test seam: runs before the generation check).
    public enum Job: Equatable, Sendable {
        case partial(generation: Int)
        case workedBefore(generation: Int)
    }

    @ObservationIgnored var beforeAdopt: (@MainActor (Job) async -> Void)?

    /// Kotlin `CallHistoryLookup` delay.
    public static let fillDelayMilliseconds = 250
    /// Kotlin's pause before the callbook lookup (`delay(700)`).
    public static let callbookDelayMilliseconds = 700

    @ObservationIgnored private let callData: CallDataModel
    @ObservationIgnored private let logbook: LogbookModel
    @ObservationIgnored private let contest: ContestModel
    @ObservationIgnored private let clock: any RescoreClock

    @ObservationIgnored private var partialKey: PartialKey?
    @ObservationIgnored private var workedKey: WorkedKey?
    @ObservationIgnored private var fillKey: FillKey?
    @ObservationIgnored private var reverseKey: ReverseKey?
    @ObservationIgnored private(set) var partialGeneration: Int = 0
    @ObservationIgnored private(set) var workedGeneration: Int = 0
    @ObservationIgnored private var fillTimer: (any RescoreTimer)?
    @ObservationIgnored private var callbookCall: String?
    @ObservationIgnored private var callbookTimer: (any RescoreTimer)?
    @ObservationIgnored private var logCalls = LogCalls(count: -1, calls: [], keys: [])
    @ObservationIgnored private var tasks: [Int: Task<Void, Never>] = [:]
    /// Untracked copies of the published outputs: `refresh()` runs inside `observe()`'s tracking, and comparing
    /// against the observed properties there would make the model's own writes trigger a redundant refresh.
    @ObservationIgnored private var shownPartial: [PartialCheck.Suggestion] = []
    @ObservationIgnored private var shownNPlusOne: [String] = []
    @ObservationIgnored private var shownWorkedBefore: WorkedBefore.Result?
    @ObservationIgnored private var shownReverse: [String] = []
    @ObservationIgnored private var nextTaskId: Int = 0

    private struct PartialKey: Equatable {
        let call: String
        let scpRevision: Int
        let logCount: Int
        let partialOn: Bool
        let nPlusOneOn: Bool
    }

    private struct WorkedKey: Equatable {
        let call: String
        let logCount: Int
        let last: Qso?
        let order: [String]?
    }

    private struct FillKey: Equatable {
        let call: String
        let callHistoryRevision: Int
        let activeId: String?
        let callbook: HamQthRecord?
    }

    private struct ReverseKey: Equatable {
        let exchange: JavaLinkedMap<String>
        let blankCall: Bool
        let callHistoryRevision: Int
        let activeId: String?
        let fieldIds: [String?]
    }

    /// The distinct calls of the log in first-occurrence order (Kotlin `mapNotNull { it.call }.toSet()`).
    private struct LogCalls: Sendable {
        let count: Int
        let calls: [String]
        let keys: Set<[UInt16]>

        static func of(_ rows: [Qso]) -> LogCalls {
            var keys = Set<[UInt16]>()
            var calls: [String] = []
            for row in rows where keys.insert(Array(row.call.utf16)).inserted {
                calls.append(row.call)
            }
            return LogCalls(count: rows.count, calls: calls, keys: keys)
        }
    }

    public init(callData: CallDataModel, logbook: LogbookModel, contest: ContestModel, clock: any RescoreClock) {
        self.callData = callData
        self.logbook = logbook
        self.contest = contest
        self.clock = clock
    }

    // MARK: - refresh

    /// Recomputes what the changed inputs (form, `master.scp`, call history, log, contest) affect.
    public func refresh() {
        let form: EntryForm = formSource()
        let rows: [Qso] = logbook.rows
        refreshPartial(call: form.call, rows: rows)
        refreshWorkedBefore(call: form.call, rows: rows)
        refreshCallbook(call: form.call)
        refreshFill(call: form.call)
        refreshReverse(form: form)
    }

    /// Calls `refresh()` whenever an observed input changes (re-armed after each change, on the main queue).
    public func observe() {
        withObservationTracking {
            refresh()
        } onChange: { [weak self] in
            MainHop.post {
                self?.observe()
            }
        }
    }

    private func refreshPartial(call: String, rows: [Qso]) {
        let partialOn: Bool = callData.scpSuggestionsEnabled
        let nPlusOneOn: Bool = callData.nPlusOneEnabled
        let key = PartialKey(call: call, scpRevision: callData.scpRevision, logCount: rows.count,
                             partialOn: partialOn, nPlusOneOn: nPlusOneOn)
        guard key != partialKey else { return }
        partialKey = key
        partialGeneration += 1
        let generation: Int = partialGeneration
        let partialQuery: Bool = partialOn && call.utf16.count >= 2
        let nPlusOneQuery: Bool = nPlusOneOn && KotlinStrings.trim(call).utf16.count >= 3
        if !partialQuery && !nPlusOneQuery {
            adoptPartial([], [])
            return
        }
        let scp: ScpDatabase = callData.scp
        let cached: LogCalls? = logCalls.count == rows.count ? logCalls : nil
        let spots: [String] = spotCalls()
        track { [weak self] in
            let computed = await Task.detached(priority: .userInitiated) {
                Self.computePartial(call: call, rows: rows, cached: cached, spotCalls: spots, scp: scp,
                                    partialOn: partialQuery, nPlusOneOn: nPlusOneQuery)
            }.value
            guard let self else { return }
            await self.beforeAdopt?(.partial(generation: generation))
            guard generation == self.partialGeneration else { return }
            self.logCalls = computed.logCalls
            self.adoptPartial(computed.partial, computed.nPlusOne)
        }
    }

    private struct PartialResult: Sendable {
        let logCalls: LogCalls
        let partial: [PartialCheck.Suggestion]
        let nPlusOne: [String]
    }

    nonisolated private static func computePartial(call: String, rows: [Qso], cached: LogCalls?, spotCalls: [String],
                                                   scp: ScpDatabase, partialOn: Bool,
                                                   nPlusOneOn: Bool) -> PartialResult {
        let interval: Perf.Interval = Perf.begin("suggestions")
        defer { Perf.end(interval, String(rows.count) + " qso") }
        let logCalls: LogCalls = cached ?? LogCalls.of(rows)
        let partial = partialOn
            ? EntrySuggestions.partial(query: call, logCalls: logCalls.calls, spotCalls: spotCalls, scp: scp) : []
        let nPlusOne = nPlusOneOn
            ? EntrySuggestions.nPlusOne(query: call, logCalls: logCalls.calls, spotCalls: spotCalls, scp: scp) : []
        return PartialResult(logCalls: logCalls, partial: partial, nPlusOne: nPlusOne)
    }

    /// Kotlin `LaunchedEffect(suggestions) { scpPick = -1 }`: a changed list drops the highlight.
    private func adoptPartial(_ suggestions: [PartialCheck.Suggestion], _ nPlusOne: [String]) {
        if suggestions != shownPartial {
            shownPartial = suggestions
            partial = suggestions
            scpPick = -1
        }
        if nPlusOne != shownNPlusOne {
            shownNPlusOne = nPlusOne
            self.nPlusOne = nPlusOne
        }
    }

    private func refreshWorkedBefore(call: String, rows: [Qso]) {
        let order: [String]? = contest.isActive ? contest.runtime.bandOrder.compactMap { $0 } : nil
        let key = WorkedKey(call: call, logCount: rows.count, last: rows.last, order: order)
        guard key != workedKey else { return }
        workedKey = key
        workedGeneration += 1
        let generation: Int = workedGeneration
        if KotlinStrings.trim(call).utf16.count < 3 {
            adoptWorkedBefore(nil)
            return
        }
        track { [weak self] in
            let result: WorkedBefore.Result? = await Task.detached(priority: .userInitiated) {
                Perf.measure("worked-before", String(rows.count) + " qso") {
                    EntrySuggestions.workedBefore(qsos: rows, call: call, contestBandOrder: order)
                }
            }.value
            guard let self else { return }
            await self.beforeAdopt?(.workedBefore(generation: generation))
            guard generation == self.workedGeneration else { return }
            self.adoptWorkedBefore(result)
        }
    }

    private func adoptWorkedBefore(_ result: WorkedBefore.Result?) {
        if result != shownWorkedBefore {
            shownWorkedBefore = result
            workedBefore = result
        }
    }

    /// `LaunchedEffect(call) { delay(700); if (active) lookupCallbook(call) }`: every change of the call restarts
    /// the pause (the blank call too: Kotlin's lookup of `""` clears the record).
    private func refreshCallbook(call: String) {
        guard call != callbookCall else { return }
        callbookCall = call
        callbookTimer?.cancel()
        let active: Bool = callbookActive()
        callbookTimer = clock.schedule(afterMilliseconds: Self.callbookDelayMilliseconds) { [weak self] in
            self?.callbookTimer = nil
            if active {
                self?.callbookLookup(call)
            }
        }
    }

    private func refreshFill(call: String) {
        let key = FillKey(call: call, callHistoryRevision: callData.callHistoryRevision, activeId: contest.activeId,
                          callbook: callbookRecord)
        guard key != fillKey else { return }
        fillKey = key
        fillTimer?.cancel()
        let record: HamQthRecord? = key.callbook
        fillTimer = clock.schedule(afterMilliseconds: Self.fillDelayMilliseconds) { [weak self] in
            self?.fillFromCallHistory(call: call, callbook: record)
        }
    }

    /// The body of the Kotlin effect after its delay: `CallbookPrefill.prefill(rec, cfields) +
    /// callHistory.prefill(call, cfields)` (in a contest, for a call of at least 3 characters) applied to the form as
    /// it is now.
    private func fillFromCallHistory(call: String, callbook: HamQthRecord?) {
        fillTimer = nil
        let active: Bool = contest.isActive
        let fields: [ContestDefinition.ExchangeField] = active ? contest.exchangeFields(call: call) : []
        let history = CallHistoryFill.fill(callHistory: callData.callHistory, call: call, fields: fields,
                                           contestActive: active)
        var fill = JavaLinkedMap<String>()
        if active && KotlinStrings.trim(call).utf16.count >= 3 {
            fill = CallbookPrefill.prefill(callbook, fields)
        }
        for (id, value) in history.entries {
            fill.put(id, value)
        }
        if fill.isEmpty && chFilled.isEmpty {
            return
        }
        let applied = CallHistoryFill.apply(form: formSource(), fill: fill, previouslyFilled: chFilled)
        chFilled = applied.filled
        formSink(applied.form)
    }

    private func refreshReverse(form: EntryForm) {
        let active: Bool = contest.isActive
        let fields: [ContestDefinition.ExchangeField] = active ? contest.exchangeFields(call: form.call) : []
        let key = ReverseKey(exchange: form.contestExchange, blankCall: KotlinStrings.isBlank(form.call),
                             callHistoryRevision: callData.callHistoryRevision, activeId: contest.activeId,
                             fieldIds: fields.map(\.id))
        guard key != reverseKey else { return }
        reverseKey = key
        let calls: [String] = CallHistoryFill.reverse(callHistory: callData.callHistory, form: form, fields: fields,
                                                      contestActive: active)
        if calls != shownReverse {
            shownReverse = calls
            reverse = calls
        }
    }

    // MARK: - picking

    /// Is the call in the log (N+1 colouring, Kotlin `c in logCalls`)?
    public func isLogged(_ call: String) -> Bool {
        logCalls.keys.contains(Array(call.utf16))
    }

    /// Kotlin `takeSuggestion(index)`: the suggested call (the entry sets it) and no highlight; `nil` = no such one.
    public func takeSuggestion(_ index: Int) -> String? {
        let calls: [String] = suggestions
        guard index >= 0, index < calls.count else { return nil }
        scpPick = -1
        return calls[index]
    }

    /// Sets the highlight (the entry's ↑/↓, clamped by the key router like Kotlin).
    public func setScpPick(_ index: Int) {
        scpPick = index
    }

    /// Kotlin `takeCall(c)` (N+1, reverse lookup): the highlight goes.
    public func tookCall() {
        scpPick = -1
    }

    /// ↓/↑ with suggestions (`EP:994-999`): `false` = no suggestions, the key is not consumed here.
    public func moveScpPick(_ delta: Int) -> Bool {
        let count: Int = partial.count
        guard count > 0 else { return false }
        if delta > 0 {
            scpPick = min(scpPick + 1, count - 1)
        } else {
            scpPick = max(scpPick - 1, -1)
        }
        return true
    }

    /// Esc with a highlight (`EP:992-993`): drops it; `false` = none (Esc wipes).
    public func clearScpPick() -> Bool {
        guard scpPick >= 0 else { return false }
        scpPick = -1
        return true
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
