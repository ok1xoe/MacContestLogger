import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// Settings → Audio (N1MM Logger+ Audio Setup): the receive level meter, the test tone (never keyed), the playback
/// level and radio 2's output. All audio is fake.
@MainActor @Suite struct AudioSetupTests {

    @Test func levelMeterReadsTheReceiveInput() async throws {
        let app = try await KeyingApp.make()
        let setup: AudioSetupModel = app.model.audio.setup
        await setup.startMeter()
        #expect(setup.metering)
        #expect(app.model.audio.userNames.contains(AudioSetupModel.meterUser))
        // A block peaking at half scale: about −6 dBFS.
        let value = Int16(16_384)
        let block: [UInt8] = (0..<AudioCapture.block).flatMap { _ in
            [UInt8(truncatingIfNeeded: value), UInt8(truncatingIfNeeded: value >> 8)]
        }
        app.model.audio.capture.accept(block, generation: try #require(app.keying.lastAudioGeneration))
        await eventually("level") { Int(setup.peakDb.rounded()) == -6 }
        setup.stopMeter()
        #expect(!app.model.audio.userNames.contains(AudioSetupModel.meterUser))
        #expect(setup.peakDb == -90)
    }

    @Test func testToneGoesOnlyToTheSoundCard() async throws {
        let fake = try FakeRigctld(mode: "USB")
        defer { fake.stop() }
        let app = try await KeyingApp.make(configure: { config, _ in
            config.rig = fakeRigConfig(fake.port)
        })
        await app.connectRig(fake)
        let setup: AudioSetupModel = app.model.audio.setup
        setup.playTestTone(device: "Fake Out", level: 50)
        await setup.settle()
        await runMainQueue()
        #expect(!setup.testing)
        let played: [UInt8] = try #require(app.keying.playedPcm.last)
        #expect(played.count == AudioSetupModel.toneRate * 2)
        let peak: Int = stride(from: 0, to: played.count, by: 2)
            .map { abs(Int(Int16(played[$0]) | Int16(played[$0 + 1]) << 8)) }.max() ?? 0
        #expect(peak <= 8_193 && peak > 8_000)
        #expect(!fake.writes.contains("T 1"))
    }

    /// The playback level and, in SO2R with radio 2 active, radio 2's own output.
    @Test func levelAndRadioTwoOutput() async throws {
        let app = try await KeyingApp.make(configure: { config, dataDir in
            let wav: URL = dataDir.appendingPathComponent("wav")
            try FileManager.default.createDirectory(at: wav, withIntermediateDirectories: true)
            try Data([1]).write(to: wav.appendingPathComponent("cq.wav"))
            for set in [\VoiceKeyerConfig.runMessages, \VoiceKeyerConfig.spMessages] {
                config.voiceKeyer[keyPath: set][0] = FunctionKeyMessage(label: "CQ", text: "cq.wav")
            }
            config.voiceKeyer.outputDevice = "Out 1"
            config.voiceKeyer.outputDevice2 = "Out 2"
            config.voiceKeyer.outputLevel = 40
            config.voiceKeyer.pttViaCat = false
            config.radioMode = "SO2R"
        })
        app.entry.setMode(.ssb)
        app.entry.handle(.functionKey(0, shift: false, ctrlShift: false))
        await eventually("played") { app.keying.events.contains { $0.hasPrefix("play cq.wav") } }
        #expect(app.keying.events.last { $0.hasPrefix("play ") } == "play cq.wav on Out 1 at 40%")
        await eventually("idle") { app.keyer.voice.playingKey == nil && !app.keyer.voice.planning }
        app.model.rig.activateVfo(1)
        let second: EntryModel = app.model.vfoB.entry
        second.isWindowShown = true
        second.setMode(.ssb)
        second.handle(.functionKey(0, shift: false, ctrlShift: false))
        await eventually("played 2") { app.keying.events.filter { $0.hasPrefix("play ") }.count == 2 }
        #expect(app.keying.events.last { $0.hasPrefix("play ") } == "play cq.wav on Out 2 at 40%")
    }
}
