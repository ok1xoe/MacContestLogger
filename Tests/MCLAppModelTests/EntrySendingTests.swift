import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// The entry window transmitting through the live keyer (`EP:719-755, 817-835, 953-1003`): ESM Enter sends and logs,
/// `=` repeats, the macro actions run after the send, and `onCqSent` follows F1 even when the TX gate refuses.
@MainActor @Suite struct EntrySendingTests {

    private static func make() async throws -> KeyingApp {
        let app = try await KeyingApp.make(configure: { config, _ in winkeyerConfig(&config) })
        try await app.app.startCqWwCw()
        app.entry.setMode(.cw)
        app.entry.setFrequency("14025")
        return app
    }

    private static func sent(_ app: KeyingApp) -> [String] {
        (app.keying.lastKeyer?.events ?? []).filter { $0.hasPrefix("send ") }
    }

    /// ESM in Run: Enter sends the call and the exchange, the next Enter sends TU and logs.
    @Test func esmEnterSendsAndLogs() async throws {
        let app = try await Self.make()
        app.model.operating.applyEsm(true)
        app.model.operating.select(.run, freqHz: 14_025_000)
        app.entry.callChanged("DL1ABC")
        app.entry.editContestField("zone", "14")
        app.entry.handle(.enter(ctrl: false, step: .esm))
        await app.settle()
        #expect(Self.sent(app).count == 1)
        #expect(app.model.operating.lastSentKeys.isEmpty == false)
        app.entry.handle(.enter(ctrl: false, step: .esm))
        await app.app.model.entry.settle()
        await app.model.logbook.settle()
        await app.settle()
        #expect(app.model.logbook.rows.map(\.call) == ["DL1ABC"])
        #expect(Self.sent(app).count == 2)
        // `=` repeats what was sent last.
        let last: [Int] = app.model.operating.lastSentKeys
        app.entry.handle(.resendLast)
        await app.settle()
        #expect(Self.sent(app).count == 3)
        #expect(app.model.operating.lastSentKeys == last)
    }

    /// A message with `{LOG}` sends its text and then logs (the action after the transmission).
    @Test func macroActionsRunAfterTheSend() async throws {
        let app = try await Self.make()
        app.model.config.config.cwKeyer.spMessages[2] = FunctionKeyMessage(label: "TU", text: "TU {LOG}")
        app.entry.callChanged("DL1ABC")
        app.entry.editContestField("zone", "14")
        app.entry.handle(.functionKey(2, shift: false, ctrlShift: false))
        await app.model.entry.settle()
        await app.model.logbook.settle()
        await app.settle()
        #expect(Self.sent(app) == ["send TU@28"])
        #expect(app.model.logbook.rows.map(\.call) == ["DL1ABC"])
    }

    /// F1 with the TX gate refusing: nothing is sent, the gate's text shows, and Kotlin's `onCqSent` still runs
    /// (Run and the CQ frequency follow even under the lockout).
    @Test func cqSentEvenWhenTheGateRefuses() async throws {
        let app = try await Self.make()
        app.keyer.tx.txGate = { .verbatim("TX blokováno") }
        app.entry.handle(.functionKey(0, shift: false, ctrlShift: false))
        #expect(app.status == "TX blokováno")
        #expect(app.model.operating.runMode == .run)
        #expect(app.model.operating.cqFrequency(band: .m20) == 14_025_000)
        await app.settle()
        #expect(app.keying.openedKeyers.isEmpty)
        #expect(app.model.operating.lastSentKeys == [0])
    }

    /// `KeyerPort.canSend` of the live keyer: the entry window's mode can be keyed.
    @Test func canSendFollowsTheKeyableMode() async throws {
        let app = try await Self.make()
        #expect(app.entry.ports.keyer.canSend)
        app.entry.setMode(.rtty)
        #expect(!app.entry.ports.keyer.canSend)
        app.model.config.config.digital.engine = .fldigi
        #expect(app.entry.ports.keyer.canSend)
    }
}
