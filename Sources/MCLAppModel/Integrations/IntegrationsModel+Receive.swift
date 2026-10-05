import Foundation
import MCLCore

/// One external QSO waiting to be logged.
enum IngestItem: Sendable {
    case n1mm(String)
    case adif(String, source: String)
}

/// Reads the contest runtime on the main actor from the `@Sendable` closure of `IngestSnapshot` (the closure only
/// ever runs inside `ingest`, on the main actor).
private final class RuntimeBox: @unchecked Sendable {
    let runtime: ContestRuntime

    init(_ runtime: ContestRuntime) {
        self.runtime = runtime
    }
}

extension IntegrationsModel {

    /// The most waiting external QSOs; a flood beyond it is dropped (a datagram storm must not grow memory).
    static let maxPendingIngest = 1_000

    // MARK: - WSJT-X receiver

    /// Kotlin `startWsjtxIfEnabled`: the sender and the receiver, each on its own switch.
    public func startWsjtxIfEnabled() {
        startWsjtxSender()
        startWsjtxReceiver()
    }

    private func startWsjtxReceiver() {
        let w: WsjtxConfig = config.wsjtx
        guard w.receiveEnabled, !KotlinStrings.isBlank(w.receiveBind), wsjtxListener == nil, !isClosed else { return }
        guard !deps.network.isInert else {
            logInert("wsjtx receive")
            return
        }
        guard let target = Target.parseAll(w.receiveBind).first else {
            show(.tr("WSJT-X: příjem se nespustil (%s)", .string(invalidBind(w.receiveBind))))
            return
        }
        wsjtxGeneration += 1
        let generation: Int = wsjtxGeneration
        let ports: UdpPorts = deps.network.udp
        let handler = WsjtxListener.Handler(
            onLoggedAdif: { [weak self] adif in
                guard let adif else { return }
                MainHop.post { self?.enqueueIngest(.adif(adif, source: "WSJT-X")) }
            },
            onDecode: { [weak self] decode, from in
                MainHop.post { self?.receivedDecode(decode, from: from) }
            },
            onStatus: { [weak self] status in
                MainHop.post { self?.wsjtxStatus = status }
            },
            onClear: { [weak self] _ in
                MainHop.post { self?.wsjtxDecodes.clear() }
            })
        lane.submit({ () -> ListenerStart in
            do {
                guard let listener = try ports.makeWsjtxListener(target.host, Int(target.port), handler) else {
                    return .none
                }
                listener.start()
                return .wsjtx(listener)
            } catch {
                return .failed(ErrorText.message(error))
            }
        }, then: { [weak self] result in
            self?.wsjtxStarted(result, generation: generation, target: target)
        })
    }

    private func wsjtxStarted(_ result: ListenerStart, generation: Int, target: Target) {
        switch result {
        case .wsjtx(let listener):
            if generation != wsjtxGeneration || isClosed {
                retire(listener)
                return
            }
            wsjtxListener = listener
            show(.tr("WSJT-X: poslouchám na %s:%s", .string(target.host), .int(Int(target.port))))
        case .failed(let message):
            if generation == wsjtxGeneration {
                show(.tr("WSJT-X: příjem se nespustil (%s)", .string(message)))
            }
        case .plain, .none:
            break
        }
    }

    /// Kotlin `stopWsjtx`: the listener and the sender.
    public func stopWsjtx() {
        wsjtxGeneration += 1
        if let listener = wsjtxListener {
            wsjtxListener = nil
            retire(listener)
        }
        stopWsjtxSender()
    }

    public func restartWsjtx() {
        stopWsjtx()
        startWsjtxIfEnabled()
    }

    /// A decode: enriched with the dupe and multiplier state, newest first (`AS:3250-3266`).
    func receivedDecode(_ decode: WsjtxMessages.Decode, from: UdpEndpoint) {
        let logbook: LogbookModel = deps.logbook
        let isDupe: (String, Band?) -> Bool = { [logbook] call, band in
            Self.workedBefore(logbook, call, band)
        }
        let analyzer: SpotAnalyzer? = deps.analyzer()
        let status: WsjtxMessages.Status? = wsjtxStatus
        var decodes: WsjtxDecodes = wsjtxDecodes
        decodes.add(decode, from: from, status: status, analyzer: analyzer, isDupe: isDupe)
        wsjtxDecodes = decodes
    }

    /// Kotlin `isDupe(caller, band)` — a call worked on the band, whatever the contest's own dupe rule says.
    @MainActor private static func workedBefore(_ logbook: LogbookModel, _ call: String, _ band: Band?) -> Bool {
        logbook.isDupe(call: call, band: band)
    }

    /// Reply to the WSJT-X that sent the decode (a double click in WSJT-X's Band Activity), `row.from` only.
    public func reply(to row: WsjtxDecodes.Row) {
        if let locked = keyingRefusal() {
            show(locked)
            return
        }
        guard let listener = wsjtxListener else {
            show(.tr("WSJT-X: příjem není zapnutý (Nastavení → WSJT-X)"))
            return
        }
        let packet: [UInt8] = WsjtxMessages.encodeReply(row.decode, modifiers: 0)
        let from: UdpEndpoint = row.from
        lane.submit({ () -> String? in
            do {
                try listener.send(packet, to: from)
                return nil
            } catch {
                return ErrorText.message(error)
            }
        }, then: { [weak self] failure in
            if let failure {
                self?.show(.tr("WSJT-X: odpověď selhala (%s)", .string(failure)))
            }
        })
        if !KotlinStrings.isBlank(row.parsed.caller) {
            show(.tr("WSJT-X: volám %s", .string(row.parsed.caller)))
        }
    }

    // MARK: - N1MM receiver

    public func startN1mmIfEnabled() {
        let c: N1mmRecvConfig = config.n1mmRecv
        guard c.receiveEnabled, !KotlinStrings.isBlank(c.receiveBind), n1mmListener == nil, !isClosed else { return }
        guard !deps.network.isInert else {
            logInert("n1mm receive")
            return
        }
        guard let target = Target.parseAll(c.receiveBind).first else {
            show(.tr("N1MM příjem se nespustil (%s)", .string(invalidBind(c.receiveBind))))
            return
        }
        n1mmGeneration += 1
        let generation: Int = n1mmGeneration
        let ports: UdpPorts = deps.network.udp
        let handler: @Sendable (String) -> Void = { [weak self] xml in
            MainHop.post { self?.enqueueIngest(.n1mm(xml)) }
        }
        lane.submit({ () -> ListenerStart in
            do {
                guard let listener = try ports.makeN1mmListener(target.host, Int(target.port), handler) else {
                    return .none
                }
                listener.start()
                return .plain(listener)
            } catch {
                return .failed(ErrorText.message(error))
            }
        }, then: { [weak self] result in
            self?.plainStarted(result, kind: .n1mm, generation: generation, target: target)
        })
    }

    public func stopN1mm() {
        n1mmGeneration += 1
        if let listener = n1mmListener {
            n1mmListener = nil
            retire(listener)
        }
    }

    public func restartN1mm() {
        stopN1mm()
        startN1mmIfEnabled()
    }

    // MARK: - ADIF over UDP

    public func startAdifUdpIfEnabled() {
        let c: AdifUdpConfig = config.adifUdp
        guard c.receiveEnabled, !KotlinStrings.isBlank(c.receiveBind), adifListener == nil, !isClosed else { return }
        guard !deps.network.isInert else {
            logInert("adif receive")
            return
        }
        guard let target = Target.parseAll(c.receiveBind).first else {
            show(.tr("ADIF příjem se nespustil (%s)", .string(invalidBind(c.receiveBind))))
            return
        }
        adifGeneration += 1
        let generation: Int = adifGeneration
        let ports: UdpPorts = deps.network.udp
        let handler: @Sendable (String) -> Void = { [weak self] adif in
            MainHop.post { self?.enqueueIngest(.adif(adif, source: "ADIF")) }
        }
        lane.submit({ () -> ListenerStart in
            do {
                guard let listener = try ports.makeAdifListener(target.host, Int(target.port), handler) else {
                    return .none
                }
                listener.start()
                return .plain(listener)
            } catch {
                return .failed(ErrorText.message(error))
            }
        }, then: { [weak self] result in
            self?.plainStarted(result, kind: .adif, generation: generation, target: target)
        })
    }

    public func stopAdifUdp() {
        adifGeneration += 1
        if let listener = adifListener {
            adifListener = nil
            retire(listener)
        }
    }

    public func restartAdifUdp() {
        stopAdifUdp()
        startAdifUdpIfEnabled()
    }

    enum PlainKind {
        case n1mm, adif
    }

    private func plainStarted(_ result: ListenerStart, kind: PlainKind, generation: Int, target: Target) {
        let current: Int = kind == .n1mm ? n1mmGeneration : adifGeneration
        switch result {
        case .plain(let listener):
            if generation != current || isClosed {
                retire(listener)
                return
            }
            let port: Int = Int(target.port)
            if kind == .n1mm {
                n1mmListener = listener
                show(.tr("N1MM příjem: poslouchám na %s:%s", .string(target.host), .int(port)))
            } else {
                adifListener = listener
                show(.tr("ADIF příjem: poslouchám na %s:%s", .string(target.host), .int(port)))
            }
        case .failed(let message):
            guard generation == current else { return }
            if kind == .n1mm {
                show(.tr("N1MM příjem se nespustil (%s)", .string(message)))
            } else {
                show(.tr("ADIF příjem se nespustil (%s)", .string(message)))
            }
        case .wsjtx, .none:
            break
        }
    }

    /// `tr("neplatný bind: %s")` — the text inside Kotlin's exception message.
    private func invalidBind(_ bind: String) -> String {
        deps.language.tr("neplatný bind: %s", .string(bind))
    }

    // MARK: - ingest of external QSOs

    /// Queues an external QSO. The queue is worked off one QSO at a time on the main actor: the snapshot of the log
    /// (the dedup, the next serial) is taken only after the previous QSO was logged, so a datagram sent twice never
    /// logs two QSOs.
    func enqueueIngest(_ item: IngestItem) {
        guard !isClosed, ingestQueue.count < Self.maxPendingIngest else { return }
        ingestQueue.append(item)
        guard ingestTask == nil else { return }
        ingestTask = Task { @MainActor [weak self] in
            await self?.drainIngest()
        }
    }

    private func drainIngest() async {
        while !isClosed, !ingestQueue.isEmpty {
            let item: IngestItem = ingestQueue.removeFirst()
            await ingest(item)
            afterIngest?()
        }
        ingestTask = nil
    }

    /// The snapshot of the application state the ingest decides over (`AppState.qsos`, `contest`, `runMode`, the
    /// next serial, the station call).
    func ingestSnapshot() -> IngestSnapshot {
        let box = RuntimeBox(deps.contest.runtime)
        let fields: @Sendable (String) throws(ExpressionError) -> [ContestDefinition.ExchangeField] = { call in
            try box.runtime.exchangeFields(call: call)
        }
        return IngestSnapshot(qsos: deps.logbook.rows, isContestActive: deps.contest.isActive, exchangeFields: fields,
                              nextSerial: deps.logbook.qsoCount + 1, runMode: deps.operating.runMode,
                              ownCall: config.station.call)
    }

    private func ingest(_ item: IngestItem) async {
        let snapshot: IngestSnapshot = ingestSnapshot()
        let outcome: IngestOutcome
        switch item {
        case .n1mm(let xml):
            outcome = ExternalQsoIngest.n1mm(xml, snapshot: snapshot)
        case .adif(let record, let source):
            outcome = ExternalQsoIngest.adif(record, source: source, snapshot: snapshot)
        }
        switch outcome {
        case .drop:
            break
        case .status(let text):
            show(text)
        case .log(let ingested):
            await log(ingested)
        }
    }

    /// `log(qso)` for an imported QSO (no Club Log, plugin, broadcast or WSJT-X), then `contest.log`; a failure of
    /// either is `"<source>: import selhal (<message>)"` — the QSO is already stored when only the second fails.
    private func log(_ ingested: IngestedQso) async {
        let sync = syncInfo()
        let context = QsoLogPipeline.Context(
            activeContestId: KotlinStrings.nilIfBlank(deps.logbook.activeContestId),
            operatorCall: deps.operating.operatorCall, dxcc: deps.contest.runtime.dxccLookup,
            syncStationId: sync.stationId, reservedSerial: sync.reservedSerial)
        let (prepared, effects) = QsoLogPipeline.plan(qso: ingested.qso, isImported: true, context: context)
        do {
            try await deps.logbook.perform(prepared, effects: effects)
            let result = try deps.contest.logOrThrow(call: ingested.call, band: ingested.bandAdif,
                                                     mode: ingested.modeName, exchange: ingested.receivedRaw,
                                                     ownQth: nil, at: deps.now())
            show(ingested.status(counted: result?.counted ?? true))
        } catch {
            show(ExternalQsoIngest.failureStatus(source: ingested.source, message: ErrorText.message(error)))
        }
    }
}

/// How a listener start ended (on the lane).
enum ListenerStart: Sendable {
    case wsjtx(any WsjtxListening)
    case plain(any UdpListening)
    /// The port is inert: nothing was bound.
    case none
    case failed(String)
}
