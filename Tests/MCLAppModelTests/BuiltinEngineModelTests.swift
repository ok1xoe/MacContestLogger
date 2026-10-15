import Foundation
@testable import MCLAppModel
@testable import MCLCore
import RTTYSignalKit
import Testing

/// The RTTY engine pane under a receiver's text: the waterfall fed while shown, a click puts the mark there, shift,
/// speed, squelch and XY scope, and the receivers stay independent unless linked. Synthetic audio only.
@MainActor @Suite struct BuiltinEngineModelTests {

    private static func make() async throws -> KeyingApp {
        try await KeyingApp.make(configure: { config, _ in
            config.digital.engine = .builtin
        })
    }

    @Test func paneFollowsTheReceiverAndTunesIt() async throws {
        let app = try await Self.make()
        let digital: DigitalInterfaceModel = app.model.makeDigitalInterface()
        digital.open()
        await app.model.builtinModem.attach(0)
        await app.settle()
        #expect(digital.usesBuiltin)
        let engine: BuiltinEngineModel = app.model.makeBuiltinEngine(side: 0)
        engine.start()
        #expect(engine.tuning.markHz == 2125)
        let samples: [Double] = RTTYSignalGenerator(sampleRate: 12_000, markHz: 2125, amplitude: 0.3)
            .generate(text: "RYRYRYRYRYRY CQ TEST DL1ABC\r\n").map { Double($0) }
        try RadioSignals.feed(app, samples)
        app.radioClock.advance(by: 100)
        #expect(engine.frame > 0, "a waterfall row")
        #expect(engine.level > 0)
        engine.click(atFraction: engine.fraction(ofHz: 1500))
        #expect(abs(engine.tuning.markHz - 1500) < 1)
        #expect(app.model.builtinModem.channel(0).tuning.markHz == engine.tuning.markHz)
        #expect(app.model.builtinModem.channel(1).tuning.markHz == 2125, "receiver 2 is not touched")
        engine.setShift(425)
        engine.setBaud(75)
        #expect(engine.tuning.shiftHz == 425)
        #expect(engine.tuning.baud == 75)
        engine.setAfc(false)
        #expect(digital.isOn(.afc) == false, "the window's AFC button shows the receiver's state")
        digital.toggle(.afc)
        await app.settle()
        app.radioClock.advance(by: 100)
        #expect(engine.tuning.afc)
        engine.setSquelch(true)
        engine.adjustSquelch(steps: 2)
        #expect(engine.squelchOn)
        #expect(engine.squelchLevel == 600 + 2_048)
        engine.setXY(true)
        #expect(engine.xyEnabled)
        engine.setRange(from: 1_000, to: 2_500)
        #expect(engine.fromHz == 1_000 && engine.toHz == 2_500)
        #expect(abs(engine.hz(atFraction: 0.5) - 1_750) < 0.001)
        engine.stop()
        let frames: Int = engine.frame
        app.radioClock.advance(by: 500)
        #expect(engine.frame == frames, "no refresh after the pane closed")
        digital.close()
    }

    @Test func settingsReachTheHubAndReattachTheReceiver() async throws {
        let app = try await Self.make()
        let modem: BuiltinModemModel = app.model.builtinModem
        await modem.attach(1)
        #expect(app.model.audio.userNames == ["rtty2"])
        var setup: BuiltinModemSetup = app.model.config.config.builtinModem
        setup.set(.input2, BuiltinModemSetup.Input.radio2.rawValue)
        setup.set(.linkedTuning, flag: true)
        setup.set(.outputLevel, "80")
        app.model.config.config.builtinModem = setup
        for _ in 0..<5 {
            await Task.yield()
            await app.settle()
        }
        #expect(modem.hub.currentSettings.linked)
        #expect(modem.hub.currentSettings.level == 0.8)
        #expect(app.model.audio.userNames.isEmpty)
        #expect(app.model.audio2.userNames == ["rtty2"], "receiver 2 now listens to radio 2's input")
        modem.detach(1)
    }

    /// The pane's demodulator and profiles: saved from receiver 1, loaded onto receiver 2 only (independent tuning).
    @Test func demodulatorAndProfiles() async throws {
        let app = try await Self.make()
        let one: BuiltinEngineModel = app.model.makeBuiltinEngine(side: 0)
        let two: BuiltinEngineModel = app.model.makeBuiltinEngine(side: 1)
        one.start()
        two.start()
        one.setDemodulator("fir")
        one.setShift(850)
        #expect(one.demodulator == "fir")
        #expect(app.model.builtinModem.channel(1).choice("demodType") == "iir")
        one.saveProfile(2, name: "SITOR 850")
        #expect(one.profileError == nil)
        #expect(two.profiles[2]?.name == "SITOR 850")
        two.loadProfile(2)
        #expect(two.tuning.shiftHz == 850)
        #expect(two.demodulator == "fir")
        one.setShift(170)
        #expect(two.tuning.shiftHz == 850)
        one.deleteProfile(2)
        #expect(two.profiles[2] == nil)
        one.stop()
        two.stop()
    }

    /// The receiver's channel panel: on, the signals of its audio get channels; a click on a call fills that radio's
    /// entry window (through the Digital Interface); a click on the mark tunes the main receiver there; off on close.
    @Test func channelPanel() async throws {
        let app = try await Self.make()
        let digital: DigitalInterfaceModel = app.model.makeDigitalInterface()
        digital.open()
        await app.model.builtinModem.attach(0)
        let engine: BuiltinEngineModel = app.model.makeBuiltinEngine(side: 0)
        engine.start()
        engine.setChannels(true)
        var audio = [Double](repeating: 0, count: 0)
        let a = RTTYSignalGenerator(sampleRate: 12_000, markHz: 1115, amplitude: 0.2)
            .generate(text: "RYRYRYRYRYRYRYRY CQ DL2BBB DL2BBB\r\n", leadIn: 1.5)
        let b = RTTYSignalGenerator(sampleRate: 12_000, markHz: 1915, amplitude: 0.2)
            .generate(text: "RYRYRYRYRYRYRYRY CQ W3CCC W3CCC\r\n", leadIn: 1.5)
        audio = (0..<max(a.count, b.count)).map { index in
            Double(index < a.count ? a[index] : 0) + Double(index < b.count ? b[index] : 0)
        }
        try RadioSignals.feed(app, audio)
        app.model.builtinModem.banks[0].flush()
        app.radioClock.advance(by: 100)
        #expect(engine.channelRows.count == 2, "\(engine.channelRows)")
        let row = try #require(engine.channelRows.first { BuiltinEngineModel.calls(in: $0.text).contains("W3CCC") })
        digital.take("W3CCC")
        #expect(app.entry.form.call == "W3CCC")
        engine.tuneTo(row)
        #expect(abs(engine.tuning.markHz - row.markHz) < 1)
        engine.stop()
        #expect(!app.model.builtinModem.banks[0].configuration.enabled, "closing the pane stops the channels")
        digital.close()
    }
}
