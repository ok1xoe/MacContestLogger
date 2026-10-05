import Foundation
import MCLCore
import Observation
import os

/// The CW keyer of v1.1.1 and the hub of the keying (`AppState` `AS:983-1011, 1443-1536, 1620-1642, 1714-1799,
/// 2106-2150`): the CW speed, the lit F-key with its cancellation token (shared with the digital keyer), tuning the
/// carrier with its 30 s safeguard, Esc, the interface reset and the quit. The voice keyer (`voice`) and fldigi
/// (`digital`) hang off it.
///
/// Every keyer call runs on the `KeyerLane` (Kotlin `cwDispatcher`); the state changes on the main actor in
/// Kotlin's order and a late result of an older send never touches a newer one (`SendLamp` token). Times (the lamp's
/// estimate, the tuning safeguard, the fldigi watch, the recording limit) go through the injected clock.
@Observable @MainActor
public final class KeyerModel {

    /// Kotlin `cwSpeed` (PgUp/PgDn, the spinner); written to `config.cwKeyer.speed` without saving.
    public private(set) var cwSpeed: Int
    /// Kotlin `cwSendingKey` + `cwToken` + `digitalSending`.
    public private(set) var lamp = SendLamp()
    /// Kotlin `tuning` (Ctrl+T).
    public private(set) var isTuning: Bool = false
    /// Raised by every failed transmission (a keyer error, fldigi unreachable, a voice message that sent nothing);
    /// the CQ repeat loop stops on it.
    public private(set) var sendFailures: Int = 0

    /// The voice keyer (phone).
    public let voice: VoiceKeyerModel
    /// fldigi (RTTY/PSK).
    public let digital: DigitalKeyerModel

    /// The ports of the services the keyer depends on.
    @ObservationIgnored public var tx = TxPorts()
    /// What the free CW text and the voice messages are built from (the main entry window's `cwContext`).
    @ObservationIgnored public var messageContext: @MainActor () -> CwMessageBuilder.Context? = { nil }
    /// The main entry window's mode can be keyed (`phone || cw || digi`: `KeyerPort.canSend`).
    @ObservationIgnored public var entryModeKeyable: @MainActor () -> Bool = { false }

    @ObservationIgnored let lane: KeyerLane
    @ObservationIgnored let config: ConfigModel
    @ObservationIgnored let status: StatusModel
    @ObservationIgnored let language: LanguageModel
    @ObservationIgnored let clock: any RescoreClock
    @ObservationIgnored private let operating: OperatingModel
    @ObservationIgnored private weak var rig: RigModel?
    @ObservationIgnored private let activeCat: ActiveCatBox
    /// A keyer may be open on the lane (Kotlin `cwKeyer != null`): set when a job that opens it is queued, cleared
    /// by the reset and the quit. Esc aborts only then (Kotlin), but never misses a keyer still being opened.
    @ObservationIgnored private var keyerMayBeOpen: Bool = false
    @ObservationIgnored private var tuneTimeout: (any RescoreTimer)?
    /// Raised by every `setTune`: a late failure of an older tune never clears a newer one.
    @ObservationIgnored private var tuneGeneration: Int64 = 0
    /// The rig whose PTT carries the carrier of a CAT tune (the off goes to it, whatever is active by then).
    @ObservationIgnored private var tunedRig: Int?
    /// Rigs a CAT tune may have left keyed: its `T 1` failed and so did the `T 0` sent after it, or its off failed.
    /// The release before a disconnect and the quit send `T 0` to them.
    @ObservationIgnored private let unreleasedTune = UnreleasedRigs()
    @ObservationIgnored private var lampTimer: (any RescoreTimer)?
    @ObservationIgnored private var closed: Bool = false

    struct Dependencies {
        let hardware: HardwarePorts
        let config: ConfigModel
        let status: StatusModel
        let language: LanguageModel
        let operating: OperatingModel
        let rig: RigModel
        let clock: any RescoreClock
        let dataDir: URL
    }

    init(_ dependencies: Dependencies) {
        config = dependencies.config
        status = dependencies.status
        language = dependencies.language
        operating = dependencies.operating
        rig = dependencies.rig
        clock = dependencies.clock
        cwSpeed = dependencies.config.config.cwKeyer.speed
        let activeCat = ActiveCatBox()
        self.activeCat = activeCat
        let lane = KeyerLane(hardware: dependencies.hardware, activeCat: activeCat)
        self.lane = lane
        voice = VoiceKeyerModel(VoiceKeyerModel.Dependencies(
            hardware: dependencies.hardware, config: dependencies.config, status: dependencies.status,
            language: dependencies.language, operating: dependencies.operating, clock: dependencies.clock,
            dataDir: dependencies.dataDir))
        digital = DigitalKeyerModel(config: dependencies.config, status: dependencies.status, lane: lane,
                                    clock: dependencies.clock)
        voice.keyer = self
        digital.keyer = self
    }

    // MARK: - state

    /// Kotlin `cwSendingKey`: the lit F-key (`-1` = free text), `nil` = nothing.
    public var cwSendingKey: Int? {
        lamp.key
    }

    /// Kotlin `digitalSending`.
    public var digitalSending: Bool {
        lamp.digitalSending
    }

    /// Kotlin `isSending()` (`AS:1768`): a voice message (or its plan, synchronous in Kotlin) or the CW/digital
    /// lamp — the CQ repeat waits for it.
    public var isSending: Bool {
        voice.playingKey != nil || voice.planning || lamp.key != nil
    }

    /// Esc would stop something (`stopSending()` returns `true` without the CQ repeat): tuning, a recording, a voice
    /// message, fldigi, or a lit CW key.
    public var isActive: Bool {
        isTuning || voice.isActive || lamp.digitalSending || lamp.key != nil
    }

    // MARK: - CW

    /// Kotlin `sendCw(message, index)` (`AS:1714-1735`): the simulator takes it, the TX gate may refuse it,
    /// otherwise the lamp lights, the keyer opens (or is reused) on the lane, a lit message is aborted first
    /// and the new one sent; a failure shows `"CW: …"`, success keeps the lamp lit for the estimated time.
    public func sendCw(_ message: CwMessage, key: Int) {
        if closed {
            return
        }
        if let route = tx.simulatorRoute, route(message, key) {
            return
        }
        guard txAllowed() else {
            noteSendFailure()
            return
        }
        tx.announceTx()
        let begin: SendLamp.Begin = lamp.begin(key: key)
        let wpm: Int = cwSpeed
        let request: KeyerLane.OpenRequest = openRequest()
        prepareKeyer()
        let lane: KeyerLane = self.lane
        lane.run({ devices -> String?? in
            do {
                let keyer: any CwKeyer = try lane.keyerOrOpen(devices, request)
                if begin.wasSending {
                    try keyer.abort()
                }
                try keyer.send(message, wpm: wpm)
                return .none
            } catch {
                return .some(KeyingErrors.javaMessage(error))
            }
        }, then: { [weak self] failure in
            guard let self else { return }
            if case .some(let message) = failure {
                self.lamp.finish(begin.token)
                self.show(KeyerTexts.cwFailure(message))
                self.noteSendFailure()
                return
            }
            let millis: Int64 = SendLamp.estimateMillis(message, wpm: wpm)
            self.lampTimer = self.clock.schedule(afterMilliseconds: Int(clamping: millis)) { [weak self] in
                self?.lamp.finish(begin.token)
            }
        })
    }

    /// Kotlin `sendCwText(text, hisCall)` (`AS:1620-1624`): free CW text with the F-key macros (`-1` lights nothing).
    public func sendCwText(_ text: String, call: String = "") {
        guard var context = messageContext() else { return }
        context.hisCall = call
        context.rst = "599"
        let message: CwMessage = CwMessageBuilder.build(text, context)
        if !message.isEmpty {
            sendCw(message, key: -1)
        }
    }

    /// Kotlin `requestMove(qso, bandAdif)` (`AS:1629-1642`): CW sends „PSE QSY <kHz>", phone hints what to say.
    public func requestMove(_ qso: Qso, bandAdif: String) {
        guard let band = Band.from(adif: bandAdif) else { return }
        let hz: Int64? = operating.cqFrequency(band: band) ?? rig?.tuning.lastFrequency(on: band)
        let place: String
        if let hz {
            place = KeyerTexts.moveKHz(hz)
        } else {
            place = KotlinStrings.uppercase(bandAdif)
        }
        if qso.mode == .cw {
            sendCwText("PSE QSY " + place, call: qso.call)
            status.show("%s: odesláno PSE QSY %s", .string(qso.call), .string(place))
        } else {
            let target: String = hz.map { CatStatusLine.khz($0) } ?? bandAdif
            status.show("%s: požádej o QSY na %s (nový násobič)", .string(qso.call), .string(target))
        }
    }

    /// Kotlin `abortCw()` (`AS:1743-1755`, the simulator is a separate model): with an open keyer the lamp goes out, the token
    /// moves on and `abort` is queued — even when nothing was sent; `true` = a message was lit.
    public func abortCw() -> Bool {
        if let simulated = tx.simulatorAbort?() {
            // A real message begun before the simulation started is still stopped (a release is never gated).
            if keyerMayBeOpen {
                lampTimer?.cancel()
                lane.run { devices in
                    try? devices.keyer?.abort()
                }
            }
            return simulated
        }
        guard keyerMayBeOpen else { return false }
        let wasSending: Bool = lamp.abortCw()
        lampTimer?.cancel()
        lane.run { devices in
            try? devices.keyer?.abort()
        }
        return wasSending
    }

    // MARK: - tuning

    /// Ctrl+T (`toggleTune`).
    public func toggleTune() {
        setTune(!isTuning)
    }

    /// Kotlin `setTune(on)` (`AS:987-1008`): the carrier on or off; on → status and the 30 s safeguard (injected
    /// clock — it switches off even when the lane is stuck), off → status; a failure of the current tune switches it
    /// off with `tr("Ladění: %s")` (a late failure of an older one does not touch a newer tune).
    ///
    /// Winkeyer tunes on the keyer lane (`key immediate`). A CAT tune (`CatCwKeyer.tune` = the rig's PTT) runs on the
    /// tuned rig's own `RigLane`, so its off is ordered before any disconnect of that rig, and goes to the rig that
    /// was tuned even after an SO2R switch.
    public func setTune(_ on: Bool) {
        if on == isTuning || (on && closed) {
            return
        }
        if on && !txAllowed() {
            return
        }
        isTuning = on
        tuneTimeout?.cancel()
        tuneTimeout = nil
        tuneGeneration &+= 1
        let generation: Int64 = tuneGeneration
        let failed: @MainActor @Sendable (String?) -> Void = { [weak self] message in
            guard let self, generation == self.tuneGeneration else { return }
            self.isTuning = false
            self.tunedRig = nil
            self.tuneTimeout?.cancel()
            self.tuneTimeout = nil
            self.status.show("Ladění: %s", .string(message ?? "null"))
        }
        if on {
            prepareKeyer()
            if config.config.cwKeyer.method == .cat, let index = rig?.vfo.activeCatIndex {
                tunedRig = index
            }
        }
        if let index = tunedRig, let rigLane = rig?.lanes[index] {
            if !on {
                tunedRig = nil
            }
            catTune(on, rig: index, lane: rigLane, failed: failed)
        } else {
            keyerTune(on, failed: failed)
        }
        if on {
            status.show("LADĚNÍ — nosná (Ctrl+T nebo Esc ukončí, pojistka 30 s)")
            tuneTimeout = clock.schedule(afterMilliseconds: 30_000) { [weak self] in
                self?.setTune(false)
            }
        } else {
            status.show("Ladění ukončeno")
        }
    }

    /// The keyer's own carrier on the keyer lane (Winkeyer; also the error of a keyer that is off). A carrier on that
    /// fails on an open keyer is switched off in the same job (a safety override beyond Kotlin: the keyer may have
    /// taken the command before its answer failed).
    private func keyerTune(_ on: Bool, failed: @escaping @MainActor @Sendable (String?) -> Void) {
        let request: KeyerLane.OpenRequest = openRequest()
        let lane: KeyerLane = self.lane
        lane.run({ devices -> String?? in
            var keyer: (any CwKeyer)?
            do {
                let opened: any CwKeyer = try lane.keyerOrOpen(devices, request)
                keyer = opened
                try opened.tune(on)
                return .none
            } catch {
                if on {
                    try? keyer?.tune(false)
                }
                return .some(KeyingErrors.javaMessage(error))
            }
        }, then: { failure in
            if case .some(let message) = failure {
                failed(message)
            }
        })
    }

    /// `CatCwKeyer.tune(on)` = the rig's PTT, on the tuned rig's lane (`"CW přes CAT: TRX není připojený"` without a rig).
    ///
    /// A carrier on that fails is switched off at once in the same job (a safety override beyond Kotlin): the rig got
    /// `T 1` before its answer was refused, garbled or late, so it may be transmitting, and the failure clears the
    /// tune and its 30 s safeguard. If that `T 0` fails too, or a carrier off fails, the rig is remembered as possibly
    /// keyed for the release before a disconnect and the quit.
    private func catTune(_ on: Bool, rig index: Int, lane: RigLane,
                         failed: @escaping @MainActor @Sendable (String?) -> Void) {
        let unreleased: UnreleasedRigs = unreleasedTune
        lane.run({ cat -> String?? in
            do {
                try CatCwKeyer { cat.rigOrNull() }.tune(on)
                if !on {
                    unreleased.remove(index)
                }
                return .none
            } catch {
                // Remembered unless the `T 0` went out (also when the rig went away meanwhile: its next connection
                // sends `T 0` first).
                if on, let rig = cat.rigOrNull(), (try? rig.setPtt(false)) != nil {
                    unreleased.remove(index)
                } else {
                    unreleased.insert(index)
                }
                return .some(KeyingErrors.javaMessage(error))
            }
        }, then: { failure in
            if case .some(let message) = failure {
                failed(message)
            }
        })
    }

    /// Before a user-initiated disconnect of rig `index` (the LED, a reconnect after Settings, RESETINTERFACES, a rig
    /// scan): a CAT carrier or a voice message keyed on that rig is switched off, and `T 0` is queued on the rig's
    /// lane ahead of the disconnect — the same rule as the footswitch PTT. The rig never stays keyed.
    func releaseBeforeDisconnect(rigIndex index: Int) {
        guard let rigLane = rig?.lanes[index] else { return }
        var release = false
        if isTuning, tunedRig == index {
            tuneGeneration &+= 1
            isTuning = false
            tunedRig = nil
            tuneTimeout?.cancel()
            tuneTimeout = nil
            status.show("Ladění ukončeno")
            release = true
        }
        voice.releaseBeforeDisconnect(rigLane)
        let unreleased: UnreleasedRigs = unreleasedTune
        let tuned: Bool = release
        rigLane.run { cat in
            // A rig a failed tune may have left keyed is released here too; without a connection the record stays
            // for the rig's next connection.
            Self.releaseTune(cat, rig: index, tuned: tuned, unreleased: unreleased)
        }
    }

    /// On rig `index`'s lane: `T 0` for a carrier being switched off (`tuned`) or a rig a failed tune may have left
    /// keyed; the record is dropped only once `T 0` went out on a connected rig.
    nonisolated private static func releaseTune(_ cat: any CatPort, rig index: Int, tuned: Bool,
                                                unreleased: UnreleasedRigs) {
        guard tuned || unreleased.contains(index) else { return }
        guard cat.snapshot.connected, let rig = cat.rigOrNull() else {
            if tuned {
                unreleased.insert(index)
            }
            return
        }
        if (try? rig.setPtt(false)) != nil {
            unreleased.remove(index)
        } else {
            unreleased.insert(index)
        }
    }

    /// The hook of a rig's fresh connection (its connect thread, before the first poll): a release still owed to the
    /// rig — a failed tune's or the voice keyer's — goes out as the first command. Nothing on a new connection can be
    /// keyed legitimately yet, so `T 0` is safe.
    func owedReleaseHook() -> @Sendable (Int, any RigController) -> Void {
        let unreleased: UnreleasedRigs = unreleasedTune
        let ptt: VoicePtt = voice.ptt
        let lanes: [RigLane] = rig?.lanes ?? []
        return { index, connected in
            let lane: RigLane? = index < lanes.count ? lanes[index] : nil
            let voiceReleased: Bool = lane.map { ptt.releaseOwed(connected, lane: $0) } ?? false
            guard unreleased.contains(index) else { return }
            if voiceReleased || (try? connected.setPtt(false)) != nil {
                unreleased.remove(index)
            }
        }
    }

    // MARK: - speed

    /// Kotlin `changeCwSpeed(deltaWpm)` (PgUp/PgDn ± `cwSpeedStep`).
    public func changeCwSpeed(_ deltaWpm: Int) {
        updateCwSpeed(cwSpeed + deltaWpm)
    }

    /// Kotlin `updateCwSpeed(wpm)` (`AS:2131-2138`): clamped to 5…60, into the config without saving, and
    /// `setSpeed` to an open keyer on the lane.
    public func updateCwSpeed(_ wpm: Int) {
        let clamped: Int = CwKeyerConfig.clamp(wpm)
        if clamped == cwSpeed {
            return
        }
        cwSpeed = clamped
        config.config.cwKeyer.speed = clamped
        guard keyerMayBeOpen else { return }
        lane.run { devices in
            try? devices.keyer?.setSpeed(clamped)
        }
    }

    // MARK: - Esc

    /// Kotlin `stopSending()` without the CQ repeat (the entry window clears it, `AS:1757-1765`): tuning first, then
    /// the first of voice, fldigi and CW that was active (`StopSendingChain`).
    public func stopSending() -> Bool {
        let result = StopSendingChain.run(tuning: isTuning, cqRepeat: false, voice: { voice.stop() },
                                          digital: { digital.abort() }, cw: { abortCw() })
        if result.stopTuning {
            setTune(false)
        }
        return result.stopped
    }

    // MARK: - reset and quit

    /// `cwKeyer?.close(); cwKeyer = null; cwKeyerSignature = null` of `resetInterfaces()` (`AS:2109-2111`).
    ///
    /// A Winkeyer carrier on is switched off before the keyer closes (a CAT carrier was released with the rig).
    public func resetKeyer() {
        keyerMayBeOpen = false
        let keyerTuning: Bool = isTuning && tunedRig == nil
        if keyerTuning {
            tuneGeneration &+= 1
            isTuning = false
            tuneTimeout?.cancel()
            tuneTimeout = nil
        }
        lane.run { devices in
            if keyerTuning {
                try? devices.keyer?.tune(false)
            }
            devices.keyer?.close()
            devices.keyer = nil
            devices.signature = nil
        }
    }

    /// Kotlin `shutdownKeyers()` (`AS:2141-2148`; the app calls it first in its quit, `App.kt:197`):
    /// the carrier off (a CAT carrier on its rig's lane, a Winkeyer one on the keyer lane), fldigi aborted when it
    /// sends, the CW keyer aborted and closed — all queued at once — while the voice keyer discards a recording and
    /// drains its message (PTT released) on its own lane; then both are awaited. CAT goes after. Kotlin's
    /// `configStore.save(config)` at the end (the CW speed) is done by `AppModel.shutdown` once a Settings commit or a
    /// profile load in flight has settled: saved here, it could enqueue the old configuration after the commit's write
    /// (Kotlin's commit is synchronous on the UI thread, so it never overlaps its quit).
    public func shutdown() async {
        guard !closed else { return }
        closed = true
        tuneTimeout?.cancel()
        lampTimer?.cancel()
        tuneGeneration &+= 1
        let wasTuning: Bool = isTuning
        isTuning = false
        var tuneRigLane: RigLane?
        if wasTuning, let index = tunedRig {
            tuneRigLane = rig?.lanes[index]
        }
        tunedRig = nil
        if let tuneRigLane {
            tuneRigLane.run { cat in
                try? cat.setPtt(false)
            }
        }
        // A rig a failed tune may have left keyed is released before CAT goes.
        let unreleased: UnreleasedRigs = unreleasedTune
        let rigLanes: [RigLane] = rig?.lanes ?? []
        for (index, rigLane) in rigLanes.enumerated() {
            rigLane.run { cat in
                Self.releaseTune(cat, rig: index, tuned: false, unreleased: unreleased)
            }
        }
        let keyerTuning: Bool = wasTuning && tuneRigLane == nil
        digital.shutdown()
        keyerMayBeOpen = false
        lane.run { devices in
            if keyerTuning {
                try? devices.keyer?.tune(false)
            }
            try? devices.keyer?.abort()
            devices.keyer?.close()
            devices.keyer = nil
            devices.signature = nil
            devices.fldigi = nil
            devices.fldigiSignature = nil
        }
        await voice.shutdown()
        await lane.settle()
        for rigLane in rigLanes {
            await rigLane.settle()
        }
    }

    /// Waits for the keyer lane and the voice lane (tests).
    func settle() async {
        await lane.settle()
        await voice.settle()
    }

    // MARK: - shared with the voice and digital keyers

    /// Kotlin `txAllowed()`: the TX gate's refusal is shown, nothing is sent.
    func txAllowed() -> Bool {
        if let locked = tx.rigKeyingGate() {
            show(locked)
            return false
        }
        guard let refusal = tx.txGate() else { return true }
        show(refusal)
        return false
    }

    func show(_ message: EntryStatus) {
        status.showJoined(message.parts, separator: "")
    }

    /// The pileup simulator "sends" a CW message: the lamp lights with a new token (`++cwToken`).
    func beginSimulatedCw(key: Int) -> Int64 {
        lamp.begin(key: key).token
    }

    /// The simulated message is "sent": the lamp goes out when `token` is still current (`true`).
    func finishSimulatedCw(_ token: Int64) -> Bool {
        lamp.finish(token)
    }

    /// Esc with a simulator: `wasSending`, `cwToken++`, the lamp out.
    func abortSimulatedCw() -> Bool {
        lamp.abortCw()
    }

    /// A transmission failed (the CQ repeat stops).
    func noteSendFailure() {
        sendFailures += 1
    }

    /// `sendDigitalText`: `++cwToken`, the lamp, `digitalSending`.
    func beginDigital(key: Int) -> Int64 {
        lamp.beginDigital(key: key)
    }

    func finishDigital(_ token: Int64) {
        lamp.finishDigital(token)
    }

    func failDigital(_ token: Int64) {
        lamp.failDigital(token)
    }

    func abortDigitalLamp() -> Bool {
        lamp.abortDigital()
    }

    /// The active rig's CAT session (Kotlin `cat`), read when a transmission starts.
    func activeRigLane() -> RigLane? {
        rig?.activeLane
    }

    func activeRigCat() -> (any CatPort)? {
        rig?.activeLane.cat
    }

    var isClosed: Bool {
        closed
    }

    /// The keyer will be opened (or reused) on the lane; the CAT keyer reaches the rig active now.
    private func prepareKeyer() {
        keyerMayBeOpen = true
        activeCat.set(activeRigCat())
    }

    private func openRequest() -> KeyerLane.OpenRequest {
        let keyerConfig: CwKeyerConfig = config.config.cwKeyer
        return KeyerLane.OpenRequest(method: keyerConfig.method, port: keyerConfig.winkeyerPort, wpm: cwSpeed,
                                     disabledText: language.tr(KeyerTexts.cwDisabled),
                                     noPortText: language.tr(KeyerTexts.winkeyerNoPort))
    }
}

/// The rigs a failed CAT tune may have left keyed (read and written on the rig lanes, see `catTune`).
final class UnreleasedRigs: Sendable {
    private let rigs = OSAllocatedUnfairLock<Set<Int>>(initialState: [])

    func insert(_ index: Int) {
        rigs.withLock { _ = $0.insert(index) }
    }

    func remove(_ index: Int) {
        rigs.withLock { _ = $0.remove(index) }
    }

    func contains(_ index: Int) -> Bool {
        rigs.withLock { $0.contains(index) }
    }
}
