import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// The CW keyer (`AS:983-1011, 1443-1536, 1714-1799, 2106-2150`): the signature, the lane order, the lamp's token,
/// tuning with its 30 s safeguard, the speed, Esc and the reset. Only fakes: the Winkeyer opener returns a
/// `FakeCwKeyer`, CAT reaches a fake `rigctld` on a loopback port.
@MainActor @Suite struct KeyerModelTests {

    private static func estimate(_ app: KeyingApp, _ text: String, wpm: Int = 28) throws -> Int {
        var context: CwMessageBuilder.Context = try #require(app.keyer.messageContext())
        context.rst = "599"
        return Int(SendLamp.estimateMillis(CwMessageBuilder.build(text, context), wpm: wpm))
    }

    /// `cwKeyerOrOpen`: the keyer opens once per `method|port`; the speed is not part of the signature (`setSpeed`
    /// goes to the open keyer); another port closes the old keyer; method NONE closes it and fails with its text.
    @Test func signatureReopensOnlyForAnotherMethodOrPort() async throws {
        let app = try await KeyingApp.make(configure: { config, _ in winkeyerConfig(&config) })
        app.keyer.sendCwText("TEST")
        await app.settle()
        #expect(app.keying.events == ["winkeyer open fake-winkeyer 28"])
        let first: FakeCwKeyer = try #require(app.keying.lastKeyer)
        #expect(first.events == ["send TEST@28"])
        app.keyer.updateCwSpeed(30)
        app.keyer.sendCwText("AGN")
        await app.settle()
        #expect(app.keying.openedKeyers.count == 1)
        #expect(first.events == ["send TEST@28", "speed 30", "abort", "send AGN@30"])
        app.model.config.config.cwKeyer.winkeyerPort = "fake-winkeyer-2"
        app.keyer.sendCwText("QRL")
        await app.settle()
        #expect(app.keying.openedKeyers.count == 2)
        #expect(first.events.last == "close")
        #expect(app.keying.events.last == "winkeyer open fake-winkeyer-2 30")
        let second: FakeCwKeyer = try #require(app.keying.lastKeyer)
        app.model.config.config.cwKeyer.method = .none
        app.keyer.sendCwText("TU")
        await app.settle()
        #expect(second.events.last == "close")
        #expect(app.status == "CW: CW klíč je vypnutý (Nastavení → CW klíč)")
        #expect(app.keyer.cwSendingKey == nil)
    }

    /// Winkeyer without a port, and a port that cannot be opened: `"CW: " + message`, the lamp goes out, the send
    /// counts as failed.
    @Test func openFailuresShowTheCwPrefix() async throws {
        let app = try await KeyingApp.make(configure: { config, _ in
            config.cwKeyer.method = .winkeyer
            config.cwKeyer.winkeyerPort = "  "
        })
        app.keyer.sendCwText("TEST")
        #expect(app.keyer.cwSendingKey == -1)
        await app.settle()
        #expect(app.status == "CW: Winkeyer: vyber port v Nastavení → CW klíč")
        #expect(app.keyer.cwSendingKey == nil)
        #expect(app.keyer.sendFailures == 1)
        #expect(app.keying.events.isEmpty)
        app.model.config.config.cwKeyer.winkeyerPort = "fake-winkeyer"
        app.keying.failWinkeyer("Nelze otevřít port fake-winkeyer")
        app.keyer.sendCwText("TEST")
        await app.settle()
        #expect(app.status == "CW: Nelze otevřít port fake-winkeyer")
        #expect(app.keyer.sendFailures == 2)
    }

    /// `sendCw` with a message lit: the lane aborts the running message before the new one (`if (wasSending)
    /// keyer.abort()`), in that order even while the first send is still in the keyer.
    @Test func abortGoesBeforeTheNextSend() async throws {
        let app = try await KeyingApp.make(configure: { config, _ in winkeyerConfig(&config) })
        app.keyer.sendCwText("E")
        await app.settle()
        let keyer: FakeCwKeyer = try #require(app.keying.lastKeyer)
        keyer.hold()
        app.keyer.sendCwText("TEST")
        app.keyer.sendCwText("QRZ")
        keyer.release()
        await app.settle()
        #expect(keyer.events == ["send E@28", "abort", "send TEST@28", "abort", "send QRZ@28"])
    }

    /// The lamp goes out after the estimate of its own send only: a late end of an older send (an old token) leaves
    /// the newer lamp lit.
    @Test func lateCompletionWithAnOldTokenKeepsTheLamp() async throws {
        let app = try await KeyingApp.make(configure: { config, _ in winkeyerConfig(&config) })
        let short: Int = try Self.estimate(app, "E")
        let long: Int = try Self.estimate(app, "TEST TEST TEST")
        #expect(short < long)
        app.keyer.sendCw(CwMessageBuilder.build("E", try #require(app.keyer.messageContext())), key: 0)
        await app.settle()
        app.keyer.sendCw(CwMessageBuilder.build("TEST TEST TEST", try #require(app.keyer.messageContext())), key: 4)
        await app.settle()
        #expect(app.keyer.cwSendingKey == 4)
        app.clock.advance(by: short)
        #expect(app.keyer.cwSendingKey == 4)
        app.clock.advance(by: long - short - 1)
        #expect(app.keyer.cwSendingKey == 4)
        app.clock.advance(by: 1)
        #expect(app.keyer.cwSendingKey == nil)
    }

    /// Ctrl+T: the carrier on with its status and the 30 s safeguard (injected clock), off by the safeguard; a
    /// keyer that fails switches it off with `Ladění: …`.
    @Test func tuningSwitchesItselfOffAfterThirtySeconds() async throws {
        let app = try await KeyingApp.make(configure: { config, _ in winkeyerConfig(&config) })
        app.entry.runShortcut(.tune)
        #expect(app.keyer.isTuning)
        #expect(app.status == "LADĚNÍ — nosná (Ctrl+T nebo Esc ukončí, pojistka 30 s)")
        await app.settle()
        let keyer: FakeCwKeyer = try #require(app.keying.lastKeyer)
        #expect(keyer.events == ["tune on"])
        app.clock.advance(by: 29_999)
        #expect(app.keyer.isTuning)
        app.clock.advance(by: 1)
        #expect(!app.keyer.isTuning)
        #expect(app.status == "Ladění ukončeno")
        await app.settle()
        #expect(keyer.events == ["tune on", "tune off"])
        app.clock.advance(by: 60_000)
        await app.settle()
        #expect(keyer.events == ["tune on", "tune off"])

        app.model.config.config.cwKeyer.method = .none
        app.keyer.setTune(true)
        await app.settle()
        #expect(!app.keyer.isTuning)
        #expect(app.status == "Ladění: CW klíč je vypnutý (Nastavení → CW klíč)")
    }

    /// Esc in Kotlin's order: tuning first (the CQ repeat stays on); then the CQ repeat goes off and the lit CW
    /// message is aborted; with nothing lit an open keyer still gets `abort` and only the CQ repeat counts.
    @Test func escapeStopsInKotlinsOrder() async throws {
        let app = try await KeyingApp.make(configure: { config, _ in winkeyerConfig(&config) })
        app.keyer.setTune(true)
        app.model.operating.applyCqRepeat(true)
        #expect(app.entry.stopSending())
        #expect(!app.keyer.isTuning)
        #expect(app.model.operating.cqRepeat)
        await app.settle()
        let keyer: FakeCwKeyer = try #require(app.keying.lastKeyer)
        #expect(keyer.events == ["tune on", "tune off"])

        app.keyer.sendCwText("TEST")
        await app.settle()
        #expect(app.keyer.cwSendingKey == -1)
        #expect(app.entry.stopSending())
        #expect(!app.model.operating.cqRepeat)
        #expect(app.keyer.cwSendingKey == nil)
        await app.settle()
        #expect(keyer.events.suffix(2) == ["send TEST@28", "abort"])

        #expect(!app.entry.stopSending())
        await app.settle()
        #expect(keyer.events.last == "abort")
        #expect(keyer.events.filter { $0 == "abort" }.count == 2)
    }

    /// Without a keyer ever opened Esc aborts nothing (Kotlin `cwKeyer ?: return false`).
    @Test func escapeWithoutAnOpenKeyerTouchesNothing() async throws {
        let app = try await KeyingApp.make(configure: { config, _ in winkeyerConfig(&config) })
        #expect(!app.keyer.stopSending())
        await app.settle()
        #expect(app.keying.events.isEmpty)
    }

    /// PgUp/PgDn in CW: ± `cwSpeedStep`, clamped to 5…60, into the config without saving; the open keyer
    /// gets `setSpeed`; the Settings commit's `cwSpeed` port takes the configured speed.
    @Test func cwSpeedStepsClampAndAreNotSaved() async throws {
        let app = try await KeyingApp.make(configure: { config, _ in
            winkeyerConfig(&config)
            config.cwSpeedStep = 3
        })
        app.entry.setMode(.cw)
        app.entry.handle(.cwSpeed(1))
        #expect(app.keyer.cwSpeed == 31)
        #expect(app.model.config.config.cwKeyer.speed == 31)
        #expect(app.app.savedConfig().cwKeyer.speed == 28)
        app.keyer.sendCwText("TEST")
        await app.settle()
        app.entry.handle(.cwSpeed(-1))
        app.keyer.updateCwSpeed(100)
        #expect(app.keyer.cwSpeed == 60)
        app.keyer.updateCwSpeed(1)
        #expect(app.keyer.cwSpeed == 5)
        app.keyer.updateCwSpeed(5)
        await app.settle()
        let keyer: FakeCwKeyer = try #require(app.keying.lastKeyer)
        #expect(keyer.events == ["send TEST@31", "speed 28", "speed 60", "speed 5"])
        app.model.config.config.cwKeyer.speed = 40
        app.model.settings.services.cwSpeed()
        #expect(app.keyer.cwSpeed == 40)
    }

    /// RESETINTERFACES: the CW keyer is closed and opens again at the next send.
    @Test func resetInterfacesClosesTheKeyer() async throws {
        let app = try await KeyingApp.make(configure: { config, _ in winkeyerConfig(&config) })
        app.keyer.sendCwText("TEST")
        await app.settle()
        let first: FakeCwKeyer = try #require(app.keying.lastKeyer)
        app.model.rig.resetInterfaces()
        await app.settle()
        #expect(first.events.last == "close")
        #expect(app.status == "Rozhraní resetována (CW klíč se otevře při dalším vysílání)")
        app.keyer.sendCwText("AGN")
        await app.settle()
        #expect(app.keying.openedKeyers.count == 2)
    }

    /// CW over CAT reaches the active rig's `rigctld` (`KEYSPD`, `b`); without a rig `CW přes CAT: TRX není
    /// připojený`.
    @Test func catKeyerSendsThroughTheActiveRig() async throws {
        let fake = try FakeRigctld()
        let app = try await KeyingApp.make(configure: { config, _ in config.rig = fakeRigConfig(fake.port) })
        app.keyer.sendCwText("TEST")
        await app.settle()
        #expect(app.status == "CW: CW přes CAT: TRX není připojený")
        await app.connectRig(fake)
        app.keyer.sendCwText("TEST")
        await app.settle()
        await eventually("morse sent") { fake.writes.contains { $0.hasPrefix("b ") } }
        #expect(fake.writes.contains("L KEYSPD 28"))
        #expect(fake.writes.contains("b TEST"))
    }

    /// `requestMove`: CW sends „PSE QSY <kHz>" (the band's CQ frequency, else its last frequency, else the band);
    /// phone only tells what to ask for.
    @Test func requestMoveSendsOrHints() async throws {
        let app = try await KeyingApp.make(configure: { config, _ in winkeyerConfig(&config) })
        var qso = Qso()
        qso.call = "DL1ABC"
        qso.mode = .cw
        app.keyer.requestMove(qso, bandAdif: "20m")
        #expect(app.status == "DL1ABC: odesláno PSE QSY 20M")
        await app.settle()
        #expect(app.keying.lastKeyer?.events == ["send PSE QSY 20M@28"])
        app.model.operating.onCqSent(14_025_400)
        app.keyer.requestMove(qso, bandAdif: "20m")
        #expect(app.status == "DL1ABC: odesláno PSE QSY 14025")
        qso.mode = .ssb
        app.keyer.requestMove(qso, bandAdif: "20m")
        #expect(app.status == "DL1ABC: požádej o QSY na 14025.4 kHz (nový násobič)")
        app.keyer.requestMove(qso, bandAdif: "40m")
        #expect(app.status == "DL1ABC: požádej o QSY na 40m (nový násobič)")
        app.keyer.requestMove(qso, bandAdif: "nope")
        #expect(app.status == "DL1ABC: požádej o QSY na 40m (nový násobič)")
    }
}
