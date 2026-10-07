import Foundation
import MCLCore
import Observation
import os

/// The DX cluster connections of v1.1.1 (`AS:144-146, 170, 336-398`, `ui/dxcluster/DxClusterConnection.kt`): the
/// main connection driven from the DX Cluster window and the **parallel** ones (favourites with „Souběžně": more
/// nodes, RBN and skimmers at once) that share its spot buffer and traffic log (lines prefixed `[tag] `).
///
/// Threads: every connection has its `ClusterLane`; the session calls run there. `onChange` (called under
/// the session's lock) only posts a hop to the main actor, which re-reads the session's `snapshot` into `main` /
/// `parallel` — a connection the parallel plan dropped meanwhile is ignored by its token. `onSpot` runs on the reader
/// thread and only calls the `Sendable` ports `pluginSpot` and `spotShare`; `onSelfSpot` hops to the main actor
/// and writes the message window; the traffic log's changes are coalesced into `logRevision`. An error the session
/// does not handle (`onUnexpectedError`, a throwing call on the lane) goes to the traffic log and the status line.
@Observable @MainActor
public final class DxClusterModel {

    /// The main connection's state (Kotlin `dxCluster.connected/status/loggedIn/lastWwv/currentFavorite`).
    public private(set) var main = DxClusterSession.Snapshot()
    /// The parallel connections' states by connection key (`host:port`), in `parallelKeys` order.
    public internal(set) var parallel: [String: DxClusterSession.Snapshot] = [:]
    /// Kotlin `parallelClusters.keys` in insertion order (`mutableStateMapOf`).
    public internal(set) var parallelKeys: [String] = []
    /// Rises after every batch of traffic-log lines (the console redraws from `log.snapshot()`).
    public private(set) var logRevision: Int = 0
    /// The favourite chosen in the DX Cluster window (a label or a name, Kotlin `selectedName`).
    public var selection: String = ""

    /// The shared spot buffer (Kotlin `dxCluster.spots`, `SpotBuffer(90)`).
    @ObservationIgnored public let spots: SpotBuffer
    /// The shared traffic log (Kotlin `dxCluster.log`).
    @ObservationIgnored public let log: DxClusterTrafficLog

    @ObservationIgnored let config: ConfigModel
    @ObservationIgnored private let status: StatusModel
    @ObservationIgnored let language: LanguageModel
    @ObservationIgnored private let messages: MessagesModel
    @ObservationIgnored private let network: NetworkPorts
    @ObservationIgnored let translator: TranslatorBox
    @ObservationIgnored let sink = ClusterSink()
    /// The station was spotted (the plugins' `SELF_SPOTTED`); runs on the main actor with the message.
    /// The Bands/Modes filter changed (wired to `SpotFeed.filterChanged`).
    @ObservationIgnored public var onSpotFilterChanged: (@MainActor () -> Void)?
    @ObservationIgnored public var onSelfSpotted: (@MainActor (SelfSpot) -> Void)?
    @ObservationIgnored let hooks = SpotHooks()
    @ObservationIgnored private(set) var mainLane: ClusterLane!
    @ObservationIgnored private(set) var mainToken: Int = 0
    @ObservationIgnored var parallelLanes: [String: (token: Int, lane: ClusterLane)] = [:]
    /// Lanes of connections dropped by the parallel plan (awaited at the quit).
    @ObservationIgnored var retiredLanes: [ClusterLane] = []
    @ObservationIgnored private var nextToken: Int = 0
    @ObservationIgnored private var logListener: DxClusterTrafficLog.ListenerID?
    @ObservationIgnored private let logPending = OSAllocatedUnfairLock(initialState: false)
    /// Set by the quit's `shutdown()`: from then on the window's actions (connect, login, logout, send, the parallel
    /// plan) do nothing, so no session opens or sends during the rest of the quit.
    @ObservationIgnored private(set) var closed = false

    init(config: ConfigModel, status: StatusModel, language: LanguageModel, messages: MessagesModel,
         network: NetworkPorts, now: @escaping @Sendable () -> Date) {
        self.config = config
        self.status = status
        self.language = language
        self.messages = messages
        self.network = network
        spots = SpotBuffer(maxAgeMinutes: 90, clock: now)
        log = DxClusterTrafficLog()
        translator = TranslatorBox(translator: language.translator, decimalSeparator: language.decimalSeparator)
        translator.follow(language)
        sink.model = self
        let created: (token: Int, lane: ClusterLane) = makeLane(tag: "", name: "dxcluster")
        mainToken = created.token
        mainLane = created.lane
        resetSelection()
        observeLog()
    }

    // MARK: - the ports of the network services

    /// Every received spot to the network (`publishSpot`; called on the reader thread).
    public var spotShare: @Sendable (DxSpot) -> Void {
        get { hooks.share }
        set { hooks.share = newValue }
    }

    /// Every received spot to the plugins (`SPOT_RECEIVED`; called on the reader thread, before `spotShare`).
    public var pluginSpot: @Sendable (DxSpot) -> Void {
        get { hooks.plugin }
        set { hooks.plugin = newValue }
    }

    // MARK: - the main connection's state

    public var connected: Bool { main.connected }
    public var connecting: Bool { main.connecting }
    public var loggedIn: Bool { main.loggedIn }
    /// The status line (Kotlin's default „Odpojeno" is not translated).
    public var statusText: String { main.status }
    /// The last WWV message of the main node (Info window and propagation).
    public var lastWwv: WwvMessage? { main.lastWwv }
    public var currentFavorite: DxClusterFavorite? { main.currentFavorite }

    // MARK: - the main connection

    /// Kotlin `conn.toggle(fav)`: connected → disconnect „Odpojeno", otherwise connect.
    public func toggle(_ fav: DxClusterFavorite) {
        guard !closed else { return }
        mainLane.run { session in try session.toggle(fav) }
    }

    /// Kotlin `conn.connect(fav)` (no auto-login).
    public func connect(_ fav: DxClusterFavorite) {
        guard !closed else { return }
        mainLane.run { session in try session.connect(fav, autoLogin: false) }
    }

    /// Kotlin `conn.login(fav)` („Přihlásit").
    public func login(_ fav: DxClusterFavorite) {
        guard !closed else { return }
        mainLane.run { session in session.login(fav) }
    }

    /// Kotlin `conn.logout()` („Odhlásit", `BYE`).
    public func logout() {
        guard !closed else { return }
        mainLane.run { session in try session.logout() }
    }

    /// Kotlin `conn.send(cmd)` (the command line, the macro buttons, Spot It).
    public func send(_ command: String) {
        guard !closed else { return }
        mainLane.run { session in try session.send(command) }
    }

    /// Kotlin `conn.disconnect(message)`.
    public func disconnect(_ message: String) {
        mainLane.run { session in try session.disconnect(message) }
    }

    /// „Vymazat" (Kotlin `log.clear(); lines = emptyList()`): the traffic log is emptied and the console redrawn
    /// (the log's own listener fires only when a line is added).
    public func clearLog() {
        log.clear()
        logRevision += 1
    }

    // MARK: - favourites and macros (the file only)

    public var favorites: [DxClusterFavorite] {
        config.config.dxCluster.favorites
    }

    /// The selection when the window opens: `lastFavorite`, else the first favourite's name.
    public func resetSelection() {
        let dx: DxClusterConfig = config.config.dxCluster
        selection = ClusterTexts.initialSelection(lastFavorite: dx.lastFavorite, favorites: dx.favorites)
    }

    /// The favourite the window connects to (the selection's label or name, else the first).
    public var selectedFavorite: DxClusterFavorite? {
        ClusterTexts.selectedFavorite(selection, favorites: favorites, translator: language.translator)
    }

    /// Kotlin's dropdown `onSelect`: the chosen label becomes the selection; the matching favourite's name is saved as
    /// `lastFavorite` (a failed write is swallowed).
    public func selectFavorite(_ label: String) {
        selection = label
        let translator: Translator = language.translator
        let chosen: [UInt16] = Array(label.utf16)
        guard let fav = favorites.first(where: {
            Array(ClusterTexts.favLabel($0, translator: translator).utf16) == chosen
        }) else { return }
        config.config.dxCluster.lastFavorite = fav.name
        config.saveSilently()
    }

    /// The ten macro buttons (Kotlin: the stored command, else the default one at that place).
    public var macros: [DxClusterCommand] {
        let stored: [DxClusterCommand] = config.config.dxCluster.commands
        let defaults: [DxClusterCommand] = DxClusterConfig.defaultCommands()
        return (0..<DxClusterConfig.commandCount).map { index in
            index < stored.count ? stored[index] : defaults[index]
        }
    }

    /// „Upravit tlačítko" → „Uložit": the trimmed button at `index`, the ten buttons saved; a failed write shows
    /// `tr("Uložení tlačítka selhalo (%s)")`.
    public func saveMacro(index: Int, label: String, command: String) {
        var commands: [DxClusterCommand] = macros
        guard commands.indices.contains(index) else { return }
        commands[index] = ClusterTexts.editedMacro(label: label, command: command)
        config.config.dxCluster.commands = commands
        config.save(failureKey: ClusterTexts.macroSaveFailedKey)
    }

    // MARK: - Bands/Modes spot filter

    /// The Bands/Modes spot filter from the configuration.
    public var spotFilter: SpotFilter {
        config.config.dxCluster.spotFilter
    }

    /// Applies and saves a new Bands/Modes filter; the band map, Available Mults and spot navigation follow at once.
    public func setSpotFilter(_ filter: SpotFilter) {
        guard filter != config.config.dxCluster.spotFilter else { return }
        config.config.dxCluster.spotFilter = filter
        config.save(failureKey: ClusterTexts.macroSaveFailedKey)
        onSpotFilterChanged?()
    }

    // MARK: - Settings (the ports of `SettingsServices`)

    /// Kotlin `saveConfig`: `dxCluster.myCall` and every parallel connection's `myCall` = the station call.
    public func applyMyCall() {
        let call: String = config.config.station.call
        mainLane.run { session in session.myCall = call }
        for key in parallelKeys {
            parallelLanes[key]?.lane.run { session in session.myCall = call }
        }
    }

    /// Kotlin `dxCluster.setBufferMinutes(config.dxCluster.spotBufferMinutes)` (only after Settings — the buffer
    /// starts with 90 minutes whatever the configuration says, as in Kotlin).
    public func setBufferMinutes() {
        spots.setMaxAgeMinutes(config.config.dxCluster.spotBufferMinutes)
    }

    // MARK: - lifecycle

    /// Waits until every lane's queued work and the session threads have finished, then lets the posted state hops
    /// run (tests).
    func settle() async {
        await mainLane.idle()
        for entry in parallelLanes.values {
            await entry.lane.idle()
        }
        for lane in retiredLanes {
            await lane.idle()
        }
        await Self.runPostedWork()
    }

    /// Every lane: main, parallel, and the ones the plan dropped.
    private var allLanes: [ClusterLane] {
        var lanes: [ClusterLane] = [mainLane]
        lanes += parallelKeys.compactMap { parallelLanes[$0]?.lane }
        lanes += retiredLanes
        return lanes
    }

    /// The quit, first part, before the database closes: the main **and** every parallel connection
    /// `disconnect(tr("ukončeno"))` on its lane, and only the lanes awaited — their jobs never wait for the network
    /// (a connect or a send runs on the session's own thread), so a connect hanging in DNS or in its 8 s timeout does
    /// not hold up the final backup. A connect that finishes later closes its client (the session's epoch): never
    /// adopted, no auto-login. The log listener is removed; the window's actions do nothing from now on (`closed`).
    func shutdown() async {
        closed = true
        let message: String = language.tr("ukončeno")
        let lanes: [ClusterLane] = allLanes
        for lane in lanes {
            lane.run { session in try session.disconnect(message) }
        }
        for lane in lanes {
            await lane.settle()
        }
        if let logListener {
            log.removeListener(logListener)
        }
        logListener = nil
        await Self.runPostedWork()
    }

    /// The quit, last part (after the database closed): waits for the sessions' own threads (a connect in flight
    /// ends in its timeout and closes itself), then drops the callbacks.
    func drain() async {
        for lane in allLanes {
            await lane.idle()
        }
        sink.model = nil
    }

    // MARK: - internals

    /// A new session with its lane, wired like Kotlin `wireSelfSpot` (`onSpot`, `myCall`, `onSelfSpot`).
    func makeLane(tag: String, name: String) -> (token: Int, lane: ClusterLane) {
        nextToken += 1
        let token: Int = nextToken
        let sink: ClusterSink = self.sink
        let translator: TranslatorBox = self.translator
        let hooks = ClusterHooks(
            spots: spots, log: log, tag: tag, translate: { key in translator.translate(key) },
            onChange: { _ in sink.changed(token) },
            onUnexpectedError: { error in sink.unexpected(error) })
        let session: any ClusterSessionPort = network.makeSession(hooks)
        let spotHooks: SpotHooks = self.hooks
        session.onSpot = { spot in
            spotHooks.plugin(spot)
            spotHooks.share(spot)
        }
        session.myCall = config.config.station.call
        session.onSelfSpot = { own in sink.selfSpot(own) }
        let lane = ClusterLane(session: session, name: name, onError: { error in sink.unexpected(error) })
        return (token, lane)
    }

    /// The hop of `onChange`: re-read the session of `token` (a dropped one is ignored).
    func refresh(_ token: Int) {
        if token == mainToken {
            let fresh: DxClusterSession.Snapshot = mainLane.session.snapshot
            if fresh != main {
                main = fresh
            }
            return
        }
        guard let key = parallelKeys.first(where: { parallelLanes[$0]?.token == token }),
              let lane = parallelLanes[key]?.lane else { return }
        let fresh: DxClusterSession.Snapshot = lane.session.snapshot
        if parallel[key] != fresh {
            parallel[key] = fresh
        }
    }

    /// Kotlin `onSelfSpot`: RBN → `tr("RBN: %s tě slyší na %s kHz")` + SNR + WPM, otherwise the untranslated
    /// „Byl jsi spotnut: …"; the frequency in the system's decimal format (Kotlin `"%.1f".format`).
    func selfSpotted(_ own: SelfSpot) {
        onSelfSpotted?(own)
        let text: String = SpotActions.selfSpotMessage(own, translator: language.translator,
                                                       decimalSeparator: language.decimalSeparator)
        messages.add(text, at: own.at)
    }

    /// An error no Kotlin code catches: into the traffic log and the status line.
    func unexpected(_ message: String) {
        status.showVerbatim(message)
        try? log.info(message)
    }

    private func observeLog() {
        let pending: OSAllocatedUnfairLock<Bool> = logPending
        logListener = log.addListener { [weak self] in
            let first: Bool = pending.withLock { waiting in
                if waiting { return false }
                waiting = true
                return true
            }
            guard first else { return }
            MainHop.post {
                pending.withLock { $0 = false }
                self?.logRevision += 1
            }
        }
    }

    static func runPostedWork() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            MainHop.post {
                continuation.resume()
            }
        }
    }
}

/// The ports `spotShare` and `pluginSpot`, read on the reader threads.
final class SpotHooks: Sendable {
    private struct State {
        var share: @Sendable (DxSpot) -> Void = { _ in }
        var plugin: @Sendable (DxSpot) -> Void = { _ in }
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    var share: @Sendable (DxSpot) -> Void {
        get { state.withLock { $0.share } }
        set { state.withLock { $0.share = newValue } }
    }

    var plugin: @Sendable (DxSpot) -> Void {
        get { state.withLock { $0.plugin } }
        set { state.withLock { $0.plugin = newValue } }
    }
}

/// The sessions' callbacks → the main actor (`MainHop.post` = the main queue's FIFO), never synchronously.
final class ClusterSink: @unchecked Sendable {
    private let lock = NSLock()
    private weak var target: DxClusterModel?

    var model: DxClusterModel? {
        get { lock.withLock { target } }
        set { lock.withLock { target = newValue } }
    }

    func changed(_ token: Int) {
        let model: DxClusterModel? = self.model
        MainHop.post {
            model?.refresh(token)
        }
    }

    func selfSpot(_ own: SelfSpot) {
        let model: DxClusterModel? = self.model
        MainHop.post {
            model?.selfSpotted(own)
        }
    }

    func unexpected(_ error: any Error) {
        let model: DxClusterModel? = self.model
        let message: String = ErrorText.message(error)
        MainHop.post {
            model?.unexpected(message)
        }
    }
}
