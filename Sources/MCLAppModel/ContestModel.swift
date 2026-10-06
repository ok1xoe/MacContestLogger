import Foundation
import MCLCore
import Observation
import os

/// The active contest (Kotlin `AppState` contest part, `KA:1087-1257, 3428-3449, 3451-4005`) over `ContestRuntime`:
/// new/continue/open with the activation plan, the start-up offer, the recount (`RescoreScheduler`)
/// and the live preview and logging.
///
/// `ContestRuntime` is not observable, so the model mirrors what views read (`activeId`, `score`, `lastPreview`…)
/// after every change. SQLite work and replays run on `BlockingQueue`; a replay is adopted on the main thread only
/// when the log revision it was taken at is still current (`.stale` → replay again).
@Observable @MainActor
public final class ContestModel {

    /// Contest data (definitions, multiplier sets, DXCC, band plan).
    public private(set) var environment: ContestEnvironment
    @ObservationIgnored public private(set) var runtime: ContestRuntime

    public private(set) var activeId: String?
    public private(set) var activeName: String?
    public private(set) var definition: ContestDefinition?
    public private(set) var score: ScoreState?
    public private(set) var scoreError: ExpressionError?
    public private(set) var lastPreview: ContestSession.LogResult?
    /// Setup of the active contest, stored at activation (Kotlin re-reads the row on every `activeContestSetup()`).
    public private(set) var activeSetup: ContestSetup?
    /// QTCs of the active contest (Kotlin `qtcs`).
    public private(set) var qtcs: [QtcRecord] = []
    /// Offer Continue/New/Open (Kotlin `showStartupDialog`).
    public var showStartupDialog: Bool = false
    /// Activation effects of other subsystems (plugin event, cluster start), in order.
    public private(set) var deferredEffects: [ActivationEffect] = []

    /// Runs after a successful activation (the entry window takes the contest's mode and reports).
    @ObservationIgnored public var onActivated: (@MainActor () -> Void)?
    /// The activation's plugin event `CONTEST_OPENED` (an opening activation only): the event and its JSON.
    @ObservationIgnored public var onFirePlugin: (@MainActor (PluginRunner.Event, String) -> Void)?
    /// The activation's last step `.startClusterIfIdle`: the cluster starts when no session runs.
    @ObservationIgnored public var onStartClusterIfIdle: (@MainActor () -> Void)?
    /// Kotlin `availBands = …; availModes = …` of an opening activation (`AS:3605-3610`): the available
    /// multipliers' default filter.
    @ObservationIgnored public var onDefaultSpotFilters: (@MainActor (Set<Band>, Set<String>) -> Void)?

    @ObservationIgnored let scheduler: RescoreScheduler
    @ObservationIgnored private let config: ConfigModel
    @ObservationIgnored private let status: StatusModel
    @ObservationIgnored private let database: DatabaseModel
    @ObservationIgnored private let logbook: LogbookModel
    @ObservationIgnored private var capture: RescoreCapture?
    @ObservationIgnored private var activationChain: Task<Bool, Never>?
    /// A contest is being created, opened or activated (until its log is replayed and re-read). The entry accepts
    /// no input meanwhile: Kotlin activates synchronously on the UI thread, so nothing can be logged in between.
    public private(set) var isActivating: Bool = false
    @ObservationIgnored private var activationDepth: Int = 0
    @ObservationIgnored private var columnsKey: ColumnsKey?
    @ObservationIgnored private(set) var rescoreTask: Task<Void, Never>?
    /// Test seam: runs after an activation replay and before its adoption (a QSO logged here makes it stale).
    @ObservationIgnored var afterActivationReplay: (@MainActor () async -> Void)?

    /// What Kotlin `requestRescore` captures at request time (KA:1229-1232).
    private struct RescoreCapture {
        let contestId: String?
        let snapshot: [Qso]
        let before: Int64?
    }

    private struct ColumnsKey: Equatable {
        let activeId: String?
        let columns: [LogTableColumns.Column]
    }

    init(environment: ContestEnvironment, config: ConfigModel, status: StatusModel, database: DatabaseModel,
         logbook: LogbookModel, clock: any RescoreClock) {
        self.environment = environment
        self.config = config
        self.status = status
        self.database = database
        self.logbook = logbook
        self.scheduler = RescoreScheduler(clock: clock)
        self.runtime = Self.makeRuntime(environment, config: config)
        scheduler.onRun = { [weak self] job in
            self?.runRescore(job)
        }
        logbook.freshSession = { [weak self] in
            self?.runtime.freshSession()
        }
        logbook.onEdited = { [weak self] in
            self?.requestRescore()
        }
        sync()
    }

    /// Kotlin `buildContestController`: the station's call, grid and ITU zone are read live from the config.
    private static func makeRuntime(_ environment: ContestEnvironment, config: ConfigModel) -> ContestRuntime {
        ContestRuntime(
            environment: environment,
            myCall: { MainActor.assumeIsolated { config.config.station.call } },
            myGrid: { MainActor.assumeIsolated { config.config.station.gridSquare } },
            myItuZone: { MainActor.assumeIsolated { config.config.station.ituZone } })
    }

    /// Loads the contest environment off the main thread (`contestDataDir`, fallback `dataDir/contest-data`;
    /// DXCC from `dxccDir`, Kotlin `~/dxcc-json`). With `clubLogDxcc` the cached Club Log `cty.xml` in
    /// `dataDir/clublog` is the DXCC source when a copy exists.
    public nonisolated static func loadEnvironment(contestDataDir: String?, dxccDir: URL?, dataDir: URL,
                                                   clubLogDxcc: Bool = false) async -> ContestEnvironment {
        let fallback: String = dataDir.appendingPathComponent("contest-data").path
        let dxcc: String? = dxccDir?.path
        let cache = ClubLogCtyCache(dataDir: dataDir)
        let loaded: ContestEnvironment? = try? await BlockingQueue.run {
            ContestEnvironment.load(dataRoot: contestDataDir, dxccDir: dxcc, fallbackDataRoot: fallback,
                                    clubLog: clubLogDxcc ? cache.load() : nil)
        }
        return loaded ?? ContestEnvironment.load(dataRoot: nil, dxccDir: nil, fallbackDataRoot: "/nonexistent")
    }

    // MARK: - state

    public var isActive: Bool {
        activeId != nil
    }

    public var engineAvailable: Bool {
        environment.engineAvailable
    }

    /// Received exchange fields for the callsign (Kotlin `contest.exchangeFields(call)`; empty outside a contest).
    public func exchangeFields(call: String) -> [ContestDefinition.ExchangeField] {
        _ = definition
        return (try? runtime.exchangeFields(call: call)) ?? []
    }

    /// Kotlin `contest.isComplete(call, exchange)`.
    public func isComplete(call: String, exchange: JavaLinkedMap<String>) -> Bool {
        _ = definition
        return (try? runtime.isComplete(call: call, exchange: exchange)) ?? false
    }

    public var usesSerial: Bool {
        _ = definition
        return runtime.usesSerial
    }

    public var usesExchangeBeyondRst: Bool {
        _ = definition
        return runtime.usesExchangeBeyondRst
    }

    public var usesRoverQth: Bool {
        _ = definition
        return runtime.usesRoverQth
    }

    public var primaryMode: Mode {
        _ = definition
        return runtime.primaryMode
    }

    public var isMultiMode: Bool {
        _ = definition
        return runtime.isMultiMode
    }

    /// Copies the runtime state into the observable properties; the log table follows the contest's columns.
    private func sync() {
        activeId = runtime.activeId
        activeName = runtime.activeName
        definition = runtime.definition
        score = runtime.score
        scoreError = runtime.scoreError
        lastPreview = runtime.lastPreview
        let columns: [LogTableColumns.Column] = LogTableColumns.visible(
            usesSerial: runtime.usesSerial, usesExchangeBeyondRst: runtime.usesExchangeBeyondRst,
            contestActive: runtime.isActive)
        let key = ColumnsKey(activeId: runtime.activeId, columns: columns)
        if key != columnsKey {
            columnsKey = key
            logbook.setContestColumns(columns)
        }
    }

    // MARK: - preview and log

    /// Kotlin `contest.preview(...)` while typing (dupe and multiplier highlighting); an engine error keeps the
    /// previous preview.
    public func preview(call: String, band: String, mode: String, exchange: JavaLinkedMap<String>, ownQth: String?) {
        try? runtime.preview(call: call, band: band, mode: mode, exchange: exchange, ownQth: ownQth)
        lastPreview = runtime.lastPreview
    }

    /// Kotlin `contest.log(...)` after `state.log(qso)`; `nil` outside a contest. An engine error (a Kotlin crash)
    /// goes to the status line.
    @discardableResult
    public func log(call: String, band: String, mode: String, exchange: JavaLinkedMap<String>, ownQth: String?,
                    at: Date = Date()) -> ContestSession.LogResult? {
        defer { sync() }
        do {
            return try runtime.log(call: call, band: band, mode: mode, exchange: exchange, ownQth: ownQth, at: at)
        } catch {
            status.showVerbatim(error.description)
            return nil
        }
    }

    /// `log` for a caller that reports a failure itself (the external QSO ingest: Kotlin's exception becomes
    /// `"<source>: import selhal (…)"`); an engine error is thrown, the status line is not touched.
    @discardableResult
    func logOrThrow(call: String, band: String, mode: String, exchange: JavaLinkedMap<String>, ownQth: String?,
                    at: Date) throws(ContestSessionError) -> ContestSession.LogResult? {
        defer { sync() }
        return try runtime.log(call: call, band: band, mode: mode, exchange: exchange, ownQth: ownQth, at: at)
    }

    /// Menu `contest.none` (Kotlin `contest.deactivate()`): free logging. **A deliberate divergence from Kotlin**,
    /// whose logbook kept its active contest (the next QSOs went into that contest's log unscored): here the
    /// logbook leaves the contest too, so new QSOs are stored without a contest and the log shows the free-logging
    /// QSOs. One item of the activation chain; the entry accepts no input until the log is re-read.
    public func deactivate() {
        runtime.deactivate()
        activeSetup = nil
        qtcs = []
        sync()
        beginActivation()
        let previous: Task<Bool, Never>? = activationChain
        let task = Task { () -> Bool in
            _ = await previous?.value
            defer { self.endActivation() }
            // An activation already in flight at the click finished after it: its contest stays open.
            guard !self.isActive else { return false }
            await self.perform { try await self.logbook.setActiveContest(nil) }
            await self.perform { try await self.logbook.refresh() }
            return false
        }
        activationChain = task
    }

    // MARK: - new, continue, open

    /// Kotlin `createAndStartContest(definitionId, setup)`.
    @discardableResult
    public func createAndStart(definitionId: String, setup: ContestSetup) async -> Bool {
        beginActivation()
        defer { endActivation() }
        let contestsDir: URL? = runtime.contestsDir
        let yaml: String? = (try? await BlockingQueue.run {
            ContestRuntime.rawYaml(contestsDir: contestsDir, definitionId: definitionId)
        }) ?? nil
        let station: StationConfig = config.config.station
        let store: ConfigStore = config.store
        let created: Result<ContestActivation.Opening, ContestMessage>
        do {
            created = try await database.handle.run { access in
                try ContestActivation.createContest(definitionId: definitionId, yaml: yaml, setup: setup,
                                                    station: station, configStore: store, store: access.contests)
            }
        } catch {
            status.showVerbatim(ErrorText.message(error))
            return false
        }
        return await activateAndAnnounce(created)
    }

    /// Kotlin `continueLastContest()`: `false` when there is no readable last contest (no message).
    @discardableResult
    public func continueLastContest() async -> Bool {
        beginActivation()
        defer { endActivation() }
        let found: ContestActivation.Opening?? = try? await database.handle.run { access in
            try ContestActivation.continueLastContest(repository: access.repository, store: access.contests)
        }
        guard let opening = found ?? nil else { return false }
        return await activate(opening)
    }

    /// Kotlin `openContest(contestId)`.
    @discardableResult
    public func open(contestId: String) async -> Bool {
        beginActivation()
        defer { endActivation() }
        let found: Result<ContestActivation.Opening, ContestMessage>
        do {
            found = try await database.handle.run { access in
                try ContestActivation.openContest(contestId: contestId, store: access.contests)
            }
        } catch {
            status.showVerbatim(ErrorText.message(error))
            return false
        }
        return await activateAndAnnounce(found)
    }

    private func activateAndAnnounce(_ result: Result<ContestActivation.Opening, ContestMessage>) async -> Bool {
        switch result {
        case .failure(let message):
            status.show(message)
            return false
        case .success(let opening):
            guard await activate(opening) else { return false }
            if let started = opening.startedMessage {
                status.show(started)
            }
            return true
        }
    }

    /// Kotlin `offerStartupDialog()`: AUTORELOAD opens the last contest at once, otherwise the dialog is offered when
    /// the database holds a contest.
    public func offerStartupDialog() async {
        if config.config.autoReloadLastContest, await continueLastContest() {
            status.show("Otevřen poslední závod (AUTORELOAD)")
            return
        }
        let any: Bool? = try? await database.handle.run { access in
            !(try access.contests.listSummaries().isEmpty)
        }
        showStartupDialog = any ?? false
    }

    /// Kotlin `lastContestLabel()` (the Continue button).
    public func lastContestLabel() async -> String? {
        let label: String?? = try? await database.handle.run { access in
            try ContestActivation.lastContestLabel(repository: access.repository, store: access.contests)
        }
        return label ?? nil
    }

    /// Kotlin `contestBrowserRows()`, read once off the main thread.
    public func browserRows() async -> [ContestBrowserRow] {
        let store: ConfigStore = config.store
        let rows: [ContestBrowserRow]? = try? await database.handle.run { access in
            try ContestActivation.browserRows(store: access.contests, configStore: store)
        }
        return rows ?? []
    }

    /// The database was switched (Kotlin `openDatabase` after the swap): no contest, no active contest in the
    /// logbook, the log re-read (its recount request is a no-op without a contest).
    public func databaseSwitched() async {
        runtime.deactivate()
        activeSetup = nil
        qtcs = []
        sync()
        await perform { try await self.logbook.setActiveContest(nil) }
        await perform { try await self.logbook.refresh() }
        requestRescore()
    }

    // MARK: - activation

    /// Kotlin `activateContest(contestId, def)`; activations run one after another.
    @discardableResult
    public func activate(_ opening: ContestActivation.Opening) async -> Bool {
        beginActivation()
        defer { endActivation() }
        let previous: Task<Bool, Never>? = activationChain
        let task = Task { () -> Bool in
            _ = await previous?.value
            return await self.runActivation(opening, kind: .open)
        }
        activationChain = task
        return await task.value
    }

    private func beginActivation() {
        activationDepth += 1
        isActivating = true
    }

    private func endActivation() {
        activationDepth -= 1
        if activationDepth == 0 {
            isActivating = false
        }
    }

    /// Why a contest is activated: a user opening, or the reopen after a contest-data reload.
    private enum ActivationKind {
        case open
        case reopen
    }

    /// A reopen must not repeat the one-time effects of an opening (spot-filter reset, `CONTEST_OPENED`): the
    /// contest never closed from the user's point of view. Starting the cluster when idle stays.
    private func runActivation(_ opening: ContestActivation.Opening, kind: ActivationKind) async -> Bool {
        let interval: Perf.Interval = Perf.begin("activate")
        defer { Perf.end(interval) }
        let plan: ActivationPlan = ContestActivation.plan(row: opening.row, definition: opening.definition,
                                                          stationCall: config.config.station.call,
                                                          configStore: config.store)
        let contestId: String = plan.contestId
        for effect in plan.effects {
            switch effect {
            case .setSessionExtras(let tour, let bonusStations):
                runtime.setSessionExtras(tour: tour, bonusStations: bonusStations)
            case .activateDefinition:
                if let error = runtime.activate(contestId: contestId, definition: plan.definition) {
                    sync()
                    status.show(ContestActivation.failure(error))
                    return false
                }
                activeSetup = plan.setup
                sync()
            case .setActiveContest:
                await perform { try await self.logbook.setActiveContest(contestId) }
            case .setLastContestId:
                await perform {
                    try await self.database.handle.run { access in
                        try access.repository.metaSet("last_contest_id", contestId)
                    }
                }
            case .reloadQtcs:
                await reloadQtcs(contestId: contestId)
            case .replayLog:
                await replayLog(contestId: contestId)
            case .refreshFromLogbook:
                await perform { try await self.logbook.refresh() }
            case .setDefaultSpotFilters(let bands, let modes):
                if kind == .open {
                    onDefaultSpotFilters?(bands, modes)
                }
            case .firePlugin(let event, let json):
                if kind == .open {
                    deferredEffects.append(effect)
                    onFirePlugin?(event, json)
                }
            case .startClusterIfIdle:
                // `if (syncCoordinator == null) startClusterIfEnabled()` (`AS:3617`); still recorded.
                deferredEffects.append(effect)
                onStartClusterIfIdle?()
            }
        }
        onActivated?()
        return true
    }

    /// Kotlin `reloadQtcs(contestId)`.
    func reloadQtcs(contestId: String?) async {
        var records: [QtcRecord] = []
        if let contestId = KotlinStrings.nilIfBlank(contestId) {
            do {
                records = try await database.handle.run { access in
                    try access.repository.findQtcs(contestId: contestId)
                }
            } catch {
                status.showVerbatim(ErrorText.message(error))
            }
        }
        qtcs = records
        runtime.setQtcCount(Int32(records.count))
        sync()
    }

    /// `ActivationEffect.replayLog`: the contest's QSOs in Kotlin order replayed into a fresh session off the main
    /// thread, adopted only when the log revision is unchanged; `.stale` replays the current log again.
    private func replayLog(contestId: String) async {
        let interval: Perf.Interval = Perf.begin("replay")
        defer { Perf.end(interval, String(logbook.rows.count) + " qso") }
        while true {
            let revision: Int64 = logbook.revision
            guard let fresh = runtime.freshSession() else { return }
            let handle: LogbookHandle = database.handle
            do {
                let qsos: [Qso] = try await handle.run { access in
                    try access.repository.findAll(contestId: contestId)
                }
                try await BlockingQueue.run {
                    ContestRuntime.replayLogged(ContestActivation.replayOrder(qsos), into: fresh)
                }
            } catch {
                status.showVerbatim(ErrorText.message(error))
                return
            }
            await afterActivationReplay?()
            switch runtime.adopt(session: fresh, forContestId: contestId, replayedRevision: revision,
                                 currentRevision: logbook.revision) {
            case .adopted:
                reapplyExtras()
                sync()
                return
            case .stale:
                continue
            case .otherContest:
                return
            }
        }
    }

    /// A replayed session got the extras of its creation; ones changed meanwhile are applied again.
    private func reapplyExtras() {
        runtime.setSessionExtras(tour: runtime.tour, bonusStations: runtime.bonusStations)
        runtime.setQtcCount(runtime.qtcCount)
    }

    // MARK: - recount

    /// Kotlin `requestRescore(manual)`: captures the contest, the log snapshot and the score first (a manual request
    /// runs at once).
    public func requestRescore(manual: Bool = false) {
        if runtime.isActive {
            capture = RescoreCapture(contestId: runtime.activeId, snapshot: logbook.rows, before: runtime.score?.total)
        }
        if let message = scheduler.request(manual: manual, isActive: runtime.isActive, revision: logbook.revision) {
            status.show(message)
        }
    }

    private func runRescore(_ job: RescoreScheduler.Job) {
        guard let capture, let fresh = runtime.freshSession() else {
            scheduler.cancel()
            return
        }
        rescoreTask = Task { [weak self] in
            let outcome: ContestReplay.Outcome? = try? await BlockingQueue.run {
                Perf.measure("rescore", String(capture.snapshot.count) + " qso") {
                    ContestReplay.replay(fresh, capture.snapshot)
                }
            }
            guard let self, let outcome else { return }
            await self.finishRescore(job, capture: capture, outcome: outcome)
        }
    }

    private func finishRescore(_ job: RescoreScheduler.Job, capture: RescoreCapture,
                               outcome: ContestReplay.Outcome) async {
        switch scheduler.finish(job, currentRevision: logbook.revision) {
        case .discard:
            return
        case .rerun(let manual):
            requestRescore(manual: manual)
            return
        case .adopt:
            break
        }
        guard runtime.adopt(outcome, forContestId: capture.contestId) else { return }
        reapplyExtras()
        sync()
        guard job.manual else { return }
        let dxcc: (any DxccLookup)? = runtime.dxccLookup
        let snapshot: [Qso] = capture.snapshot
        let filled: Int = (try? await database.handle.run { access in
            RescoreScheduler.backfillDxcc(snapshot, dxcc: dxcc) { qso in
                try access.service.update(qso)
            }
        }) ?? 0
        if filled > 0 {
            logbook.bumpRevision()
        }
        let after: Int64 = runtime.score?.total ?? 0
        let parts: [ContestMessage] = RescoreScheduler.summary(replayed: outcome.replayed, skipped: outcome.skipped,
                                                               before: capture.before, after: after, filled: filled)
        status.showJoined(parts, separator: " · ")
    }

    // MARK: - setup of the active contest (TOUR, BONUS) and RELOAD

    /// The active contest's TOUR session (`contest.tour`).
    public var tour: Tour? {
        _ = definition
        return runtime.tour
    }

    /// The active contest's bonus stations (`contest.bonusStations`).
    public var bonusStations: [String] {
        _ = definition
        return runtime.bonusStations
    }

    /// Kotlin `contest.isKnownLocation(value)`: `nil` = the contest has no list of locations.
    public func isKnownLocation(_ value: String) -> Bool? {
        KnownLocation.check(value, definition: runtime.definition, registry: environment.registry)
    }

    /// Kotlin `updateSetup(change)` (`AS:3832-3844`): the active contest's setup changed and written to its database
    /// row, off the main thread. `false` = not saved, with Kotlin's status: no contest `tr("Není aktivní závod")`;
    /// otherwise `tr("Závod není v databázi — nastavení se neuložilo")` — also after a failed write, whose own text
    /// Kotlin overwrites at once.
    public func updateSetup(_ change: (inout ContestSetup) -> Void) async -> Bool {
        guard let id = activeId else {
            status.show(EntryTexts.noActiveContest)
            return false
        }
        var setup: ContestSetup = activeSetup ?? ContestSetup()
        change(&setup)
        let json: String = config.store.toJSON(setup)
        let saved: Bool
        do {
            saved = try await database.handle.run { access in
                try access.contests.updateSetup(contestId: id, setupJson: json)
            }
        } catch {
            saved = false
        }
        guard saved else {
            status.show("Závod není v databázi — nastavení se neuložilo")
            return false
        }
        if activeId == id {
            activeSetup = setup
        }
        return true
    }

    /// `contest.setSessionExtras(tour, bonusStations)`.
    public func setSessionExtras(tour: Tour?, bonusStations: [String]) {
        runtime.setSessionExtras(tour: tour, bonusStations: bonusStations)
        sync()
        // The marks replay into a session with the extras: the tracker is rebuilt over a fresh one.
        logbook.refreshMarks()
    }

    /// Where the contest data came from (RELOAD loads it again); set by the app model.
    @ObservationIgnored var environmentSource: (dxccDir: URL?, dataDir: URL)?

    /// Runs after every contest-data reload (the definition editor refreshes its lists).
    @ObservationIgnored public var onDataReloaded: (@MainActor () -> Void)?

    /// Kotlin `reloadAll()` (`AS:2093-2099`): the contest data loaded again (a new runtime without a contest), then
    /// the contest that was active opened again; status `tr("Definice závodů znovu načteny")` + `" a závod otevřen"`.
    public func reloadAll() async {
        let reopened: Bool = await reloadContestData(kind: .open)
        status.showJoined(EntryTexts.reloaded(contestOpen: reopened).parts, separator: "")
    }

    /// Kotlin `reloadContestData()` (`AS:3706-3708`, `contest = buildContestController()`) after the definition
    /// editor saves with reload, a county import, a definition update and a profile load: the contest data loaded
    /// again off the main thread and a new runtime.
    ///
    /// **A documented fix:** Kotlin's new controller has no active contest while the log keeps it, so the next
    /// QSOs go into the contest's log without score and dupe check until the contest is opened again. Here the
    /// contest that was active is opened again at once (its stored definition, setup and log replayed), without a
    /// status text of its own — the caller's text stays. The entry accepts no input until then (`isActivating`).
    ///
    /// - Returns: whether a contest was active (and its reopening was attempted).
    @discardableResult
    public func reloadContestData() async -> Bool {
        await reloadContestData(kind: .reopen)
    }

    /// `kind` is `.open` for the RELOAD command only (Kotlin `reloadAll` calls `openContest`, which resets the spot
    /// filters, fires `CONTEST_OPENED` and starts the cluster); the other reload paths reopen silently.
    @discardableResult
    private func reloadContestData(kind: ActivationKind) async -> Bool {
        beginActivation()
        defer { endActivation() }
        // One item of the activation chain: a reload never overlaps an activation or another reload (a second
        // reload started during the first one's reopen would read no active contest and drop it).
        let previous: Task<Bool, Never>? = activationChain
        let task = Task { () -> Bool in
            _ = await previous?.value
            return await self.runReload(kind: kind)
        }
        activationChain = task
        return await task.value
    }

    /// The reload as one chain item; the reopen goes straight to `runActivation` (not through the chain it is in).
    private func runReload(kind: ActivationKind) async -> Bool {
        let id: String? = activeId
        if let source = environmentSource {
            environment = await Self.loadEnvironment(contestDataDir: config.config.contestDataDir,
                                                     dxccDir: source.dxccDir, dataDir: source.dataDir,
                                                     clubLogDxcc: config.config.clubLog.ctyEnabled)
        }
        runtime = Self.makeRuntime(environment, config: config)
        activeSetup = nil
        sync()
        await beforeReopen?()
        if let id {
            await reopen(contestId: id, kind: kind)
        }
        onDataReloaded?()
        return id != nil
    }

    /// Kotlin `openContest(id)` without its text and without the chain (the caller is a chain item).
    private func reopen(contestId: String, kind: ActivationKind) async {
        let found: Result<ContestActivation.Opening, ContestMessage>
        do {
            found = try await database.handle.run { access in
                try ContestActivation.openContest(contestId: contestId, store: access.contests)
            }
        } catch {
            status.showVerbatim(ErrorText.message(error))
            return
        }
        switch found {
        case .failure(let message):
            status.show(message)
        case .success(let opening):
            _ = await runActivation(opening, kind: kind)
        }
    }

    /// Kotlin `reloadBandData()` (`AS:3717-3724`, after the Settings wrote the band plan and the digi frequencies):
    /// both read again from `contestDataDir` (blank → the default directory) off the main thread and put into the
    /// environment **without** a new runtime — the active contest, its session and the log stay as they are. One
    /// item of the activation chain, so a contest-data reload in flight (its environment read before the files were
    /// written) cannot replace the new tables afterwards.
    public func reloadBandData() async {
        guard let source = environmentSource else { return }
        let fallback: String = source.dataDir.appendingPathComponent("contest-data").path
        let root: URL = ContestEnvironment.dataRoot(configured: config.config.contestDataDir, fallback: fallback)
        let previous: Task<Bool, Never>? = activationChain
        let task = Task { () -> Bool in
            _ = await previous?.value
            let tables: (BandPlan, DigiFrequencies)? = try? await BlockingQueue.run {
                (BandPlan.fromDir(root), DigiFrequencies.fromDir(root))
            }
            if let tables {
                self.environment = self.environment.replacingBandData(bandPlan: tables.0, digiFrequencies: tables.1)
            }
            return false
        }
        activationChain = task
        _ = await task.value
    }

    /// Test seam: runs inside a reload after the runtime was replaced and before the contest is reopened.
    @ObservationIgnored var beforeReopen: (@MainActor () async -> Void)?

    // MARK: - helpers

    /// Kotlin lets SQLite exceptions escape (the UI would crash); here the error goes to the status line.
    private func perform(_ body: () async throws -> Void) async {
        do {
            try await body()
        } catch {
            status.showVerbatim(ErrorText.message(error))
        }
    }

    /// Waits for the activations in flight (quit, database switch).
    func settleActivations() async {
        while let task = activationChain {
            _ = await task.value
            if task == activationChain {
                return
            }
        }
    }

    /// Waits for a running recount (quit, database switch, tests).
    func settleRescore() async {
        while let task = rescoreTask {
            await task.value
            if task == rescoreTask {
                return
            }
        }
    }
}
