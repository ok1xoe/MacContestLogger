import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// "Odvysílat CW" of the QTC window (`QtcWindow.kt:83-85`): the series goes out as free CW text through the keyer to the
/// trimmed partner, and only when the button is pressed. A recording Winkeyer — nothing is keyed.
@MainActor @Suite struct QtcSendTests {

    private static let lines: [QtcPlanner.Line] = [
        QtcPlanner.Line(time: "1202", call: "G3ABC", serial: 3),
        QtcPlanner.Line(time: "1210", call: "DL1XYZ", serial: 7),
    ]

    private static func make() async throws -> KeyingApp {
        let app = try await KeyingApp.make(configure: { config, _ in
            winkeyerConfig(&config)
            config.cwKeyer.speed = 30
        })
        app.entry.setMode(.cw)
        return app
    }

    /// The text of the series header and the lines, built like any free CW text (macros, upper case).
    private static func expected(_ app: KeyingApp, partner: String) throws -> String {
        var context: CwMessageBuilder.Context = try #require(app.keyer.messageContext())
        context.hisCall = partner
        context.rst = "599"
        let text: String = QtcSession.cwSendText(groupNr: 2, lines: lines)
        return CwMessageBuilder.build(text, context).plainText()
    }

    @Test func theSeriesGoesOutAsFreeCwText() async throws {
        let app = try await Self.make()
        #expect(app.keying.openedKeyers.isEmpty)
        app.model.qtcSending.send(groupNr: 2, lines: Self.lines, partner: "  DL1ABC ")
        await app.settle()
        let key: FakeCwKeyer = try #require(app.keying.lastKeyer)
        let text: String = try Self.expected(app, partner: "DL1ABC")
        #expect(key.events.filter { $0.hasPrefix("send ") } == ["send \(text)@30"])
        #expect(text.contains("G3ABC"))
        #expect(app.keyer.cwSendingKey == -1)
    }

    /// The button is disabled for an empty series: nothing is sent, the keyer is not opened.
    @Test func anEmptySeriesSendsNothing() async throws {
        let app = try await Self.make()
        app.model.qtcSending.send(groupNr: 1, lines: [], partner: "DL1ABC")
        await app.settle()
        #expect(app.keying.openedKeyers.isEmpty)
        #expect(app.keyer.cwSendingKey == nil)
    }

    /// The TX lockout refuses it like any other CW (no simulation running).
    @Test func aTxLockoutRefusesIt() async throws {
        let app = try await Self.make()
        app.keyer.tx.txGate = { .verbatim("TX blokováno") }
        app.model.qtcSending.send(groupNr: 1, lines: Self.lines, partner: "DL1ABC")
        await app.settle()
        #expect(app.status == "TX blokováno")
        #expect(app.keying.openedKeyers.isEmpty)
    }
}
