import Foundation
import MCLCore
import Observation
import os

/// One cluster session: the transport, the station network and the coordinator of a `start`. The lane jobs of the
/// session read `usable`; it turns `false` when the connect failed, so a QSO logged while the connect was still
/// queued is not published into a dead transport.
final class SyncSession: @unchecked Sendable {
    let id: Int
    let stationId: String
    let transport: any SyncTransport
    let network: StationNetwork
    let coordinator: SyncCoordinator
    let statusSlot = StatusSlot()
    private let flag = OSAllocatedUnfairLock(initialState: true)

    init(id: Int, stationId: String, transport: any SyncTransport, network: StationNetwork,
         coordinator: SyncCoordinator) {
        self.id = id
        self.stationId = stationId
        self.transport = transport
        self.network = network
        self.coordinator = coordinator
    }

    var usable: Bool {
        flag.withLock { $0 }
    }

    func markUnusable() {
        flag.withLock { $0 = false }
    }
}

/// The network log of v1.1.1 (`AppState` `syncCoordinator`, `stationNet`, `clusterConnected`, `netStatusJob`,
/// `startClusterIfEnabled`, `stopCluster`, `AS:2735-2762, 2899-2960, 3127-3160`): the MQTT session of the station
/// (QSOs, presence of the other stations, messages, the serial server, shared spots), local-first — the station logs
/// and counts dupes and score by itself without the network; the network only replicates.
///
/// Threads: the transport is built and connected on the `SyncLane`; its callbacks run on the
/// transport's threads and only post a hop to the main actor carrying the generation of the session they belong to,
/// so a message that arrives after `stop` is dropped. A remote QSO state is applied to the database through the
/// handle's exclusive access (`SyncCoordinator.LogbookAccess`), then the log is re-read on the main actor; a burst of
/// states makes one re-read. Nothing on the main actor waits for the network: every publish is queued on the lane.
///
/// Kotlin quirks kept: `connected` is the one-time snapshot of the transport after the start; the own status
/// is published at once and then every second (the core publishes only a change or the 30 s heartbeat); a serial
/// request is repeated after 3 s without a reply. Deliberate differences: the connect does not block the UI thread,
/// and a failed connect closes its transport and forgets the station network (Kotlin keeps both).
@Observable @MainActor
public final class ClusterSyncModel {

    /// The period of the state loop.
    public static let stateIntervalMs = 1_000
    /// Kotlin `delay(50)` before the status of a started transmission is published.
    public static let announceDelayMs = 50
    /// The quit waits at most this long for the goodbye and the close.
    public static let closeBoundMs = 3_000

    /// The inputs of the own status that other models own; wired by the app.
    public struct Sources {
        /// The active rig's frequency (Kotlin `cat.state?.freqHz()`), `nil` without a CAT state.
        public var catFreqHz: @MainActor () -> Int? = { nil }
        /// The active rig's mode.
        public var catMode: @MainActor () -> Mode? = { nil }
        /// Kotlin `tunedFreqHz`.
        public var tunedFreqHz: @MainActor () -> Int = { 0 }
        public var runMode: @MainActor () -> RunMode = { .searchAndPounce }
        /// Kotlin `operatorCall`.
        public var operatorCall: @MainActor () -> String = { "" }
        /// Kotlin `typedCall`.
        public var typedCall: @MainActor () -> String = { "" }
        /// Kotlin `isSending()`.
        public var isSending: @MainActor () -> Bool = { false }

        public init() {}
    }

    public struct Dependencies {
        let config: ConfigModel
        let status: StatusModel
        let database: DatabaseModel
        let logbook: LogbookModel
        let contest: ContestModel
        let spots: SpotBuffer
        let network: NetworkPorts
        let dataDir: URL
        let clock: any RescoreClock
        let now: @Sendable () -> Date

        init(config: ConfigModel, status: StatusModel, database: DatabaseModel, logbook: LogbookModel,
             contest: ContestModel, spots: SpotBuffer, network: NetworkPorts, dataDir: URL, clock: any RescoreClock,
             now: @escaping @Sendable () -> Date) {
            self.config = config
            self.status = status
            self.database = database
            self.logbook = logbook
            self.contest = contest
            self.spots = spots
            self.network = network
            self.dataDir = dataDir
            self.clock = clock
            self.now = now
        }
    }

    /// Kotlin `clusterConnected`: the transport's state right after the start (one snapshot, never updated).
    public private(set) var connected = false
    /// The other stations (Kotlin reads `stationNet.peers()` on every redraw; here refreshed with every change and
    /// every second).
    public private(set) var peers: [StationNetwork.Peer] = []
    /// Kotlin `netRevision`: rises when a station's state arrives and with every tick.
    public private(set) var revision = 0
    /// This station's id while a session exists (Kotlin `syncCoordinator != null`), otherwise `nil`.
    public private(set) var stationId: String?
    /// The number reserved at the serial server (`reservedSerial`).
    public private(set) var reservation = SerialReservation()

    /// The number reserved at the serial server for the next QSO, `nil` = counting locally.
    public var reservedSerial: Int? {
        reservation.reserved
    }

    /// A session exists (Kotlin `syncCoordinator != null`, `stationNet != null`).
    public var isRunning: Bool {
        stationId != nil
    }

    @ObservationIgnored public var sources = Sources()
    /// A message for this station arrived (the network model takes it).
    @ObservationIgnored var onMessage: (@MainActor (NetMessageWire) -> Void)?

    @ObservationIgnored private let config: ConfigModel
    @ObservationIgnored private let status: StatusModel
    @ObservationIgnored private let database: DatabaseModel
    @ObservationIgnored private let logbook: LogbookModel
    @ObservationIgnored private let contest: ContestModel
    @ObservationIgnored private let spots: SpotBuffer
    @ObservationIgnored private let network: NetworkPorts
    @ObservationIgnored private let dataDir: URL
    @ObservationIgnored private let clock: any RescoreClock
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored let lane = SyncLane()
    @ObservationIgnored private var session: SyncSession?
    @ObservationIgnored private(set) var generation = 0
    @ObservationIgnored private var loopTimer: (any RescoreTimer)?
    @ObservationIgnored private var announceTimer: (any RescoreTimer)?
    @ObservationIgnored private(set) var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var refreshDirty = false
    /// The re-read of the log after remote states (`logbook.refresh()`); a seam of the tests.
    @ObservationIgnored var reload: @MainActor () async throws -> Void = {}
    /// Set by the quit's `shutdown()`: nothing starts afterwards.
    @ObservationIgnored private(set) var closed = false

    public init(_ dependencies: Dependencies) {
        config = dependencies.config
        status = dependencies.status
        database = dependencies.database
        logbook = dependencies.logbook
        contest = dependencies.contest
        spots = dependencies.spots
        network = dependencies.network
        dataDir = dependencies.dataDir
        clock = dependencies.clock
        now = dependencies.now
        reload = { [logbook = dependencies.logbook] in
            try await logbook.refresh()
        }
    }

    /// The station network of the session (the interlock reads its peers; `nil` = no network).
    var stationNetwork: StationNetwork? {
        session?.network
    }

    // MARK: - start

    /// Kotlin `startClusterIfEnabled()`: silent without the setting, the broker or the station id; without an active
    /// contest it only says so (the activation starts it, `startIfIdle`); otherwise the session is built here and
    /// connected on the lane.
    public func start() {
        guard !closed, session == nil else { return }
        let cluster: ClusterConfig = config.config.cluster
        if !cluster.enabled || KotlinStrings.isBlank(cluster.brokerHost) || KotlinStrings.isBlank(cluster.stationId) {
            return
        }
        if KotlinStrings.isBlank(logbook.activeContestId) {
            status.show("Cluster se připojí po aktivaci závodu.")
            return
        }
        if network.isInert {
            // An inert run creates no session directory and shows no status text, only the log line (as the
            // integrations do; `NetworkPorts.disabledMessage` is never shown in the status line).
            appLog.notice("Cluster: \(NetworkPorts.disabledMessage, privacy: .public)")
            return
        }
        generation += 1
        let id: Int = generation
        let transport: any SyncTransport
        do {
            transport = try makeTransport(cluster)
        } catch {
            showFailure(error)
            return
        }
        do {
            try open(transport, cluster: cluster, id: id)
        } catch {
            lane.submit { transport.close() }
            showFailure(error)
        }
    }

    /// The activation's `.startClusterIfIdle` (`AS:3617`): only when no session runs.
    public func startIfIdle() {
        if session == nil {
            start()
        }
    }

    private func makeTransport(_ cluster: ClusterConfig) throws -> any SyncTransport {
        let dir: URL = dataDir.appendingPathComponent("mqtt", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return try network.makeSyncTransport(cluster, dir)
    }

    /// The station network (its Last Will and its subscription come before the connect), the coordinator and the
    /// subscriptions; then the connect on the lane.
    private func open(_ transport: any SyncTransport, cluster: ClusterConfig, id: Int) throws {
        let now: @Sendable () -> Date = self.now
        let stationNetwork = StationNetwork(transport: transport, stationId: cluster.stationId,
                                            clock: { JavaInstant(date: now()) })
        try stationNetwork.start { [weak self] in
            MainHop.post { self?.peersChanged(id) }
        }
        stationNetwork.onMessages { [weak self] message in
            MainHop.post { self?.received(message, id) }
        }
        stationNetwork.onSerialReplies { [weak self] reply in
            MainHop.post { self?.received(reply, id) }
        }
        let handle: LogbookHandle = database.handle
        let coordinator = SyncCoordinator(
            access: { body in try handle.withDatabase { access in try body(access.service) } },
            transport: transport, stationId: cluster.stationId,
            onChange: { [weak self] in MainHop.post { self?.remoteChanged(id) } })
        coordinator.shareSpots { [weak self] wire in
            MainHop.post { self?.received(wire, id) }
        }
        let opened = SyncSession(id: id, stationId: cluster.stationId, transport: transport, network: stationNetwork,
                                 coordinator: coordinator)
        session = opened
        stationId = cluster.stationId
        let host: String = cluster.brokerHost
        let port: Int = cluster.port
        lane.submit { [weak self] in
            do {
                try coordinator.start()
                let isConnected: Bool = transport.isConnected
                MainHop.post { self?.connectSucceeded(id, host: host, port: port, connected: isConnected) }
            } catch {
                opened.markUnusable()
                transport.close()
                let message: String = ErrorText.message(error)
                MainHop.post { self?.connectFailed(id, message: message) }
            }
        }
    }

    private func connectSucceeded(_ id: Int, host: String, port: Int, connected isConnected: Bool) {
        guard id == generation, let opened = session, opened.id == id else { return }
        connected = isConnected
        peers = opened.network.peers()
        status.show("Připojeno ke clusteru %s:%s jako %s", .string(host), .string(String(port)),
                    .string(opened.stationId))
        tick(opened)
    }

    private func connectFailed(_ id: Int, message: String) {
        guard id == generation, session?.id == id else { return }
        forgetSession()
        status.show("Cluster: připojení selhalo (%s) — pokračuji lokálně", .string(message))
    }

    private func showFailure(_ error: any Error) {
        status.show("Cluster: připojení selhalo (%s) — pokračuji lokálně", .string(ErrorText.message(error)))
    }

    // MARK: - the state loop

    /// One round of Kotlin's `netStatusJob`: the own status (coalesced), the serial reservation, the redraw; then the
    /// next round after a second.
    private func tick(_ opened: SyncSession) {
        guard opened.id == generation, session === opened else { return }
        offerStatus(opened)
        ensureReservation()
        peers = opened.network.peers()
        revision += 1
        loopTimer = clock.schedule(afterMilliseconds: Self.stateIntervalMs) { [weak self] in
            self?.tick(opened)
        }
    }

    /// The own status for the lane: the newest one only (a publish already queued takes the newer status).
    private func offerStatus(_ opened: SyncSession) {
        let own: StationStatusWire = ownStatus()
        guard opened.statusSlot.offer(own) else { return }
        lane.submit {
            guard opened.usable, let latest = opened.statusSlot.take() else { return }
            do {
                try opened.network.publish(latest)
            } catch {
                appLog.error("Cluster status not published: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// Kotlin `ownStationStatus()`.
    func ownStatus() -> StationStatusWire {
        StationStatusBuilder.status(
            stationId: config.config.cluster.stationId, operatorCall: sources.operatorCall(),
            stationType: config.config.cluster.stationType, catFreqHz: sources.catFreqHz(),
            catMode: sources.catMode(), tunedFreqHz: sources.tunedFreqHz(), runMode: sources.runMode(),
            qsoCount: logbook.qsoCount, sending: sources.isSending(), typedCall: sources.typedCall())
    }

    /// The band of the own frequency as the interlock compares it (Kotlin `Band.fromFrequencyHz(...).adif`).
    func ownBand() -> String {
        let frequency: Int = sources.catFreqHz() ?? sources.tunedFreqHz()
        return Band.from(frequencyHz: frequency)?.adif ?? ""
    }

    /// Kotlin `announceTx()`: 50 ms after a transmission starts (its state is set only after the start) the own
    /// status goes out, so the other stations lock out at once. Never waits for the network.
    public func announceTx() {
        guard let opened = session else { return }
        announceTimer?.cancel()
        let id: Int = opened.id
        announceTimer = clock.schedule(afterMilliseconds: Self.announceDelayMs) { [weak self] in
            guard let self, id == self.generation, let current = self.session, current.id == id else { return }
            self.offerStatus(current)
        }
    }

    // MARK: - stop

    /// Kotlin `stopCluster()` without waiting: the loop ends, the station says goodbye and the transport closes on the
    /// lane, the reservation is forgotten, and from now on there is no network (the interlock allows, nothing is
    /// published). Idempotent.
    func stopNow() {
        refreshDirty = false
        guard let stopped = session else {
            reservation.reset()
            return
        }
        forgetSession()
        lane.submit {
            do {
                try stopped.network.goOffline()
            } catch {
                appLog.notice("Cluster goodbye not sent: \(String(describing: error), privacy: .public)")
            }
            stopped.coordinator.close()
        }
    }

    private func forgetSession() {
        generation += 1
        session = nil
        loopTimer?.cancel()
        loopTimer = nil
        announceTimer?.cancel()
        announceTimer = nil
        reservation.reset()
        connected = false
        stationId = nil
        peers = []
        revision += 1
    }

    /// `stopCluster()` and the wait for the goodbye and the close, at most `closeBoundMs`: a broker that does
    /// not answer cannot hold the caller.
    public func stop() async {
        stopNow()
        await waitForLane(boundMs: Self.closeBoundMs)
    }

    /// The database switch's cluster step: `stop()` and then the wait for a re-read of the old log in flight, bounded
    /// like the close (a stuck read cannot hold the switch). Nothing of the old log reaches the new database.
    public func stopAndAwaitRefresh() async {
        await stop()
        await awaitRefresh(boundMs: Self.closeBoundMs)
    }

    private func awaitRefresh(boundMs: Int) async {
        guard let task = refreshTask else { return }
        let gate = OneShot()
        let timer: any RescoreTimer = clock.schedule(afterMilliseconds: boundMs) {
            gate.fire()
        }
        Task {
            await task.value
            gate.fire()
        }
        await gate.wait()
        timer.cancel()
    }

    /// The quit's cluster step: the session stops (bounded wait), nothing starts afterwards, and a re-read of
    /// the log in flight finishes before the database closes.
    public func shutdown() async {
        closed = true
        await stop()
        await refreshTask?.value
    }

    /// `stopCluster()` + `startClusterIfEnabled()` (the Settings effect `restartCluster`); the new connect queues
    /// behind the old close.
    public func restart() {
        stopNow()
        start()
    }

    private func waitForLane(boundMs: Int) async {
        let gate = OneShot()
        let timer: any RescoreTimer = clock.schedule(afterMilliseconds: boundMs) {
            gate.fire()
        }
        lane.submit {
            gate.fire()
        }
        await gate.wait()
        timer.cancel()
    }

    // MARK: - NETON and NETOFF

    /// Kotlin `networkOn()`.
    public func networkOn() {
        switch NetworkCommands.on(config: config.config.cluster, running: isRunning) {
        case .notConfigured(let message), .alreadyRunning(let message):
            show(message)
        case .start:
            config.config.cluster.enabled = true
            config.saveSilently()
            start()
        }
    }

    /// Kotlin `networkOff()`.
    public func networkOff() {
        stopNow()
        config.config.cluster.enabled = false
        config.saveSilently()
        show(NetworkCommands.off)
    }

    private func show(_ message: EntryStatus) {
        status.showJoined(message.parts, separator: "")
    }

    // MARK: - publishing

    /// `coord.publishInsert(qso)` on the lane (Kotlin `scope.launch(Dispatchers.IO)`).
    public func publishInsert(_ qso: Qso) {
        publish(qso) { coordinator, qso in try coordinator.publishInsert(qso) }
    }

    public func publishUpdate(_ qso: Qso) {
        publish(qso) { coordinator, qso in try coordinator.publishUpdate(qso) }
    }

    public func publishDelete(_ qso: Qso) {
        publish(qso) { coordinator, qso in try coordinator.publishDelete(qso) }
    }

    private func publish(_ qso: Qso, _ send: @escaping @Sendable (SyncCoordinator, Qso) throws -> Void) {
        guard let opened = session else { return }
        lane.submit {
            guard opened.usable else { return }
            do {
                try send(opened.coordinator, qso)
            } catch {
                appLog.error("Cluster publish failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// A spot of the own DX cluster to the other stations (Kotlin `wireSelfSpot`: only with a session and the sharing
    /// on); queued on the lane with a cap. The spots that come from the network are never shared again: they
    /// go to the buffer directly, not through the connection's `onSpot`.
    public func shareSpot(_ spot: DxSpot) {
        guard let opened = session, config.config.cluster.shareSpots else { return }
        lane.submitSpot {
            guard opened.usable else { return }
            do {
                try opened.coordinator.publishSpot(spotter: spot.spotter, freqHz: spot.freqHz, dxCall: spot.dxCall,
                                                   comment: spot.comment)
            } catch {
                appLog.notice("Shared spot not published: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// Sends a station message on the lane; `completion` runs on the main actor with the sent message or the error
    /// (Kotlin `withContext(Dispatchers.IO) { runCatching { net.send(...) } }`). Without a session nothing is sent.
    func send(type: String, to: String, text: String?, call: String?, freqHz: Int, mode: String?,
              completion: @escaping @MainActor (Result<NetMessageWire, any Error>) -> Void) {
        guard let opened = session else { return }
        let operatorCall: String = sources.operatorCall()
        lane.submit {
            let result: Result<NetMessageWire, any Error> = Result {
                try opened.network.send(type, operator: operatorCall, to: to, text: text, call: call,
                                        freqHz: freqHz, mode: mode)
            }
            MainHop.post { completion(result) }
        }
    }

    // MARK: - serial reservation

    /// Kotlin `ensureSerialReservation()`: asks for a number when the serial server is on and none is reserved; a
    /// request without a reply is repeated after 3 s.
    func ensureReservation() {
        let nowMs = Int64((now().timeIntervalSince1970 * 1_000).rounded(.down))
        let opened: SyncSession? = session
        let request: String? = reservation.tick(nowMs: nowMs, enabled: config.config.cluster.serialServer,
                                                hasNet: opened != nil, newId: { UUID().uuidString.lowercased() })
        guard let request, let opened else { return }
        lane.submit {
            guard opened.usable else { return }
            do {
                try opened.network.requestSerial(request)
            } catch {
                appLog.notice("Serial request not sent: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// The QSO just stored carried the reserved number (`log`): it is used up and the next one is requested.
    @discardableResult
    public func consumeReserved(_ serial: Int?) -> Bool {
        guard reservation.consumed(serial: serial) else { return false }
        ensureReservation()
        return true
    }

    /// Kotlin `nextSerial()`: the reserved number, otherwise the local count.
    public func nextSerial() -> Int {
        reservedSerial ?? logbook.nextSerial
    }

    // MARK: - callbacks of the session (on the main actor, generation checked)

    private func peersChanged(_ id: Int) {
        guard id == generation, let opened = session else { return }
        peers = opened.network.peers()
        revision += 1
    }

    private func received(_ message: NetMessageWire, _ id: Int) {
        guard id == generation, session != nil else { return }
        onMessage?(message)
    }

    private func received(_ reply: SerialReply, _ id: Int) {
        guard id == generation, session != nil else { return }
        reservation.reply(reply)
    }

    /// A spot of another station's telnet into this station's band map (Kotlin: `isShareSpots` is read when it
    /// arrives).
    private func received(_ wire: SpotWire, _ id: Int) {
        guard id == generation, session != nil, config.config.cluster.shareSpots else { return }
        // Kotlin hands a missing spotter or call to the buffer, which throws: the spot is lost.
        guard let spotter = wire.spotter, let dxCall = wire.dxCall else { return }
        spots.add(DxSpot(spotter: spotter, freqHz: wire.freqHz, dxCall: dxCall, comment: wire.comment ?? ""))
    }

    // MARK: - remote QSO states

    /// A remote state was applied to the database (on a transport thread): the log is re-read (Kotlin
    /// `refreshFromLogbook()`). States arriving while a re-read runs make one more after it.
    func remoteChanged(_ id: Int) {
        guard id == generation, session != nil else { return }
        refreshDirty = true
        guard refreshTask == nil else { return }
        refreshTask = Task { @MainActor [weak self] in
            while let self, self.refreshDirty {
                self.refreshDirty = false
                await self.refreshLog()
            }
            self?.refreshTask = nil
        }
    }

    private func refreshLog() async {
        do {
            try await reload()
        } catch {
            if !closed {
                status.showVerbatim(ErrorText.message(error))
            }
            return
        }
        contest.requestRescore()
    }

    // MARK: - tests

    /// Waits for the lane, the hops posted before and a re-read in flight (tests).
    func settle() async {
        await lane.settle()
        await DxClusterModel.runPostedWork()
        await refreshTask?.value
    }
}
