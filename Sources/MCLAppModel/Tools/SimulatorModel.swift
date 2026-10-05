import Foundation
import MCLCore
import Observation

/// The pileup simulator of v1.1.1 (`AppState` `AS:1646-1712`, `AS:2790-2795`; window `SimulatorWindow.kt`): the CW of
/// the F-keys, the CW keyboard, the QTC and the PSE QSY go to the simulator instead of the key, the calling stations
/// play through the sound port, the logged QSOs are checked.
///
/// **Safety (a deliberate divergence from Kotlin):** while a simulation starts
/// or runs nothing may key the real rig and nothing simulated may leave the machine.
/// - Every CW message is taken by `route` (before the TX gate, as Kotlin); the rig keying that is not CW (voice,
///   digital, tune, the footswitch PTT) is refused by `keyingRefusal` with a status text. The release paths (PTT off,
///   tune off, stop) are never gated.
/// - The simulated QSOs are stored in the local database as in Kotlin, but `allowsOutwardEffects` is `false` while the
///   session runs (the cluster, Club Log, the score reporting, the broadcast, BCLOG and the plugins stay silent), and
///   `isSimulated` keeps their later edits and deletes from being published either.
///
/// The session is created only after the sound output opened (`SimulatorSession.isRunning` starts `true`), and the
/// output opens on the model's own lane: `makeSimAudio` blocks. While it opens the gate is already closed.
/// `close()` of the sink runs on the lane too (the real player waits up to 500 ms), never on the main thread.
@Observable @MainActor
public final class SimulatorModel {

    struct Dependencies {
        let hardware: HardwarePorts
        let config: ConfigModel
        let status: StatusModel
        let language: LanguageModel
        let callData: CallDataModel
        /// The clock of the "message sent" estimate (`CwTiming.estimateMillis`): the keyer's.
        let clock: any RescoreClock
        /// Kotlin `simRandom`; `SystemPileupRandom` in the app, seeded in tests.
        let random: any PileupRandom
    }

    /// Kotlin `simRandom` (the callers, their speeds, the reply amplitudes); a test sets a seeded one before `start`.
    @ObservationIgnored var random: any PileupRandom

    /// The text of every refused keying.
    static let refusalKey = "Simulátor běží — vysílání do TRX je zamčené (nejdřív ho zastav)"

    /// Kotlin `simulatorOn`: a session runs.
    public private(set) var isOn: Bool = false
    /// The sound output is opening (the gate is closed already, the session does not exist yet).
    public private(set) var isStarting: Bool = false
    /// The check of every logged QSO, newest first (Kotlin `simChecks`).
    public private(set) var checks: [PileupSimulator.Check] = []
    public private(set) var qsos: Int = 0
    public private(set) var errors: Int = 0
    /// What the last start said, for the window: the refusal („nejdřív vypni …"), the audio failure or the running
    /// hint — the same text as the status line. Cleared by a stop.
    public private(set) var startNotice: String?

    /// The name of an outward service that is live (cluster session, score reporting, N1MM broadcast, Club Log), `nil`
    /// = none; wired by the app model. A simulation does not start while one is: its QSOs stay in the log and would reach
    /// the aggregates (score, BCLOG) and, after a restart, the per-QSO services (the tags are in memory only).
    @ObservationIgnored var liveOutwardService: @MainActor () -> String? = { nil }
    /// The keyer whose lamp and speed the simulated sends use; set by the app model.
    @ObservationIgnored weak var keyer: KeyerModel?

    @ObservationIgnored private let deps: Dependencies
    @ObservationIgnored private let lane = SerialLane(name: "sim-audio")
    @ObservationIgnored private var session: SimulatorSession?
    @ObservationIgnored private var sink: (any SimAudioSink)?
    /// Raised by every start and stop: a late result of an older start never creates a session.
    @ObservationIgnored private var generation: Int = 0
    @ObservationIgnored private var replyTimer: (any RescoreTimer)?
    /// The lamp token of the message the simulator is "sending" (cleared with the lamp when the session stops).
    @ObservationIgnored private var pendingToken: Int64?
    /// The uuids of the QSOs logged while a session ran: never published, not even after it stopped.
    @ObservationIgnored private var simulatedUuids: Set<String> = []
    @ObservationIgnored private var closed: Bool = false
    /// While a session runs: once a second, a service that was switched on meanwhile (cluster, score reporting, N1MM
    /// broadcast, Club Log) stops the simulation — the start refusal only covers the services that are live at the start.
    @ObservationIgnored private var serviceWatch: RepeatingTick?

    init(_ dependencies: Dependencies) {
        deps = dependencies
        random = dependencies.random
    }

    // MARK: - the gates

    /// What every keying of the real rig that is not CW asks first: `nil` = allowed (no simulation).
    public var keyingRefusal: EntryStatus? {
        let allowed: Bool = !isStarting && (session?.allowsRigKeying ?? true)
        return allowed ? nil : EntryStatus.tr(Self.refusalKey)
    }

    /// Publishing a QSO outward (sync, Club Log, score, broadcast, plugins) is allowed only while no session runs.
    public var allowsOutwardEffects: Bool {
        session?.allowsOutwardEffects ?? true
    }

    /// Whether this QSO may be published (an insert, an edit, a delete, Club Log, plugins, broadcast, WSJT-X): never a
    /// QSO that a session logged; real QSOs (edits, deletes, ingested ones) flow as usual while it runs.
    public func allowsPublishing(_ qso: Qso) -> Bool {
        !isSimulated(qso)
    }

    public func isSimulated(_ qso: Qso) -> Bool {
        !qso.uuid.isEmpty && simulatedUuids.contains(qso.uuid)
    }

    // MARK: - start and stop

    /// Kotlin `startSimulator(settings, noise)`: a running session is stopped first; the output opens on the lane, then
    /// the session starts with the callsigns of `master.scp` (an empty database makes them up). A failed output shows
    /// `Simulátor: zvukový výstup nejde otevřít (…)` and nothing starts.
    public func start(settings: PileupSimulator.Settings, noise: Float) {
        guard !closed else { return }
        if let service = liveOutwardService() {
            let key = "Simulátor: nejdřív vypni %s, nebo použij zkušební závod"
            startNotice = deps.language.tr(key, .string(service))
            deps.status.show(key, .string(service))
            return
        }
        stop()
        generation += 1
        let mine: Int = generation
        isStarting = true
        // Whatever the real rig is keying now (a carrier, a voice message, a CW message) is released: the gate only
        // refuses new keying, so the one in progress is stopped here (a release is never gated).
        _ = keyer?.stopSending()
        let make = deps.hardware.makeSimAudio
        let level = Double(noise)
        lane.submit({ () -> Result<any SimAudioSink, any Error> in
            Result { try make(level) }
        }, then: { [weak self] result in
            self?.opened(result, generation: mine, settings: settings)
        })
    }

    private func opened(_ result: Result<any SimAudioSink, any Error>, generation mine: Int,
                        settings: PileupSimulator.Settings) {
        guard mine == generation, !closed else {
            if case .success(let late) = result {
                lane.submit { late.close() }
            }
            return
        }
        isStarting = false
        switch result {
        case .failure(let error):
            let text: String = SimulatorSession.audioFailureText(message: KeyingErrors.javaMessage(error),
                                                                 translate: deps.language.translator)
            startNotice = text
            deps.status.showVerbatim(text)
        case .success(let output):
            sink = output
            let scp: ScpDatabase = deps.callData.scp
            session = SimulatorSession(settings: settings, scp: scp, random: random)
            checks = []
            qsos = 0
            errors = 0
            isOn = true
            let watch = RepeatingTick(clock: deps.clock, milliseconds: 1_000) { [weak self] in
                self?.stopIfServiceSwitchedOn()
            }
            serviceWatch = watch
            watch.start()
            let started: String = SimulatorSession.startText(scpSize: scp.size, translate: deps.language.translator)
            startNotice = started
            deps.status.showVerbatim(started)
        }
    }

    /// Kotlin `stopSimulator()` (also the closing of the window): the session ends at once (the gate
    /// opens), the output closes on the lane. Unlike Kotlin the lit F-key of a simulated message goes out with it.
    public func stop() {
        generation += 1
        isStarting = false
        startNotice = nil
        replyTimer?.cancel()
        replyTimer = nil
        serviceWatch?.stop()
        serviceWatch = nil
        session?.stop()
        session = nil
        isOn = false
        if let token = pendingToken {
            pendingToken = nil
            _ = keyer?.finishSimulatedCw(token)
        }
        if let output = sink {
            sink = nil
            lane.submit { output.close() }
        }
    }

    /// An outward service came on while the simulation runs: the simulation ends (a status text says why).
    func stopIfServiceSwitchedOn() {
        guard session != nil, let service = liveOutwardService() else { return }
        stop()
        deps.status.show("Simulátor zastaven: zapnula se služba %s — použij zkušební závod bez služeb", .string(service))
    }

    /// The simulator window was closed.
    public func windowClosed() {
        stop()
    }

    /// Kotlin `setSimulatorNoise(level)`.
    public func setNoise(_ level: Float) {
        sink?.setNoiseLevel(Double(level))
    }

    /// The quit: the session stops and the lane (the output's `close`) is awaited. Kotlin leaves the player open.
    public func shutdown() async {
        closed = true
        stop()
        // An output that is still opening is closed when its result arrives on the main queue: wait for that too.
        await lane.settle()
        await drainMainQueue()
        await lane.settle()
    }

    /// Waits for the sound lane (tests).
    func settle() async {
        await lane.settle()
        await drainMainQueue()
        await lane.settle()
    }

    // MARK: - CW

    /// `tx.simulatorRoute` (Kotlin `simulator?.let { sendSimulated(it, message, index); return }`, `AS:1692-1715`):
    /// the message is rendered into the sound output and, once the estimated sending time has passed, the stations
    /// reply. `true` = the simulator took it (also while the output is still opening: the message is then dropped with
    /// a status text, so it can never reach the real key); `false` = no simulation, the keyer sends it.
    func route(_ message: CwMessage, key: Int) -> Bool {
        if isStarting {
            deps.status.show(Self.refusalKey)
            return true
        }
        guard let current = session, current.isRunning else { return false }
        guard let keyer, let output = sink else { return true }
        let wpm: Int = keyer.cwSpeed
        let pitch = Double(deps.config.config.cwPitchHz)
        let rate: Float = SimAudioPlayer.sampleRate
        let text: String = message.plainText()
        let token: Int64 = keyer.beginSimulatedCw(key: key)
        pendingToken = token
        output.play(CwSynth.render(text, wpm: Int32(clamping: wpm), pitchHz: pitch, amplitude: 0.3, sampleRate: rate),
                    delayMs: 0)
        replyTimer?.cancel()
        let millis: Int = Int(clamping: SendLamp.estimateMillis(message, wpm: wpm))
        replyTimer = deps.clock.schedule(afterMilliseconds: millis) { [weak self] in
            self?.replies(to: text, session: current, token: token, pitch: pitch)
        }
        return true
    }

    private func replies(to text: String, session expected: SimulatorSession, token: Int64, pitch: Double) {
        guard session === expected, expected.isRunning, let keyer, let output = sink else { return }
        guard keyer.finishSimulatedCw(token) else { return }
        pendingToken = nil
        let rate: Float = SimAudioPlayer.sampleRate
        for reply in expected.onSent(text) {
            let from: PileupSimulator.Caller = reply.transmission.from
            let samples: [Float] = CwSynth.render(reply.transmission.text, wpm: from.wpm,
                                                  pitchHz: pitch + Double(from.pitchOffsetHz),
                                                  amplitude: reply.amplitude, sampleRate: rate)
            output.play(samples, delayMs: reply.transmission.delayMs)
        }
    }

    /// `tx.simulatorAbort` (Esc, `AS:1741-1748`): the scheduled signals are dropped, the lamp goes out; the result is
    /// whether a message was lit. `nil` = no simulation (the keyer's own abort applies).
    func abort() -> Bool? {
        guard let current = session, current.isRunning else { return nil }
        replyTimer?.cancel()
        replyTimer = nil
        pendingToken = nil
        sink?.clear()
        return keyer?.abortSimulatedCw() ?? false
    }

    // MARK: - logged QSOs

    /// The `.simulator` effect of a QSO logged here (never an import, `AS:2790-2795`): the QSO is compared with the
    /// station that was worked and the counters follow.
    func qsoLogged(_ qso: Qso) {
        // The tag follows the plan, not the session: a QSO planned while the simulation ran stays simulated even when
        // the session was stopped during the database write.
        if !qso.uuid.isEmpty {
            simulatedUuids.insert(qso.uuid)
        }
        guard let current = session, current.isRunning else { return }
        current.onLogged(call: qso.call, exchangeRcvd: qso.exchangeRcvd, serialRcvd: qso.serialRcvd)
        checks = current.checks
        qsos = current.qsos
        errors = current.errors
    }
}
