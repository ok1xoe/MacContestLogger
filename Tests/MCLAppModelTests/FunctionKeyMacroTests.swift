import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// The N1MM macros added beside the Java set, through the entry window and a fake Winkeyer: the actions
/// (`{CQ}`, `{EXCHSENT}`, `{FORCELOG}`, `{SPACE}`), `{COMMENT}`, the `{VARYMSGn}` counters and the last-QSO data.
@MainActor @Suite struct FunctionKeyMacroTests {

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

    private static func press(_ app: KeyingApp, _ index: Int) async {
        app.entry.handle(.functionKey(index, shift: false, ctrlShift: false))
        await app.model.entry.settle()
        await app.model.logbook.settle()
        await app.settle()
    }

    private static func setKey(_ app: KeyingApp, _ index: Int, _ text: String) {
        app.model.config.config.cwKeyer.spMessages[index] = FunctionKeyMessage(label: "K", text: text)
        app.model.config.config.cwKeyer.runMessages[index] = FunctionKeyMessage(label: "K", text: text)
    }

    /// `{CQ}` on another key works as F1: Run and the CQ frequency.
    @Test func cqMacroSwitchesToRun() async throws {
        let app = try await Self.make()
        Self.setKey(app, 9, "{CQ} CQ TEST *")
        #expect(app.model.operating.runMode == .searchAndPounce)
        await Self.press(app, 9)
        #expect(app.model.operating.runMode == .run)
        #expect(app.model.operating.cqFrequency(band: .m20) == 14_025_000)
    }

    /// `{EXCHSENT}` marks the exchange sent for ESM; `{SPACE}` moves on to the exchange.
    @Test func exchangeSentAndSpace() async throws {
        let app = try await Self.make()
        Self.setKey(app, 6, "! 5NN 15 {EXCHSENT}{SPACE}")
        app.entry.callChanged("DL1ABC")
        let focus: Int = app.entry.exchangeFocusRequest
        await Self.press(app, 6)
        #expect(app.entry.esmProgress.exchangeSent)
        #expect(app.entry.exchangeFocusRequest == focus + 1)
    }

    /// `{FORCELOG}` logs past the exchange check, with the forced note; `{COMMENT}` adds to the note first.
    @Test func forceLogWithComment() async throws {
        let app = try await Self.make()
        Self.setKey(app, 6, "TU {COMMENT loud} {FORCELOG}")
        app.entry.callChanged("DL1ABC")
        await Self.press(app, 6)
        #expect(app.model.logbook.rows.map(\.call) == ["DL1ABC"])
        #expect(app.model.logbook.rows.first?.comment == "loud")
    }

    /// `{COMMENT}` with an empty call field adds to the last logged QSO's note.
    @Test func commentGoesToTheLastQsoWhenTheFieldIsEmpty() async throws {
        let app = try await Self.make()
        app.entry.callChanged("DL1ABC")
        app.entry.editContestField("zone", "14")
        app.entry.submit()
        await app.model.entry.settle()
        await app.model.logbook.settle()
        Self.setKey(app, 6, "{COMMENT qsy 80}")
        await Self.press(app, 6)
        await app.model.logbook.settle()
        #expect(app.model.logbook.rows.last?.comment == "qsy 80")
    }

    /// `{VARYMSG1}`: the counter moves on with every send; the third send is the alternate one.
    @Test func varyMessageCountsSends() async throws {
        let app = try await Self.make()
        Self.setKey(app, 0, "{VARYMSG1 &CQ&CQ CQ&3&} TEST")
        for _ in 0..<3 {
            await Self.press(app, 0)
        }
        #expect(Self.sent(app).map { $0.replacingOccurrences(of: "@28", with: "") }
            == ["send CQ TEST", "send CQ TEST", "send CQ CQ TEST"])
        #expect(app.model.operating.varyCounts == [3, 0])
    }

    /// The last-QSO macros read the log.
    @Test func lastQsoMacros() async throws {
        let app = try await Self.make()
        app.entry.callChanged("DL1ABC")
        app.entry.editContestField("zone", "14")
        app.entry.submit()
        await app.model.entry.settle()
        await app.model.logbook.settle()
        Self.setKey(app, 6, "{LASTCALL} {LASTEXCH}")
        await Self.press(app, 6)
        #expect(Self.sent(app).last?.hasPrefix("send DL1ABC") == true)
    }
}
