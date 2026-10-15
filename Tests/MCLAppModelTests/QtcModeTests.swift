import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// WAE QTC from the entry window (N1MM): Ctrl+Z, `{DIGQTCR}` / `{DIGQTCS}`, `{QTC}`, the QTC window's message buttons
/// through the fake Winkeyer, the QTC setup and the band map's QTC colours. Nothing transmits by itself.
@MainActor @Suite struct QtcModeTests {

    private static func make(call: String = "OK1XOE", contest: String = "wae-cw",
                             edit: @escaping (inout AppConfig) -> Void = { _ in }) async throws -> KeyingApp {
        let app = try await KeyingApp.make(configure: { config, _ in
            winkeyerConfig(&config)
            config.station.call = call
            config.cwKeyer.runMessages[2] = FunctionKeyMessage(label: "TU", text: "TU")
            config.cwKeyer.runMessages[9] = FunctionKeyMessage(label: "QTC", text: "QTC {QTC} {DIGQTCS}")
            edit(&config)
        })
        let started: Bool = await app.model.contest.createAndStart(definitionId: contest, setup: ContestSetup())
        try #require(started, "activation failed: \(app.status)")
        app.entry.setMode(.cw)
        app.entry.setFrequency("14025")
        app.model.operating.select(.run, freqHz: 14_025_000)
        return app
    }

    private static func sent(_ app: KeyingApp) -> [String] {
        (app.keying.lastKeyer?.events ?? []).filter { $0.hasPrefix("send ") }
    }

    private var windowId: String { QtcModel.windowId }

    @Test func ctrlZOpensTheReceiveWindowInEuropeAndClosesIt() async throws {
        let app = try await Self.make()
        app.entry.callChanged("W1AW")
        app.entry.runShortcut(.qtcMode)
        #expect(app.model.windows.isOpen(windowId))
        #expect(!app.model.qtc.sendMode)
        #expect(app.model.qtc.partner == "W1AW")
        app.model.qtc.open()
        #expect(app.model.qtc.partner == "W1AW", "the window's opening keeps the partner Ctrl+Z set")
        await app.settle()
        #expect(Self.sent(app).isEmpty, "Ctrl+Z sends nothing unless asked to")
        app.entry.runShortcut(.qtcMode)
        #expect(!app.model.windows.isOpen(windowId))
        #expect(ShortcutAction.qtcMode.defaultKeys == "Ctrl+Z")
    }

    @Test func ctrlZAsksForQtcsWhenTheOptionIsOn() async throws {
        let app = try await Self.make(edit: { config in
            var setup = config.qtc
            setup.set(.ctrlZSendsAsk, flag: true)
            config.qtc = setup
        })
        app.entry.callChanged("W1AW")
        app.entry.runShortcut(.qtcMode)
        await app.settle()
        #expect(Self.sent(app).first?.hasPrefix("send QTC?") == true, "\(Self.sent(app))")
    }

    @Test func ctrlZOutsideEuropeLogsTheQsoAndOpensTheSendWindow() async throws {
        let app = try await Self.make(call: "W1AW")
        app.entry.callChanged("OK1ABC")
        app.entry.editContestField("nr", "5")
        app.entry.runShortcut(.qtcMode)
        await app.model.entry.settle()
        await app.model.logbook.settle()
        #expect(app.model.logbook.rows.map(\.call) == ["OK1ABC"])
        #expect(app.model.windows.isOpen(windowId))
        #expect(app.model.qtc.sendMode)
        #expect(app.model.qtc.partner == "OK1ABC")
    }

    @Test func ctrlZWithoutQtcInTheContestSaysSo() async throws {
        let app = try await Self.make(contest: "cq-ww-cw")
        app.entry.runShortcut(.qtcMode)
        #expect(!app.model.windows.isOpen(windowId))
        #expect(app.status == "Aktivní závod QTC nemá (WAE DX Contest).")
    }

    @Test func theMessageButtonsSendThroughTheEntryWindow() async throws {
        let app = try await Self.make()
        let qtc: QtcModel = app.model.qtc
        app.entry.callChanged("W1AW")
        app.entry.runShortcut(.qtcMode)
        #expect(qtc.messageKinds == [.ask, .ready, .confirm, .again(1), .receivedDone])
        qtc.received = "1234 DL1ABC 56\n1235 DL2XYZ 7"
        #expect(qtc.againNumber == 3)
        qtc.press(.ready)
        await app.settle()
        qtc.press(.again(qtc.againNumber))
        await app.settle()
        qtc.press(.receivedDone)
        await app.settle()
        let sent: [String] = Self.sent(app)
        #expect(sent.count == 3, "\(sent)")
        #expect(sent.first?.hasPrefix("send QRV") == true)
        #expect(sent.dropFirst().first?.hasPrefix("send AGN 3") == true)
        #expect(sent.last?.hasPrefix("send TU") == true, "an unset TU message sends the TU key")
        #expect(qtc.label(.receivedDone) == "TU")
    }

    /// Phone plays the wav file of the message through the voice keyer (here it is missing, so nothing keys).
    @Test func phonePlaysTheWavFile() async throws {
        let app = try await Self.make(contest: "wae-ssb")
        app.entry.setMode(.ssb)
        #expect(app.model.qtc.family == .phone)
        app.model.qtc.press(.ready)
        await app.settle()
        await app.settle()
        #expect(app.status.hasPrefix("QTC: chybí qtc-qrv.wav"), "\(app.status)")
        #expect(Self.sent(app).isEmpty)
    }

    @Test func aMessageNotSetForTheModeSaysSo() async throws {
        let app = try await Self.make(edit: { config in
            var setup = config.qtc
            setup.set(.cwConfirm, "")
            config.qtc = setup
        })
        app.model.qtc.press(.confirm)
        await app.settle()
        #expect(Self.sent(app).isEmpty)
        #expect(app.status == "QTC: zpráva Cfm není nastavená (Nastavení QTC)")
    }

    @Test func returnInTheHeaderSendsQrvOnlyWhenSetUp() async throws {
        let app = try await Self.make()
        app.model.qtc.headerSubmitted()
        await app.settle()
        #expect(Self.sent(app).isEmpty)
        app.model.qtc.setSetup(.cwQrvOnHeader, flag: true)
        app.model.qtc.headerSubmitted()
        await app.settle()
        #expect(Self.sent(app).first?.hasPrefix("send QRV") == true)
        #expect(await app.app.savedConfigFlushed().qtc.flag(.cwQrvOnHeader))
    }

    /// `{QTC}` is the header of the series in the open window; `{DIGQTCS}` opens it to send.
    @Test func qtcMacrosOfAnFKey() async throws {
        let app = try await Self.make()
        app.entry.callChanged("W1AW")
        app.entry.runShortcut(.qtcMode)
        app.model.qtc.group = "12"
        app.entry.handle(.functionKey(9, shift: false, ctrlShift: false))
        await app.settle()
        #expect(Self.sent(app).last?.hasPrefix("send QTC 12/10") == true, "\(Self.sent(app))")
        #expect(app.model.qtc.sendMode, "{DIGQTCS} switched the window to sending")
        #expect(app.model.windows.isOpen(windowId))
    }

    /// N1MM's band map colours: QTCs can pass with a station of another continent until the colour limit.
    @Test func theBandMapKnowsWhereQtcsAreLeft() async throws {
        let app = try await Self.make(edit: { config in
            var setup = config.qtc
            setup.set(.colorMax, "2")
            config.qtc = setup
        })
        let rules = try #require(app.model.contest.runtime.qtcConfig)
        #expect(app.model.bandmap.qtcLeft("W1AW", config: rules))
        #expect(!app.model.bandmap.qtcLeft("OK1ABC", config: rules), "Europe with Europe exchanges none")
        let lines = [QtcPlanner.Line(time: "1200", call: "DL1ABC", serial: 1),
                     QtcPlanner.Line(time: "1201", call: "DL2ABC", serial: 2)]
        #expect(await app.model.qtc.save(sent: false, partner: "W1AW", group: 1, lines: lines))
        #expect(!app.model.bandmap.qtcLeft("W1AW", config: rules))
    }
}
