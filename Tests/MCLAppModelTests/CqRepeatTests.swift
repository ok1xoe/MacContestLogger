import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// The CQ repeat loop (`EP:757-768`) over the keyer clock: F1 again and again, typing a call pauses it,
/// clearing the call resumes it, Esc switches it off, a mode that cannot be keyed and a failed send stop it.
@MainActor @Suite struct CqRepeatTests {

    private static func make() async throws -> KeyingApp {
        let app = try await KeyingApp.make(configure: { config, _ in
            winkeyerConfig(&config)
            config.runMode.repeatSeconds = 2.0
        })
        app.entry.setMode(.cw)
        app.entry.setFrequency("14025")
        return app
    }

    private static func sends(_ app: KeyingApp) -> Int {
        (app.keying.lastKeyer?.events ?? []).filter { $0.hasPrefix("send ") }.count
    }

    private static func cqLength(_ app: KeyingApp) throws -> Int {
        var context: CwMessageBuilder.Context = try #require(app.keyer.messageContext())
        context.rst = "599"
        let text: String = app.model.config.config.cwKeyer.spMessages[0].text
        return Int(SendLamp.estimateMillis(CwMessageBuilder.build(text, context), wpm: 28))
    }

    /// Alt+R: F1 at once, 250 ms, the message's time, the pause, F1 again; Run follows the first CQ.
    @Test func callsCqAgainAndAgain() async throws {
        let app = try await Self.make()
        let length: Int = try Self.cqLength(app)
        app.entry.runShortcut(.cqRepeat)
        await runMainQueue()
        #expect(app.keyer.cwSendingKey == 0)
        await app.settle()
        #expect(Self.sends(app) == 1)
        #expect(app.model.operating.runMode == .run)
        app.clock.advance(by: 250)
        app.clock.advance(by: length)
        #expect(app.keyer.cwSendingKey == nil)
        app.clock.advance(by: 1_999)
        await app.settle()
        #expect(Self.sends(app) == 1)
        app.clock.advance(by: 1)
        await app.settle()
        #expect(Self.sends(app) == 2)
        #expect(app.model.operating.cqRepeat)
    }

    /// Typing a call pauses the loop (nothing is sent however long it waits), clearing it sends F1 at once; Esc
    /// switches the repeat off.
    @Test func typingPausesClearingResumesEscapeStops() async throws {
        let app = try await Self.make()
        app.entry.callChanged("DL1")
        app.entry.runShortcut(.cqRepeat)
        await runMainQueue()
        await app.settle()
        #expect(app.keying.openedKeyers.isEmpty)
        app.clock.advance(by: 60_000)
        await app.settle()
        #expect(app.keying.openedKeyers.isEmpty)
        app.entry.callChanged("")
        await runMainQueue()
        await app.settle()
        #expect(Self.sends(app) == 1)
        app.entry.callChanged("DL1ABC")
        await runMainQueue()
        app.clock.advance(by: 60_000)
        await app.settle()
        #expect(Self.sends(app) == 1)
        app.entry.callChanged("")
        await runMainQueue()
        await app.settle()
        #expect(Self.sends(app) == 2)
        #expect(app.entry.stopSending())
        #expect(!app.model.operating.cqRepeat)
        await runMainQueue()
        app.clock.advance(by: 60_000)
        await app.settle()
        #expect(Self.sends(app) == 2)
    }

    /// A mode that cannot be keyed (RTTY without fldigi) switches the repeat off at once and sends nothing,
    /// and it stays off when the mode becomes keyable again.
    @Test func notKeyableModeStopsTheRepeat() async throws {
        let app = try await Self.make()
        app.entry.setMode(.rtty)
        app.entry.runShortcut(.cqRepeat)
        await runMainQueue()
        #expect(!app.model.operating.cqRepeat)
        #expect(app.status == "Opakování CQ vypnuto")
        app.entry.setMode(.cw)
        await runMainQueue()
        app.clock.advance(by: 60_000)
        await app.settle()
        #expect(app.keying.openedKeyers.isEmpty)
    }

    /// A failed F1 (the keyer is off) switches the repeat off; the keyer's error stays in the status line.
    @Test func failedSendStopsTheRepeat() async throws {
        let app = try await Self.make()
        app.model.config.config.cwKeyer.method = .none
        app.entry.runShortcut(.cqRepeat)
        await runMainQueue()
        await app.settle()
        #expect(app.status == "CW: CW klíč je vypnutý (Nastavení → CW klíč)")
        app.clock.advance(by: 250)
        await app.settle()
        #expect(!app.model.operating.cqRepeat)
        #expect(app.status == "CW: CW klíč je vypnutý (Nastavení → CW klíč)")
        app.model.config.config.cwKeyer.method = .winkeyer
        app.clock.advance(by: 60_000)
        await app.settle()
        #expect(app.keying.openedKeyers.isEmpty)
    }

    /// The TX lockout (the gate) stops the repeat before F1 with the gate's text; post-contest entry switches
    /// it off (`AS:1832-1838`).
    @Test func lockoutAndPostContestStopTheRepeat() async throws {
        let app = try await Self.make()
        app.keyer.tx.txGate = { .verbatim("TX blokováno") }
        app.entry.runShortcut(.cqRepeat)
        await runMainQueue()
        #expect(!app.model.operating.cqRepeat)
        #expect(app.status == "TX blokováno")
        app.keyer.tx.txGate = { nil }
        app.entry.runShortcut(.cqRepeat)
        await runMainQueue()
        await app.settle()
        #expect(Self.sends(app) == 1)
        app.model.operating.setPostContest(true)
        await runMainQueue()
        #expect(!app.model.operating.cqRepeat)
        app.clock.advance(by: 60_000)
        await app.settle()
        #expect(Self.sends(app) == 1)
    }
}
