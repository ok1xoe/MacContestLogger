import Foundation
import MCLCore
import Observation
import os

/// Recording the contest (`contest.record`; `AppState` `AS:2411-2479`; Java `audio/ContestRecorder`): the
/// receiver audio into hourly wav files, and playing back the recording around a QSO.
///
/// The recorder is written from the `audio-capture` queue through a lock (Kotlin's plain field was a data race) and
/// never after it was closed: a block delivered after the switch-off is dropped (Kotlin's `closeDatabase` closed it
/// without removing the listener, so a late block reopened the file).
@Observable @MainActor
public final class RecordingModel {

    /// Kotlin `contestRecording` (the „● REC" mark).
    public private(set) var isRecording: Bool = false
    /// A switch on or off is in progress (the audio input opens on its lane).
    public private(set) var isSwitching: Bool = false

    @ObservationIgnored private let audio: AudioModel
    @ObservationIgnored private let config: ConfigModel
    @ObservationIgnored private let status: StatusModel
    @ObservationIgnored private let hardware: HardwarePorts
    @ObservationIgnored private let dataDir: URL
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let sink = RecorderSink()
    @ObservationIgnored private var listener: AudioCapture.ListenerID?
    @ObservationIgnored private let lane = SerialLane(name: "recording")
    @ObservationIgnored private let playbackCancelled = PlaybackFlag()
    @ObservationIgnored private var closed = false

    static let user = "recorder"

    struct Dependencies {
        let audio: AudioModel
        let config: ConfigModel
        let status: StatusModel
        let hardware: HardwarePorts
        let dataDir: URL
        let now: @Sendable () -> Date
    }

    init(_ dependencies: Dependencies) {
        audio = dependencies.audio
        config = dependencies.config
        status = dependencies.status
        hardware = dependencies.hardware
        dataDir = dependencies.dataDir
        now = dependencies.now
    }

    /// Kotlin `recordingsDir()`: the configured directory when not blank, otherwise `<data>/recordings`.
    public var recordingsDir: String {
        let configured: String = config.config.recordingsDir
        return KotlinStrings.isBlank(configured) ? dataDir.appendingPathComponent("recordings").path : configured
    }

    /// The menu item `contest.record` (`setRecording(!contestRecording)`).
    public func toggle() {
        let on: Bool = !isRecording
        Task { [weak self] in
            await self?.setRecording(on)
        }
    }

    /// Kotlin `setRecording(on)` (`AS:2422-2448`). On: a recorder, its listener, the audio input — a failure takes
    /// the listener back and shows `tr("Nahrávání: %s (Nastavení → Audio → Vstup přijímače)")` without saving the
    /// config; off: the listener goes, the input is released, the recorder closed (on the lane). Both save
    /// `recordContest`.
    public func setRecording(_ on: Bool) async {
        guard on != isRecording, !isSwitching, !closed else { return }
        let dir: String = recordingsDir
        if on {
            guard let path = try? JavaPath(dir) else { return }
            isSwitching = true
            sink.open(ContestRecorder(dir: path, sampleRate: Int32(AudioCapture.sampleRate)))
            let sink: RecorderSink = self.sink
            let now: @Sendable () -> Date = self.now
            let id: AudioCapture.ListenerID = audio.addRawListener { pcm in
                sink.write(pcm, at: now())
            }
            let error: String? = await audio.acquire(Self.user)
            isSwitching = false
            if let error {
                audio.removeRawListener(id)
                closeRecorder()
                status.show("Nahrávání: %s (Nastavení → Audio → Vstup přijímače)", .string(error))
                return
            }
            if closed {
                audio.removeRawListener(id)
                return
            }
            listener = id
            isRecording = true
            status.show("Nahrávání závodu zapnuto → %s", .string(dir))
        } else {
            stopRecording()
            status.show("Nahrávání závodu vypnuto")
        }
        config.config.recordContest = on
        config.saveSilently()
    }

    /// The listener goes, the input is released and the recorder closed (after it nothing is written).
    private func stopRecording() {
        if let listener {
            audio.removeRawListener(listener)
        }
        listener = nil
        audio.release(Self.user)
        closeRecorder()
        isRecording = false
    }

    /// The recorder leaves the sink at once (a later block is dropped) and closes on the lane.
    private func closeRecorder() {
        guard let recorder = sink.take() else { return }
        lane.submit {
            try? recorder.close()
        }
    }

    /// Kotlin `playQsoRecording(qso)` (`AS:2451-2477`): the recording from 10 s before to 5 s after the
    /// QSO, read and played on the lane on the default output (`playPcm`); no stop and no guard against overlap
    /// — only the quit cancels it.
    public func playQsoRecording(_ qso: Qso) {
        guard let at = qso.timestampUtc, let dir = try? JavaPath(recordingsDir) else { return }
        let recorder = ContestRecorder(dir: dir, sampleRate: Int32(AudioCapture.sampleRate))
        guard let segment = recorder.segment(qsoTime: at, beforeSec: 10, afterSec: 5) else {
            status.show("Nahrávka pro %s není (nahrávání bylo vypnuté?)", .string(qso.call))
            return
        }
        status.show("Přehrávám nahrávku QSO %s", .string(qso.call))
        let play: @Sendable ([UInt8], WavFile.PcmFormat, String?, () -> Bool) throws(AudioIOError) -> Void =
            hardware.playPcm
        let cancelled: PlaybackFlag = playbackCancelled
        lane.submit({ () -> String? in
            do {
                let bytes: [UInt8] = try RecordingPlayback.read(segment: segment)
                try play(bytes, WavFile.PcmFormat.capture, nil, { cancelled.isSet })
                return nil
            } catch {
                return KeyingErrors.javaMessage(error) ?? "null"
            }
        }, then: { [weak self] failure in
            guard let self, let failure, !self.closed else { return }
            self.status.show("Přehrání selhalo: %s", .string(failure))
        })
    }

    /// Kotlin `if (config.isRecordContest) setRecording(true)` at start-up (`App.kt:144`).
    func startIfConfigured() async {
        if config.config.recordContest {
            await setRecording(true)
        }
    }

    /// The quit: a playback stops, the listener goes, the input is released and the recorder closed —
    /// nothing is written after it.
    func shutdown() async {
        guard !closed else { return }
        closed = true
        playbackCancelled.set()
        if isRecording {
            stopRecording()
        }
        closeRecorder()
        await lane.settle()
    }

    /// Waits for the closes and playbacks queued before (tests).
    func settle() async {
        await lane.settle()
    }
}

/// The open recorder, written from the audio queue — under a lock, so a block never reaches a recorder that was
/// taken out to be closed.
final class RecorderSink: Sendable {
    private let state = OSAllocatedUnfairLock<ContestRecorder?>(initialState: nil)

    func open(_ recorder: ContestRecorder) {
        state.withLock { $0 = recorder }
    }

    /// Kotlin `runCatching { recorder?.write(pcm, Instant.now()) }`.
    func write(_ pcm: [UInt8], at: Date) {
        state.withLock { recorder in
            try? recorder?.write(pcm, at: at)
        }
    }

    /// Takes the recorder out (nothing is written to it afterwards).
    func take() -> ContestRecorder? {
        state.withLock { recorder in
            let taken: ContestRecorder? = recorder
            recorder = nil
            return taken
        }
    }

    var isOpen: Bool {
        state.withLock { $0 != nil }
    }
}

/// Set once at the quit; the playback reads it between its blocks.
final class PlaybackFlag: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: false)

    func set() {
        state.withLock { $0 = true }
    }

    var isSet: Bool {
        state.withLock { $0 }
    }
}
