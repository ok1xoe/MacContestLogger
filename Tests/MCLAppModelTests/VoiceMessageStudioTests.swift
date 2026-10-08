import AVFoundation
import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// Settings → Function Keys, SSB: recording, playing, choosing and deleting the files of the voice messages. The
/// capture and the playback are fakes (nothing is recorded or played), the files live in the test's data directory.
@MainActor @Suite struct VoiceMessageStudioTests {

    private static func make(f1 text: String = "cq.wav", maxRecord: Int = 30) async throws -> KeyingApp {
        let app = try await KeyingApp.make(configure: { config, _ in
            config.voiceKeyer.inputDevice = "Fake In"
            config.voiceKeyer.maxRecordSeconds = maxRecord
            config.voiceKeyer.runMessages[0] = FunctionKeyMessage(label: "CQ", text: text)
            config.voiceKeyer.spMessages[0] = FunctionKeyMessage(label: "CQ", text: text)
        })
        app.entry.setMode(.ssb)
        return app
    }

    private static func request(_ app: KeyingApp, _ text: String, index: Int = 0, run: Bool = true,
                                wavDir: String = "") -> VoiceMessageStudio.Request {
        VoiceMessageStudio.Request(slot: .init(run: run, index: index), text: text, wavDir: wavDir)
    }

    private static func wavDir(_ app: KeyingApp) -> URL {
        app.app.dataDir.appendingPathComponent("wav")
    }

    /// 16-bit mono PCM of `frames` frames at `rate`.
    private static func pcmWav(rate: Int32 = 8_000, frames: Int = 8_000, channels: Int = 1) -> [UInt8] {
        var bytes: [UInt8] = []
        func put32(_ value: Int) { for shift in stride(from: 0, to: 32, by: 8) { bytes.append(UInt8((value >> shift) & 255)) } }
        func put16(_ value: Int) { for shift in stride(from: 0, to: 16, by: 8) { bytes.append(UInt8((value >> shift) & 255)) } }
        let data: Int = frames * channels * 2
        bytes += Array("RIFF".utf8); put32(36 + data); bytes += Array("WAVEfmt ".utf8); put32(16)
        put16(1); put16(channels); put32(Int(rate)); put32(Int(rate) * channels * 2); put16(channels * 2); put16(16)
        bytes += Array("data".utf8); put32(data)
        bytes += [UInt8](repeating: 1, count: data)
        return bytes
    }

    private static func write(_ bytes: [UInt8], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(bytes).write(to: url)
    }

    private func settle(_ app: KeyingApp) async {
        await app.model.keyer.voice.studio.settle()
        await app.settle()
    }

    // MARK: - the file of a key is the planner's

    @Test func targetEqualsThePlannersRecordTarget() async throws {
        let app = try await Self.make()
        let studio = app.keyer.voice.studio
        let operatorCall: String = app.model.operating.operatorCall
        let dir = try JavaPath(Self.wavDir(app).path)
        for text in ["cq.wav", " CQ.WAV ", "{OPERATOR}/CQ.wav", "sub\\x.wav", "../up.wav"] {
            let expected: JavaPath? = try VoiceMessagePlanner.recordTarget(text, operatorCall: operatorCall, wavDir: dir)
            #expect(studio.target(for: Self.request(app, text)) == .target(try #require(expected)), "\(text)")
        }
        // The draft wav directory wins over the default one.
        let custom: String = app.app.dataDir.appendingPathComponent("custom").path
        #expect(studio.target(for: Self.request(app, "cq.wav", wavDir: " \(custom) "))
                == .target(try JavaPath(custom).resolve("cq.wav").normalize()))
    }

    @Test func messagesWithoutOneWavFileHaveNoTarget() async throws {
        let app = try await Self.make()
        let studio = app.keyer.voice.studio
        let cases: [(String, VoiceMessagePlanner.NotRecordable)] = [
            ("", .empty), ("empty.wav", .empty), ("a.wav,b.wav", .several), ("[CQ contest *]", .speech),
            ("{WIPE}", .macro), ("{LOG}", .macro), ("{RUN}", .macro), ("*", .macro), ("{MYCALL}", .macro),
            ("!", .macro), ("#", .macro), ("@", .macro), ("cq.mp3", .notWav),
        ]
        for (text, reason) in cases {
            #expect(studio.target(for: Self.request(app, text)) == .unavailable(reason), "\(text)")
        }
        app.model.operating.operatorCall = " "
        #expect(studio.target(for: Self.request(app, "{OPERATOR}/cq.wav")) == .unavailable(.operatorMissing))
    }

    // MARK: - recording

    @Test func recordingSavesIntoTheKeyersFile() async throws {
        let app = try await Self.make()
        let studio = app.keyer.voice.studio
        let target: String = Self.wavDir(app).appendingPathComponent("cq.wav").path
        #expect(!FileManager.default.fileExists(atPath: Self.wavDir(app).path))
        studio.record(Self.request(app, "cq.wav"))
        #expect(studio.recordingStarting)
        await eventually("recording") { studio.recordingSlot != nil && !studio.recordingStarting }
        #expect(app.keying.events == ["microphone access", "record cq.wav from Fake In"])
        let recording: FakeRecording = try #require(app.keying.messageRecordings.first)
        #expect(recording.target.description == target)
        // The folder exists before the capture writes into it.
        #expect(FileManager.default.fileExists(atPath: Self.wavDir(app).path))
        app.clock.advance(by: 1_000)
        app.clock.advance(by: 1_000)
        #expect(studio.elapsedSeconds == 2)
        studio.stopRecording()
        #expect(studio.recordingSlot == nil)
        await eventually("saved") { studio.notice == .tr("Nahrávka uložena: %s", .string(target)) }
        #expect(recording.events == ["stop"])
    }

    @Test func recordingStopsByItselfAtTheLimit() async throws {
        let app = try await Self.make(maxRecord: 3)
        let studio = app.keyer.voice.studio
        studio.record(Self.request(app, "cq.wav"))
        await eventually("recording") { studio.recordingSlot != nil && !studio.recordingStarting }
        app.clock.advance(by: 1_000)
        app.clock.advance(by: 1_000)
        #expect(studio.isRecording)
        app.clock.advance(by: 1_000)
        #expect(!studio.isRecording)
        await eventually("stopped") { app.keying.messageRecordings.first?.events == ["stop"] }

        // A long Audio setting is capped at 60 s.
        let app2 = try await Self.make(maxRecord: 600)
        let studio2 = app2.keyer.voice.studio
        studio2.record(Self.request(app2, "cq.wav"))
        await eventually("recording") { studio2.recordingSlot != nil && !studio2.recordingStarting }
        for _ in 0..<59 { app2.clock.advance(by: 1_000) }
        #expect(studio2.isRecording)
        app2.clock.advance(by: 1_000)
        #expect(!studio2.isRecording)
    }

    @Test func overwritingAnExistingFileAsksFirst() async throws {
        let app = try await Self.make()
        let studio = app.keyer.voice.studio
        let file = Self.wavDir(app).appendingPathComponent("cq.wav")
        try Self.write(Self.pcmWav(), to: file)
        studio.record(Self.request(app, "cq.wav"))
        let prompt = try #require(studio.prompt)
        #expect(prompt.message == .tr("Soubor %s už existuje. Přepsat novou nahrávkou?", .string(file.path)))
        #expect(!studio.isRecording)
        #expect(app.keying.events.isEmpty)
        studio.cancelPrompt()
        #expect(studio.prompt == nil)
        await settle(app)
        #expect(app.keying.events.isEmpty)

        studio.record(Self.request(app, "cq.wav"))
        studio.confirmPrompt()
        await eventually("recording") { studio.recordingSlot != nil && !studio.recordingStarting }
        #expect(app.keying.events == ["microphone access", "record cq.wav from Fake In"])
        studio.abandon()
        await settle(app)
        // A discarded recording leaves the original alone.
        #expect(app.keying.messageRecordings.first?.events == ["cancel"])
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func deniedMicrophoneSaysSo() async throws {
        let app = try await Self.make()
        let studio = app.keyer.voice.studio
        app.keying.allowMicrophone(false)
        studio.record(Self.request(app, "cq.wav"))
        await eventually("denied") { studio.notice != nil }
        #expect(studio.notice == .tr(
            "Mikrofon není povolený — povol ho v Nastavení systému → Soukromí a zabezpečení → Mikrofon"))
        #expect(!studio.isRecording)
        #expect(app.keying.messageRecordings.isEmpty)
    }

    @Test func aCaptureThatDoesNotOpenIsReported() async throws {
        let app = try await Self.make()
        let studio = app.keyer.voice.studio
        app.keying.failRecording("nic")
        studio.record(Self.request(app, "cq.wav"))
        await eventually("failed") { studio.notice != nil }
        #expect(studio.notice == .tr("Nahrávání nezačalo: %s", .string("Záznamové zařízení není dostupné: nic")))
        #expect(!studio.isRecording)
    }

    @Test func macrosAreNotRecorded() async throws {
        let app = try await Self.make()
        let studio = app.keyer.voice.studio
        studio.record(Self.request(app, "{WIPE}"))
        #expect(studio.notice == VoiceMessageStudio.explanation(.macro))
        await settle(app)
        #expect(app.keying.events.isEmpty)
        #expect(!studio.isRecording)
    }

    // MARK: - refusals while the keyer is busy

    @Test func refusedWhileTheVoiceKeyerPlays() async throws {
        let app = try await Self.make()
        try Self.write(Self.pcmWav(), to: Self.wavDir(app).appendingPathComponent("cq.wav"))
        app.keying.holdPlayback()
        app.entry.handle(.functionKey(0, shift: false, ctrlShift: false))
        await eventually("planned") { !app.keyer.voice.planning }
        await eventually("on the air") { app.keyer.voice.playingKey == 0 }
        await eventually("playing") { app.keying.events.contains { $0.hasPrefix("play cq.wav") } }
        let studio = app.keyer.voice.studio
        let busy: EntryStatus = .tr("Hlasový klíč právě vysílá nebo nahrává — nejdřív ho zastav (Esc)")
        studio.record(Self.request(app, "cq.wav"))
        #expect(studio.notice == busy)
        #expect(!studio.isRecording)
        studio.play(Self.request(app, "cq.wav"))
        #expect(studio.playingSlot == nil)
        studio.delete(Self.request(app, "cq.wav"))
        #expect(studio.prompt == nil)
        studio.pick(Self.request(app, "cq.wav"), from: Self.wavDir(app).appendingPathComponent("cq.wav"))
        #expect(studio.prompt == nil)
        #expect(app.keying.events.filter { $0.hasPrefix("record") }.isEmpty)
        app.keying.releasePlayback()
        _ = app.keyer.voice.stop()
    }

    @Test func refusedWhileTheKeyerRecordsAndTheOtherWayAround() async throws {
        let app = try await Self.make()
        let studio = app.keyer.voice.studio
        app.entry.handle(.functionKey(0, shift: false, ctrlShift: true))
        await eventually("recording") { app.keyer.voice.recordingKey == 0 }
        studio.record(Self.request(app, "cq.wav"))
        #expect(!studio.isRecording)
        #expect(app.keying.messageRecordings.count == 1)
        _ = app.keyer.voice.stop()
        await settle(app)

        studio.record(Self.request(app, "cq.wav"))
        await eventually("recording") { studio.recordingSlot != nil && !studio.recordingStarting }
        // The keyer's own recording and playing are refused while Settings records.
        #expect(app.keyer.voice.toggleRecording(0) == .tr("Zpráva se nahrává v Nastavení — nejdřív ji ukonči"))
        #expect(app.keyer.voice.play([0], hisCall: "", freqHz: 0, opposite: false)
                == .tr("Zpráva se nahrává v Nastavení — nejdřív ji ukonči"))
        studio.abandon()
        await settle(app)
    }

    // MARK: - playing

    @Test func playingGoesToTheDefaultOutputWithoutPtt() async throws {
        let app = try await Self.make()
        let studio = app.keyer.voice.studio
        let file = Self.wavDir(app).appendingPathComponent("cq.wav")
        try Self.write(Self.pcmWav(), to: file)
        studio.play(Self.request(app, "cq.wav"))
        await eventually("played") { app.keying.events == ["play cq.wav on -"] }
        await eventually("over") { studio.playingSlot == nil }
        #expect(app.keyer.voice.ptt.requestedKeys == 0)

        // Nothing to play for a missing file.
        studio.play(Self.request(app, "tu.wav", index: 1))
        #expect(studio.notice == .tr("Soubor %s ještě není nahraný",
                                    .string(Self.wavDir(app).appendingPathComponent("tu.wav").path)))
        #expect(app.keying.events == ["play cq.wav on -"])
    }

    @Test func playingCanBeStopped() async throws {
        let app = try await Self.make()
        let studio = app.keyer.voice.studio
        try Self.write(Self.pcmWav(), to: Self.wavDir(app).appendingPathComponent("cq.wav"))
        app.keying.holdPlayback()
        studio.play(Self.request(app, "cq.wav"))
        #expect(studio.playingSlot == .init(run: true, index: 0))
        await eventually("started") { !app.keying.events.isEmpty }
        studio.play(Self.request(app, "cq.wav"))
        #expect(studio.playingSlot == nil)
        app.keying.releasePlayback()
        await settle(app)
    }

    @Test func aPlaybackErrorIsShown() async throws {
        let app = try await Self.make()
        let studio = app.keyer.voice.studio
        try Self.write(Self.pcmWav(), to: Self.wavDir(app).appendingPathComponent("cq.wav"))
        app.keying.failPlayback("Zvukové zařízení není dostupné")
        studio.play(Self.request(app, "cq.wav"))
        await eventually("failed") { studio.notice != nil }
        #expect(studio.notice == .tr("Přehrávání selhalo: %s", .string("Zvukové zařízení není dostupné")))
        #expect(studio.playingSlot == nil)
    }

    // MARK: - choosing a file

    @Test func pickingCopiesTheFileUnderTheKeyersName() async throws {
        let app = try await Self.make()
        let studio = app.keyer.voice.studio
        let source = app.app.dataDir.appendingPathComponent("elsewhere/My Recording.wav")
        let bytes = Self.pcmWav(rate: 22_050, frames: 22_050)
        try Self.write(bytes, to: source)
        studio.pick(Self.request(app, "cq.wav"), from: source)
        let target = Self.wavDir(app).appendingPathComponent("cq.wav")
        await eventually("copied") { FileManager.default.fileExists(atPath: target.path) }
        await settle(app)
        #expect(try [UInt8](Data(contentsOf: target)) == bytes)
        // A copy: the source stays, and no temporary file is left.
        #expect(FileManager.default.fileExists(atPath: source.path))
        #expect(!FileManager.default.fileExists(atPath: target.path + ".import"))
        #expect(studio.notice == .tr("Zkopírováno: %s", .string(target.path)))
        #expect(studio.files[.init(run: true, index: 0)]?.seconds == 1.0)
    }

    @Test func pickingOverAnExistingFileAsksFirst() async throws {
        let app = try await Self.make()
        let studio = app.keyer.voice.studio
        let target = Self.wavDir(app).appendingPathComponent("cq.wav")
        let old = Self.pcmWav(frames: 100)
        try Self.write(old, to: target)
        let source = app.app.dataDir.appendingPathComponent("new.wav")
        let new = Self.pcmWav(frames: 400)
        try Self.write(new, to: source)
        studio.pick(Self.request(app, "cq.wav"), from: source)
        await eventually("asked") { studio.prompt != nil }
        #expect(try [UInt8](Data(contentsOf: target)) == old)
        studio.cancelPrompt()
        await settle(app)
        #expect(try [UInt8](Data(contentsOf: target)) == old)

        studio.pick(Self.request(app, "cq.wav"), from: source)
        await eventually("asked") { studio.prompt != nil }
        studio.confirmPrompt()
        await eventually("replaced") { (try? [UInt8](Data(contentsOf: target))) == new }
    }

    @Test func pickingRefusesWhatCannotBeUsed() async throws {
        let app = try await Self.make()
        let studio = app.keyer.voice.studio
        let target = Self.wavDir(app).appendingPathComponent("cq.wav")

        let text = app.app.dataDir.appendingPathComponent("notes.wav")
        try Self.write(Array("not audio at all".utf8), to: text)
        studio.pick(Self.request(app, "cq.wav"), from: text)
        await eventually("refused") { studio.notice == .tr("Nepodporovaný formát — použij wav, aiff, caf, mp3 nebo m4a") }

        let silent = app.app.dataDir.appendingPathComponent("silent.wav")
        try Self.write(Self.pcmWav(frames: 0), to: silent)
        studio.pick(Self.request(app, "cq.wav"), from: silent)
        await eventually("empty") { studio.notice == .tr("Soubor neobsahuje žádný zvuk") }

        let long = app.app.dataDir.appendingPathComponent("long.wav")
        try Self.write(Self.pcmWav(rate: 4_000, frames: 4_000 * 301), to: long)
        studio.pick(Self.request(app, "cq.wav"), from: long)
        await eventually("long") { studio.notice == .tr("Zpráva je příliš dlouhá (nejvýš %s s)", .int(300)) }

        studio.pick(Self.request(app, "cq.wav"), from: app.app.dataDir.appendingPathComponent("missing.wav"))
        await eventually("unreadable") {
            if case .some(let notice) = studio.notice { return notice.czech.hasPrefix("Soubor nejde přečíst") }
            return false
        }
        await settle(app)
        #expect(!FileManager.default.fileExists(atPath: target.path))
    }

    @Test func pickingAnAiffConvertsItToTheRecordingFormat() async throws {
        let app = try await Self.make()
        let studio = app.keyer.voice.studio
        let source = app.app.dataDir.appendingPathComponent("tone.aiff")
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 44_100, channels: 2,
                                                interleaved: true))
        do {
            let file = try AVAudioFile(forWriting: source, settings: format.settings,
                                       commonFormat: .pcmFormatInt16, interleaved: true)
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100))
            buffer.frameLength = 44_100
            for index in 0..<(44_100 * 2) { buffer.int16ChannelData![0][index] = Int16(truncatingIfNeeded: (index % 100) * 100) }
            try file.write(from: buffer)
        }
        studio.pick(Self.request(app, "cq.wav"), from: source)
        let target = Self.wavDir(app).appendingPathComponent("cq.wav")
        await eventually("converted") { FileManager.default.fileExists(atPath: target.path) }
        await settle(app)
        let info = try #require(VoiceWavImport.inspect([UInt8](try Data(contentsOf: target))).seconds)
        #expect(abs(info - 1.0) < 0.05)
        let wav = try #require(WavFile.parse([UInt8](try Data(contentsOf: target))))
        #expect(wav.channels == 1 && wav.bits == 16 && wav.sampleRate == 22_050)
        #expect(studio.notice == .tr("Převedeno na 16bitové mono wav 22 050 Hz a uloženo: %s", .string(target.path)))
    }

    @Test func importValidation() throws {
        let dir = try TempDir()
        let good = dir.child("good.wav")
        try Self.write(Self.pcmWav(rate: 44_100, frames: 100, channels: 2), to: good)
        #expect(try VoiceWavImport.prepare(good).converted == false)
        // A 3 kHz wav is below what the keyer plays: it is not copied as it is and AVFoundation converts it.
        #expect(VoiceWavImport.inspect(Self.pcmWav(rate: 3_000, frames: 10)).seconds == nil)
        #expect(VoiceWavImport.inspect(Self.pcmWav(rate: 8_000, frames: 4_000)).seconds == 0.5)
        #expect(VoiceWavImport.inspect(Array("garbage".utf8)).seconds == nil)
    }

    // MARK: - deleting and listing

    @Test func deletingAsksAndRemovesTheFile() async throws {
        let app = try await Self.make()
        let studio = app.keyer.voice.studio
        let target = Self.wavDir(app).appendingPathComponent("cq.wav")
        try Self.write(Self.pcmWav(), to: target)
        studio.refresh([Self.request(app, "cq.wav")])
        await eventually("listed") { studio.files[.init(run: true, index: 0)] != nil }
        #expect(studio.files[.init(run: true, index: 0)]?.seconds == 1.0)

        studio.delete(Self.request(app, "cq.wav"))
        #expect(studio.prompt?.message == .tr("Smazat soubor %s?", .string(target.path)))
        studio.cancelPrompt()
        #expect(FileManager.default.fileExists(atPath: target.path))

        studio.delete(Self.request(app, "cq.wav"))
        studio.confirmPrompt()
        await eventually("deleted") { !FileManager.default.fileExists(atPath: target.path) }
        await eventually("unlisted") { studio.files[.init(run: true, index: 0)] == nil }
        #expect(studio.notice == .tr("Smazáno: %s", .string(target.path)))

        // Nothing to delete.
        studio.delete(Self.request(app, "cq.wav"))
        #expect(studio.prompt == nil)
    }

    @Test func listingShowsMissingAndUnreadableFiles() async throws {
        let app = try await Self.make()
        let studio = app.keyer.voice.studio
        try Self.write(Array("junk".utf8), to: Self.wavDir(app).appendingPathComponent("bad.wav"))
        studio.refresh([Self.request(app, "bad.wav"), Self.request(app, "none.wav", index: 1),
                        Self.request(app, "{WIPE}", index: 2)])
        await eventually("listed") { studio.files[.init(run: true, index: 0)] != nil }
        #expect(studio.files[.init(run: true, index: 0)]?.seconds == nil)
        #expect(studio.files[.init(run: true, index: 1)] == nil)
        #expect(studio.files[.init(run: true, index: 2)] == nil)
    }

    @Test func theFolderIsCreatedForFinder() async throws {
        let app = try await Self.make()
        let studio = app.keyer.voice.studio
        let url = try #require(studio.folder(wavDir: ""))
        #expect(url.path == Self.wavDir(app).path)
        var directory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) && directory.boolValue)
    }
}
