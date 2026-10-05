import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// The voice keyer (`AS:1282-1441`): PTT over CAT around the files, the plan's texts, Esc, the errors and recording a
/// message (Ctrl+Shift+F). The audio output and the recording input are fakes; PTT reaches a fake `rigctld` on a
/// loopback port.
@MainActor @Suite struct VoiceKeyerModelTests {

    /// A phone app: `wav/cq.wav` and `wav/tu.wav` exist, F1 = `text`, F2 = `tu.wav`, PTT over CAT without a delay.
    private static func make(_ fake: FakeRigctld?, f1 text: String = "cq.wav", pttDelayMs: Int = 0,
                             viaCat: Bool = true) async throws -> KeyingApp {
        let app = try await KeyingApp.make(configure: { config, dataDir in
            let wav: URL = dataDir.appendingPathComponent("wav")
            try FileManager.default.createDirectory(at: wav, withIntermediateDirectories: true)
            try Data([1]).write(to: wav.appendingPathComponent("cq.wav"))
            try Data([1]).write(to: wav.appendingPathComponent("tu.wav"))
            for set in [\VoiceKeyerConfig.runMessages, \VoiceKeyerConfig.spMessages] {
                var messages: [FunctionKeyMessage] = config.voiceKeyer[keyPath: set]
                messages[0] = FunctionKeyMessage(label: "CQ", text: text)
                messages[1] = FunctionKeyMessage(label: "TU", text: "tu.wav")
                config.voiceKeyer[keyPath: set] = messages
            }
            config.voiceKeyer.outputDevice = "Fake Out"
            config.voiceKeyer.inputDevice = "Fake In"
            config.voiceKeyer.pttDelayMs = pttDelayMs
            config.voiceKeyer.pttViaCat = viaCat
            if let fake {
                config.rig = fakeRigConfig(fake.port)
            }
        })
        app.entry.setMode(.ssb)
        if let fake {
            await app.connectRig(fake)
            app.keying.probePlay { " PTT " + fake.writes.joined(separator: ",") }
        }
        return app
    }

    private static func pressF(_ app: KeyingApp, _ index: Int, ctrlShift: Bool = false) {
        app.entry.handle(.functionKey(index, shift: false, ctrlShift: ctrlShift))
    }

    /// F1 in phone: PTT on → (delay) → the files → PTT off, the key lit while it plays.
    @Test func pttWrapsTheFiles() async throws {
        let fake = try FakeRigctld(mode: "USB")
        let app = try await Self.make(fake)
        Self.pressF(app, 0)
        #expect(app.keyer.voice.planning)
        await eventually("played") { app.keyer.voice.playingKey == nil && !app.keyer.voice.planning }
        await eventually("PTT off") { fake.writes == ["T 1", "T 0"] }
        #expect(app.keying.events == ["play cq.wav on Fake Out PTT T 1"])
        #expect(app.model.operating.runMode == .run)
    }

    /// Without PTT over CAT (VOX) the rig is not keyed; the files still play.
    @Test func voxDoesNotKeyTheRig() async throws {
        let fake = try FakeRigctld(mode: "USB")
        let app = try await Self.make(fake, viaCat: false)
        Self.pressF(app, 1)
        await eventually("played") { app.keying.events.count == 1 }
        await app.settle()
        #expect(app.keying.events == ["play tu.wav on Fake Out PTT "])
        #expect(fake.writes.isEmpty)
    }

    /// An audio error: PTT is still released, `Hlasový klíč: …` shows and the send counts as failed.
    @Test func audioErrorStillReleasesThePtt() async throws {
        let fake = try FakeRigctld(mode: "USB")
        let app = try await Self.make(fake)
        app.keying.failPlayback("Nepodporovaný formát wav: cq.wav")
        Self.pressF(app, 0)
        await eventually("failed") { app.status == "Hlasový klíč: Nepodporovaný formát wav: cq.wav" }
        await eventually("PTT off") { fake.writes == ["T 1", "T 0"] }
        #expect(app.keyer.voice.playingKey == nil)
        #expect(app.keyer.sendFailures == 1)
    }

    /// Esc during the PTT delay: the message stops, no file plays, PTT is released.
    @Test func escapeStopsTheMessageAndReleasesThePtt() async throws {
        let fake = try FakeRigctld(mode: "USB")
        let app = try await Self.make(fake, pttDelayMs: 2_000)
        // The delay lasts until the Esc cancels it, however slow the runner; released at the end, a message the Esc
        // failed to cancel would play.
        app.keying.holdPttDelay()
        Self.pressF(app, 0)
        await eventually("keyed") { fake.writes == ["T 1"] && app.keyer.voice.playingKey == 0 }
        #expect(app.keyer.isSending)
        #expect(app.entry.stopSending())
        #expect(app.keyer.voice.playingKey == nil)
        await eventually("PTT off") { fake.writes == ["T 1", "T 0"] }
        app.keying.releasePttDelay()
        await eventually("message over") { !app.keyer.voice.isOnAir }
        await app.settle()
        #expect(app.keying.events.isEmpty)
    }

    /// Missing files are reported and the rest plays; a message of only missing files plays nothing; an empty one
    /// says so.
    @Test func missingAndEmptyMessages() async throws {
        let app = try await Self.make(nil, f1: "cq.wav, gone.wav")
        Self.pressF(app, 0)
        await eventually("planned") { !app.keyer.voice.planning }
        let wav: String = app.app.dataDir.appendingPathComponent("wav").path
        #expect(app.status == "F1: chybí gone.wav (v \(wav))")
        await eventually("played") { app.keying.events == ["play cq.wav on Fake Out"] }

        // F1 switched to Run (`onCqSent`): the Run set is used from now on.
        #expect(app.model.operating.runMode == .run)
        await eventually("finished") { app.keyer.voice.playingKey == nil }
        app.model.config.config.voiceKeyer.runMessages[0].text = "gone.wav"
        Self.pressF(app, 0)
        await eventually("planned") { !app.keyer.voice.planning }
        #expect(app.status == "F1: chybí gone.wav (v \(wav))")
        #expect(app.keyer.voice.playingKey == nil)

        app.model.config.config.voiceKeyer.runMessages[0].text = " "
        Self.pressF(app, 0)
        await eventually("planned") { !app.keyer.voice.planning }
        #expect(app.status == "F1: zpráva je prázdná (Nastavení → Function Keys)")
        #expect(app.keyer.sendFailures == 2)
        await app.settle()
        #expect(app.keying.events == ["play cq.wav on Fake Out"])
    }

    /// `[text]` is spoken by speech synthesis (on the voice lane); a failed synthesis is a missing `TTS: …` item.
    @Test func speechThatFailsIsReportedAsMissing() async throws {
        let app = try await Self.make(nil, f1: "[CQ test]")
        Self.pressF(app, 0)
        await eventually("planned") { !app.keyer.voice.planning }
        let wav: String = app.app.dataDir.appendingPathComponent("wav").path
        #expect(app.keying.events == ["say CQ test"])
        #expect(app.status == "F1: chybí TTS: CQ test (v \(wav))")
    }

    /// Ctrl+Shift+F1: the recording starts (the target is the message's one wav file), F-keys are refused while it
    /// runs, the second press saves it; `maxRecordSeconds` ends a forgotten one; Esc saves too.
    @Test func recordingAMessage() async throws {
        let app = try await Self.make(nil)
        let target: String = app.app.dataDir.appendingPathComponent("wav/cq.wav").path
        Self.pressF(app, 0, ctrlShift: true)
        await eventually("recording") { app.keyer.voice.recordingKey == 0 }
        #expect(app.keying.events == ["record cq.wav from Fake In"])
        #expect(app.status == "● Nahrávám F1 → \(target) (Ctrl+Shift+F1 nebo Esc ukončí)")
        Self.pressF(app, 1)
        #expect(app.status == "Nahrává se — nejdřív ukonči záznam (Esc)")
        Self.pressF(app, 0, ctrlShift: true)
        #expect(app.keyer.voice.recordingKey == nil)
        await eventually("saved") { app.status == "Nahrávka uložena: \(target)" }
        let first: FakeRecording = try #require(app.keying.messageRecordings.first)
        #expect(first.events == ["stop"])

        Self.pressF(app, 0, ctrlShift: true)
        await eventually("recording") { app.keyer.voice.recordingKey == 0 }
        app.clock.advance(by: 29_999)
        #expect(app.keyer.voice.recordingKey == 0)
        app.clock.advance(by: 1)
        #expect(app.keyer.voice.recordingKey == nil)
        await eventually("saved") { app.status == "Nahrávka uložena: \(target)" }

        Self.pressF(app, 0, ctrlShift: true)
        await eventually("recording") { app.keyer.voice.recordingKey == 0 }
        #expect(app.entry.stopSending())
        await eventually("saved") { app.keyer.voice.recordingKey == nil && app.keying.messageRecordings.count == 3 }
        await app.settle()
        #expect(app.status == "Nahrávka uložena: \(target)")
        #expect(app.keying.messageRecordings.map(\.events) == [["stop"], ["stop"], ["stop"]])
    }

    /// Recording failures and refusals: a composite message cannot be recorded, an input that does not open says
    /// so, a stop that fails says the file was not saved, and CW refuses Ctrl+Shift+F.
    @Test func recordingFailures() async throws {
        let app = try await Self.make(nil, f1: "cq.wav, tu.wav")
        Self.pressF(app, 0, ctrlShift: true)
        #expect(app.status == "F1: nahrávat jde jen zprávu s jedním wav souborem (Nastavení → Function Keys)")
        app.keying.failRecording("no input")
        Self.pressF(app, 1, ctrlShift: true)
        await eventually("failed") { app.status.hasPrefix("Nahrávání nezačalo") }
        #expect(app.status == "Nahrávání nezačalo: Záznamové zařízení není dostupné: no input")
        #expect(app.keyer.voice.recordingKey == nil)
        app.keying.failRecording(nil)
        app.keying.failRecordingStop("disk full")
        Self.pressF(app, 1, ctrlShift: true)
        await eventually("recording") { app.keyer.voice.recordingKey == 1 }
        Self.pressF(app, 1, ctrlShift: true)
        await eventually("not saved") { app.status == "Nahrávka se neuložila: disk full" }
        app.entry.setMode(.cw)
        Self.pressF(app, 1, ctrlShift: true)
        #expect(app.status == "Nahrávání zpráv (Ctrl+Shift+F) je jen pro fone")
    }

    /// Esc while the recording input is still opening: the recording is discarded when it arrives.
    @Test func escapeBeforeTheRecordingStartedDiscardsIt() async throws {
        let app = try await Self.make(nil)
        Self.pressF(app, 0, ctrlShift: true)
        #expect(app.keyer.voice.recordingStarting)
        #expect(app.entry.stopSending())
        await app.settle()
        #expect(app.keyer.voice.recordingKey == nil)
        #expect(app.keying.messageRecordings.first?.events == ["cancel"])
    }
}
