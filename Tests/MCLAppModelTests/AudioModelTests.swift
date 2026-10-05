import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// The shared receiver audio (`AS:152-167`) and the contest recording (`AS:2411-2479`).
/// The input never opens a device (a deviceless capture fed with synthetic blocks); the playback output is a
/// fake that keeps the bytes.
@MainActor @Suite struct AudioModelTests {

    /// Two users share one start; the input closes with the last one; a failed start does not register its user,
    /// so the next user tries again.
    @Test func referenceCountingAndAFailedStart() async throws {
        let app = try await KeyingApp.make(configure: { config, _ in config.rxAudioDevice = "Fake Rx" })
        let audio: AudioModel = app.model.audio
        app.keying.failAudio("busy")
        #expect(await audio.acquire("waterfall") == "Zvukový vstup není dostupný: busy")
        #expect(audio.userNames.isEmpty)
        app.keying.failAudio(nil)
        #expect(await audio.acquire("waterfall") == nil)
        #expect(await audio.acquire("cwreader") == nil)
        #expect(app.keying.events == ["audio start Fake Rx", "audio start Fake Rx"])
        #expect(audio.capture.isRunning)
        audio.release("waterfall")
        await audio.settle()
        #expect(audio.capture.isRunning)
        audio.release("cwreader")
        await audio.settle()
        #expect(!audio.capture.isRunning)
    }

    /// A second user arriving while the first user's start is in flight waits for it and shares the input: one
    /// start, not two.
    @Test func secondUserDuringAStartSharesIt() async throws {
        let app = try await KeyingApp.make(configure: { config, _ in config.rxAudioDevice = "Fake Rx" })
        let audio: AudioModel = app.model.audio
        app.keying.holdAudioStart()
        let first = Task { await audio.acquire("waterfall") }
        await eventually("start in flight") { app.keying.events.count == 1 }
        let second = Task { await audio.acquire("cwreader") }
        await runMainQueue()
        app.keying.releaseAudioStart()
        #expect(await first.value == nil)
        #expect(await second.value == nil)
        #expect(app.keying.events == ["audio start Fake Rx"])
        #expect(audio.userNames == ["waterfall", "cwreader"])
        #expect(audio.capture.isRunning)
    }

    /// Every user leaves while the start is in flight, then a new user comes: the close runs after that start, and
    /// the new user starts the input again instead of taking the one about to close.
    @Test func userAfterACloseInFlightStartsAgain() async throws {
        let app = try await KeyingApp.make(configure: { config, _ in config.rxAudioDevice = "Fake Rx" })
        let audio: AudioModel = app.model.audio
        app.keying.holdAudioStart()
        let first = Task { await audio.acquire("waterfall") }
        await eventually("start in flight") { app.keying.events.count == 1 }
        audio.release("waterfall")
        let second = Task { await audio.acquire("cwreader") }
        await runMainQueue()
        app.keying.releaseAudioStart()
        #expect(await first.value == nil)
        #expect(await second.value == nil)
        await audio.settle()
        #expect(app.keying.events == ["audio start Fake Rx", "audio start Fake Rx"])
        #expect(audio.userNames == ["cwreader"])
        #expect(audio.capture.isRunning)
        audio.release("cwreader")
        await audio.settle()
        #expect(!audio.capture.isRunning)
    }
}

@MainActor @Suite struct RecordingModelTests {

    static let hour: Date = Date(timeIntervalSince1970: TimeInterval(1_790_000_000 / 3600 * 3600))

    private static func make(record: Bool = false) async throws -> KeyingApp {
        try await KeyingApp.make(configure: { config, dataDir in
            config.recordingsDir = dataDir.appendingPathComponent("rec").path
            config.recordContest = record
        })
    }

    private static func pcm(_ count: Int) -> [UInt8] {
        (0..<count).map { UInt8(truncatingIfNeeded: $0 % 251) }
    }

    private static func feed(_ app: KeyingApp, _ bytes: [UInt8]) throws {
        let generation: UInt64 = try #require(app.keying.lastAudioGeneration)
        app.model.audio.capture.accept(bytes, generation: generation)
    }

    /// ON: the recorder gets the raw blocks, the status names the directory, `recordContest` is saved; OFF: the
    /// listener goes, the input closes, the file is complete and nothing more is written.
    @Test func recordingOnAndOff() async throws {
        let app = try await KeyingApp.make(configure: { config, dataDir in
            config.recordingsDir = dataDir.appendingPathComponent("rec").path
        })
        let recording: RecordingModel = app.model.recording
        let dir: String = app.app.dataDir.appendingPathComponent("rec").path
        await recording.setRecording(true)
        #expect(recording.isRecording)
        #expect(app.status == "Nahrávání závodu zapnuto → \(dir)")
        #expect(await app.app.savedConfigFlushed().recordContest)
        try Self.feed(app, Self.pcm(4096))
        await recording.setRecording(false)
        await app.settle()
        #expect(!recording.isRecording)
        #expect(app.status == "Nahrávání závodu vypnuto")
        #expect(!app.model.audio.capture.isRunning)
        #expect(await !app.app.savedConfigFlushed().recordContest)
        let files: [String] = try FileManager.default.contentsOfDirectory(atPath: dir)
        #expect(files.count == 1)
        let file: String = dir + "/" + files[0]
        let size: Int = try #require(try FileManager.default.attributesOfItem(atPath: file)[.size] as? Int)
        #expect(size == 44 + 4096)
        app.model.audio.capture.accept(Self.pcm(4096), generation: try #require(app.keying.lastAudioGeneration))
        let after: Int = try #require(try FileManager.default.attributesOfItem(atPath: file)[.size] as? Int)
        #expect(after == size)
    }

    /// A failed input: the listener is taken back, the error shows, `recordContest` is not saved (pin).
    @Test func recordingErrorKeepsTheConfig() async throws {
        let app = try await Self.make()
        app.keying.failAudio("busy")
        await app.model.recording.setRecording(true)
        #expect(!app.model.recording.isRecording)
        #expect(app.status == "Nahrávání: Zvukový vstup není dostupný: busy (Nastavení → Audio → Vstup přijímače)")
        #expect(await !app.app.savedConfigFlushed().recordContest)
        #expect(app.model.audio.userNames.isEmpty)
    }

    /// `recordContest` in the config starts the recording at start-up; the menu item toggles it.
    @Test func startUpAndTheMenuItem() async throws {
        let app = try await Self.make(record: true)
        #expect(app.model.recording.isRecording)
        #expect(app.model.menu.isImplemented("contest.record"))
        _ = MenuActions.perform("contest.record", app: app.model)
        await eventually("off") { !app.model.recording.isRecording }
        #expect(app.status == "Nahrávání závodu vypnuto")
    }

    /// No block reaches a recorder after it was taken out to be closed (Kotlin reopened the file).
    @Test func sinkWritesNothingAfterTake() throws {
        let dir = try TempDir()
        let sink = RecorderSink()
        sink.open(ContestRecorder(dir: try JavaPath(dir.url.path), sampleRate: 12_000))
        sink.write([1, 2], at: Self.hour)
        let taken: ContestRecorder = try #require(sink.take())
        try taken.close()
        sink.write([3, 4], at: Self.hour)
        #expect(!sink.isOpen)
        let files: [String] = try FileManager.default.contentsOfDirectory(atPath: dir.url.path)
        let size = try FileManager.default.attributesOfItem(atPath: dir.url.path + "/" + files[0])[.size] as? Int
        #expect(size == 46)
    }

    /// „Přehrát nahrávku QSO": the fake output gets exactly the bytes from 10 s before to 5 s after the QSO; no
    /// recording of that hour says so; a failing output says so.
    @Test func playbackOfAQsoSegment() async throws {
        let app = try await KeyingApp.make(configure: { config, dataDir in
            config.recordingsDir = dataDir.appendingPathComponent("rec").path
        })
        let recorder = ContestRecorder(dir: try JavaPath(app.model.recording.recordingsDir), sampleRate: 12_000)
        let bytes: [UInt8] = Self.pcm(24_000 * 20 + 1_280)
        try recorder.write(bytes, at: Self.hour)
        try recorder.close()
        var qso = Qso()
        qso.call = "DL1ABC"
        qso.timestampUtc = Self.hour.addingTimeInterval(15)
        app.model.recording.playQsoRecording(qso)
        #expect(app.status == "Přehrávám nahrávku QSO DL1ABC")
        await app.settle()
        #expect(app.keying.playedPcm == [Array(bytes[120_000..<480_000])])
        qso.timestampUtc = Self.hour.addingTimeInterval(3600 * 5)
        app.model.recording.playQsoRecording(qso)
        #expect(app.status == "Nahrávka pro DL1ABC není (nahrávání bylo vypnuté?)")
        qso.timestampUtc = Self.hour.addingTimeInterval(15)
        app.keying.failPlayback("no output")
        app.model.recording.playQsoRecording(qso)
        await app.settle()
        #expect(app.status == "Přehrání selhalo: no output")
        // The log table's item reaches the same playback (always enabled, as in Kotlin).
        #expect(LogTableModel.MenuItem.playRecording.isEnabled)
    }
}
