import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// fldigi (`AS:1538-1618`): the text over XML-RPC on the keyer lane, the lamp shared with CW, the TX watch (500 ms,
/// at most 240 polls) and the errors. fldigi is a fake XML-RPC server on a loopback port.
@MainActor @Suite struct DigitalKeyerModelTests {

    /// Answers `main.get_trx_state` from a script (the last answer repeats).
    final class TrxScript: @unchecked Sendable {
        private let lock = NSLock()
        private var states: [String]
        private(set) var polls = 0

        init(_ states: [String]) {
            self.states = states
        }

        func next() -> String {
            lock.withLock {
                polls += 1
                return states.count > 1 ? states.removeFirst() : states[0]
            }
        }

        var pollCount: Int {
            lock.withLock { polls }
        }
    }

    private static func make(_ server: FakeFldigiServer) async throws -> KeyingApp {
        let app = try await KeyingApp.make(configure: { config, _ in
            config.digital.engine = .fldigi
            config.digital.fldigiHost = "127.0.0.1"
            config.digital.fldigiPort = server.port
        }, setUp: { keying in
            keying.fldigiPort = server.port
        })
        app.entry.setMode(.rtty)
        return app
    }

    private static func serve(_ server: FakeFldigiServer, _ script: TrxScript) {
        server.respond { method in
            method == "main.get_trx_state" ? (200, script.next()) : (200, "")
        }
    }

    /// F1: `" text "` to fldigi (clear, add with `^r`, TX), the lamp lit, `digitalSending`; after 500 ms the watch
    /// polls every 500 ms and the lamp goes out at the first state that is not `TX` — no further polls.
    @Test func transmitThenWatchUntilReceive() async throws {
        let server = try FakeFldigiServer()
        let script = TrxScript(["TX", "TX", "RX"])
        Self.serve(server, script)
        let app = try await Self.make(server)
        app.entry.callChanged("")
        app.entry.handle(.functionKey(0, shift: false, ctrlShift: false))
        #expect(app.keyer.cwSendingKey == 0)
        #expect(app.keyer.digitalSending)
        await app.settle()
        #expect(server.methods == ["text.clear_tx", "text.add_tx", "main.tx"])
        for _ in 0..<3 {
            app.clock.advance(by: 500)
            await app.settle()
        }
        #expect(script.pollCount == 3)
        #expect(app.keyer.cwSendingKey == nil)
        #expect(!app.keyer.digitalSending)
        app.clock.advance(by: 5_000)
        await app.settle()
        #expect(script.pollCount == 3)
        #expect(app.model.operating.runMode == .run)
    }

    /// fldigi that keeps transmitting: the watch gives up after 240 polls (2 minutes) and the lamp goes out.
    @Test func watchStopsAfterTwoHundredFortyPolls() async throws {
        let server = try FakeFldigiServer()
        let script = TrxScript(["TX"])
        Self.serve(server, script)
        let app = try await Self.make(server)
        app.model.digitalSendForTest("TEST", key: 2)
        await app.settle()
        for _ in 0..<240 {
            app.clock.advance(by: 500)
            await app.settle()
        }
        #expect(script.pollCount == 240)
        #expect(app.keyer.cwSendingKey == 2)
        app.clock.advance(by: 500)
        await app.settle()
        #expect(script.pollCount == 240)
        #expect(app.keyer.cwSendingKey == nil)
        #expect(!app.keyer.digitalSending)
    }

    /// An fldigi error: `fldigi: … (běží fldigi s XML-RPC na host:port?)`, the lamp out, the send failed.
    @Test func fldigiErrorShowsTheHint() async throws {
        let server = try FakeFldigiServer()
        server.respond { _ in (500, "") }
        let app = try await Self.make(server)
        app.model.digitalSendForTest("TEST", key: 0)
        await app.settle()
        #expect(app.status == "fldigi: fldigi: HTTP 500 (běží fldigi s XML-RPC na 127.0.0.1:\(server.port)?)")
        #expect(app.keyer.cwSendingKey == nil)
        #expect(!app.keyer.digitalSending)
        #expect(app.keyer.sendFailures == 1)
    }

    /// Esc while fldigi sends: `main.abort` + `text.clear_tx`, the lamp out, the watch ends without polling; Esc
    /// with nothing sent does not reach fldigi.
    @Test func escapeAbortsOnlyWhileSending() async throws {
        let server = try FakeFldigiServer()
        let script = TrxScript(["TX"])
        Self.serve(server, script)
        let app = try await Self.make(server)
        #expect(!app.keyer.digital.abort())
        app.model.digitalSendForTest("TEST", key: 0)
        await app.settle()
        #expect(app.entry.stopSending())
        #expect(app.keyer.cwSendingKey == nil)
        await app.settle()
        #expect(server.methods.suffix(2) == ["main.abort", "text.clear_tx"])
        app.clock.advance(by: 5_000)
        await app.settle()
        #expect(script.pollCount == 0)
    }

    /// A digital mode without fldigi sends nothing (`F%s: pro %s nastav fldigi …`).
    @Test func digitalModeWithoutFldigi() async throws {
        let app = try await KeyingApp.make()
        app.entry.setMode(.rtty)
        app.entry.handle(.functionKey(0, shift: false, ctrlShift: false))
        #expect(app.status == "F1: pro RTTY nastav fldigi (Nastavení → Digitální módy)")
        #expect(app.keyer.cwSendingKey == nil)
    }
}

extension AppModel {
    /// `sendDigitalText(text, index)` of a test.
    func digitalSendForTest(_ text: String, key: Int) {
        keyer.digital.send(text, key: key)
    }
}
