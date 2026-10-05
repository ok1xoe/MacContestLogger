import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// Quit: the keying stops before CAT goes — the carrier off, the CW keyer aborted and closed, the voice
/// message drained with its PTT released over the still-connected rig, a message recording discarded — then the
/// rigs, and last the contest recorder and the receiver audio. Nothing transmits after it.
@MainActor @Suite struct KeyerShutdownTests {

    @Test func quitStopsTheKeyingBeforeCat() async throws {
        let fake = try FakeRigctld(mode: "USB")
        let app = try await KeyingApp.make(configure: { config, dataDir in
            winkeyerConfig(&config)
            config.rig = fakeRigConfig(fake.port)
            let wav: URL = dataDir.appendingPathComponent("wav")
            try FileManager.default.createDirectory(at: wav, withIntermediateDirectories: true)
            try Data([1]).write(to: wav.appendingPathComponent("cq.wav"))
            config.voiceKeyer.spMessages[0] = FunctionKeyMessage(label: "CQ", text: "cq.wav")
            config.voiceKeyer.pttDelayMs = 2_000
            config.recordingsDir = dataDir.appendingPathComponent("rec").path
        }, setUp: { keying in
            // The delay lasts until the quit cancels it, however slow the runner; released after the quit, a message
            // the quit failed to cancel would play.
            keying.holdPttDelay()
        })
        await app.connectRig(fake)
        app.keyer.setTune(true)
        await app.settle()
        let keyer: FakeCwKeyer = try #require(app.keying.lastKeyer)
        #expect(keyer.events == ["tune on"])
        _ = app.keyer.voice.play([0], hisCall: "", freqHz: 14_250_000, opposite: false)
        await eventually("keyed") { fake.writes == ["T 1"] && app.keyer.voice.playingKey == 0 }
        await app.model.recording.setRecording(true)
        #expect(app.model.recording.isRecording)
        app.keyer.updateCwSpeed(33)

        await app.model.shutdown()
        app.keying.releasePttDelay()
        await eventually("message over") { !app.keyer.voice.isOnAir }
        await runMainQueue()

        #expect(fake.writes == ["T 1", "T 0"])
        #expect(keyer.events == ["tune on", "speed 33", "tune off", "abort", "close"])
        #expect(!app.keyer.isTuning)
        #expect(app.keyer.voice.playingKey == nil)
        #expect(app.keying.events.filter { $0.hasPrefix("play") }.isEmpty)
        #expect(!app.model.rig.cat1.connected)
        #expect(!app.model.recording.isRecording)
        #expect(!app.model.audio.capture.isRunning)
        #expect(app.app.savedConfig().cwKeyer.speed == 33)

        // Nothing transmits after the quit: F-keys, Ctrl+T, the CQ repeat and the voice keyer are inert.
        app.entry.setMode(.cw)
        app.keyer.sendCwText("TEST")
        app.keyer.setTune(true)
        app.model.operating.applyCqRepeat(true)
        _ = app.keyer.voice.play([0], hisCall: "", freqHz: 14_250_000, opposite: false)
        await runMainQueue()
        app.clock.advance(by: 60_000)
        await app.settle()
        #expect(keyer.events == ["tune on", "speed 33", "tune off", "abort", "close"])
        #expect(app.keying.openedKeyers.count == 1)
        #expect(!app.keyer.isTuning)
        #expect(fake.writes == ["T 1", "T 0"])
    }

    /// A message recording in progress is discarded at the quit (Kotlin `recording?.cancel()`).
    @Test func quitDiscardsAMessageRecording() async throws {
        let app = try await KeyingApp.make(configure: { config, dataDir in
            let wav: URL = dataDir.appendingPathComponent("wav")
            try FileManager.default.createDirectory(at: wav, withIntermediateDirectories: true)
            config.voiceKeyer.spMessages[0] = FunctionKeyMessage(label: "CQ", text: "cq.wav")
        })
        app.entry.setMode(.ssb)
        _ = app.keyer.voice.toggleRecording(0)
        await eventually("recording") { app.keyer.voice.recordingKey == 0 }
        await app.model.shutdown()
        #expect(app.keying.messageRecordings.first?.events == ["cancel"])
        #expect(app.keyer.voice.recordingKey == nil)
    }

    /// The inert hardware (the default environment and `MCL_INERT_HARDWARE=1`) opens no keyer, plays and records
    /// nothing, speaks nothing, reaches no fldigi and opens no audio input — every port fails before any I/O.
    @Test func inertKeyingPortsOpenNothing() throws {
        let inert: HardwarePorts = HardwarePorts.production(environment: [HardwarePorts.inertVariable: "1"])
        #expect(inert.isInert)
        let path = try JavaPath("/nonexistent/cq.wav")
        #expect(throws: InertHardwareError.self) { _ = try inert.openWinkeyer("fake", 28) }
        #expect(throws: InertHardwareError.self) { try inert.voicePlayer { nil }(path, { false }) }
        #expect(throws: InertHardwareError.self) { _ = try inert.recordMessage(path, nil) }
        #expect(throws: InertHardwareError.self) { _ = try inert.makeFldigi("127.0.0.1", 1) }
        #expect(inert.synthesize(path, "", "test") == nil)
        #expect(throws: AudioIOError(InertHardwareError.message)) { try inert.startAudio(AudioCapture(), nil) }
        #expect(!AppModel.Environment(dataDir: URL(fileURLWithPath: "/nonexistent"), dxccDir: nil,
                                      rescoreClock: ManualClock(), geometryClock: ManualClock()).hardware.openWinkeyerIsLive)
    }
}

extension HardwarePorts {
    /// The default environment's Winkeyer opener is the inert one (it throws without opening anything).
    var openWinkeyerIsLive: Bool {
        (try? openWinkeyer("fake", 28)) != nil
    }
}
