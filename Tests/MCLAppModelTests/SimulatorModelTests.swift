import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// The pileup simulator model (`AS:1646-1712`, `AS:2790-2795`): the sound port, start and stop, the routed CW, the
/// replies, the check of a logged QSO, Esc. The sound is a recording sink — never `SimAudioPlayer`, never a device.
@MainActor @Suite struct SimulatorModelTests {

    static let settings = PileupSimulator.Settings(activity: 6, minWpm: 22, maxWpm: 32, pitchSpreadHz: 300)

    @MainActor struct Rig {
        let app: KeyingApp
        let audio: SimAudioFactory

        var simulator: SimulatorModel { app.model.simulator }
        var keyer: KeyerModel { app.keyer }

        /// Starts the simulation and waits until the output opened.
        func start(noise: Float = 0.15) async {
            simulator.random = CountingPileupRandom()
            simulator.start(settings: SimulatorModelTests.settings, noise: noise)
            await simulator.settle()
        }

        func pressF1() {
            app.entry.handle(.functionKey(0, shift: false, ctrlShift: false))
        }
    }

    static func make(failing: String? = nil, mode: Mode = .cw) async throws -> Rig {
        let audio = SimAudioFactory()
        audio.fail(failing)
        let app = try await KeyingApp.make(configure: { config, _ in
            winkeyerConfig(&config)
            config.cwKeyer.speed = 30
            config.cwPitchHz = 650
        }, adjust: { audio.install(into: &$0) })
        app.entry.setMode(mode)
        app.entry.setFrequency("14025")
        return Rig(app: app, audio: audio)
    }

    // MARK: - the sound port

    /// The inert environment (the default of `Environment` and `MCL_INERT_HARDWARE`) hands out a silent sink: the
    /// simulator then runs logically, nothing is played and no device is touched.
    @Test func inertHardwareHasASilentSink() throws {
        #expect(try HardwarePorts.inert.makeSimAudio(0.15) is SilentSimAudio)
        let inertByVariable: HardwarePorts = .production(environment: [HardwarePorts.inertVariable: "1"])
        #expect(try inertByVariable.makeSimAudio(0.15) is SilentSimAudio)
    }

    @Test func theSimulatorRunsOverTheSilentSinkInAnInertApp() async throws {
        let app = try await TestApp.make()
        let simulator: SimulatorModel = app.model.simulator
        simulator.start(settings: Self.settings, noise: 0.2)
        await simulator.settle()
        #expect(simulator.isOn)
        #expect(app.model.status.message == "Simulátor běží — zavolej CQ (F1); bez master.scp jsou volačky smyšlené")
        simulator.stop()
        #expect(!simulator.isOn)
        await simulator.settle()
    }

    // MARK: - start and stop

    @Test func startOpensTheOutputWithTheNoiseAndShowsTheStartText() async throws {
        let rig = try await Self.make()
        #expect(!rig.simulator.isOn)
        await rig.start(noise: 0.25)
        #expect(rig.simulator.isOn)
        #expect(!rig.simulator.isStarting)
        #expect(rig.audio.requestedNoise == [0.25])
        #expect(rig.app.status == "Simulátor běží — zavolej CQ (F1); bez master.scp jsou volačky smyšlené")
        #expect(rig.simulator.checks.isEmpty)
        #expect(rig.simulator.qsos == 0)
        #expect(rig.simulator.errors == 0)
    }

    /// A failing output factory: the Kotlin text with the message, no session, keying is not locked.
    @Test func aFailedOutputShowsTheTextAndNothingRuns() async throws {
        let rig = try await Self.make(failing: "no device")
        await rig.start()
        #expect(!rig.simulator.isOn)
        #expect(!rig.simulator.isStarting)
        #expect(rig.app.status == "Simulátor: zvukový výstup nejde otevřít (no device)")
        #expect(rig.simulator.startNotice == "Simulátor: zvukový výstup nejde otevřít (no device)")
        #expect(rig.simulator.keyingRefusal == nil)
        #expect(rig.simulator.allowsOutwardEffects)
        #expect(rig.audio.sinks.isEmpty)
    }

    /// `close()` runs on the simulator's own lane, never on the main thread; a second start closes the first output.
    @Test func stopClosesTheOutputOffTheMainThread() async throws {
        let rig = try await Self.make()
        await rig.start()
        let first: RecordingSimAudio = try #require(rig.audio.sink)
        await rig.start()
        await rig.simulator.settle()
        #expect(first.closes == 1)
        let second: RecordingSimAudio = try #require(rig.audio.sink)
        #expect(second !== first)
        rig.simulator.stop()
        rig.simulator.stop()
        await rig.simulator.settle()
        #expect(second.closes == 1)
        #expect(first.closedOnMain + second.closedOnMain == [false, false])
        #expect(!rig.simulator.isOn)
    }

    /// Closing the window is a stop.
    @Test func closingTheWindowStops() async throws {
        let rig = try await Self.make()
        await rig.start()
        rig.simulator.windowClosed()
        #expect(!rig.simulator.isOn)
        await rig.simulator.settle()
        #expect(rig.audio.sink?.closes == 1)
    }

    @Test func theNoiseSliderReachesTheSink() async throws {
        let rig = try await Self.make()
        await rig.start()
        rig.simulator.setNoise(0.4)
        let level: Double = Double(Float(0.4))
        #expect(rig.audio.sink?.noiseLevels == [level])
        rig.simulator.stop()
        rig.simulator.setNoise(0.1)
        #expect(rig.audio.sink?.noiseLevels == [level])
    }

    /// While the output opens the gate is closed already; a stop meanwhile discards the late output and no session
    /// ever exists.
    @Test func aStopWhileTheOutputOpensDiscardsIt() async throws {
        let rig = try await Self.make()
        rig.audio.holdOpen()
        rig.simulator.start(settings: Self.settings, noise: 0.15)
        #expect(rig.simulator.isStarting)
        #expect(rig.simulator.keyingRefusal != nil)
        rig.simulator.stop()
        #expect(rig.simulator.keyingRefusal == nil)
        rig.audio.releaseOpen()
        await rig.simulator.settle()
        await rig.simulator.settle()
        #expect(!rig.simulator.isOn)
        #expect(rig.audio.sink?.closes == 1)
    }

    // MARK: - the routed CW and the replies

    /// F1 goes to the sink at amplitude 0.3 right away and lights the key; after the estimated sending time the key
    /// goes out and the callers answer. `CwSynth.render` at the keyer's speed and the configured pitch.
    @Test func cwIsRenderedAndTheStationsAnswerAfterTheEstimate() async throws {
        let rig = try await Self.make()
        await rig.start()
        let sink: RecordingSimAudio = try #require(rig.audio.sink)
        var context: CwMessageBuilder.Context = try #require(rig.keyer.messageContext())
        context.rst = "599"
        let text: String = rig.app.model.config.config.cwKeyer.spMessages[0].text
        let message: CwMessage = CwMessageBuilder.build(text, context)
        let length: Int = Int(SendLamp.estimateMillis(message, wpm: 30))
        rig.pressF1()
        #expect(rig.keyer.cwSendingKey == 0)
        let first: RecordingSimAudio.Played = try #require(sink.plays.first)
        #expect(first.delayMs == 0)
        #expect(first.peak > 0.25 && first.peak <= 0.3)
        let expected: [Float] = CwSynth.render(message.plainText(), wpm: 30, pitchHz: 650, amplitude: 0.3,
                                               sampleRate: SimAudioPlayer.sampleRate)
        #expect(first.samples == expected.count)
        rig.app.clock.advance(by: length - 1)
        #expect(rig.keyer.cwSendingKey == 0)
        #expect(sink.plays.count == 1)
        rig.app.clock.advance(by: 1)
        #expect(rig.keyer.cwSendingKey == nil)
        // Nothing reached the real keyer.
        #expect(rig.app.keying.openedKeyers.isEmpty)
        // Callers answer a CQ sooner or later; the replies are played after the message, at 0.1...0.5.
        var guardCount = 0
        while sink.plays.count == 1 && guardCount < 40 {
            rig.pressF1()
            rig.app.clock.advance(by: length)
            guardCount += 1
        }
        let reply: RecordingSimAudio.Played = try #require(sink.plays.dropFirst().first)
        #expect(reply.peak > 0.09 && reply.peak <= 0.5)
        #expect(reply.delayMs >= 0)
        #expect(rig.app.keying.openedKeyers.isEmpty)
    }

    /// A newer message makes the older one's reply timer void (`cwToken` moved on).
    @Test func aNewerMessageVoidsTheOlderOnesReply() async throws {
        let rig = try await Self.make()
        await rig.start()
        let sink: RecordingSimAudio = try #require(rig.audio.sink)
        rig.pressF1()
        rig.app.clock.advance(by: 100)
        rig.pressF1()
        #expect(sink.plays.count == 2)
        rig.app.clock.advance(by: 120_000)
        #expect(rig.keyer.cwSendingKey == nil)
        #expect(rig.app.keying.openedKeyers.isEmpty)
    }

    // MARK: - a service switched on during the run

    /// Club Log configured while the simulation runs: within a second the simulation stops, with a status text.
    @Test func aServiceSwitchedOnDuringTheRunStopsTheSimulation() async throws {
        let rig = try await Self.make()
        await rig.start()
        rig.app.clock.advance(by: 1_000)
        #expect(rig.simulator.isOn)
        rig.app.model.config.config.clubLog.enabled = true
        rig.app.model.config.config.clubLog.email = "user@example.test"
        rig.app.model.config.config.clubLog.appPassword = "secret-password"
        rig.app.model.config.config.clubLog.apiKey = "secret-apikey"
        rig.app.clock.advance(by: 1_000)
        #expect(!rig.simulator.isOn)
        #expect(rig.simulator.keyingRefusal == nil)
        #expect(rig.app.status == "Simulátor zastaven: zapnula se služba Club Log — použij zkušební závod bez služeb")
        await rig.simulator.settle()
        #expect(rig.audio.sink?.closes == 1)
    }

    // MARK: - Esc

    /// Esc clears the sink and reports whether a message was lit (so Esc does not "stop nothing" and the key stays
    /// out of it); with nothing lit it still clears and answers `false`.
    @Test func escapeClearsTheSinkAndReportsWhatWasLit() async throws {
        let rig = try await Self.make()
        await rig.start()
        let sink: RecordingSimAudio = try #require(rig.audio.sink)
        rig.pressF1()
        #expect(rig.keyer.cwSendingKey == 0)
        #expect(rig.keyer.stopSending())
        #expect(sink.clears == 1)
        #expect(rig.keyer.cwSendingKey == nil)
        // The timer of the aborted message does nothing.
        rig.app.clock.advance(by: 120_000)
        #expect(sink.plays.count == 1)
        #expect(!rig.keyer.stopSending())
        #expect(sink.clears == 2)
        #expect(rig.app.keying.openedKeyers.isEmpty)
        #expect(!rig.app.keying.events.contains { $0.hasPrefix("winkeyer") })
    }

    /// Stopping the simulation turns a lit simulated key off (Kotlin leaves it lit).
    @Test func stopPutsTheSimulatedKeyOut() async throws {
        let rig = try await Self.make()
        await rig.start()
        rig.pressF1()
        #expect(rig.keyer.cwSendingKey == 0)
        rig.simulator.stop()
        #expect(rig.keyer.cwSendingKey == nil)
    }

    // MARK: - the lockout and the log

    /// Kotlin order: the simulator takes the CW before the TX gate, so a lockout does not stop it.
    @Test func aTxLockoutDoesNotStopTheSimulator() async throws {
        let rig = try await Self.make()
        await rig.start()
        let sink: RecordingSimAudio = try #require(rig.audio.sink)
        rig.keyer.tx.txGate = { .verbatim("TX blokováno") }
        rig.pressF1()
        #expect(sink.plays.count == 1)
        #expect(rig.keyer.cwSendingKey == 0)
        #expect(rig.app.status != "TX blokováno")
        #expect(rig.app.keying.openedKeyers.isEmpty)
    }

    /// A QSO logged by the operator is checked against the worked station and counted (`AS:2790-2795`); an import is
    /// not, and the counters and the list reset with a new start.
    @Test func aLoggedQsoIsCheckedAndImportsAreNot() async throws {
        let rig = try await Self.make()
        try await rig.app.app.startCqWwCw()
        await rig.start()
        await rig.app.app.logContestQso(call: "DL1ABC", zone: "14")
        await rig.app.settle()
        #expect(rig.simulator.checks.count == 1)
        let check: PileupSimulator.Check = try #require(rig.simulator.checks.first)
        #expect(check.loggedCall == "DL1ABC")
        #expect(check.expectedCall.isEmpty)
        #expect(!check.ok)
        #expect(rig.simulator.qsos == 1)
        #expect(rig.simulator.errors == 1)
        // A second QSO: newest first.
        await rig.app.app.logContestQso(call: "OK2XYZ", zone: "15")
        #expect(rig.simulator.checks.map(\.loggedCall) == ["OK2XYZ", "DL1ABC"])
        // An import goes through the pipeline without the simulator effect.
        var imported = Qso()
        imported.call = "SP9AAA"
        let context = QsoLogPipeline.Context(activeContestId: rig.app.model.contest.activeId, operatorCall: "OK1XOE",
                                             simulatorActive: true)
        let (prepared, effects) = QsoLogPipeline.plan(qso: imported, isImported: true, context: context)
        #expect(!effects.contains(.simulator))
        try await rig.app.model.logbook.perform(prepared, effects: effects)
        #expect(rig.simulator.checks.count == 2)
        #expect(rig.simulator.qsos == 2)
        await rig.start()
        #expect(rig.simulator.checks.isEmpty)
        #expect(rig.simulator.qsos == 0)
    }
}
