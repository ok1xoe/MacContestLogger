import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// Transmitter safety of the keying: the quit stops keying before it waits for anything, a
/// user disconnect of a rig first releases a carrier or voice PTT keyed on it, and every release goes to the rig that
/// was keyed — also after an SO2R switch. Only fakes: `FakeRigctld` on loopback ports, a fake Winkeyer, fake audio.
@MainActor @Suite struct KeyerSafetyTests {

    /// A CAT-keyed app on one fake rig (connected), or SO2R on two (both connected, rig 1 active).
    private static func make(_ fake1: FakeRigctld, _ fake2: FakeRigctld? = nil, method: CwKeyerConfig.Method = .cat,
                             speech: Bool = false, readTimeoutMs: Int? = nil,
                             pollIntervalMs: Int64? = nil) async throws -> KeyingApp {
        let app = try await KeyingApp.make(configure: { config, dataDir in
            config.cwKeyer.method = method
            config.cwKeyer.winkeyerPort = "fake-winkeyer"
            config.rig = fakeRigConfig(fake1.port)
            if let fake2 {
                config.radioMode = "SO2R"
                config.rig2 = fakeRigConfig(fake2.port)
            }
            let wav: URL = dataDir.appendingPathComponent("wav")
            try FileManager.default.createDirectory(at: wav, withIntermediateDirectories: true)
            try Data([1]).write(to: wav.appendingPathComponent("cq.wav"))
            let text: String = speech ? "[CQ], cq.wav" : "cq.wav"
            config.voiceKeyer.spMessages[0] = FunctionKeyMessage(label: "CQ", text: text)
            config.voiceKeyer.runMessages[0] = FunctionKeyMessage(label: "CQ", text: text)
            // Held: the PTT delay and the fake output last until the message is cancelled, so no message ends by
            // itself and none reaches the audio while a loaded runner starves the test.
            config.voiceKeyer.pttDelayMs = 2_000
        }, setUp: { keying in
            keying.holdPttDelay()
            keying.holdPlayback()
        }, pollIntervalMs: pollIntervalMs)
        if let readTimeoutMs {
            app.hardware.setRigReadTimeout(readTimeoutMs)
        }
        await app.connectRig(fake1)
        if fake2 != nil {
            app.model.rig.toggle(vfo: 1)
            await eventually("rig 2") { app.model.rig.cat2.state != nil }
        }
        return app
    }

    private static func keyVoice(_ app: KeyingApp, _ fake: FakeRigctld) async {
        _ = app.keyer.voice.play([0], hisCall: "", freqHz: 14_250_000, opposite: false)
        await eventually("keyed") { fake.writes == ["T 1"] && app.keyer.voice.playingKey == 0 }
    }

    // MARK: - I-1: the quit stops keying first

    /// The quit switches the carrier off and closes the keyer before it waits for the entry's work (a database
    /// drain held open here); the drain then finishes and the quit completes.
    @Test func quitStopsKeyingBeforeTheDrain() async throws {
        let app = try await KeyingApp.make(configure: { config, _ in winkeyerConfig(&config) })
        app.keyer.setTune(true)
        await app.settle()
        let keyer: FakeCwKeyer = try #require(app.keying.lastKeyer)
        let gate = HeldGate()
        app.entry.track {
            await gate.wait()
        }
        let model: AppModel = app.model
        let quit = Task { @MainActor in
            await model.shutdown()
        }
        await eventually("keying stopped") { keyer.events.suffix(3) == ["tune off", "abort", "close"] }
        #expect(!app.keyer.isTuning)
        #expect(gate.isWaiting)
        gate.open()
        await quit.value
        #expect(keyer.events == ["tune on", "tune off", "abort", "close"])
    }

    /// A CAT carrier at the quit: `T 0` reaches the rig before it disconnects.
    @Test func catTuneIsReleasedAtTheQuit() async throws {
        let fake = try FakeRigctld()
        let app = try await Self.make(fake)
        app.keyer.setTune(true)
        await eventually("carrier") { fake.writes == ["T 1"] }
        await app.model.shutdown()
        #expect(fake.writes == ["T 1", "T 0"])
        #expect(!app.model.rig.cat1.connected)
    }

    // MARK: - I-2: a user disconnect releases first

    /// The LED, a reconnect after Settings, a scan and RESETINTERFACES: a CAT carrier on the rig is switched off and
    /// `T 0` precedes the disconnect.
    @Test func catTuneIsReleasedBeforeEveryUserDisconnect() async throws {
        let fake = try FakeRigctld()
        let app = try await Self.make(fake)
        let rig: MCLAppModel.RigModel = app.model.rig
        // (name, the disconnect, whether it connects again by itself)
        let disconnects: [(String, @MainActor () async -> Void, Bool)] = [
            ("toggle", { rig.toggle(vfo: 0) }, false),
            ("reconnect", { rig.reconnect(disconnectFirst: true) }, true),
            ("scan", { await rig.disconnectForScan(reason: "scan") }, false),
            ("reset", { rig.resetInterfaces() }, true),
        ]
        for (name, disconnect, reconnects) in disconnects {
            await eventually("connected before \(name)") { rig.cat1.connected && rig.cat1.state != nil }
            let before: Int = fake.writes.count
            app.keyer.setTune(true)
            await eventually("carrier \(name)") { fake.writes.count == before + 1 }
            #expect(fake.writes.last == "T 1", "\(name)")
            await disconnect()
            #expect(!app.keyer.isTuning, "\(name)")
            await rig.settle()
            await eventually("released \(name)") { fake.writes.count == before + 2 }
            #expect(fake.writes.last == "T 0", "\(name)")
            await app.settle()
            if reconnects {
                // `T 0` went to the old session: the new session's first poll comes after it.
                await eventually("reconnected \(name)") { rig.cat1.connected && rig.cat1.state != nil }
                Self.expectReleaseBeforeTheNextSession(fake.commands, name)
            } else {
                await eventually("disconnected \(name)") { !rig.cat1.connected }
                rig.toggle(vfo: 0)
            }
        }
    }

    /// In the command log, the last `T 1` is followed by `T 0` before the next poll (`f`) — the reconnected
    /// session's first read (the old session's poller sleeps through the test).
    private static func expectReleaseBeforeTheNextSession(_ commands: [String], _ name: String,
                                                          sourceLocation: SourceLocation = #_sourceLocation) {
        guard let keyedAt = commands.lastIndex(of: "T 1") else {
            Issue.record("no T 1 (\(name))", sourceLocation: sourceLocation)
            return
        }
        let after: ArraySlice<String> = commands[(keyedAt + 1)...]
        let released: Int? = after.firstIndex(of: "T 0")
        let polled: Int? = after.firstIndex(of: "f")
        #expect(released != nil, "\(name)", sourceLocation: sourceLocation)
        #expect(polled != nil, "\(name)", sourceLocation: sourceLocation)
        if let released, let polled {
            #expect(released < polled, "\(name): \(Array(after))", sourceLocation: sourceLocation)
        }
    }

    /// N-1: a voice message whose key (`T 1`) is already queued on the rig's lane when the operator disconnects the
    /// rig (the LED, a reconnect, RESETINTERFACES): the key is refused after the release — no `T 1` reaches the rig,
    /// neither before the disconnect nor on the reconnected session.
    @Test func voiceKeyQueuedBeforeAUserDisconnectNeverKeys() async throws {
        let fake = try FakeRigctld(mode: "USB")
        let app = try await Self.make(fake)
        let rig: MCLAppModel.RigModel = app.model.rig
        let disconnects: [(String, @MainActor () async -> Void, Bool)] = [
            ("toggle", { rig.toggle(vfo: 0) }, false),
            ("reconnect", { rig.reconnect(disconnectFirst: true) }, true),
            ("reset", { rig.resetInterfaces() }, true),
        ]
        for (name, disconnect, reconnects) in disconnects {
            await eventually("connected before \(name)") { rig.cat1.connected && rig.cat1.state != nil }
            let gate = DispatchSemaphore(value: 0)
            rig.lanes[0].run { _ in
                gate.wait()
            }
            let keys: Int = app.keyer.voice.ptt.requestedKeys
            _ = app.keyer.voice.play([0], hisCall: "", freqHz: 14_250_000, opposite: false)
            await eventually("key queued \(name)") { app.keyer.voice.ptt.requestedKeys == keys + 1 }
            await disconnect()
            gate.signal()
            await rig.settle()
            await app.settle()
            if reconnects {
                await eventually("reconnected \(name)") { rig.cat1.connected && rig.cat1.state != nil }
            } else {
                await eventually("disconnected \(name)") { !rig.cat1.connected }
            }
            await eventually("message over \(name)") { app.keyer.voice.playingKey == nil }
            await rig.settle()
            #expect(!fake.writes.contains("T 1"), "\(name): \(fake.writes)")
            if !reconnects {
                rig.toggle(vfo: 0)
            }
        }
        #expect(app.keying.events.filter { $0.hasPrefix("play") }.isEmpty)
    }

    /// A voice message keyed on the rig: the LED stops it and `T 0` precedes the disconnect.
    @Test func voicePttIsReleasedBeforeAUserDisconnect() async throws {
        let fake = try FakeRigctld(mode: "USB")
        let app = try await Self.make(fake)
        await Self.keyVoice(app, fake)
        app.model.rig.toggle(vfo: 0)
        #expect(app.keyer.voice.playingKey == nil)
        await eventually("disconnected") { !app.model.rig.cat1.connected }
        #expect(fake.writes == ["T 1", "T 0"])
        // Released now: a message the LED failed to stop would play.
        app.keying.releasePttDelay()
        await eventually("message over") { !app.keyer.voice.isOnAir }
        await app.settle()
        #expect(app.keying.events.isEmpty)
    }

    /// The message's own PTT off and the release before a user disconnect race for the keyed rig: the LED stops the
    /// message while the rig's lane is busy, so the voice keyer asks for its PTT off before the lane runs the release
    /// queued ahead of the disconnect. That release still sends `T 0` before the disconnect.
    @Test func voicePttOffRacingAUserDisconnectStillReleases() async throws {
        let fake = try FakeRigctld(mode: "USB")
        let app = try await Self.make(fake)
        let rig: MCLAppModel.RigModel = app.model.rig
        await Self.keyVoice(app, fake)
        let gate = DispatchSemaphore(value: 0)
        rig.lanes[0].run { _ in
            gate.wait()
        }
        let releases: Int = app.keyer.voice.ptt.requestedReleases
        rig.toggle(vfo: 0)
        await eventually("PTT off asked for") { app.keyer.voice.ptt.requestedReleases == releases + 1 }
        gate.signal()
        await rig.settle()
        await eventually("disconnected") { !rig.cat1.connected }
        await rig.settle()
        #expect(fake.writes == ["T 1", "T 0"])
    }

    // MARK: - I-3 / M-3: releases go to the keyed rig

    /// SO2R: a voice message keyed rig 1; after switching to rig 2 a new message interrupts it — rig 1 is released
    /// (not the newly active rig 2), rig 2 is keyed for the new message, and Esc releases rig 2.
    @Test func voiceReleaseGoesToTheKeyedRigAfterAnSo2rSwitch() async throws {
        let fake1 = try FakeRigctld(mode: "USB")
        let fake2 = try FakeRigctld(freqHz: 7_150_000, mode: "LSB")
        let app = try await Self.make(fake1, fake2)
        await Self.keyVoice(app, fake1)
        app.model.rig.activateVfo(1)
        #expect(app.model.rig.vfo.activeCatIndex == 1)
        _ = app.keyer.voice.play([0], hisCall: "", freqHz: 7_150_000, opposite: false)
        await eventually("rig 1 released, rig 2 keyed") {
            fake1.writes == ["T 1", "T 0"] && fake2.writes.filter { $0.hasPrefix("T ") } == ["T 1"]
                && app.keyer.voice.playingKey == 0
        }
        #expect(fake1.writes == ["T 1", "T 0"], "\(app.status)")
        #expect(fake2.writes.filter { $0.hasPrefix("T ") } == ["T 1"], "\(app.status)")
        #expect(app.entry.stopSending())
        await eventually("rig 2 released") { fake2.writes.filter { $0.hasPrefix("T ") } == ["T 1", "T 0"] }
        await app.settle()
        #expect(fake1.writes == ["T 1", "T 0"])
    }

    /// A voice key the rig refuses — the same failure as an answer that comes too late on a loaded machine (the
    /// read timeout) — may still have keyed it: `T 0` follows on that rig at once and nothing is played. After an SO2R
    /// switch the next message keys rig 2 only, and Esc releases rig 2.
    @Test func aFailedVoiceKeyIsReleasedOnTheSameRig() async throws {
        let fake1 = try FakeRigctld(mode: "USB")
        let fake2 = try FakeRigctld(freqHz: 7_150_000, mode: "LSB")
        let app = try await Self.make(fake1, fake2)
        fake1.reject("T")
        _ = app.keyer.voice.play([0], hisCall: "", freqHz: 14_250_000, opposite: false)
        await eventually("refused key released") { fake1.writes.count == 2 && app.keyer.voice.playingKey == nil }
        #expect(fake1.writes == ["T 1", "T 0"])
        #expect(app.status.hasPrefix("Hlasový klíč: "), "\(app.status)")
        #expect(app.keying.events.isEmpty)
        app.model.rig.activateVfo(1)
        _ = app.keyer.voice.play([0], hisCall: "", freqHz: 7_150_000, opposite: false)
        await eventually("rig 2 keyed") {
            fake2.writes.filter { $0.hasPrefix("T ") } == ["T 1"] && app.keyer.voice.playingKey == 0
        }
        #expect(app.entry.stopSending())
        await eventually("rig 2 released") { fake2.writes.filter { $0.hasPrefix("T ") } == ["T 1", "T 0"] }
        await app.settle()
        #expect(fake1.writes == ["T 1", "T 0"])
    }

    /// SO2R: a CAT carrier on rig 1 is switched off on rig 1 after switching to rig 2.
    @Test func catTuneOffGoesToTheTunedRig() async throws {
        let fake1 = try FakeRigctld()
        let fake2 = try FakeRigctld(freqHz: 7_010_000)
        let app = try await Self.make(fake1, fake2)
        app.keyer.setTune(true)
        await eventually("carrier") { fake1.writes == ["T 1"] }
        app.model.rig.activateVfo(1)
        app.keyer.sendCwText("TEST")
        app.keyer.setTune(false)
        await app.settle()
        await app.model.rig.settle()
        await eventually("released") { fake1.writes.contains("T 0") }
        #expect(fake1.writes.filter { $0.hasPrefix("T ") } == ["T 1", "T 0"])
        #expect(!fake2.writes.contains { $0.hasPrefix("T ") })
    }

    /// SO2R: CW over CAT sent on rig 1; after switching to rig 2, Esc stops the morse on rig 1.
    @Test func cwOverCatAbortReachesTheSendingRig() async throws {
        let fake1 = try FakeRigctld()
        let fake2 = try FakeRigctld(freqHz: 7_010_000)
        let app = try await Self.make(fake1, fake2)
        app.keyer.sendCwText("TEST")
        await app.settle()
        await eventually("sent") { fake1.writes.contains("b TEST") }
        app.model.rig.activateVfo(1)
        #expect(app.entry.stopSending())
        await app.settle()
        await eventually("stopped") { fake1.writes.contains("\\stop_morse") }
        #expect(!fake2.writes.contains("\\stop_morse"))
    }

    /// Esc while a message is still being planned (speech synthesis held): nothing is keyed or played afterwards.
    @Test func escapeDuringTheVoicePlanSendsNothing() async throws {
        let fake = try FakeRigctld(mode: "USB")
        let app = try await Self.make(fake, speech: true)
        app.keying.holdSpeech()
        _ = app.keyer.voice.play([0], hisCall: "", freqHz: 14_250_000, opposite: false)
        #expect(app.keyer.voice.planning)
        #expect(app.entry.stopSending())
        #expect(!app.keyer.voice.planning)
        app.keying.releaseSpeech()
        await app.settle()
        await app.settle()
        #expect(app.keying.events == ["say CQ"])
        #expect(app.keyer.voice.playingKey == nil)
        #expect(fake.writes.isEmpty)
    }

    // MARK: - a failed carrier or voice key is released

    /// A CAT carrier whose `T 1` the rig refuses may still be on: `T 0` follows on that rig at once, and the failure
    /// is shown as before.
    @Test func refusedCatTuneIsReleased() async throws {
        let fake = try FakeRigctld()
        let app = try await Self.make(fake)
        fake.reject("T")
        app.keyer.setTune(true)
        await eventually("tune failed") { !app.keyer.isTuning }
        await app.model.rig.settle()
        #expect(fake.writes == ["T 1", "T 0"])
        #expect(app.status.hasPrefix("Ladění: "), "\(app.status)")
    }

    /// A CAT carrier whose answer to `T 1` comes after the read timeout: the `T 0` sent after it times out as well, so
    /// the rig stays remembered as possibly keyed and the release before the LED's disconnect sends `T 0` again.
    @Test func lateAnswerToACatTuneIsReleasedBeforeTheDisconnect() async throws {
        let fake = try FakeRigctld()
        let app = try await Self.make(fake, readTimeoutMs: 200)
        fake.holdAnswer(to: "T 1")
        app.keyer.setTune(true)
        await eventually("tune failed") { !app.keyer.isTuning }
        #expect(app.status.hasPrefix("Ladění: "), "\(app.status)")
        fake.releaseAnswer()
        await eventually("cleanup received") { fake.writes == ["T 1", "T 0"] }
        app.model.rig.toggle(vfo: 0)
        await app.model.rig.settle()
        await eventually("released again") { fake.writes == ["T 1", "T 0", "T 0"] }
        await eventually("disconnected") { !app.model.rig.cat1.connected }
    }

    /// The same for a voice key: its answer comes after the read timeout, the `T 0` after it times out too, so the rig
    /// stays recorded as keyed and the release before the LED's disconnect sends `T 0` again.
    @Test func lateAnswerToAVoiceKeyIsReleasedBeforeTheDisconnect() async throws {
        let fake = try FakeRigctld(mode: "USB")
        let app = try await Self.make(fake, readTimeoutMs: 200)
        fake.holdAnswer(to: "T 1")
        _ = app.keyer.voice.play([0], hisCall: "", freqHz: 14_250_000, opposite: false)
        await eventually("key failed") { app.status.hasPrefix("Hlasový klíč: ") }
        #expect(app.keyer.voice.playingKey == nil)
        fake.releaseAnswer()
        await eventually("cleanup received") { fake.writes == ["T 1", "T 0"] }
        app.model.rig.toggle(vfo: 0)
        await app.model.rig.settle()
        await eventually("released again") { fake.writes == ["T 1", "T 0", "T 0"] }
        await eventually("disconnected") { !app.model.rig.cat1.connected }
    }

    /// A failed tune whose `T 0` could not get through, then a poll error drops the rig: the LED's release finds no
    /// connection and keeps the record, and the first command of the reconnected session is `T 0`.
    @Test func aReleaseOwedAcrossAPollErrorGoesFirstOnTheReconnect() async throws {
        let fake = try FakeRigctld()
        let app = try await Self.make(fake, readTimeoutMs: 200, pollIntervalMs: 50)
        let rig: MCLAppModel.RigModel = app.model.rig
        fake.holdAnswer(to: "T 1")
        app.keyer.setTune(true)
        await eventually("tune failed") { !app.keyer.isTuning }
        await eventually("poll error") { !rig.cat1.connected }
        fake.releaseAnswer()
        await eventually("old connection gone") { fake.openConnections == 0 }
        let before: Int = fake.commands.count
        rig.toggle(vfo: 0)
        await eventually("reconnected") { rig.cat1.connected && rig.cat1.state != nil }
        let fresh: [String] = Array(fake.commands.dropFirst(before))
        #expect(fresh.first == "T 0", "\(fresh)")
        #expect(fresh.filter { $0 == "T 0" }.count == 1, "\(fresh)")
    }

    /// The voice keyer's form of the owed release: a voice key whose `T 1` and `T 0` time out, then a poll error drops
    /// the rig; the reconnected session's first command is `T 0`.
    @Test func aVoiceReleaseOwedAcrossAPollErrorGoesFirstOnTheReconnect() async throws {
        let fake = try FakeRigctld(mode: "USB")
        let app = try await Self.make(fake, readTimeoutMs: 200, pollIntervalMs: 50)
        let rig: MCLAppModel.RigModel = app.model.rig
        fake.holdAnswer(to: "T 1")
        _ = app.keyer.voice.play([0], hisCall: "", freqHz: 14_250_000, opposite: false)
        await eventually("key failed") { app.status.hasPrefix("Hlasový klíč: ") }
        await eventually("poll error") { !rig.cat1.connected }
        fake.releaseAnswer()
        await eventually("old connection gone") { fake.openConnections == 0 }
        let before: Int = fake.commands.count
        rig.toggle(vfo: 0)
        await eventually("reconnected") { rig.cat1.connected && rig.cat1.state != nil }
        let fresh: [String] = Array(fake.commands.dropFirst(before))
        #expect(fresh.first == "T 0", "\(fresh)")
        #expect(app.keyer.voice.ptt.keyedLanes.isEmpty)
    }

    /// SO2R: rig 1's voice key fails and its `T 0` times out (rig 1 stays recorded as keyed); a message on rig 2 then
    /// keys and is released. Rig 2's record never overwrites rig 1's: the LED of rig 1 still sends `T 0` to rig 1.
    @Test func aVoiceKeyRecordOnOneRigSurvivesAKeyOnTheOther() async throws {
        let fake1 = try FakeRigctld(mode: "USB")
        let fake2 = try FakeRigctld(freqHz: 7_150_000, mode: "LSB")
        let app = try await Self.make(fake1, fake2, readTimeoutMs: 200)
        fake1.holdAnswer(to: "T 1")
        _ = app.keyer.voice.play([0], hisCall: "", freqHz: 14_250_000, opposite: false)
        await eventually("key failed") { app.status.hasPrefix("Hlasový klíč: ") }
        fake1.releaseAnswer()
        await eventually("cleanup received") { fake1.writes == ["T 1", "T 0"] }
        app.model.rig.activateVfo(1)
        _ = app.keyer.voice.play([0], hisCall: "", freqHz: 7_150_000, opposite: false)
        await eventually("rig 2 keyed") {
            fake2.writes.filter { $0.hasPrefix("T ") } == ["T 1"] && app.keyer.voice.playingKey == 0
        }
        #expect(app.entry.stopSending())
        await eventually("rig 2 released") { fake2.writes.filter { $0.hasPrefix("T ") } == ["T 1", "T 0"] }
        app.model.rig.toggle(vfo: 0)
        await eventually("rig 1 released again") { fake1.writes == ["T 1", "T 0", "T 0"] }
        await app.model.rig.settle()
        #expect(fake2.writes.filter { $0.hasPrefix("T ") } == ["T 1", "T 0"])
    }

    /// A Winkeyer carrier on that fails is switched off in the same job.
    @Test func failedWinkeyerTuneIsSwitchedOff() async throws {
        let app = try await KeyingApp.make(configure: { config, _ in winkeyerConfig(&config) })
        app.keyer.sendCwText("E")
        await app.settle()
        let keyer: FakeCwKeyer = try #require(app.keying.lastKeyer)
        keyer.failNextTune("Winkeyer neodpovídá")
        app.keyer.setTune(true)
        await app.settle()
        #expect(!app.keyer.isTuning)
        #expect(keyer.events.suffix(2) == ["tune on", "tune off"])
        #expect(app.status == "Ladění: Winkeyer neodpovídá")
    }

    // MARK: - M-4: a late tune failure

    /// A failure of an older tune that arrives after a newer tune started does not clear the newer one; its safeguard
    /// still switches the carrier off.
    @Test func lateTuneFailureKeepsTheNewerTune() async throws {
        let app = try await KeyingApp.make(configure: { config, _ in winkeyerConfig(&config) })
        app.keyer.sendCwText("E")
        await app.settle()
        let keyer: FakeCwKeyer = try #require(app.keying.lastKeyer)
        keyer.hold()
        app.keyer.sendCwText("TEST")
        keyer.failNextTune("Winkeyer neodpovídá")
        app.keyer.setTune(true)
        app.keyer.setTune(false)
        app.keyer.setTune(true)
        keyer.release()
        await app.settle()
        #expect(app.keyer.isTuning)
        // The failed older tune is switched off in its own job, before the newer tune's on.
        #expect(keyer.events.suffix(4) == ["tune on", "tune off", "tune off", "tune on"])
        app.clock.advance(by: 30_000)
        #expect(!app.keyer.isTuning)
        await app.settle()
        #expect(keyer.events.last == "tune off")
    }
}

/// A gate a task waits at until the test opens it (no thread is blocked).
@MainActor
final class HeldGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var opened = false

    var isWaiting: Bool {
        continuation != nil
    }

    func wait() async {
        if opened {
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.continuation = continuation
        }
    }

    func open() {
        opened = true
        continuation?.resume()
        continuation = nil
    }
}
