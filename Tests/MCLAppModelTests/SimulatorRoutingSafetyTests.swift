import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// While a pileup simulation starts or runs, NOTHING keys the real rig — CW goes to the
/// simulator, voice, digital, tune and the footswitch PTT are refused with a status text — and nothing simulated leaves
/// the machine (see `SimulatorOutwardSafetyTests`). Releases are never gated. Only fakes: a recording Winkeyer, a fake
/// `rigctld` on a loopback port, a fake fldigi server, recording sound sinks — no device, no real rig.
@MainActor @Suite struct SimulatorRoutingSafetyTests {

    private static let refusal = "Simulátor běží — vysílání do TRX je zamčené (nejdřív ho zastav)"

    // MARK: - CW through a Winkeyer

    private static func cwApp() async throws -> SimulatorModelTests.Rig {
        try await SimulatorModelTests.make()
    }

    private static func cwQso(_ call: String = "DL1ABC") -> Qso {
        var qso = Qso()
        qso.call = call
        qso.mode = .cw
        qso.band = .m20
        return qso
    }

    private static func keyerSawNothing(_ rig: SimulatorModelTests.Rig, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(rig.app.keying.openedKeyers.isEmpty, "the Winkeyer was opened", sourceLocation: sourceLocation)
        #expect(rig.app.keying.events.isEmpty, "the keying hardware was touched", sourceLocation: sourceLocation)
        let sends: Int = rig.app.keying.lastKeyer?.events.filter { $0.hasPrefix("send") }.count ?? 0
        #expect(sends == 0, sourceLocation: sourceLocation)
    }

    /// F1, CW from the keyboard, the QTC series, PSE QSY and the CQ repeat all end in the sink; the key gets 0 bytes.
    /// After `stop` the same paths go through the TX gate to the key.
    @Test func everyCwPathGoesToTheSimulatorAndAfterStopToTheKey() async throws {
        let rig = try await Self.cwApp()
        await rig.start()
        let sink: RecordingSimAudio = try #require(rig.audio.sink)
        let model: AppModel = rig.app.model
        var played = 0

        // F1
        rig.pressF1()
        played += 1
        #expect(sink.plays.count == played)
        // CW from the keyboard (the CW keyboard window sends through `sendCwText`).
        model.keyer.sendCwText("TEST DE OK1XOE", call: "")
        played += 1
        #expect(sink.plays.count == played)
        // The QTC series.
        model.qtcSending.send(groupNr: 1, lines: [QtcPlanner.Line(time: "1202", call: "G3ABC", serial: 3)],
                              partner: " DL1ABC ")
        played += 1
        #expect(sink.plays.count == played)
        // PSE QSY for a CW QSO.
        model.moveMults.request(Self.cwQso(), band: "40m")
        played += 1
        #expect(sink.plays.count == played)
        #expect(rig.app.status == "DL1ABC: odesláno PSE QSY 40M")
        Self.keyerSawNothing(rig)

        // The CQ repeat sends F1 again and again — all into the sink (it waits for the lit key of the last message).
        rig.app.clock.advance(by: 120_000)
        played = sink.plays.count
        rig.app.entry.runShortcut(.cqRepeat)
        await runMainQueue()
        #expect(model.operating.cqRepeat)
        #expect(sink.plays.count == played + 1)
        played += 1
        rig.app.clock.advance(by: 120_000)
        await rig.app.settle()
        #expect(sink.plays.count > played)
        Self.keyerSawNothing(rig)

        // Stop: the CQ repeat is switched off by hand, the lamp is out, and a send goes to the real key.
        model.operating.applyCqRepeat(false)
        rig.simulator.stop()
        await rig.simulator.settle()
        #expect(rig.keyer.keyingRefusalForTests == nil)
        let before: Int = sink.plays.count
        rig.pressF1()
        await rig.app.settle()
        #expect(sink.plays.count == before)
        let key: FakeCwKeyer = try #require(rig.app.keying.lastKeyer)
        #expect(key.events.contains { $0.hasPrefix("send ") })
    }

    /// After `stop` the TX gate applies again: a lockout refuses the key.
    @Test func afterStopTheTxGateGuardsTheKey() async throws {
        let rig = try await Self.cwApp()
        await rig.start()
        rig.simulator.stop()
        rig.keyer.tx.txGate = { .verbatim("TX blokováno") }
        rig.pressF1()
        await rig.app.settle()
        #expect(rig.app.status == "TX blokováno")
        Self.keyerSawNothing(rig)
        rig.keyer.tx.txGate = { nil }
        rig.pressF1()
        await rig.app.settle()
        #expect(rig.app.keying.lastKeyer?.events.contains { $0.hasPrefix("send ") } == true)
    }

    /// While the output is still opening the gate is closed: a CW message is dropped with the lock text, never keyed.
    @Test func cwWhileTheOutputOpensIsDroppedNotKeyed() async throws {
        let rig = try await Self.cwApp()
        rig.audio.holdOpen()
        rig.simulator.start(settings: SimulatorModelTests.settings, noise: 0.15)
        rig.pressF1()
        await rig.app.settle()
        #expect(rig.app.status == Self.refusal)
        Self.keyerSawNothing(rig)
        rig.audio.releaseOpen()
        await rig.simulator.settle()
        #expect(rig.simulator.isOn)
        #expect(rig.audio.sink?.plays.isEmpty == true)
    }

    /// A message already being sent by the real key when the simulation starts is aborted at the start (a release),
    /// and Esc during the simulation still aborts an open key.
    @Test func startingTheSimulationStopsAMessageOnTheRealKey() async throws {
        let rig = try await Self.cwApp()
        rig.pressF1()
        await rig.app.settle()
        let key: FakeCwKeyer = try #require(rig.app.keying.lastKeyer)
        #expect(key.events.contains { $0.hasPrefix("send ") })
        await rig.start()
        await rig.app.settle()
        #expect(key.events.last == "abort")
        #expect(rig.keyer.cwSendingKey == nil)
    }

    // MARK: - voice, digital, tune and the footswitch through a CAT rig

    @MainActor private struct CatRig {
        let app: KeyingApp
        let audio: SimAudioFactory
        let rig: FakeRigctld
        let fldigi: FakeFldigiServer

        var simulator: SimulatorModel { app.model.simulator }
        var keyer: KeyerModel { app.keyer }

        func start() async {
            simulator.random = CountingPileupRandom()
            simulator.start(settings: SimulatorModelTests.settings, noise: 0.15)
            await simulator.settle()
        }
    }

    private static func catApp() async throws -> CatRig {
        let rig = try FakeRigctld(mode: "USB")
        let fldigi = try FakeFldigiServer()
        let audio = SimAudioFactory()
        let app = try await KeyingApp.make(configure: { config, dataDir in
            let wav: URL = dataDir.appendingPathComponent("wav")
            try FileManager.default.createDirectory(at: wav, withIntermediateDirectories: true)
            try Data([1]).write(to: wav.appendingPathComponent("cq.wav"))
            for set in [\VoiceKeyerConfig.runMessages, \VoiceKeyerConfig.spMessages] {
                var messages: [FunctionKeyMessage] = config.voiceKeyer[keyPath: set]
                messages[0] = FunctionKeyMessage(label: "CQ", text: "cq.wav")
                config.voiceKeyer[keyPath: set] = messages
            }
            config.voiceKeyer.outputDevice = "Fake Out"
            config.voiceKeyer.pttDelayMs = 0
            config.voiceKeyer.pttViaCat = true
            config.cwKeyer.method = .cat
            config.rig = fakeRigConfig(rig.port)
            config.digital.engine = .fldigi
            config.digital.fldigiHost = "127.0.0.1"
            config.digital.fldigiPort = fldigi.port
            config.footswitchAction = "PTT"
        }, setUp: { keying in
            keying.fldigiPort = fldigi.port
        }, adjust: { audio.install(into: &$0) })
        app.entry.setMode(.ssb)
        await app.connectRig(rig)
        return CatRig(app: app, audio: audio, rig: rig, fldigi: fldigi)
    }

    private static func pressVoiceF1(_ rig: CatRig) {
        rig.app.entry.handle(.functionKey(0, shift: false, ctrlShift: false))
    }

    /// Voice F1, the digital text, Ctrl+T and the footswitch press are refused with the status text: the rig gets no
    /// `T 1`, nothing plays, fldigi gets no call. After `stop` each of them works (the positive controls).
    @Test func voiceDigitalTuneAndFootswitchAreRefusedWhileItRuns() async throws {
        let cat = try await Self.catApp()
        defer { cat.fldigi.stop() }
        await cat.start()
        let model: AppModel = cat.app.model
        let status: StatusModel = model.status

        Self.pressVoiceF1(cat)
        #expect(cat.app.status == Self.refusal)
        #expect(!cat.keyer.voice.planning)
        #expect(cat.keyer.voice.playingKey == nil)

        status.clear()
        cat.keyer.digital.send("CQ TEST")
        #expect(cat.app.status == Self.refusal)
        #expect(!cat.keyer.digitalSending)

        status.clear()
        cat.keyer.setTune(true)
        #expect(cat.app.status == Self.refusal)
        #expect(!cat.keyer.isTuning)

        status.clear()
        model.rig.footswitch(true)
        #expect(cat.app.status == Self.refusal)
        #expect(model.rig.footswitchPttRig == nil)

        await cat.app.settle()
        await model.rig.settle()
        #expect(cat.rig.writes.isEmpty, "the rig was keyed: \(cat.rig.writes)")
        #expect(!cat.app.keying.events.contains { $0.hasPrefix("play") })
        #expect(cat.fldigi.methods.isEmpty)
        #expect(cat.app.keying.openedKeyers.isEmpty)

        // Stop: the same four go through (the TX gate is open).
        cat.simulator.stop()
        await cat.simulator.settle()
        Self.pressVoiceF1(cat)
        await eventually("voice keyed") { cat.rig.writes.contains("T 1") }
        await eventually("voice done") { cat.keyer.voice.playingKey == nil && !cat.keyer.voice.planning }
        await eventually("voice released") { cat.rig.writes == ["T 1", "T 0"] }
        cat.keyer.setTune(true)
        #expect(cat.keyer.isTuning)
        await eventually("carrier") { cat.rig.writes == ["T 1", "T 0", "T 1"] }
        cat.keyer.setTune(false)
        await eventually("carrier off") { cat.rig.writes.last == "T 0" }
        cat.keyer.digital.send("CQ TEST")
        await cat.app.settle()
        await eventually("fldigi called") { !cat.fldigi.methods.isEmpty }
        model.rig.footswitch(true)
        #expect(model.rig.footswitchPttRig != nil)
        model.rig.footswitch(false)
        await model.rig.settle()
    }

    /// Releases are never gated: a carrier on when the simulation starts is switched off (the start releases it), a
    /// footswitch PTT held across the start is released by its release edge, and tune-off is not refused.
    @Test func releasesAreNeverGated() async throws {
        let cat = try await Self.catApp()
        defer { cat.fldigi.stop() }
        let model: AppModel = cat.app.model
        // A carrier is on, then the simulation starts: the start switches it off.
        cat.keyer.setTune(true)
        await eventually("carrier") { cat.rig.writes == ["T 1"] }
        await cat.start()
        #expect(!cat.keyer.isTuning)
        await eventually("carrier released") { cat.rig.writes == ["T 1", "T 0"] }
        // tune off while the simulation runs is not refused (nothing to release, but the call is accepted silently).
        cat.keyer.setTune(false)
        // A footswitch PTT pressed before the simulation: its release goes to the rig while it runs.
        cat.simulator.stop()
        await cat.simulator.settle()
        model.rig.footswitch(true)
        await eventually("ptt on") { cat.rig.writes.suffix(1) == ["T 1"] }
        await cat.start()
        model.rig.footswitch(false)
        await model.rig.settle()
        await eventually("ptt released") { cat.rig.writes.suffix(2) == ["T 1", "T 0"] }
        #expect(model.rig.footswitchPttRig == nil)
        // The quit releases whatever is left (the transmit release is not gated either).
        await model.shutdown()
        #expect(cat.rig.writes.last == "T 0")
    }

    /// Esc while the simulation runs stops the simulation's sound, not the real key, and reports what was lit.
    @Test func escapeDuringTheSimulationTouchesNoRealKey() async throws {
        let cat = try await Self.catApp()
        defer { cat.fldigi.stop() }
        await cat.start()
        cat.app.entry.setMode(.cw)
        cat.app.entry.handle(.functionKey(0, shift: false, ctrlShift: false))
        #expect(cat.keyer.cwSendingKey == 0)
        #expect(cat.keyer.stopSending())
        #expect(cat.audio.sink?.clears == 1)
        await cat.app.model.rig.settle()
        #expect(cat.rig.writes.isEmpty)
    }
}

extension KeyerModel {
    /// What the keying paths ask first (`TxPorts.rigKeyingGate`).
    @MainActor var keyingRefusalForTests: EntryStatus? {
        tx.rigKeyingGate()
    }
}
