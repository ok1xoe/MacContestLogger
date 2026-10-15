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
}
