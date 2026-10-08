import Foundation
import MCLCore
import Observation
import os

/// The voice keyer of v1.1.1 (DVK, `AppState` `AS:1282-1441`; Java `voice/VoiceKeyer`): the Run / S&P messages of
/// F1–F12 (Shift = the other set), planned into wav files (letters, numbers, `[text]` spoken by speech synthesis
/// cached in `<wav>/.tts-cache`), played with PTT over CAT (`isPttViaCat` and a connected rig; otherwise VOX), and
/// the recording of a message (Ctrl+Shift+F, „Recording on the Fly").
///
/// Planning (it may synthesise speech) and starting or stopping a recording block: they run on the voice lane and
/// come back to the main actor; a press, Esc or the quit in between cancels them by generation, so nothing plays or
/// records after Esc. The PTT release always goes to the rig that was keyed.
@Observable @MainActor
public final class VoiceKeyerModel {

    /// Kotlin `voicePlayingKey`.
    public private(set) var playingKey: Int?
    /// Kotlin `voiceRecordingKey`.
    public private(set) var recordingKey: Int?
    /// A message is being planned (between the press and the start of the playback).
    public private(set) var planning: Bool = false
    /// A recording is starting (the input opens on the voice lane).
    public private(set) var recordingStarting: Bool = false

    @ObservationIgnored weak var keyer: KeyerModel?
    /// Performs a control macro of a message (`{LOG}`, `{WIPE}`, `{RUN}`…) in the entry window; wired by the app.
    @ObservationIgnored var performAction: (@MainActor (CwMessage.Action) -> Void)?
    @ObservationIgnored private let voiceKeyer: VoiceKeyer
    @ObservationIgnored let ptt: VoicePtt
    @ObservationIgnored private let settings: VoiceSettingsBox
    @ObservationIgnored private let lane = SerialLane(name: "voice-keyer-plan")
    @ObservationIgnored private let hardware: HardwarePorts
    @ObservationIgnored private let config: ConfigModel
    @ObservationIgnored private let status: StatusModel
    @ObservationIgnored private let language: LanguageModel
    @ObservationIgnored private let operating: OperatingModel
    @ObservationIgnored private let clock: any RescoreClock
    @ObservationIgnored private let dataDir: URL
    /// Kotlin `voiceToken`.
    @ObservationIgnored private var voiceToken: Int64 = 0
    /// Cancels a plan or a recording start in flight.
    @ObservationIgnored private var generation: Int64 = 0
    /// Kotlin `recording`.
    @ObservationIgnored private var recording: (any MessageRecording)?
    /// Kotlin `recordingTimeout`.
    @ObservationIgnored private var recordingTimeout: (any RescoreTimer)?
    @ObservationIgnored private var closed: Bool = false

    struct Dependencies {
        let hardware: HardwarePorts
        let config: ConfigModel
        let status: StatusModel
        let language: LanguageModel
        let operating: OperatingModel
        let clock: any RescoreClock
        let dataDir: URL
    }

    init(_ dependencies: Dependencies) {
        hardware = dependencies.hardware
        config = dependencies.config
        status = dependencies.status
        language = dependencies.language
        operating = dependencies.operating
        clock = dependencies.clock
        dataDir = dependencies.dataDir
        let settings = VoiceSettingsBox()
        self.settings = settings
        let ptt = VoicePtt()
        self.ptt = ptt
        voiceKeyer = VoiceKeyer(audio: dependencies.hardware.voicePlayer { settings.outputDevice },
                                ptt: { on in try ptt.set(on) },
                                pttDelayMs: { settings.pttDelayMs }, delay: dependencies.hardware.voicePttDelay)
    }

    /// Esc would stop something here.
    public var isActive: Bool {
        playingKey != nil || planning || recording != nil || recordingStarting
    }

    /// Kotlin `wavDir()`: the configured directory (trimmed), otherwise `<data>/wav`.
    public var wavDirectory: String {
        let configured: String = KotlinStrings.trim(config.config.voiceKeyer.wavDir)
        return configured.isEmpty ? dataDir.appendingPathComponent("wav").path : configured
    }

    /// Kotlin `functionKeyMessages(opposite)`: the Run set in Run (Shift = the other).
    func messages(opposite: Bool) -> [FunctionKeyMessage] {
        let keys = FunctionKeySet(run: config.config.voiceKeyer.runMessages, sp: config.config.voiceKeyer.spMessages)
        return keys.messages(run: operating.isRun, opposite: opposite)
    }

    // MARK: - playing

    /// Kotlin `playFunctionKeys(indices, hisCall, freqHz, opposite)` (`AS:1315-1350`). The result is the status
    /// shown at once (a recording in progress); the plan's texts (`chybí`, `zpráva je prázdná`) and the keyer's
    /// error follow when the plan or the playback is done.
    public func play(_ indices: [Int], hisCall: String, freqHz: Int64, opposite: Bool) -> EntryStatus? {
        guard let last = indices.last, let keyer, !closed else { return nil }
        if recording != nil || recordingStarting {
            keyer.noteSendFailure()
            return .tr("Nahrává se — nejdřív ukonči záznam (Esc)")
        }
        guard keyer.txAllowed() else {
            keyer.noteSendFailure()
            return nil
        }
        keyer.tx.announceTx()
        let set: [FunctionKeyMessage] = messages(opposite: opposite)
        let texts: [String] = indices.compactMap { index in
            guard index >= 0, index < set.count, !KotlinStrings.isBlank(set[index].text) else { return nil }
            return set[index].text
        }
        let app: AppConfig = config.config
        let request = PlanRequest(
            text: texts.joined(separator: ","), wavDir: wavDirectory, lettersPath: app.voiceKeyer.lettersPath,
            context: VoiceMessagePlanner.Context(operatorCall: operating.operatorCall, myCall: app.station.call,
                                                 hisCall: hisCall, serial: Int32(clamping: nextSerial()),
                                                 freqHz: freqHz, functionKeys: set.map(\.text)),
            ttsVoice: app.ttsVoice, synthesize: hardware.synthesize)
        settings.update(outputDevice: app.voiceKeyer.outputDevice, pttDelayMs: app.voiceKeyer.pttDelayMs)
        ptt.arm(target: keyer.activeRigLane(), viaCat: app.voiceKeyer.pttViaCat)
        generation &+= 1
        let planGeneration: Int64 = generation
        planning = true
        lane.submit({ request.run() }, then: { [weak self] outcome in
            guard let self, planGeneration == self.generation, !self.closed else { return }
            self.planning = false
            self.planned(outcome, indices: indices, key: last)
        })
        return nil
    }

    private func planned(_ outcome: PlanOutcome, indices: [Int], key: Int) {
        let label: String = FunctionKeyRouter.keysLabel(indices)
        switch outcome {
        case .failed(let message):
            show(.tr("Hlasový klíč: %s", .string(message)))
            keyer?.noteSendFailure()
        case .plan(let plan, let wav):
            if !plan.unknownMacros.isEmpty {
                show(.tr("%s: makra %s zatím neumím — vynechána", .string(label),
                         .string(plan.unknownMacros.joined(separator: " "))))
            }
            if !plan.missing.isEmpty {
                show(.tr("%s: chybí %s (v %s)", .string(label), .string(plan.missing.joined(separator: ", ")),
                         .string(wav)))
            }
            // Actions before the first audio (or of a message with no audio) are performed at once.
            let leading: [CwMessage.Action] = plan.leadingActions
            for action in leading {
                performAction?(action)
            }
            if plan.files.isEmpty {
                if plan.missing.isEmpty && plan.unknownMacros.isEmpty && leading.isEmpty {
                    show(.tr("%s: zpráva je prázdná (Nastavení → Function Keys)", .string(label)))
                }
                // A message of control macros only is a success; one that sent nothing because of missing files is not.
                if !plan.missing.isEmpty || (leading.isEmpty && plan.unknownMacros.isEmpty) {
                    keyer?.noteSendFailure()
                }
                return
            }
            voiceToken &+= 1
            let token: Int64 = voiceToken
            playingKey = key
            // Runs on the voice queue: the action is performed on the main actor and the next audio waits for it (so
            // `{LOG},tu.wav` logs before "tu" starts), but never longer than a second, so a busy main actor cannot
            // hold the transmitter keyed.
            let onAction: @Sendable (CwMessage.Action) -> Void = { [weak self] action in
                let done = DispatchSemaphore(value: 0)
                MainHop.post {
                    defer { done.signal() }
                    guard let self, self.voiceToken == token, self.playingKey != nil else { return }
                    self.performAction?(action)
                }
                _ = done.wait(timeout: .now() + 1)
            }
            voiceKeyer.play(steps: plan.playSteps, onAction: onAction) { [weak self] error in
                MainHop.post {
                    self?.finished(token: token, error: error)
                }
            }
        }
    }

    private func finished(token: Int64, error: String?) {
        if voiceToken == token {
            playingKey = nil
        }
        if let error {
            show(.tr("Hlasový klíč: %s", .string(error)))
            keyer?.noteSendFailure()
        }
    }

    /// Kotlin `stopVoice()` (`AS:1384-1396`): a recording is saved, otherwise the message (or its plan) is stopped;
    /// `true` = something was stopped.
    public func stop() -> Bool {
        if recording != nil || recordingStarting {
            finishRecording()
            return true
        }
        if planning {
            generation &+= 1
            planning = false
            if playingKey == nil {
                return true
            }
        }
        if playingKey != nil {
            voiceKeyer.stop()
            voiceToken &+= 1
            playingKey = nil
            return true
        }
        return false
    }

    // MARK: - recording a message

    /// Kotlin `toggleRecording(index)` (`AS:1403-1424`): the second press (or Esc) saves; only a message of one wav
    /// file can be recorded; `maxRecordSeconds` ends a forgotten recording. Opening the input runs on the voice lane.
    public func toggleRecording(_ index: Int) -> EntryStatus? {
        if recording != nil || recordingStarting {
            finishRecording()
            return nil
        }
        guard !closed else { return nil }
        let set: [FunctionKeyMessage] = messages(opposite: false)
        guard index >= 0, index < set.count else { return nil }
        let wav: JavaPath? = try? JavaPath(wavDirectory)
        let target: JavaPath? = wav.flatMap { dir in
            (try? VoiceMessagePlanner.recordTarget(set[index].text, operatorCall: operating.operatorCall,
                                                   wavDir: dir)) ?? nil
        }
        guard let target else {
            return .tr("F%s: nahrávat jde jen zprávu s jedním wav souborem (Nastavení → Function Keys)",
                       .int(index + 1))
        }
        _ = stop()
        let device: String = config.config.voiceKeyer.inputDevice
        let record: @Sendable (JavaPath, String?) throws -> any MessageRecording = hardware.recordMessage
        generation &+= 1
        let startGeneration: Int64 = generation
        recordingStarting = true
        lane.submit({ () -> RecordStart in
            do {
                return .started(try record(target, device))
            } catch {
                return .failed(KeyingErrors.javaMessage(error) ?? "null")
            }
        }, then: { [weak self] outcome in
            self?.recordStarted(outcome, index: index, target: target, generation: startGeneration)
        })
        return nil
    }

    private func recordStarted(_ outcome: RecordStart, index: Int, target: JavaPath, generation started: Int64) {
        guard started == generation, !closed else {
            // Esc, a second press or the quit came first: the recording is discarded.
            if case .started(let recording) = outcome {
                lane.submit {
                    recording.cancel()
                }
            }
            return
        }
        recordingStarting = false
        switch outcome {
        case .failed(let message):
            show(.tr("Nahrávání nezačalo: %s", .string(message)))
        case .started(let recording):
            self.recording = recording
            recordingKey = index
            show(.tr("● Nahrávám F%s → %s (Ctrl+Shift+F%s nebo Esc ukončí)", .int(index + 1),
                     .string(target.description), .int(index + 1)))
            let seconds: Int = config.config.voiceKeyer.maxRecordSeconds
            recordingTimeout = clock.schedule(afterMilliseconds: seconds * 1000) { [weak self] in
                guard let self, self.recording != nil else { return }
                self.finishRecording()
            }
        }
    }

    /// Kotlin `finishRecording()` (`AS:1426-1439`): `Recording.stop` on the voice lane, then the status.
    private func finishRecording() {
        if recordingStarting {
            generation &+= 1
            recordingStarting = false
            return
        }
        guard let recording else { return }
        self.recording = nil
        recordingKey = nil
        recordingTimeout?.cancel()
        recordingTimeout = nil
        lane.submit({ () -> String?? in
            do {
                try recording.stop()
                return .none
            } catch {
                return .some(KeyingErrors.javaMessage(error))
            }
        }, then: { [weak self] failure in
            guard let self else { return }
            if case .some(let message) = failure {
                self.show(.tr("Nahrávka se neuložila: %s", .string(message ?? "null")))
            } else {
                self.show(.tr("Nahrávka uložena: %s", .string(recording.target.description)))
            }
        })
    }

    // MARK: - quit

    /// The voice part of `shutdownKeyers()` (`AS:2141-2144`): the recording in progress is discarded (a starting one
    /// too), the keyer closed and its last message drained — the PTT is released before CAT goes (`close`
    /// only here).
    func shutdown() async {
        guard !closed else { return }
        closed = true
        generation &+= 1
        planning = false
        recordingStarting = false
        recordingTimeout?.cancel()
        let recording: (any MessageRecording)? = self.recording
        self.recording = nil
        recordingKey = nil
        playingKey = nil
        let voiceKeyer: VoiceKeyer = self.voiceKeyer
        // The message on the air stops at once (the state lock only), not when the plan lane is free; the lane then
        // drains it (its PTT released over the rig's lane).
        voiceKeyer.close()
        lane.submit {
            recording?.cancel()
            voiceKeyer.closeAndDrain()
        }
        await lane.settle()
        // A rig still recorded as keyed (a failed key whose `T 0` failed too) is released before CAT goes.
        let ptt: VoicePtt = self.ptt
        for held in ptt.keyedLanes {
            held.run { cat in
                try? ptt.release(cat, lane: held)
            }
            await held.settle()
        }
    }

    /// Before a user disconnect of `rigLane`'s rig (on the main actor, before the disconnect is queued): the PTT is
    /// fenced (no message armed before now keys any more), a message aimed at that rig — planning or playing — is
    /// stopped, and a job on the rig's lane, ahead of the disconnect, sends `T 0` if a key got through before the fence.
    func releaseBeforeDisconnect(_ rigLane: RigLane) {
        let aimed: Bool = ptt.fence(rigLane)
        if aimed && (planning || playingKey != nil) {
            _ = stop()
        }
        let ptt: VoicePtt = self.ptt
        rigLane.run { cat in
            try? ptt.release(cat, lane: rigLane)
        }
    }

    /// The voice keyer runs a message (from its PTT on until its PTT off; tests).
    var isOnAir: Bool {
        voiceKeyer.isPlaying
    }

    /// Waits for the voice lane (tests).
    func settle() async {
        await lane.settle()
    }

    private func nextSerial() -> Int {
        keyer?.messageContext()?.serial ?? 1
    }

    private func show(_ message: EntryStatus) {
        status.showJoined(message.parts, separator: "")
    }
}

/// The plan of a message, made on the voice lane (`VoiceMessagePlanner.plan` with speech synthesis).
private struct PlanRequest: Sendable {
    let text: String
    let wavDir: String
    let lettersPath: String
    let context: VoiceMessagePlanner.Context
    let ttsVoice: String
    let synthesize: @Sendable (JavaPath, String, String) -> JavaPath?

    func run() -> PlanOutcome {
        do {
            let wav = try JavaPath(wavDir)
            let letters: JavaPath = try VoiceMessagePlanner.resolveDir(lettersPath, operatorCall: context.operatorCall,
                                                                       wavDir: wav)
            let cache: JavaPath = try wav.resolve(".tts-cache")
            let voice: String = ttsVoice
            let synthesize = self.synthesize
            let plan = try VoiceMessagePlanner.plan(text, ctx: context, wavDir: wav, lettersDir: letters,
                                                    exists: { Self.isRegularFile($0) },
                                                    speech: { said in synthesize(cache, voice, said) })
            return .plan(plan, wav: wav.description)
        } catch {
            return .failed(KeyingErrors.javaMessage(error) ?? "null")
        }
    }

    /// Java `Files.isRegularFile`.
    static func isRegularFile(_ path: JavaPath) -> Bool {
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path.description, isDirectory: &directory) && !directory.boolValue
    }
}

private enum PlanOutcome: Sendable {
    case plan(VoiceMessagePlanner.Plan, wav: String)
    case failed(String)
}

private enum RecordStart: Sendable {
    case started(any MessageRecording)
    case failed(String)
}

/// What the voice keyer's threads read: the output device and the PTT delay of the message being played.
private final class VoiceSettingsBox: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: (device: "", delay: Int32(150)))

    func update(outputDevice: String, pttDelayMs: Int) {
        state.withLock { $0 = (outputDevice, Int32(clamping: pttDelayMs)) }
    }

    var outputDevice: String {
        state.withLock { $0.device }
    }

    var pttDelayMs: Int32 {
        state.withLock { $0.delay }
    }
}

/// The voice keyer's PTT (Kotlin `{ on -> if (isPttViaCat && cat.connected) cat.setPtt(on) }`).
///
/// Every PTT command runs **on the rig's own `RigLane`** (the voice keyer's queue waits for it), so it is ordered with
/// that rig's connect, disconnect and the release before a user disconnect:
/// - `arm` (main actor, when a message starts) takes the active rig and the current fence epoch;
/// - the key (`T 1`) is a lane job that keys only while the message's epoch is still current and the rig connected,
///   and records the keyed rig in the same job;
/// - a user disconnect raises the epoch on the main actor (`fence`) and queues `release` (`T 0`) ahead of the
///   disconnect: a key queued before it is released before the disconnect, a key after it is refused;
/// - a key whose command fails is released in the same job (`T 0` on that rig), since the rig may have taken it;
/// - the release (`T 0`) goes only to the rig that was keyed (a message that keyed nothing releases nothing — Kotlin
///   would re-evaluate its condition), and the keyed rig is taken only on its lane, by whichever release runs first;
/// - a record is dropped only once its `T 0` went out on a connected rig; a rig released while disconnected (a poll
///   error) keeps it, and its next connection sends `T 0` before anything else (`releaseOwed`).
final class VoicePtt: @unchecked Sendable {
    private let lock = NSLock()
    private var via = true
    private var target: RigLane?
    /// Every rig that may be keyed by the voice keyer (SO2R: a key on the other rig never overwrites a rig whose
    /// release is still owed).
    private var keyed: [RigLane] = []
    /// The rig the current message keyed (its own PTT off goes there).
    private var messageLane: RigLane?
    private var epoch: Int64 = 0
    private var armed: Int64 = 0
    private var keyRequests = 0
    private var releaseRequests = 0

    /// Key jobs handed to a rig lane so far (tests).
    var requestedKeys: Int {
        lock.withLock { keyRequests }
    }

    /// The rigs recorded as keyed.
    var keyedLanes: [RigLane] {
        lock.withLock { keyed }
    }

    /// `lane`'s rig is recorded as keyed.
    func isKeyed(_ lane: RigLane) -> Bool {
        lock.withLock { keyed.contains { $0 === lane } }
    }

    /// PTT-off calls of the voice keyer so far (tests).
    var requestedReleases: Int {
        lock.withLock { releaseRequests }
    }

    /// A message starts: its rig and the current fence epoch.
    func arm(target: RigLane?, viaCat: Bool) {
        lock.withLock {
            self.target = target
            via = viaCat
            armed = epoch
        }
    }

    /// The voice keyer's `ptt(on)` (its own queue; blocks until the rig's lane ran the command).
    func set(_ on: Bool) throws {
        if on {
            let request: (lane: RigLane, epoch: Int64)? = lock.withLock { () -> (lane: RigLane, epoch: Int64)? in
                guard via, let target else { return nil }
                keyRequests += 1
                return (target, armed)
            }
            guard let request else { return }
            try Self.runAndWait(on: request.lane) { [self] cat in
                try key(cat, lane: request.lane, epoch: request.epoch)
            }
            return
        }
        // The keyed rig is only looked up here and taken on its lane: a release before a user disconnect queued ahead
        // of this job then still finds it and sends `T 0` before the disconnect (taking it here would leave that job
        // nothing to release, and this job would reach the rig only after the disconnect).
        let held: RigLane? = lock.withLock { () -> RigLane? in
            releaseRequests += 1
            let lane = messageLane
            messageLane = nil
            return lane
        }
        if let held {
            try Self.runAndWait(on: held) { [self] cat in
                try release(cat, lane: held)
            }
        }
    }

    /// On `lane`'s rig lane: `T 0` if the rig is recorded as keyed, and the record dropped once it went out. A rig
    /// that is not connected keeps its record — the `T 0` then goes out first on its next connection (`releaseOwed`).
    func release(_ cat: any CatPort, lane: RigLane) throws {
        guard cat.snapshot.connected, isKeyed(lane) else { return }
        try cat.setPtt(false)
        forget(lane)
    }

    /// A fresh connection of `lane`'s rig (its connect thread, before the first poll): `T 0` first if the rig is still
    /// recorded as keyed. `true` = that `T 0` went out.
    func releaseOwed(_ rig: any RigController, lane: RigLane) -> Bool {
        guard isKeyed(lane), (try? rig.setPtt(false)) != nil else { return false }
        forget(lane)
        return true
    }

    private func record(_ lane: RigLane) {
        lock.withLock {
            if !keyed.contains(where: { $0 === lane }) {
                keyed.append(lane)
            }
        }
    }

    private func forget(_ lane: RigLane) {
        lock.withLock { keyed.removeAll { $0 === lane } }
    }

    /// The key, on the rig's lane: only for a current epoch and a connected rig; the keyed rig is recorded at once.
    ///
    /// A key that fails is released at once on the same rig, in the same lane job (a safety override beyond Kotlin):
    /// the rig already received `T 1` when its answer is refused, garbled or late (the 2 s read timeout), so it may be
    /// transmitting, and the voice keyer never sends PTT off after a failed PTT on. `T 0` to an unkeyed rig is
    /// harmless; the key's error goes on to the voice keyer, and if that `T 0` fails as well the rig is recorded as
    /// keyed.
    private func key(_ cat: any CatPort, lane: RigLane, epoch armedEpoch: Int64) throws {
        let current: Bool = lock.withLock { epoch == armedEpoch }
        guard current, cat.snapshot.connected else { return }
        do {
            try cat.setPtt(true)
        } catch {
            do {
                try cat.setPtt(false)
            } catch {
                // That `T 0` failed too: the rig counts as keyed, so the release before a disconnect, the quit and
                // the next connection of the rig send `T 0` again.
                record(lane)
            }
            throw error
        }
        record(lane)
        lock.withLock { messageLane = lane }
    }

    /// Before a user disconnect (main actor): no message armed before now keys any more. `true` = the current
    /// message is aimed at `lane`'s rig.
    func fence(_ lane: RigLane) -> Bool {
        lock.withLock { () -> Bool in
            epoch &+= 1
            return target === lane
        }
    }


    /// Runs `body` on `lane` and waits for it (only from the voice keyer's own queue, never from the main thread, the
    /// rig lane itself or Swift's pool).
    private static func runAndWait(on lane: RigLane, _ body: @escaping @Sendable (any CatPort) throws -> Void) throws {
        let done = DispatchSemaphore(value: 0)
        let failure = OSAllocatedUnfairLock<String?>(initialState: nil)
        lane.run { cat in
            do {
                try body(cat)
            } catch {
                failure.withLock { $0 = String(describing: error) }
            }
            done.signal()
        }
        done.wait()
        if let message = failure.withLock({ $0 }) {
            throw KeyingFailure(message: message)
        }
    }
}
