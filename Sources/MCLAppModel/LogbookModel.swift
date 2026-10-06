import Foundation
import MCLCore
import Observation
import os

/// The open contest's log (Kotlin `AppState.qsos`, `qsoCount`, `logRevision`, `dupeChecker`) and the log table's view
/// of it (`LogTable.kt`: sort, search, points and multipliers).
///
/// `rows` is a snapshot of the active contest's QSOs. A new QSO is inserted on `BlockingQueue`; the main thread only
/// appends the row and updates the dupe index (O(1)). Sorting and searching run off the main thread with a generation:
/// a late result of an older generation is dropped.
///
/// Edits and deletes (Kotlin `update`, `delete`, `deleteLastQso`, `wipeLog`, `bulkUpdate`) run as one job each on the
/// database handle's serial queue (`LogbookMutations`); their changes go into the dupe index. The marks and the
/// statistics of the operating rules follow an append at the end of the time line incrementally; anything else
/// recomputes them off the main thread with a generation.
@Observable @MainActor
public final class LogbookModel {

    /// How the displayed rows changed last (the table inserts one row, reloads the changed rows or removes the
    /// deleted ones instead of reloading everything).
    public enum ViewChange: Equatable, Sendable {
        case reload
        case appended(index: Int)
        /// The same rows in the same order; the rows at these indexes changed (an edit).
        case updated(indexes: [Int])
        /// The rows at these indexes of the previous view are gone; the others kept their order and content.
        case removed(indexes: [Int])
    }

    /// QSOs of the active contest (Kotlin `qsos`).
    public private(set) var rows: [Qso] = []
    /// The newest row (`rows.last`; one place for the expression, which is slow to type-check inside the entry model).
    public var lastRow: Qso? {
        rows.last
    }
    /// Raised with every change of the log (Kotlin `logRevision`); a recount compares it with its snapshot.
    public private(set) var revision: Int64 = 0
    /// Kotlin `qsoCount = logbook.count()`.
    public private(set) var qsoCount: Int = 0
    /// Active contest of the logbook (Kotlin `logbook.getActiveContest()`), `""` = none.
    public private(set) var activeContestId: String = ""

    /// Rows after search and sort (the log table).
    public private(set) var displayed: [Qso] = []
    /// Raised whenever `displayed` changes.
    public private(set) var displayRevision: Int = 0
    public private(set) var lastViewChange: ViewChange = .reload
    /// Sort column chosen by the operator (Kotlin `sortCol`, default time ascending).
    public private(set) var sortColumn: LogTableColumns.Column = .time
    public private(set) var ascending: Bool = true
    /// Search text (`QsoSearch`).
    public private(set) var query: String = ""
    /// Columns that make sense for the active contest (`LogTableColumns.visible`).
    public private(set) var visibleColumns: [LogTableColumns.Column] =
        LogTableColumns.visible(usesSerial: true, usesExchangeBeyondRst: true, contestActive: false)
    /// Points, dupe and new multipliers by QSO id (N1MM Marking Multipliers).
    public private(set) var marks: [Int64: QsoMarks.Mark] = [:]
    /// Raised whenever `marks` is replaced (the table reloads only the points and multiplier cells).
    public private(set) var marksRevision: Int = 0

    /// Warnings about possible errors by QSO id (Kotlin `state.logWarnings(snapshot)`, `LT:212`), computed off the
    /// main thread with a generation whenever the log, `master.scp` or the contest changes.
    public private(set) var warnings: LogWarnings.Warnings = LogWarnings.Warnings()
    /// Raised whenever `warnings` is replaced (the table reloads the warning cells).
    public private(set) var warningsRevision: Int = 0
    /// Kotlin `onlyWarnings`: the view shows only QSOs with a warning.
    public private(set) var onlyWarnings: Bool = false

    /// Effects this model does not perform itself (cluster publish, plugins, broadcast…), in the order they came.
    public private(set) var deferredEffects: [LogEffect] = []

    /// The time statistics of this station's QSOs (Kotlin `ContestStats.of(mine)` in `operatingViolation`, L1):
    /// QSOs without a station id or with `config.cluster.stationId`. Appended incrementally, recomputed off the main
    /// thread after anything else.
    public private(set) var statsForRules: ContestStats = ContestStats.of([])

    /// A fresh session of the active contest for the marks (`nil` outside a contest); set by the app model.
    @ObservationIgnored var freshSession: (@MainActor () -> ContestSession?)?
    /// `setRit(0)` after a logged QSO (the `.clearRit` effect); set by the app model to the rig's.
    @ObservationIgnored var clearRit: (@MainActor () -> Void)?
    /// This station's id (`config.cluster.stationId`) for `statsForRules`; set by the app model.
    @ObservationIgnored var ownStationId: @MainActor () -> String = { "" }
    /// Waits for the entry's submissions in flight (set by the app model): delete-last and WIPELOG take the log only
    /// after them, inside the mutation chain, so a QSO just submitted is never missed.
    @ObservationIgnored var settleInserts: (@MainActor () async -> Void)?
    /// After an edit or delete: Kotlin `requestRescore()` (debounced); set by the contest model.
    @ObservationIgnored var onEdited: (@MainActor () -> Void)?
    /// `master.scp` and the DXCC lookup of the warnings (Kotlin `state.scp`, `contest.dxccLookup`); set by the app
    /// model.
    @ObservationIgnored var warningSources: (@MainActor () -> WarningSources)?
    /// A QSO logged here (never an import) was stored: Club Log, the plugins, the broadcast and WSJT-X; set by
    /// the app model.
    @ObservationIgnored var onLiveQso: (@MainActor (Qso) -> Void)?
    /// A committed edit: the N1MM broadcast reports it as a replace.
    @ObservationIgnored var onQsoEdited: (@MainActor (_ old: Qso, _ new: Qso) -> Void)?
    /// A committed delete: the N1MM broadcast reports every deleted QSO.
    @ObservationIgnored var onQsoDeleted: (@MainActor (Qso) -> Void)?
    /// The pileup simulator is running (Kotlin `simulator != null`): `QsoLogPipeline.Context.simulatorActive`.
    @ObservationIgnored var simulatorActive: @MainActor () -> Bool = { false }
    /// The `.simulator` effect: the stored QSO is compared with the station that was worked.
    @ObservationIgnored var onSimulatorQso: (@MainActor (Qso) -> Void)?
    /// May this QSO be published outward (the cluster, its server serial, Club Log, the broadcast,
    /// the plugins — an insert, an edit or a delete)? Decided per QSO: no for a QSO the pileup simulator logged.
    @ObservationIgnored var outwardGate: @MainActor (Qso) -> Bool = { _ in true }
    /// The cluster session: publishes the writes, marks the QSO's origin, hands out the serial server's number
    /// and turns deletes into tombstones while it runs; set by the app model.
    @ObservationIgnored weak var cluster: ClusterSyncModel?
    /// The serial server's number handed to a submission that is not stored yet (a second submission before it is
    /// stored counts locally, above it).
    @ObservationIgnored private var serverSerialInUse: Int?

    @ObservationIgnored private let database: DatabaseModel
    @ObservationIgnored private let status: StatusModel
    @ObservationIgnored private var mutations = LogbookMutations(existing: [])
    /// Serials handed out for submissions not stored yet (one unit per QSO copy still to be inserted).
    public private(set) var reservedSerials: Int = 0
    /// Highest serial handed out in the active contest. A failed insert leaves a gap instead of a repeat: after A (N)
    /// fails and B (N+1) is stored, the count says N+1 again, the mark says N+2.
    @ObservationIgnored private var issuedHighWater: Int = 0
    @ObservationIgnored private var viewGeneration: Int = 0
    @ObservationIgnored private var viewCurrent: Bool = true
    @ObservationIgnored private var marksGeneration: Int = 0
    @ObservationIgnored private(set) var viewTask: Task<Void, Never>?
    @ObservationIgnored private(set) var marksTask: Task<Void, Never>?
    /// The one marks tracker (single owner, replaced as a whole after a recompute); `nil` outside a contest.
    @ObservationIgnored private var tracker: QsoMarksTracker?
    /// `tracker` holds the current `rows` (no recompute pending).
    @ObservationIgnored private var trackerCurrent: Bool = false
    @ObservationIgnored private var statsGeneration: Int = 0
    /// `statsForRules` holds the current `rows` of this station id.
    @ObservationIgnored private var statsStationId: String?
    @ObservationIgnored private(set) var statsTask: Task<Void, Never>?
    /// Edits and deletes run one after another (each is one job on the handle's serial queue).
    @ObservationIgnored private(set) var mutationTask: Task<Void, Never>?
    @ObservationIgnored private var warningsGeneration: Int = 0
    @ObservationIgnored private(set) var warningsTask: Task<Void, Never>?
    /// A fresh session of the active contest for the warnings' exchange fields (stateless queries only); dropped on
    /// a contest change.
    @ObservationIgnored private var warningsSession: ContestSession?
    @ObservationIgnored private var warningsSessionLoaded: Bool = false

    init(database: DatabaseModel, status: StatusModel) {
        self.database = database
        self.status = status
    }

    // MARK: - queries

    /// Next serial number to send (Kotlin `logbook.nextSerial()` = count of the active contest + 1); submissions
    /// reserved but not stored yet count too.
    public var nextSerial: Int {
        serverSerial ?? localNextSerial
    }

    /// Kotlin `nextSerial()` = `reservedSerial ?: logbook.nextSerial()` (`AS:2736`): the number reserved at the serial
    /// server, unless a submission already took it.
    /// Free logging (no active contest) always counts locally: its QSOs never reach the cluster.
    private var serverSerial: Int? {
        guard !activeContestId.isEmpty, let reserved = cluster?.reservedSerial, reserved != serverSerialInUse else {
            return nil
        }
        return reserved
    }

    private var localNextSerial: Int {
        max(qsoCount + reservedSerials + 1, issuedHighWater + 1)
    }

    /// The station id a QSO logged now carries (`config.cluster.stationId` while the cluster session exists, Kotlin
    /// `syncCoordinator?.let { qso.stationId = … }`), otherwise `nil`.
    public var syncStationId: String? {
        cluster?.stationId
    }

    /// The serial server's number the QSO being planned may carry (`QsoLogPipeline.Context.reservedSerial`).
    public var reservedServerSerial: Int? {
        cluster?.reservedSerial
    }

    /// Reserves the serial of a submission synchronously (Kotlin computes it on the UI thread right before the
    /// synchronous insert): returns `nextSerial` and counts `units` QSO copies as pending until `perform` stores
    /// or fails them (or `releaseReservation`).
    public func reserveSerial(units: Int = 1) -> Int {
        if cluster?.reservedSerial == nil {
            serverSerialInUse = nil
        }
        let serial: Int = nextSerial
        reservedSerials += units
        if serial == serverSerial {
            // The authority's number does not move the local high-water mark (Kotlin counts locally again from the
            // QSO count once the server number is used up).
            serverSerialInUse = serial
        } else {
            issuedHighWater = max(issuedHighWater, serial)
        }
        return serial
    }

    /// A submission with `serial` failed and its units are released: when no later serial was handed out meanwhile,
    /// the number is free again (the restored form re-submits with it); otherwise it stays a gap.
    public func withdrawSerial(_ serial: Int) {
        if serverSerialInUse == serial {
            serverSerialInUse = nil
        }
        if issuedHighWater == serial && reservedSerials == 0 {
            issuedHighWater = serial - 1
        }
    }

    /// Gives back reserved units that will not be stored.
    public func releaseReservation(_ units: Int = 1) {
        reservedSerials = max(0, reservedSerials - units)
    }

    /// Kotlin `isDupe(call, band)`: `band != null && dupeChecker.isDupe(call, band)`.
    public func isDupe(call: String, band: Band?) -> Bool {
        guard let band else { return false }
        return mutations.isDupe(call: call, band: band)
    }

    /// Kotlin `logbook.setClockOffset(Duration.ofMillis(offset))` (the NTP check): the offset is added to the time of
    /// the QSOs logged from now on (zero without the correction). A closed database keeps the old offset.
    public func setClockOffset(milliseconds: Int64) async {
        let seconds: TimeInterval = Double(milliseconds) / 1000.0
        _ = try? await database.handle.run { access in
            access.service.clockOffset = seconds
        }
    }

    /// Kotlin `effectiveSort`: the chosen column when visible, otherwise time.
    public var effectiveSort: LogTableColumns.Column {
        LogTableColumns.effectiveSort(sortColumn, visible: visibleColumns)
    }

    // MARK: - log state

    /// Kotlin `logbook.setActiveContest(id)`.
    public func setActiveContest(_ contestId: String?) async throws {
        let id: String = contestId ?? ""
        if id != activeContestId {
            // Another contest (or database): its serials start from its own count.
            issuedHighWater = 0
        }
        activeContestId = id
        try await database.handle.run { access in
            access.service.activeContestId = id
        }
    }

    /// Kotlin `refreshFromLogbook`: re-reads the active contest's QSOs and the count, rebuilds the dupe index and
    /// raises the revision. The recount (`rescore = true` in Kotlin) is requested by the caller.
    public func refresh() async throws {
        let interval: Perf.Interval = Perf.begin("refresh")
        defer { Perf.end(interval, String(rows.count) + " qso") }
        // The dupe index is built off the main thread too (O(n) over the whole log).
        let loaded: LoadedLog = try await database.handle.run { access in
            try Self.load(access.service)
        }
        take(loaded)
    }

    /// The active contest's log as `refresh` reads it: rows, count and the dupe index built from them.
    struct LoadedLog: Sendable {
        let rows: [Qso]
        let count: Int
        let mutations: LogbookMutations
    }

    /// Reads the log on the handle's queue (inside a job).
    nonisolated static func load(_ service: LogbookService) throws -> LoadedLog {
        let all: [Qso] = try service.findAll()
        return LoadedLog(rows: all, count: try service.count(), mutations: LogbookMutations(existing: all))
    }

    /// Takes a re-read log over: the rows, the count, the dupe index, the revision and every derived view.
    /// `importedIds`: rows of a merge keep the in-memory `imported` mark (a transient field, not stored — Kotlin
    /// keeps the merged instances in `qsos` until the next re-read).
    private func take(_ loaded: LoadedLog, importedIds: Set<Int64> = []) {
        let main: Perf.Interval = Perf.begin("refresh-main")
        defer { Perf.end(main) }
        var read: [Qso] = loaded.rows
        if !importedIds.isEmpty {
            for index in read.indices where read[index].id.map({ importedIds.contains($0) }) ?? false {
                read[index].imported = true
            }
        }
        rows = read
        qsoCount = loaded.count
        mutations = loaded.mutations
        revision += 1
        rowsReplaced()
    }

    /// Kotlin `logRevision++` (e.g. countries filled by a manual recount).
    public func bumpRevision() {
        revision += 1
    }

    /// Executes the logbook effects of `QsoLogPipeline.plan` for a prepared QSO: `persist` on `BlockingQueue`
    /// (together with the count), then on the main thread in order `bumpRevision`, `addDupe`, `appendRow`,
    /// `refreshCount`. Effects of other subsystems are recorded in `deferredEffects`; `status` and `contestLog` belong
    /// to the caller. Returns the stored QSO (`nil` when the plan has no `persist`).
    /// `reserved` = the QSO holds one unit of `reserveSerial`; it is released together with the new count (or on a
    /// refusal or failure), so `nextSerial` never moves back or skips.
    ///
    /// `contestId` = the active contest captured when the QSO was submitted (`nil` = the current one). The QSO is
    /// stored under it even if another contest became active meanwhile; the row, dupe index and count are then left
    /// to the new contest's re-read (only the revision is raised).
    @discardableResult
    public func perform(_ qso: Qso, effects: [LogEffect], reserved: Bool = false,
                        contestId: String? = nil) async throws -> Qso? {
        guard effects.contains(.persist) else {
            if reserved {
                releaseReservation()
            }
            return nil
        }
        let stored: (qso: Qso, count: Int)
        do {
            stored = try await database.handle.run { access in
                try Perf.measure("log-insert") {
                    let current: String = access.service.activeContestId
                    if let contestId {
                        access.service.activeContestId = contestId
                    }
                    defer { access.service.activeContestId = current }
                    return (try LogbookMutations.insert(qso, into: access.service), try access.service.count())
                }
            }
        } catch {
            if reserved {
                releaseReservation()
            }
            throw error
        }
        if reserved {
            releaseReservation()
        }
        let interval: Perf.Interval = Perf.begin("log-main")
        defer { Perf.end(interval) }
        // The simulated tag comes first, before the contest-switch return and every publishing effect.
        if effects.contains(.simulator) {
            onSimulatorQso?(stored.qso)
        }
        if let contestId, contestId != activeContestId {
            revision += 1
            return stored.qso
        }
        for effect in effects {
            switch effect {
            case .persist, .status, .contestLog:
                break
            case .bumpRevision:
                revision += 1
            case .addDupe:
                mutations.didInsert(stored.qso)
            case .appendRow:
                append(stored.qso)
            case .refreshCount:
                qsoCount = stored.count
            case .clearRit where clearRit != nil:
                // `if (ritHz != 0 && config.isRitClearAfterLog) setRit(0)` (`AS:2797`).
                clearRit?()
            case .consumeReservedSerial:
                // `reservedSerial = null; ensureSerialReservation()` (`AS:2781-2784`).
                if serverSerialInUse == stored.qso.serialSent {
                    serverSerialInUse = nil
                }
                // A simulated QSO never takes a cluster server serial.
                if outwardGate(stored.qso) {
                    cluster?.consumeReserved(stored.qso.serialSent)
                }
            case .publishInsert:
                if outwardGate(stored.qso) {
                    cluster?.publishInsert(stored.qso)
                }
            case .simulator where onSimulatorQso != nil:
                break // done before the loop (the tag precedes every publishing effect)
            case .simulator, .clearRit, .clubLog, .plugin, .broadcast, .wsjtx:
                deferredEffects.append(effect)
            }
        }
        // The effects of a QSO logged here (Club Log, plugins, broadcast, WSJT-X) are decided by their owners, in
        // Kotlin's order; `.plugin` is in the plan of a live QSO only.
        if effects.contains(.plugin), outwardGate(stored.qso) {
            onLiveQso?(stored.qso)
        }
        return stored.qso
    }

    // MARK: - edits and deletes

    /// A free-logging QSO (no contest) never goes to the cluster — not its insert, edit or delete: the wire carries
    /// no contest and a receiving station would file it under its own active contest.
    nonisolated static func syncsToCluster(_ qso: Qso) -> Bool {
        !qso.contestId.isEmpty
    }

    /// What an edit job returns to the main thread.
    private struct EditResult: Sendable {
        let changes: [LogbookMutations.Change]
        let error: String?
    }

    /// What a delete job returns to the main thread.
    private struct DeleteResult: Sendable {
        let changes: [LogbookMutations.Change]
        let count: Int
        let status: ContestMessage?
        /// The rows with a `uuid` were turned into tombstones (the cluster runs) and are published as deleted.
        var tombstoned: Bool = false
    }

    /// Kotlin `update(qso)` (`AS:2805-2818`): the edited row is shown at once (the model row is replaced on the main
    /// thread at submit), the write is one job on the handle's serial queue, and the stored result — the row as
    /// written (`Change.updated.new`) — replaces it. Then the dupe index, the revision, the view, the marks and the
    /// statistics follow, and the recount is requested (debounced).
    ///
    /// - Returns: the written row; `nil` when the row is no longer stored or the write failed (the error is shown).
    @discardableResult
    public func update(_ edit: LogbookMutations.Edit) async -> Qso? {
        await startUpdate(edit).value
    }

    /// `update` started now: the model row is replaced before this returns (a later edit of the same row starts
    /// from it), the write is queued behind the mutations before it.
    @discardableResult
    public func startUpdate(_ edit: LogbookMutations.Edit) -> Task<Qso?, Never> {
        let job: Task<EditResult, Never> = startEdits([edit])
        return Task { @MainActor in
            let result: EditResult = await job.value
            for change in result.changes {
                if case .updated(_, let new) = change {
                    return new
                }
            }
            return nil
        }
    }

    /// The bulk edit of the log table (Kotlin `bulkUpdate`, `AS:2839-2847`): every row is saved one by one in one job;
    /// the outcome's status (`"%s: upraveno %s QSO"` / `"%s: nic se nezměnilo"`) is shown at once, as Kotlin sets it
    /// right after the synchronous writes; a failed write shows its error afterwards.
    public func bulk(_ outcome: BulkAction.Outcome) async {
        _ = await startBulk(outcome).value
    }

    /// `bulk` started now (the status and the edited rows show before this returns).
    @discardableResult
    public func startBulk(_ outcome: BulkAction.Outcome) -> Task<Void, Never> {
        if let message = outcome.status {
            status.show(message)
        }
        let job: Task<EditResult, Never> = startEdits(outcome.edits)
        return Task { _ = await job.value }
    }

    /// The X-QSO toggle of the log table (`LT:364-367`): the row is updated, the status shows `"<call>: …"` at once.
    public func toggleXqso(_ row: Qso) async {
        _ = await startToggleXqso(row).value
    }

    /// `toggleXqso` started now.
    @discardableResult
    public func startToggleXqso(_ row: Qso) -> Task<Qso?, Never> {
        let toggled: (qso: Qso, status: ContestMessage) = LogTableEdit.toggleXqso(row)
        status.show(toggled.status)
        return startUpdate(LogbookMutations.Edit(old: row, new: toggled.qso))
    }

    /// Kotlin `delete(qso)` / `delete(list)`: a hard delete in one job — while the cluster runs a tombstone for every
    /// row with a `uuid` (#31, `persistDelete`), published as deleted; the rows still stored are removed from the log,
    /// the dupe index, the count, the marks and the statistics.
    public func delete(_ rows: [Qso]) async {
        _ = await startDelete(rows).value
    }

    /// `delete` queued now behind the mutations before it; the task tells whether the job succeeded (a failure has
    /// shown its error).
    @discardableResult
    public func startDelete(_ rows: [Qso]) -> Task<Bool, Never> {
        guard !rows.isEmpty else { return Task { true } }
        let tombstone: Bool = cluster?.isRunning ?? false
        return enqueueDelete(rows: false) { _, service in
            let changes: [LogbookMutations.Change] = try LogbookMutations.delete(rows, in: service,
                                                                                tombstone: tombstone)
            return DeleteResult(changes: changes, count: try service.count(), status: nil, tombstoned: tombstone)
        }
    }

    /// Kotlin `deleteLastQso` (Ctrl+D): the row is picked when the job runs — the last row of the log at that moment
    /// that is still stored (`tr("Deník je prázdný")` / `tr("Smazáno poslední QSO %s")`). The caller waits for the
    /// submissions in flight first, so the QSO just logged is the last row.
    public func deleteLast() async {
        let tombstone: Bool = cluster?.isRunning ?? false
        await performDelete(rows: true) { rows, service in
            let result = try LogbookMutations.deleteLast(of: rows, in: service, tombstone: tombstone)
            return DeleteResult(changes: result.changes, count: try service.count(), status: result.status,
                                tombstoned: tombstone)
        }
    }

    /// Kotlin `wipeLog` (WIPELOG / CLEARLOGNOW): every row of the log at execution time is deleted, status
    /// `tr("Deník vymazán (%s QSO)")`. L6: the serial high-water mark is reset (unless a submission is in flight), so the
    /// next serial is 1 again (Kotlin `count + 1`) even after an earlier gap. County line, note and CQ frequencies stay.
    public func wipeLog() async {
        let tombstone: Bool = cluster?.isRunning ?? false
        await performDelete(rows: true) { rows, service in
            let result = try LogbookMutations.wipe(rows, in: service, tombstone: tombstone)
            return DeleteResult(changes: result.changes, count: try service.count(), status: result.status,
                                tombstoned: tombstone)
        } after: { model in
            // A submission reserved inside the wipe window (after the settle, before the job ended) is still in
            // flight and keeps its serial and its reservation; the numbers start again only when none is.
            if model.reservedSerials == 0 {
                model.issuedHighWater = 0
            }
        }
    }

    // MARK: - import and merge

    /// What an import or merge job inserts: the QSOs (in order) and a value for the caller (e.g. the duplicates).
    public struct BatchPlan<Value: Sendable>: Sendable {
        public var qsos: [Qso]
        public var value: Value

        public init(qsos: [Qso], value: Value) {
            self.qsos = qsos
            self.value = value
        }
    }

    /// The end of an import or merge job.
    public enum BatchOutcome<Value: Sendable>: Sendable {
        /// `prepare` failed: nothing was inserted and the log is unchanged.
        case refused(any Error)
        /// `inserted` QSOs were stored; `error` = an insert failed after them (the ones before it stay, as in Kotlin's
        /// loop of `logbook.log` calls) or the re-read failed.
        case stored(inserted: Int, value: Value, error: (any Error)?)
    }

    /// Kotlin `importQsos` / `mergeLog` (`AS:4115-4180`): one job on the handle's serial queue, chained behind the other
    /// mutations: `prepare` runs first with the database (the merge reads the log it compares against here, not from
    /// a main-thread snapshot), then every planned QSO goes through `LogbookService.log` (the active contest of the
    /// log), then the log is re-read in the same job. On the main thread the rows, the count, the dupe index (a full
    /// rebuild, Kotlin `DupeChecker(logbook.findAll())`), the revision, the view, the marks, the statistics and the
    /// warnings follow. The recount is the caller's (Kotlin `requestRescore()`).
    ///
    /// Ordering: the job waits for the submissions already made (`settleInserts`, which also waits for a submission
    /// chained behind another), so every QSO submitted before the import or merge is stored before `prepare` runs —
    /// the merge compares against it instead of inserting its twin. Nothing is read from the main thread for the job
    /// (`prepare` reads inside it). A QSO submitted later queues its insert behind the job (or ahead of it, when its
    /// insert reached the handle first): its row is appended after the re-read or is part of it — never twice, as the
    /// main-thread halves resume in the handle queue's order.
    ///
    /// `contestId`: the log's active contest the caller prepared for (the exchange conversion, the merge filter); when
    /// the active contest differs at job time (a contest switch waited in the chain) the job refuses with
    /// `ContestChanged` and inserts nothing — Kotlin runs all of it synchronously, so it cannot happen there.
    public func importBatch<Value: Sendable>(
        contestId: String? = nil,
        _ prepare: @escaping @Sendable (LogbookHandle.Access) throws -> BatchPlan<Value>
    ) async -> BatchOutcome<Value> {
        await enqueue { () -> BatchOutcome<Value> in
            await self.settleInserts?()
            let handle: LogbookHandle = self.database.handle
            let job: BatchJob<Value>
            do {
                job = try await handle.run { access in
                    try Perf.measure("log-import") {
                        if let contestId, !access.service.activeContestId.utf16.elementsEqual(contestId.utf16) {
                            return BatchJob<Value>.refused(ContestChanged())
                        }
                        return try Self.runBatch(access, prepare)
                    }
                }
            } catch {
                // The handle is closed: nothing ran.
                return .refused(error)
            }
            switch job {
            case .refused(let error):
                return .refused(error)
            case .stored(let inserted, let value, let error, let loaded, let importedIds):
                if let loaded {
                    self.take(loaded, importedIds: importedIds)
                } else {
                    self.revision += 1
                }
                return .stored(inserted: inserted, value: value, error: error)
            }
        }.value
    }

    // MARK: - DXCC refill

    /// What `refillDxcc` did: the QSOs read and the ones whose country changed; `error` = an update or the re-read
    /// failed (the rows updated before it stay, as in Kotlin's loop of `logbook.update` calls).
    public struct RefillOutcome: Sendable {
        public let total: Int
        public let changed: Int
        public let error: (any Error)?
    }

    /// Kotlin `refillDxcc()` (`AS:1162-1186`) on the log: one job on the handle's serial queue, chained behind the
    /// other mutations (submissions in flight are stored first): `findAll` of the active contest,
    /// `DxccFiller.refillAll`, `LogbookService.update` for every changed QSO — locally only (no sync, no recount: the
    /// country does not affect the score) — and, when anything changed, the log re-read in the same job. Only then
    /// the rows and the revision change (Kotlin `logRevision++` only on a change). `nil` = the handle is closed.
    public func refillDxcc(_ dxcc: any DxccLookup) async -> RefillOutcome? {
        await enqueue { () -> RefillOutcome? in
            await self.settleInserts?()
            let job: RefillJob
            do {
                job = try await self.database.handle.run { access in
                    try Perf.measure("refill-dxcc") {
                        try Self.runRefill(access.service, dxcc)
                    }
                }
            } catch {
                return nil
            }
            if let loaded = job.loaded {
                self.take(loaded)
            } else if job.updated > 0 {
                // Rows were rewritten but the re-read failed: the snapshots taken before are stale.
                self.revision += 1
            }
            return RefillOutcome(total: job.total, changed: job.changed, error: job.error)
        }.value
    }

    private struct RefillJob: Sendable {
        let total: Int
        let changed: Int
        let updated: Int
        let error: (any Error)?
        let loaded: LoadedLog?
    }

    private nonisolated static func runRefill(_ service: LogbookService, _ dxcc: any DxccLookup) throws -> RefillJob {
        var snapshot: [Qso] = try service.findAll()
        let changed: [Qso] = DxccFiller.refillAll(&snapshot, dxcc)
        var failure: (any Error)?
        var updated: Int = 0
        for qso in changed {
            do {
                try service.update(qso)
                updated += 1
            } catch {
                failure = error
                break
            }
        }
        guard updated > 0 else {
            return RefillJob(total: snapshot.count, changed: changed.count, updated: 0, error: failure, loaded: nil)
        }
        do {
            return RefillJob(total: snapshot.count, changed: changed.count, updated: updated, error: failure,
                             loaded: try load(service))
        } catch {
            return RefillJob(total: snapshot.count, changed: changed.count, updated: updated, error: failure ?? error,
                             loaded: nil)
        }
    }

    /// The log's active contest changed between the preparation of an import or merge and its job.
    public struct ContestChanged: Error, Equatable {}

    /// What the import job hands back from the handle's queue.
    private enum BatchJob<Value: Sendable>: Sendable {
        case refused(any Error)
        case stored(inserted: Int, value: Value, error: (any Error)?, loaded: LoadedLog?, importedIds: Set<Int64>)
    }

    private nonisolated static func runBatch<Value: Sendable>(
        _ access: LogbookHandle.Access, _ prepare: (LogbookHandle.Access) throws -> BatchPlan<Value>
    ) throws -> BatchJob<Value> {
        let plan: BatchPlan<Value>
        do {
            plan = try prepare(access)
        } catch {
            return .refused(error)
        }
        var inserted: Int = 0
        var importedIds: Set<Int64> = []
        var failure: (any Error)?
        for qso in plan.qsos {
            do {
                let stored: Qso = try LogbookMutations.insert(qso, into: access.service)
                inserted += 1
                if stored.imported, let id = stored.id {
                    importedIds.insert(id)
                }
            } catch {
                failure = error
                break
            }
        }
        do {
            let loaded: LoadedLog = try load(access.service)
            return .stored(inserted: inserted, value: plan.value, error: failure, loaded: loaded,
                           importedIds: importedIds)
        } catch {
            return .stored(inserted: inserted, value: plan.value, error: failure ?? error, loaded: nil,
                           importedIds: importedIds)
        }
    }

    /// Waits for the edits and deletes in flight (tests, quit).
    func settleMutations() async {
        while let task = mutationTask {
            await task.value
            if task == mutationTask {
                return
            }
        }
    }

    /// Queues `body` after the mutations enqueued before it (their main-thread halves stay in order); the place in
    /// the queue is taken when this is called.
    private func enqueue<T: Sendable>(_ body: @escaping @MainActor () async -> T) -> Task<T, Never> {
        let previous: Task<Void, Never>? = mutationTask
        let task = Task { @MainActor () -> T in
            await previous?.value
            return await body()
        }
        mutationTask = Task {
            _ = await task.value
        }
        return task
    }

    /// The edited rows are shown at once (Kotlin edits the shared row instance before the write), the write is
    /// queued.
    private func startEdits(_ edits: [LogbookMutations.Edit]) -> Task<EditResult, Never> {
        guard !edits.isEmpty else { return Task { EditResult(changes: [], error: nil) } }
        for edit in edits {
            showEdited(edit.new)
        }
        scheduleView(diff: true)
        return enqueue {
            let handle: LogbookHandle = self.database.handle
            let result: EditResult
            do {
                result = try await handle.run { access in
                    Perf.measure("log-update", String(edits.count) + " qso") {
                        let out = LogbookMutations.bulk(edits, in: access.service)
                        return EditResult(changes: out.changes, error: out.error.map { ErrorText.message($0) })
                    }
                }
            } catch {
                result = EditResult(changes: [], error: ErrorText.message(error))
            }
            await self.takeEdits(result)
            return result
        }
    }

    /// The model row of an edit at submit (Kotlin edits the shared row instance before the write).
    private func showEdited(_ qso: Qso) {
        guard let id = qso.id, let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[index] = qso
    }

    private func takeEdits(_ result: EditResult) async {
        let interval: Perf.Interval = Perf.begin("log-update-main")
        mutations.apply(result.changes)
        for change in result.changes {
            if case .updated(let old, let new) = change {
                showEdited(new)
                if outwardGate(new) {
                    onQsoEdited?(old, new)
                    if Self.syncsToCluster(new) {
                        cluster?.publishUpdate(new)
                    }
                }
            }
        }
        revision += 1
        Perf.end(interval, String(result.changes.count) + " qso")
        if let error = result.error {
            // The rows shown at submit may now differ from the database: read it again.
            status.showVerbatim(error)
            do {
                try await refresh()
            } catch {
                status.showVerbatim(ErrorText.message(error))
            }
        } else {
            rowsReplaced(diff: true)
        }
        onEdited?()
    }

    /// One delete job; `rows: true` hands it the log as it is when the job starts (after earlier mutations).
    private func performDelete(rows withRows: Bool,
                               _ job: @escaping @Sendable ([Qso], LogbookService) throws -> DeleteResult,
                               after: (@MainActor (LogbookModel) -> Void)? = nil) async {
        _ = await enqueueDelete(rows: withRows, job, after: after).value
    }

    private func enqueueDelete(rows withRows: Bool,
                               _ job: @escaping @Sendable ([Qso], LogbookService) throws -> DeleteResult,
                               after: (@MainActor (LogbookModel) -> Void)? = nil) -> Task<Bool, Never> {
        enqueue { () -> Bool in
            if withRows {
                await self.settleInserts?()
            }
            // The submissions made so far are stored (`settleInserts`), so `snapshot` holds them. The rows are read
            // before `handle.run` hops off the main thread to enqueue the job; a submission whose insert reaches the
            // handle in that hop is not in the snapshot and survives the delete (its row is appended afterwards).
            let snapshot: [Qso] = withRows ? self.rows : []
            let handle: LogbookHandle = self.database.handle
            do {
                let result: DeleteResult = try await handle.run { access in
                    try Perf.measure("log-delete", String(snapshot.count) + " qso") {
                        try job(snapshot, access.service)
                    }
                }
                self.takeDeletes(result)
                after?(self)
                if let message = result.status {
                    self.status.show(message)
                }
                self.onEdited?()
                return true
            } catch {
                self.status.showVerbatim(ErrorText.message(error))
                self.onEdited?()
                return false
            }
        }
    }

    private func takeDeletes(_ result: DeleteResult) {
        mutations.apply(result.changes)
        var ids: Set<Int64> = []
        for change in result.changes {
            if case .deleted(let qso) = change, let id = qso.id {
                ids.insert(id)
                if outwardGate(qso) {
                    onQsoDeleted?(qso)
                    if result.tombstoned && !qso.uuid.isEmpty && Self.syncsToCluster(qso) {
                        cluster?.publishDelete(qso)
                    }
                }
            }
        }
        rows.removeAll { row in row.id.map { ids.contains($0) } ?? false }
        qsoCount = result.count
        revision += 1
        rowsReplaced(diff: true)
    }

    // MARK: - view

    /// Kotlin `onSort(col)`: the same column flips the direction, another one sorts ascending.
    public func sort(by column: LogTableColumns.Column) {
        if sortColumn == column {
            ascending.toggle()
        } else {
            sortColumn = column
            ascending = true
        }
        scheduleView()
    }

    public func setQuery(_ text: String) {
        query = text
        scheduleView()
    }

    /// Kotlin `onToggleWarnings`: only the QSOs with a warning, or all of them again.
    public func setOnlyWarnings(_ on: Bool) {
        guard on != onlyWarnings else { return }
        onlyWarnings = on
        scheduleView()
    }

    /// The contest changed: visible columns, the marks and the warnings follow it.
    public func setContestColumns(_ columns: [LogTableColumns.Column]) {
        visibleColumns = columns
        scheduleView()
        scheduleMarks()
        dropWarningsSession()
        scheduleWarnings()
    }

    /// Recomputes the marks (Kotlin `LaunchedEffect(snapshot, contest.activeId)`).
    public func refreshMarks() {
        scheduleMarks()
        dropWarningsSession()
        scheduleWarnings()
    }

    /// Recomputes the warnings (`master.scp` was loaded again: Kotlin `remember(snapshot, state.scp, …)`).
    public func refreshWarnings() {
        scheduleWarnings()
    }

    private func append(_ qso: Qso) {
        rows.append(qso)
        if canAppendDirectly(qso) {
            displayed.append(qso)
            lastViewChange = .appended(index: displayed.count - 1)
            displayRevision += 1
        } else {
            scheduleView()
        }
        appendMarks(qso)
        appendStats(qso)
        scheduleWarnings()
    }

    /// A new row goes to the end of the time-ascending, unfiltered view without a re-sort (`QsoSort` is stable and
    /// puts QSOs without a time last).
    private func canAppendDirectly(_ qso: Qso) -> Bool {
        guard viewCurrent, query.isEmpty, !onlyWarnings, effectiveSort == .time, ascending,
              let time = qso.timestampUtc else {
            return false
        }
        guard let last = displayed.last else { return true }
        guard let lastTime = last.timestampUtc else { return false }
        return lastTime <= time
    }

    /// `diff`: the rows changed by an edit or a delete — the view reports the changed or removed rows when the order
    /// of the others stayed (the table then reloads or removes only those).
    private func rowsReplaced(diff: Bool = false) {
        scheduleView(diff: diff)
        scheduleMarks()
        scheduleStats()
        scheduleWarnings()
    }

    private func scheduleView(diff: Bool = false) {
        viewGeneration += 1
        viewCurrent = false
        let generation: Int = viewGeneration
        let snapshot: [Qso] = rows
        let column: LogTableColumns.Column = effectiveSort
        let ascending: Bool = self.ascending
        let query: String = self.query
        // A later generation is scheduled before `displayed` changes again, so the view this one replaces is the
        // current one when its result is taken.
        let previous: [Qso]? = diff ? displayed : nil
        let warned: Set<Int64>? = onlyWarnings ? Set(warnings.ids) : nil
        viewTask = Task { [weak self] in
            let result: (rows: [Qso], change: ViewChange)? = try? await BlockingQueue.run {
                Perf.measure("view", String(snapshot.count) + " qso") {
                    var filtered: [Qso] = QsoSearch.filter(snapshot, query)
                    if let warned {
                        filtered = filtered.filter { qso in qso.id.map { warned.contains($0) } ?? false }
                    }
                    let sorted: [Qso] = QsoSort.sort(filtered, key: LogTableColumns.sortKey(for: column),
                                                     ascending: ascending)
                    let change: ViewChange = previous.map { LogViewDiff.change(from: $0, to: sorted) } ?? .reload
                    return (sorted, change)
                }
            }
            guard let self, let result, generation == self.viewGeneration else { return }
            self.displayed = result.rows
            self.viewCurrent = true
            self.lastViewChange = result.change
            self.displayRevision += 1
        }
    }

    private func dropWarningsSession() {
        warningsSession = nil
        warningsSessionLoaded = false
    }

    /// Kotlin `remember(snapshot, state.scp, state.contest.activeId) { state.logWarnings(snapshot) }` off the main
    /// thread with a generation. A failing exchange-field expression (Kotlin: the composition throws) gives no
    /// warnings.
    private func scheduleWarnings() {
        warningsGeneration += 1
        let generation: Int = warningsGeneration
        if !warningsSessionLoaded {
            warningsSession = freshSession?()
            warningsSessionLoaded = true
        }
        let session: ContestSession? = warningsSession
        let sources: WarningSources = warningSources?() ?? WarningSources(scp: nil, dxcc: nil)
        let snapshot: [Qso] = rows
        warningsTask = Task { [weak self] in
            let result: LogWarnings.Warnings? = try? await BlockingQueue.run {
                Perf.measure("log-warnings", String(snapshot.count) + " qso") {
                    Self.analyzeWarnings(snapshot, session: session, sources: sources)
                }
            }
            guard let self, let result, generation == self.warningsGeneration else { return }
            let changed: Bool = result != self.warnings
            self.warnings = result
            self.warningsRevision += 1
            if changed && self.onlyWarnings {
                self.scheduleView()
            }
        }
    }

    /// Kotlin `AppState.logWarnings(list)` (`AS:2828-2837`).
    nonisolated static func analyzeWarnings(_ qsos: [Qso], session: ContestSession?,
                                            sources: WarningSources) -> LogWarnings.Warnings {
        let scp: ScpDatabase? = sources.scp.flatMap { $0.size > 0 ? $0 : nil }
        let dxcc: (any DxccLookup)? = sources.dxcc
        let inScp: ((String) -> Bool)? = scp.map { db in { call in db.contains(call) } }
        do {
            return try LogWarnings.analyze(
                qsos,
                receivedFields: { call in try session?.activeReceivedFields(call: call) ?? [] },
                inScp: inScp,
                cqZones: { call in Set(dxcc?.resolve(call)?.cq ?? []) },
                ituZones: { call in Set(dxcc?.resolve(call)?.itu ?? []) })
        } catch {
            return LogWarnings.Warnings()
        }
    }

    /// A QSO at the end of the time line is replayed into the tracker's session on the main thread; otherwise
    /// (or while a recompute is pending) the marks are recomputed.
    private func appendMarks(_ qso: Qso) {
        guard trackerCurrent, let tracker else {
            scheduleMarks()
            return
        }
        let interval: Perf.Interval = Perf.begin("marks")
        let appended: Bool = tracker.append(qso)
        Perf.end(interval, "append")
        if appended {
            marks = tracker.marks
            marksRevision += 1
        } else {
            scheduleMarks()
        }
    }

    /// The full recompute off the main thread: a new tracker over a fresh session replaces the old one as a whole.
    private func scheduleMarks() {
        marksGeneration += 1
        trackerCurrent = false
        let generation: Int = marksGeneration
        guard let fresh = freshSession?() else {
            tracker = nil
            marks = [:]
            marksRevision += 1
            marksTask = nil
            return
        }
        let snapshot: [Qso] = rows
        marksTask = Task { [weak self] in
            let result: QsoMarksTracker? = try? await BlockingQueue.run {
                Perf.measure("marks", String(snapshot.count) + " qso") {
                    QsoMarksTracker.recomputed(fresh: fresh, qsos: snapshot)
                }
            }
            guard let self, generation == self.marksGeneration else { return }
            self.tracker = result
            self.trackerCurrent = result != nil
            self.marks = result?.marks ?? [:]
            self.marksRevision += 1
        }
    }

    /// L1: this station's statistics follow an append at the end of the time line.
    private func appendStats(_ qso: Qso) {
        let me: String = ownStationId()
        guard statsStationId == me else {
            scheduleStats()
            return
        }
        guard Self.isOwn(qso, me) else { return }
        if let next = statsForRules.appending(qso) {
            statsForRules = next
        } else {
            scheduleStats()
        }
    }

    /// `ContestStats.of(mine)` off the main thread.
    private func scheduleStats() {
        statsGeneration += 1
        statsStationId = nil
        let generation: Int = statsGeneration
        let me: String = ownStationId()
        let snapshot: [Qso] = rows
        statsTask = Task { [weak self] in
            let result: ContestStats? = try? await BlockingQueue.run {
                Perf.measure("operating-rules-stats", String(snapshot.count) + " qso") {
                    ContestStats.of(snapshot.filter { Self.isOwn($0, me) })
                }
            }
            guard let self, let result, generation == self.statsGeneration else { return }
            self.statsForRules = result
            self.statsStationId = me
        }
    }

    /// Kotlin `qsos.filter { it.stationId.isNullOrBlank() || it.stationId == me }`.
    nonisolated static func isOwn(_ qso: Qso, _ me: String) -> Bool {
        KotlinStrings.isBlank(qso.stationId) || qso.stationId == me
    }

    /// Waits for the pending view and marks computations (tests, measurements).
    func settle() async {
        while true {
            let view = viewTask
            let marks = marksTask
            let stats = statsTask
            let mutation = mutationTask
            let warnings = warningsTask
            await mutation?.value
            await view?.value
            await marks?.value
            await stats?.value
            await warnings?.value
            if view == viewTask && marks == marksTask && stats == statsTask && mutation == mutationTask
                && warnings == warningsTask {
                return
            }
        }
    }
}

/// What the log warnings read besides the log: `master.scp` (`nil` or empty = not checked) and the DXCC lookup.
public struct WarningSources: Sendable {
    public let scp: ScpDatabase?
    public let dxcc: (any DxccLookup)?

    public init(scp: ScpDatabase?, dxcc: (any DxccLookup)?) {
        self.scp = scp
        self.dxcc = dxcc
    }
}

/// How the log view changed after an edit or a delete (`LogbookModel.ViewChange`): the rows of `new` are the rows
/// of `old` in the same order with some changed (`updated`), or `old` without some rows (`removed`); anything else
/// is a `reload`.
public enum LogViewDiff {

    public static func change(from old: [Qso], to new: [Qso]) -> LogbookModel.ViewChange {
        if old.count == new.count {
            var changed: [Int] = []
            for index in old.indices {
                guard old[index].id == new[index].id else { return .reload }
                if old[index] != new[index] {
                    changed.append(index)
                }
            }
            return .updated(indexes: changed)
        }
        guard new.count < old.count else { return .reload }
        var removed: [Int] = []
        var next: Int = 0
        for index in old.indices {
            if next < new.count && old[index].id == new[next].id && old[index] == new[next] {
                next += 1
            } else {
                removed.append(index)
            }
        }
        return next == new.count ? .removed(indexes: removed) : .reload
    }
}
