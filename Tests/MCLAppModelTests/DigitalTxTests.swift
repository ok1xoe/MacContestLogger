import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// Transmitting from the Digital Interface (N1MM): a held transmission (`{TX}` without `{RX}`, Alt+T, Ctrl+K, the TX
/// window), Esc, the CW ID with the modem restored, the message buttons, `{CLRRX}`, `{NAME}`, sending a text file and
/// the RX text written to a file. Fake fldigi on loopback; the TX watch runs on the manual keyer clock.
@MainActor @Suite struct DigitalTxTests {

    /// fldigi that reports TX until told otherwise.
    final class Fldigi: @unchecked Sendable {
        private let lock = NSLock()
        private var trx = "RX"
        private var modem = "RTTY"
        private var rx = ""

        func set(trx state: String) {
            lock.withLock { trx = state }
        }

        func receive(_ text: String) {
            lock.withLock { rx += text }
        }

        func answer(_ method: String) -> (status: Int, value: String) {
            lock.withLock {
                switch method {
                case "main.get_trx_state": return (200, trx)
                case "modem.get_name": return (200, modem)
                case "text.get_rx_length": return (200, String(rx.utf16.count))
                case "text.get_rx": return (200, rx)
                default: return (200, "")
                }
            }
        }
    }

    private static func make(_ fldigi: Fldigi, configure: @escaping (inout AppConfig) -> Void = { _ in }) async throws
        -> (KeyingApp, FakeFldigiServer) {
        let server = try FakeFldigiServer()
        server.respond { fldigi.answer($0) }
        let app = try await KeyingApp.make(configure: { config, _ in
            config.digital.engine = .fldigi
            config.digital.fldigiHost = "127.0.0.1"
            config.digital.fldigiPort = server.port
            config.station.call = "OK1XOE"
            configure(&config)
        }, setUp: { keying in
            keying.fldigiPort = server.port
        })
        app.entry.setMode(.rtty)
        app.entry.setFrequency("14080")
        return (app, server)
    }

    private static func added(_ server: FakeFldigiServer) -> [String] {
        server.requests.filter { $0.contains("text.add_tx") }.map { request in
            guard let start = request.range(of: "<string>"), let end = request.range(of: "</string>") else { return "" }
            return String(request[start.upperBound..<end.lowerBound])
        }
    }

    /// Runs the TX watch with fldigi back on receive.
    private static func finishWatch(_ app: KeyingApp, _ fldigi: Fldigi) async {
        fldigi.set(trx: "RX")
        for _ in 0..<4 {
            app.clock.advance(by: 500)
            await app.settle()
        }
    }

    @Test func txWithoutRxHoldsUntilAltT() async throws {
        let fldigi = Fldigi()
        let (app, server) = try await Self.make(fldigi) { config in
            config.digital.runMessages[0] = FunctionKeyMessage(label: "CQ", text: "{TX} CQ TEST *")
            config.digital.spMessages[0] = FunctionKeyMessage(label: "CQ", text: "{TX} CQ TEST *")
        }
        fldigi.set(trx: "TX")
        app.entry.handle(.functionKey(0, shift: false, ctrlShift: false))
        await app.settle()
        #expect(Self.added(server) == [" CQ TEST OK1XOE "], "no ^r: fldigi keeps transmitting")
        #expect(app.keyer.digital.isHolding)
        #expect(app.keyer.digitalSending)
        // Typing in the TX window goes out at once.
        app.keyer.digital.typeHeld("TU")
        await app.settle()
        #expect(Self.added(server).last == "TU")
        // Alt+T: back to receive after the text (^r), the lamp goes out with the watch.
        app.entry.runShortcut(.toggleTx)
        await app.settle()
        #expect(Self.added(server).last == "^r")
        await Self.finishWatch(app, fldigi)
        #expect(!app.keyer.digitalSending)
        #expect(!app.keyer.digital.isHolding)
    }

    @Test func escapeEndsAHeldTransmission() async throws {
        let fldigi = Fldigi()
        let (app, server) = try await Self.make(fldigi)
        fldigi.set(trx: "TX")
        app.entry.runShortcut(.toggleTx)
        await app.settle()
        #expect(server.methods.contains("main.tx"))
        #expect(app.keyer.digital.isHolding)
        #expect(app.entry.stopSending())
        await app.settle()
        #expect(server.methods.contains("main.abort"))
        #expect(!app.keyer.digital.isHolding)
        #expect(!app.keyer.digitalSending)
    }

    /// Ctrl+K in a digital mode opens the Digital Interface, transmits and focuses its TX window.
    @Test func ctrlKOpensTheTxWindow() async throws {
        let fldigi = Fldigi()
        let (app, server) = try await Self.make(fldigi)
        let focus: Int = app.keyer.digital.txFocusRequest
        app.entry.runShortcut(.cwKeyboard)
        await app.settle()
        #expect(app.model.windows.isOpen("digitalinterface"))
        #expect(app.keyer.digital.isHolding)
        #expect(app.keyer.digital.txFocusRequest == focus + 1)
        #expect(app.entry.stopSending())
        _ = server
    }

    /// CWID: after the message fldigi sends the ID in CW, then the previous modem is restored and the lamp goes out.
    @Test func cwIdFollowsTheMessage() async throws {
        let fldigi = Fldigi()
        let (app, server) = try await Self.make(fldigi) { config in
            config.digital.cwIdEnabled = true
            config.digital.runMessages[0] = FunctionKeyMessage(label: "CQ", text: "CQ TEST")
            config.digital.spMessages[0] = FunctionKeyMessage(label: "CQ", text: "CQ TEST")
        }
        fldigi.set(trx: "TX")
        app.entry.handle(.functionKey(0, shift: false, ctrlShift: false))
        await app.settle()
        await Self.finishWatch(app, fldigi)
        let modems: [String] = server.requests.filter { $0.contains("modem.set_by_name") }
        #expect(modems.count == 2)
        #expect(modems.first?.contains("CW") == true && modems.last?.contains("RTTY") == true)
        #expect(Self.added(server).contains(" DE OK1XOE ^r"))
        #expect(!app.keyer.digitalSending)
    }

    @Test func buttonsClearRxNameAndTextFile() async throws {
        let fldigi = Fldigi()
        let (app, server) = try await Self.make(fldigi) { config in
            config.digital.diButtonCount = 8
            var buttons: [FunctionKeyMessage] = DigitalConfig.emptyButtons()
            buttons[0] = FunctionKeyMessage(label: "Hi", text: "{TX} ! {DI2} {RX}")
            buttons[1] = FunctionKeyMessage(label: "Name", text: "GL {NAME}")
            buttons[2] = FunctionKeyMessage(label: "Clr", text: "{CLRRX}")
            config.digital.diMessages = buttons
        }
        app.model.callData.adoptCallHistory(CallHistory.parse(["!!Order!!,Call,Name", "DL1ABC,HANS"]), path: "")
        let digital: DigitalInterfaceModel = app.model.makeDigitalInterface()
        // The text is there before the window's first poll (no race with the poll on a slow runner).
        fldigi.receive("CQ DE DL1ABC ")
        digital.open()
        await app.settle()
        #expect(!digital.text.isEmpty)
        #expect(digital.buttons.count == 8)
        app.entry.callChanged("DL1ABC")
        digital.pressButton(0)
        await app.settle()
        #expect(Self.added(server).last == " DL1ABC GL HANS ^r")
        digital.pressButton(2)
        #expect(digital.text.isEmpty)
        // Send Text File.
        let file: URL = app.app.dir.url.appendingPathComponent("send.txt")
        try Data("HELLO\nWORLD".utf8).write(to: file)
        await Self.finishWatch(app, fldigi)
        digital.sendTextFile(file)
        await app.settle()
        #expect(Self.added(server).last == " HELLO\nWORLD ^r")
        digital.close()
    }

    @Test func receivedTextIsWrittenToAFile() async throws {
        let fldigi = Fldigi()
        let (app, server) = try await Self.make(fldigi) { config in
            config.digital.rxOutputToFile = true
        }
        let digital: DigitalInterfaceModel = app.model.makeDigitalInterface()
        fldigi.receive("CQ DE DL1ABC ")
        digital.open()
        await app.settle()
        #expect(digital.text == "CQ DE DL1ABC ")
        let log: DigitalRxLog = try #require(digital.rxLog)
        await log.flush()
        let written: String = try String(contentsOf: log.file(for: Date()), encoding: .utf8)
        #expect(written == "CQ DE DL1ABC ")
        digital.close()
        _ = server
    }
}
