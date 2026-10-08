import Foundation
import MCLCore
import Observation
import os

/// Recording, checking, choosing and deleting the SSB voice messages in Settings → Function Keys.
///
/// A key whose message is exactly one wav file (`VoiceMessagePlanner.recordability`) has a file the voice keyer plays;
/// this model records into it, copies a chosen audio file over it, plays it on the computer's own output and deletes
/// it. The file name comes from the planner (the same rule the keyer uses), never from a second copy of it, and is
/// taken from the **draft** text and wav directory shown in Settings, so the file is already where the keyer will look
/// once the settings are applied.
///
/// Nothing here keys the rig: playback goes through the voice player port with the system default output (no PTT),
/// and everything is refused while the voice keyer plays or records, or a CW or digital message is on the air.
/// Recording uses the same input device, port and file handling as Ctrl+Shift+F (`SoundCard.record`: a temporary
/// file, moved over the original only when the recording ends successfully).
@Observable @MainActor
public final class VoiceMessageStudio {

    /// One F-key of one set.
    public struct Slot: Hashable, Sendable {
        public let run: Bool
        public let index: Int

        public init(run: Bool, index: Int) {
            self.run = run
            self.index = index
        }
    }

    /// A key as Settings shows it: the draft text and the draft wav directory (empty = the default one).
    public struct Request: Equatable, Sendable {
        public let slot: Slot
        public let text: String
        public let wavDir: String

        public init(slot: Slot, text: String, wavDir: String) {
            self.slot = slot
            self.text = text
            self.wavDir = wavDir
        }
    }

    /// A question that must be answered before an existing file is replaced or deleted.
    public struct Prompt: Equatable, Sendable {
        public let message: EntryStatus
        public let confirm: EntryStatus
        public let destructive: Bool
    }

    /// The longest recording, seconds (a forgotten recording ends by itself; the Audio setting may make it shorter).
    public static let maxRecordSeconds = 60

    /// The key being recorded (also while the input opens).
    public private(set) var recordingSlot: Slot?
    /// Seconds recorded so far.
    public private(set) var elapsedSeconds: Int = 0
    /// `true` between the press and the moment the input is open.
    public private(set) var recordingStarting: Bool = false
    /// The key being played on the computer's output.
    public private(set) var playingSlot: Slot?
    /// The files of the keys last refreshed (a key without an entry has no file).
    public private(set) var files: [Slot: VoiceMessageFile] = [:]
    /// The result of the last action, for the line under the keys.
    public private(set) var notice: EntryStatus?
    /// The question waiting for „Ano" / „Zrušit".
    public private(set) var prompt: Prompt?

    @ObservationIgnored weak var voice: VoiceKeyerModel?
    @ObservationIgnored private let hardware: HardwarePorts
    @ObservationIgnored private let config: ConfigModel
    @ObservationIgnored private let operating: OperatingModel
    @ObservationIgnored private let clock: any RescoreClock
    @ObservationIgnored private let dataDir: URL
    @ObservationIgnored private let lane = SerialLane(name: "voice-studio")
    @ObservationIgnored private let playbackLane = SerialLane(name: "voice-studio-play")
    @ObservationIgnored private var generation: Int64 = 0
    @ObservationIgnored private var recording: (any MessageRecording)?
    @ObservationIgnored private var recordingRequest: Request?
    @ObservationIgnored private var tick: (any RescoreTimer)?
    @ObservationIgnored private var starting: Task<Void, Never>?
    @ObservationIgnored private var playback: StudioPlaybackFlag?
    @ObservationIgnored private var pending: Pending?
    @ObservationIgnored private var closed: Bool = false

    private enum Pending {
        case record(Request, JavaPath)
        case pick(Request, JavaPath, VoiceImport)
        case delete(Request, JavaPath)
    }

    struct Dependencies {
        let hardware: HardwarePorts
        let config: ConfigModel
        let operating: OperatingModel
        let clock: any RescoreClock
        let dataDir: URL
    }

    init(_ dependencies: Dependencies) {
        hardware = dependencies.hardware
        config = dependencies.config
        operating = dependencies.operating
        clock = dependencies.clock
        dataDir = dependencies.dataDir
    }

    // MARK: - where a message lives

    /// The wav directory the keyer uses for a draft value: trimmed, empty = `<data>/wav`.
    public func wavDirectory(_ draft: String) -> String {
        let configured: String = KotlinStrings.trim(draft)
        return configured.isEmpty ? dataDir.appendingPathComponent("wav").path : configured
    }

    /// The file of a key, or why it has none (exactly the planner's rule).
    public func target(for request: Request) -> VoiceMessagePlanner.RecordTarget {
        guard let wav = try? JavaPath(wavDirectory(request.wavDir)) else { return .unavailable(.invalidPath) }
        return VoiceMessagePlanner.recordability(request.text, operatorCall: operating.operatorCall, wavDir: wav)
    }

    /// Why a key cannot be recorded, in Czech (the key of the translation).
    public static func explanation(_ reason: VoiceMessagePlanner.NotRecordable) -> EntryStatus {
        switch reason {
        case .empty: return .tr("Prázdná zpráva nic nevysílá — není co nahrávat")
        case .several: return .tr("Zpráva má víc položek — nahrát jde jen zpráva s jedním wav souborem")
        case .speech: return .tr("Zpráva v hranatých závorkách se čte syntézou řeči — nenahrává se")
        case .macro: return .tr("Makro (!, #, *, @, {MYCALL}, {WIPE}, {LOG}…) není wav soubor — nenahrává se")
        case .notWav: return .tr("Zpráva není název wav souboru (např. {OPERATOR}/CQ.wav)")
        case .operatorMissing: return .tr("Chybí volačka operátora pro {OPERATOR} — nastav operátora (příkaz OPON)")
        case .invalidPath: return .tr("Neplatná cesta ke zprávě nebo ke složce wav")
        }
    }

    /// The wav directory, created if missing (for „Otevřít složku ve Finderu").
    public func folder(wavDir draft: String) -> URL? {
        let url = URL(fileURLWithPath: wavDirectory(draft), isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            notice = .tr("Složku se nepodařilo vytvořit: %s", .string(error.localizedDescription))
            return nil
        }
        return url
    }

    // MARK: - state

    /// A recording is open or starting.
    public var isRecording: Bool {
        recordingSlot != nil
    }

    /// Something of the studio is running (a recording, its start or a playback).
    public var isBusy: Bool {
        recordingSlot != nil || playingSlot != nil
    }

    private func blockReason() -> EntryStatus? {
        if closed { return .tr("Aplikace se ukončuje") }
        if let voice, voice.keyerBusy || (voice.keyer?.isActive ?? false) {
            return .tr("Hlasový klíč právě vysílá nebo nahrává — nejdřív ho zastav (Esc)")
        }
        return nil
    }

    /// Re-reads the files of the keys shown.
    public func refresh(_ requests: [Request]) {
        let items: [(Slot, String?)] = requests.map { request in
            if case .target(let path) = target(for: request) { return (request.slot, path.description) }
            return (request.slot, nil)
        }
        lane.submit({ () -> [Slot: VoiceMessageFile] in
            var found: [Slot: VoiceMessageFile] = [:]
            for (slot, path) in items {
                guard let path, let info = Self.info(at: path) else { continue }
                found[slot] = info
            }
            return found
        }, then: { [weak self] found in
            self?.files = found
        })
    }

    nonisolated private static func info(at path: String) -> VoiceMessageFile? {
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &directory), !directory.boolValue else {
            return nil
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
        guard size <= VoiceWavImport.maxBytes, let data = FileManager.default.contents(atPath: path) else {
            return VoiceMessageFile(bytes: size, seconds: nil)
        }
        return VoiceWavImport.inspect([UInt8](data))
    }

    // MARK: - recording

    /// Starts recording a key (a second call, or `stopRecording`, ends it). An existing file asks first.
    public func record(_ request: Request) {
        guard !isRecording, let path = usableTarget(request) else { return }
        if FileManager.default.fileExists(atPath: path.description) {
            ask(.record(request, path), "Soubor %s už existuje. Přepsat novou nahrávkou?", "Nahrát", path,
                destructive: true)
            return
        }
        start(request, path)
    }

    private func usableTarget(_ request: Request) -> JavaPath? {
        if let reason = blockReason() {
            notice = reason
            return nil
        }
        switch target(for: request) {
        case .unavailable(let why):
            notice = Self.explanation(why)
            return nil
        case .target(let path):
            return path
        }
    }

    private func start(_ request: Request, _ path: JavaPath) {
        stopPlayback()
        generation &+= 1
        let started: Int64 = generation
        recordingSlot = request.slot
        recordingRequest = request
        recordingStarting = true
        elapsedSeconds = 0
        let access = hardware.microphoneAccess
        let record: @Sendable (JavaPath, String?) throws -> any MessageRecording = hardware.recordMessage
        let device: String = config.config.voiceKeyer.inputDevice
        starting = Task { @MainActor [weak self] in
            let allowed: Bool = await access()
            guard let self, started == self.generation, !self.closed else { return }
            guard allowed else {
                self.reset()
                self.notice = .tr("Mikrofon není povolený — povol ho v Nastavení systému → Soukromí a zabezpečení → Mikrofon")
                return
            }
            self.lane.submit({ () -> RecordStart in
                do {
                    let folder: String = (path.description as NSString).deletingLastPathComponent
                    try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
                    return .started(try record(path, device))
                } catch {
                    return .failed(KeyingErrors.javaMessage(error) ?? error.localizedDescription)
                }
            }, then: { [weak self] outcome in
                self?.recordStarted(outcome, request: request, path: path, generation: started)
            })
        }
    }

    private func recordStarted(_ outcome: RecordStart, request: Request, path: JavaPath, generation started: Int64) {
        guard started == generation, !closed else {
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
            reset()
            notice = .tr("Nahrávání nezačalo: %s", .string(message))
        case .started(let opened):
            recording = opened
            notice = .tr("● Nahrávám F%s → %s", .int(request.slot.index + 1), .string(path.description))
            scheduleTick()
        }
    }

    private var limitSeconds: Int {
        min(Self.maxRecordSeconds, max(1, config.config.voiceKeyer.maxRecordSeconds))
    }

    private func scheduleTick() {
        tick = clock.schedule(afterMilliseconds: 1_000) { [weak self] in
            guard let self, self.recording != nil else { return }
            self.elapsedSeconds += 1
            if self.elapsedSeconds >= self.limitSeconds {
                self.stopRecording()
            } else {
                self.scheduleTick()
            }
        }
    }

    /// Ends the recording and saves it into the key's file.
    public func stopRecording() {
        guard recordingSlot != nil else { return }
        if recording == nil {
            // The input is still opening: nothing was recorded.
            generation &+= 1
            starting?.cancel()
            reset()
            return
        }
        let finished = recording
        let request = recordingRequest
        reset()
        guard let finished else { return }
        lane.submit({ () -> String?? in
            do {
                try finished.stop()
                return .none
            } catch {
                return .some(KeyingErrors.javaMessage(error))
            }
        }, then: { [weak self] failure in
            guard let self else { return }
            if case .some(let message) = failure {
                self.notice = .tr("Nahrávka se neuložila: %s", .string(message ?? "null"))
            } else {
                self.notice = .tr("Nahrávka uložena: %s", .string(finished.target.description))
            }
            if let request {
                self.refresh([request])
            }
        })
    }

    private func reset() {
        tick?.cancel()
        tick = nil
        recording = nil
        recordingRequest = nil
        recordingSlot = nil
        recordingStarting = false
        elapsedSeconds = 0
    }

    // MARK: - local playback

    /// Plays a key's file on the computer's default output (no PTT, never the rig); again = stop.
    public func play(_ request: Request) {
        if playingSlot == request.slot {
            stopPlayback()
            return
        }
        guard !isRecording, let path = usableTarget(request) else {
            if isRecording { notice = .tr("Nejdřív ukonči nahrávání") }
            return
        }
        guard FileManager.default.fileExists(atPath: path.description) else {
            notice = .tr("Soubor %s ještě není nahraný", .string(path.description))
            return
        }
        stopPlayback()
        let flag = StudioPlaybackFlag()
        playback = flag
        playingSlot = request.slot
        let audio = hardware.voicePlayer { nil }
        playbackLane.submit({ () -> String? in
            do {
                try audio(path) { flag.isCancelled }
                return nil
            } catch {
                return KeyingErrors.javaMessage(error) ?? error.localizedDescription
            }
        }, then: { [weak self] failure in
            guard let self else { return }
            if self.playback === flag {
                self.playback = nil
                self.playingSlot = nil
            }
            if let failure {
                self.notice = .tr("Přehrávání selhalo: %s", .string(failure))
            }
        })
    }

    /// Stops the local playback.
    public func stopPlayback() {
        playback?.cancel()
        playback = nil
        playingSlot = nil
    }

    // MARK: - choosing a file

    /// Copies an audio file into the key's file (converting it when the keyer could not play it as it is). An existing
    /// file asks first.
    public func pick(_ request: Request, from url: URL) {
        guard !isRecording, let path = usableTarget(request) else {
            if isRecording { notice = .tr("Nejdřív ukonči nahrávání") }
            return
        }
        stopPlayback()
        lane.submit({ () -> PickOutcome in
            do throws(VoiceImportError) {
                return .ready(try VoiceWavImport.prepare(url))
            } catch {
                return .failed(error)
            }
        }, then: { [weak self] outcome in
            guard let self, !self.closed else { return }
            switch outcome {
            case .failed(let error):
                self.notice = Self.explanation(error)
            case .ready(let prepared):
                if FileManager.default.fileExists(atPath: path.description) {
                    self.ask(.pick(request, path, prepared), "Soubor %s už existuje. Přepsat vybraným souborem?",
                             "Přepsat", path, destructive: true)
                } else {
                    self.write(prepared, request: request, to: path)
                }
            }
        })
    }

    private static func explanation(_ error: VoiceImportError) -> EntryStatus {
        switch error {
        case .unreadable(let message): return .tr("Soubor nejde přečíst: %s", .string(message))
        case .tooBig: return .tr("Soubor je příliš velký (nejvýš 64 MB)")
        case .tooLong(let seconds): return .tr("Zpráva je příliš dlouhá (nejvýš %s s)", .int(seconds))
        case .unsupportedFormat: return .tr("Nepodporovaný formát — použij wav, aiff, caf, mp3 nebo m4a")
        case .empty: return .tr("Soubor neobsahuje žádný zvuk")
        }
    }

    private func write(_ prepared: VoiceImport, request: Request, to path: JavaPath) {
        let converted: Bool = prepared.converted
        lane.submit({ () -> String? in
            let target: String = path.description
            let temp: String = target + ".import"
            do {
                try FileManager.default.createDirectory(atPath: (target as NSString).deletingLastPathComponent,
                                                        withIntermediateDirectories: true)
                try Data(prepared.bytes).write(to: URL(fileURLWithPath: temp))
                guard rename(temp, target) == 0 else {
                    let message: String = String(cString: strerror(errno))
                    unlink(temp)
                    return message
                }
                return nil
            } catch {
                unlink(temp)
                return error.localizedDescription
            }
        }, then: { [weak self] failure in
            guard let self else { return }
            if let failure {
                self.notice = .tr("Soubor se neuložil: %s", .string(failure))
            } else if converted {
                self.notice = .tr("Převedeno na 16bitové mono wav 22 050 Hz a uloženo: %s", .string(path.description))
            } else {
                self.notice = .tr("Zkopírováno: %s", .string(path.description))
            }
            self.refresh([request])
        })
    }

    // MARK: - deleting

    /// Deletes a key's file after confirmation.
    public func delete(_ request: Request) {
        guard !isRecording, let path = usableTarget(request) else { return }
        guard FileManager.default.fileExists(atPath: path.description) else {
            notice = .tr("Soubor %s ještě není nahraný", .string(path.description))
            return
        }
        ask(.delete(request, path), "Smazat soubor %s?", "Smazat", path, destructive: true)
    }

    // MARK: - confirmation

    private func ask(_ action: Pending, _ question: String, _ confirm: String, _ path: JavaPath, destructive: Bool) {
        pending = action
        prompt = Prompt(message: .tr(question, .string(path.description)), confirm: .tr(confirm),
                        destructive: destructive)
    }

    /// „Ano" of the prompt.
    public func confirmPrompt() {
        let action = pending
        pending = nil
        prompt = nil
        guard let action else { return }
        if let reason = blockReason() {
            notice = reason
            return
        }
        switch action {
        case .record(let request, let path):
            start(request, path)
        case .pick(let request, let path, let prepared):
            write(prepared, request: request, to: path)
        case .delete(let request, let path):
            lane.submit({ () -> String? in
                do {
                    try FileManager.default.removeItem(atPath: path.description)
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }, then: { [weak self] failure in
                guard let self else { return }
                if let failure {
                    self.notice = .tr("Smazání selhalo: %s", .string(failure))
                } else {
                    self.notice = .tr("Smazáno: %s", .string(path.description))
                }
                self.refresh([request])
            })
        }
    }

    /// „Zrušit" of the prompt: nothing changes.
    public func cancelPrompt() {
        pending = nil
        prompt = nil
    }

    // MARK: - leaving

    /// Settings closes or the tab changes: a recording is discarded (the original file stays), playback stops.
    public func abandon() {
        cancelPrompt()
        stopPlayback()
        guard recordingSlot != nil else { return }
        generation &+= 1
        starting?.cancel()
        let discarded = recording
        reset()
        if let discarded {
            lane.submit {
                discarded.cancel()
            }
        }
    }

    /// The quit.
    func shutdown() async {
        closed = true
        abandon()
        await lane.settle()
        await playbackLane.settle()
    }

    /// Waits for the lanes (tests).
    func settle() async {
        await starting?.value
        await lane.settle()
        await playbackLane.settle()
    }
}

private enum RecordStart: Sendable {
    case started(any MessageRecording)
    case failed(String)
}

private enum PickOutcome: Sendable {
    case ready(VoiceImport)
    case failed(VoiceImportError)
}

/// Tells the playback thread to stop.
private final class StudioPlaybackFlag: Sendable {
    private let cancelledState = OSAllocatedUnfairLock(initialState: false)

    var isCancelled: Bool {
        cancelledState.withLock { $0 }
    }

    func cancel() {
        cancelledState.withLock { $0 = true }
    }
}
