import Foundation
import MCLCore
import Observation

/// The UDP integrations of v1.1.1: the N1MM broadcast with BCLOG, WSJT-X (sending the logged QSO, receiving decodes,
/// status and the logged ADIF, Reply), and the N1MM `contactinfo` and bare ADIF receivers (`AS:3163-3402`). The receive
/// half and the ingest of external QSOs are in `IntegrationsModel+Receive.swift`.
///
/// Threads: every bind, send and close of a socket that can wait (DNS) runs on the `IntegrationLane`; the listeners'
/// handlers run on their reader threads and only hop to the main actor; the broadcast providers read a `Sendable`
/// snapshot (`BroadcastSnapshot`) the main actor refreshes. A service started while a stop or restart overtakes it
/// is closed again when its start finishes (a generation per service).
///
/// Inert: with `NetworkPorts.isInert` nothing starts, binds or sends; the reason goes to the log, never
/// to the status line.
@Observable @MainActor
public final class IntegrationsModel {

    struct Dependencies {
        let config: ConfigModel
        let status: StatusModel
        let language: LanguageModel
        let contest: ContestModel
        let logbook: LogbookModel
        let operating: OperatingModel
        let rig: RigModel
        let network: NetworkPorts
        /// The spot analysis of the contest (`nil` = neutral decodes).
        let analyzer: @MainActor () -> SpotAnalyzer?
        /// The 1 s refresh of the broadcast snapshot.
        let clock: any RescoreClock
        let now: @Sendable () -> Date
    }

    /// The quit waits at most this long (ms of the injected clock) for the lane's queued closes.
    static let closeBoundMs = 3_000

    // MARK: - state

    /// The WSJT-X decodes, newest first (`AppState.wsjtxDecodes`).
    public internal(set) var wsjtxDecodes = WsjtxDecodes()
    /// The last WSJT-X status (`AppState.wsjtxStatus`).
    public internal(set) var wsjtxStatus: WsjtxMessages.Status?

    /// The broadcast runs.
    public var broadcastActive: Bool { broadcast != nil }
    /// The WSJT-X sender runs.
    public var wsjtxSendActive: Bool { wsjtxSender != nil }
    /// The bound port of the WSJT-X receiver (`nil` = not listening).
    public var wsjtxPort: Int? { wsjtxListener?.boundPort }
    /// The bound port of the N1MM receiver.
    public var n1mmPort: Int? { n1mmListener?.boundPort }
    /// The bound port of the ADIF receiver.
    public var adifPort: Int? { adifListener?.boundPort }

    let deps: Dependencies
    let lane = IntegrationLane(name: "integrations")
    @ObservationIgnored private let snapshotBox = BroadcastSnapshotBox()
    @ObservationIgnored private let contestNr: Int32
    @ObservationIgnored private var broadcast: BroadcastService?
    @ObservationIgnored private var snapshotTimer: (any RescoreTimer)?
    @ObservationIgnored var wsjtxSender: WsjtxSender?
    @ObservationIgnored var wsjtxListener: (any WsjtxListening)?
    @ObservationIgnored var n1mmListener: (any UdpListening)?
    @ObservationIgnored var adifListener: (any UdpListening)?
    /// Listeners closed but whose reader thread may still be running (awaited at the quit).
    @ObservationIgnored private var retired: [any UdpListening] = []
    @ObservationIgnored private var broadcastGeneration = 0
    @ObservationIgnored private var senderGeneration = 0
    @ObservationIgnored var wsjtxGeneration = 0
    @ObservationIgnored var n1mmGeneration = 0
    @ObservationIgnored var adifGeneration = 0
    @ObservationIgnored var isClosed = false
    /// The external QSOs waiting to be logged, one after another (`IntegrationsModel+Receive`).
    @ObservationIgnored var ingestQueue: [IngestItem] = []
    @ObservationIgnored var ingestTask: Task<Void, Never>?
    /// What the cluster session adds to a stored QSO (Kotlin `log`: the station id of a QSO logged while the session
    /// runs, the serial server's number it consumed); `(nil, nil)` without a session. Wired by the app model.
    @ObservationIgnored var syncInfo: @MainActor () -> (stationId: String?, reservedSerial: Int?) = { (nil, nil) }
    /// `false` while the pileup simulator runs — BCLOG sends nothing and the broadcast snapshot keeps
    /// the score it had before the simulation.
    @ObservationIgnored var outwardAllowed: @MainActor () -> Bool = { true }
    /// A QSO logged by the pileup simulator: BCLOG skips it.
    @ObservationIgnored var isSimulated: @MainActor (Qso) -> Bool = { _ in false }
    /// The pileup simulator refuses keying the rig (WSJT-X Reply makes WSJT-X transmit); `nil` = allowed.
    @ObservationIgnored var keyingRefusal: @MainActor () -> EntryStatus? = { nil }
    /// Test seam: runs after an ingested QSO was logged.
    @ObservationIgnored var afterIngest: (@MainActor () -> Void)?

    init(_ dependencies: Dependencies) {
        deps = dependencies
        contestNr = BroadcastMapping.contestNr(nowMs: Int64(dependencies.now().timeIntervalSince1970 * 1000))
        var initial = BroadcastSnapshot()
        initial.contestNr = contestNr
        snapshotBox.store(initial)
    }

    var config: AppConfig { deps.config.config }

    func show(_ text: EntryStatus) {
        deps.status.showJoined(text.parts, separator: "")
    }

    /// The reason a service stays off under the inert switch (the log only).
    func logInert(_ service: String) {
        appLog.notice("\(NetworkPorts.disabledMessage, privacy: .public): \(service, privacy: .public)")
    }

    // MARK: - broadcast

    /// Kotlin `startBroadcastIfEnabled`: at least one type enabled **and** with targets.
    public func startBroadcastIfEnabled() {
        let b: BroadcastConfig = config.broadcast
        let contacts: Bool = b.contactsEnabled && !KotlinStrings.isBlank(b.contactsTargets)
        let radio: Bool = b.radioEnabled && !KotlinStrings.isBlank(b.radioTargets)
        let score: Bool = b.scoreEnabled && !KotlinStrings.isBlank(b.scoreTargets)
        let appInfo: Bool = b.appInfoEnabled && !KotlinStrings.isBlank(b.appInfoTargets)
        guard contacts || radio || score || appInfo, !isClosed, broadcast == nil else { return }
        guard !deps.network.isInert else {
            logInert("broadcast")
            return
        }
        broadcastGeneration += 1
        let generation: Int = broadcastGeneration
        refreshBroadcastSnapshot()
        let ports: UdpPorts = deps.network.udp
        let box: BroadcastSnapshotBox = snapshotBox
        let now: @Sendable () -> Date = deps.now
        lane.submit({ () -> BroadcastStart in
            do {
                let service = BroadcastService(
                    config: b, broadcaster: try ports.makeBroadcaster(),
                    radioProvider: { box.radioData() }, scoreProvider: { box.scoreData(now: now()) },
                    appInfoProvider: { box.appInfoData() })
                service.start()
                return .started(service)
            } catch {
                return .failed(ErrorText.message(error))
            }
        }, then: { [weak self] result in
            self?.broadcastStarted(result, generation: generation)
        })
    }

    private func broadcastStarted(_ result: BroadcastStart, generation: Int) {
        switch result {
        case .started(let service):
            if generation != broadcastGeneration || isClosed {
                // Closed at once: after the quit's bound the lane refuses jobs, and the loops must not start sending.
                service.close()
                return
            }
            broadcast = service
            scheduleSnapshotRefresh()
        case .failed(let message):
            if generation == broadcastGeneration {
                deps.status.showVerbatim("Broadcast: start selhal (" + message + ")")
            }
        }
    }

    /// Kotlin `stopBroadcast`.
    public func stopBroadcast() {
        broadcastGeneration += 1
        snapshotTimer?.cancel()
        snapshotTimer = nil
        guard let service = broadcast else { return }
        broadcast = nil
        lane.submit { service.close() }
    }

    public func restartBroadcast() {
        stopBroadcast()
        startBroadcastIfEnabled()
    }

    /// Copies the state the providers read (the radio, the score, the contest, the station) into the snapshot.
    public func refreshBroadcastSnapshot() {
        var s = BroadcastSnapshot()
        s.stationCall = config.station.call
        s.operatorCall = deps.operating.operatorCall
        s.runMode = deps.operating.runMode
        s.catConnected = deps.rig.catConnected
        s.rig = deps.rig.activeState
        s.isContestActive = deps.contest.isActive
        s.score = deps.contest.score
        if !outwardAllowed() {
            let kept: BroadcastSnapshot = snapshotBox.value
            s.score = kept.score
            s.isContestActive = kept.isContestActive
        }
        s.activeName = deps.contest.activeName
        s.activeId = deps.contest.activeId
        s.contestNr = contestNr
        snapshotBox.store(s)
    }

    private func scheduleSnapshotRefresh() {
        snapshotTimer?.cancel()
        snapshotTimer = deps.clock.schedule(afterMilliseconds: 1_000) { [weak self] in
            guard let self, self.broadcast != nil else { return }
            self.refreshBroadcastSnapshot()
            self.scheduleSnapshotRefresh()
        }
    }

    /// `contactData(qso)` of the active contest.
    private func contactData(_ qso: Qso) -> BroadcastXml.ContactData {
        BroadcastMapping.contactData(qso, contestName: deps.contest.activeName, contestNr: contestNr,
                                     stationCall: config.station.call)
    }

    /// A QSO logged here: the contact to the N1MM targets and the QSO to WSJT-X (never an import).
    func qsoLogged(_ qso: Qso) {
        if let service = broadcast {
            let data: BroadcastXml.ContactData = contactData(qso)
            lane.submit { service.sendContactInfo(data) }
        }
        if let sender = wsjtxSender {
            let station: Station = config.station.toStation()
            lane.submit { sender.send(qso, station) }
        }
    }

    /// An edited QSO: `sendContactReplace` with the row as stored before the edit as the old call and time (a fix
    /// of a Kotlin bug that which sent the edited values as the old ones).
    func qsoEdited(old: Qso, new: Qso) {
        guard let service = broadcast else { return }
        let replace: BroadcastMapping.Replace = BroadcastMapping.replace(
            old: old, new: new, contestName: deps.contest.activeName, contestNr: contestNr, stationCall: config.station.call)
        lane.submit { service.sendContactReplace(replace.data, oldCall: replace.oldCall, oldTs: replace.oldTimestamp) }
    }

    /// A deleted QSO: `sendContactDelete`, every QSO on its own.
    func qsoDeleted(_ qso: Qso) {
        guard let service = broadcast else { return }
        let data: BroadcastXml.ContactData = contactData(qso)
        lane.submit { service.sendContactDelete(data) }
    }

    /// BCLOG: the whole log once as contact infos.
    public func broadcastWholeLog() {
        guard outwardAllowed() else {
            show(.tr(SimulatorModel.refusalKey))
            return
        }
        guard let service = broadcast else {
            show(.tr("BCLOG: UDP broadcast je vypnutý (Nastavení → Broadcast Data)"))
            return
        }
        let rows: [Qso] = deps.logbook.rows.filter { !isSimulated($0) }
        let all: [BroadcastXml.ContactData] = rows.map { contactData($0) }
        lane.submit {
            for data in all {
                service.sendContactInfo(data)
            }
        }
        show(.tr("BCLOG: odesláno %s QSO", .int(rows.count)))
    }

    // MARK: - WSJT-X sender

    /// The sending half of Kotlin `startWsjtxIfEnabled`.
    func startWsjtxSender() {
        let w: WsjtxConfig = config.wsjtx
        guard w.sendEnabled, !KotlinStrings.isBlank(w.sendTargets), wsjtxSender == nil, !isClosed else { return }
        guard !deps.network.isInert else {
            logInert("wsjtx send")
            return
        }
        senderGeneration += 1
        let generation: Int = senderGeneration
        let targets: [Target] = Target.parseAll(w.sendTargets)
        let ports: UdpPorts = deps.network.udp
        lane.submit({ () -> SenderStart in
            do {
                return .started(WsjtxSender(try ports.makeBroadcaster(), targets))
            } catch {
                return .failed(ErrorText.message(error))
            }
        }, then: { [weak self] result in
            self?.senderStarted(result, generation: generation)
        })
    }

    private func senderStarted(_ result: SenderStart, generation: Int) {
        switch result {
        case .started(let sender):
            if generation != senderGeneration || isClosed {
                sender.close()
                return
            }
            wsjtxSender = sender
        case .failed(let message):
            if generation == senderGeneration {
                show(.tr("WSJT-X: vysílání se nespustilo (%s)", .string(message)))
            }
        }
    }

    func stopWsjtxSender() {
        senderGeneration += 1
        guard let sender = wsjtxSender else { return }
        wsjtxSender = nil
        lane.submit { sender.close() }
    }

    // MARK: - closing

    /// Closes a listener now (a socket close does not wait) and remembers it for the quit's wait.
    func retire(_ listener: any UdpListening) {
        listener.close()
        retired.append(listener)
    }

    /// The quit: every service closes, the lane's queue (closes included) runs out, the readers' threads
    /// are awaited, the ingest queue is dropped. Nothing binds or sends afterwards.
    func shutdown() async {
        isClosed = true
        stopBroadcast()
        stopWsjtx()
        stopN1mm()
        stopAdifUdp()
        ingestQueue.removeAll()
        // A close queued above must still run: settle first (bounded — a bind or a send stuck in DNS must not hold the
        // database close), then refuse later jobs.
        await lane.settle(boundMs: Self.closeBoundMs, clock: deps.clock)
        lane.markClosed()
        await ingestTask?.value
        for listener in retired {
            await listener.waitUntilStopped()
        }
        retired.removeAll()
    }

    /// Waits for the lane (tests).
    func settle() async {
        await lane.settle()
        await drainMainQueue()
    }
}

/// How a broadcast start ended (on the lane).
private enum BroadcastStart: Sendable {
    case started(BroadcastService)
    case failed(String)
}

/// How a WSJT-X sender start ended.
private enum SenderStart: Sendable {
    case started(WsjtxSender)
    case failed(String)
}
