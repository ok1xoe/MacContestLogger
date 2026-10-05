import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// The Digital Interface window (`DigitalInterfaceWindow.kt`): the 300 ms poll of fldigi on the keyer lane (a fake
/// XML-RPC server on a loopback port), the hint without a modem, the restart on a new address (generation), the
/// recent calls, the clickable calls and exchange words, and the keys forwarded to the entry window.
@MainActor @Suite struct DigitalInterfaceModelTests {

    /// fldigi's RX buffer: `text.get_rx_length` gives its length, `text.get_rx` the part not served yet.
    final class RxBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var content: String = ""
        private var served: Int

        /// `served`: the part fldigi already gave out (the window asks only for what follows).
        init(served: Int = 0) {
            self.served = served
        }

        func receive(_ text: String) {
            lock.withLock { content += text }
        }

        func answer(_ method: String) -> (status: Int, value: String) {
            lock.withLock {
                switch method {
                case "text.get_rx_length":
                    return (200, String(content.utf16.count))
                case "text.get_rx":
                    let units = Array(content.utf16)
                    let part = String(decoding: units[served...], as: UTF16.self)
                    served = units.count
                    return (200, part)
                case "modem.get_name":
                    return (200, "RTTY")
                case "main.get_trx_state":
                    return (200, "RX")
                default:
                    return (200, "")
                }
            }
        }
    }

    private static func make(_ server: FakeFldigiServer?, engine: DigitalConfig.Engine = .fldigi,
                             contest: Bool = false) async throws -> KeyingApp {
        let app = try await KeyingApp.make(configure: { config, _ in
            config.digital.engine = engine
            config.digital.fldigiHost = "127.0.0.1"
            config.digital.fldigiPort = server?.port ?? 1
            winkeyerConfig(&config)
        }, setUp: { keying in
            keying.fldigiPort = server?.port
        })
        if contest {
            var setup = ContestSetup()
            setup.sentExchange = ["zone": "15"]
            #expect(await app.model.contest.createAndStart(definitionId: "cq-ww-rtty", setup: setup))
        }
        return app
    }

    private static func serve(_ server: FakeFldigiServer, _ buffer: RxBuffer) {
        server.respond { method in buffer.answer(method) }
    }

    /// The first poll at once: the text, the status „modem · trx", the recent calls without the own one; the next
    /// poll after 300 ms reads only what is new.
    @Test func pollsWhileOpen() async throws {
        let server = try FakeFldigiServer()
        let buffer = RxBuffer()
        Self.serve(server, buffer)
        let received: String = "CQ CQ DE DL1ABC DL1ABC K\nOK1XOE DE DL1ABC 599 14\n"
        buffer.receive(received)
        let app = try await Self.make(server)
        let digital: DigitalInterfaceModel = app.model.makeDigitalInterface()
        digital.open()
        await app.settle()
        #expect(digital.text == received)
        #expect(digital.status == "RTTY · RX")
        #expect(digital.error == nil)
        #expect(digital.recentCalls == ["DL1ABC"])
        let firstPoll: [String] = ["text.get_rx_length", "text.get_rx", "modem.get_name", "main.get_trx_state"]
        #expect(server.methods == firstPoll)
        buffer.receive("TU OK2XYZ ")
        app.radioClock.advance(by: 300)
        await app.settle()
        #expect(digital.text.hasSuffix("TU OK2XYZ "))
        #expect(digital.recentCalls == ["DL1ABC", "OK2XYZ"])
        app.radioClock.advance(by: 300)
        await app.settle()
        // Nothing new: no `text.get_rx`.
        let quietPoll: [String] = ["text.get_rx_length", "modem.get_name", "main.get_trx_state"]
        #expect(Array(server.methods.suffix(3)) == quietPoll)
        digital.close()
    }

    /// Nothing is polled after the window closed; „Vymazat" empties the window (fldigi's position stays, the old
    /// text is not read again).
    @Test func closeStopsThePollAndClearEmpties() async throws {
        let server = try FakeFldigiServer()
        let buffer = RxBuffer()
        Self.serve(server, buffer)
        buffer.receive("CQ DE DL1ABC K ")
        let app = try await Self.make(server)
        let digital: DigitalInterfaceModel = app.model.makeDigitalInterface()
        digital.open()
        await app.settle()
        digital.clear()
        #expect(digital.text.isEmpty)
        #expect(digital.recentCalls.isEmpty)
        app.radioClock.advance(by: 300)
        await app.settle()
        #expect(digital.text.isEmpty)
        digital.close()
        let count: Int = server.methods.count
        app.radioClock.advance(by: 3_000)
        await app.settle()
        #expect(server.methods.count == count)
        #expect(app.radioClock.pendingCount == 0)
    }

    /// Without a modem: the hint, no status, no XML-RPC, checked again after 1 s.
    @Test func noModem() async throws {
        let app = try await Self.make(nil, engine: .none)
        let digital: DigitalInterfaceModel = app.model.makeDigitalInterface()
        digital.open()
        #expect(digital.error?.czech == "Modem není nastavený — Nastavení → Digitální módy → Modem pro RTTY / PSK.")
        #expect(digital.status.isEmpty)
        app.radioClock.advance(by: 999)
        #expect(app.radioClock.pendingCount == 1)
        app.radioClock.advance(by: 1)
        #expect(app.radioClock.pendingCount == 1)
        digital.close()
        #expect(app.radioClock.pendingCount == 0)
    }

    /// fldigi not answering: `fldigi nedostupné (host:port): message`, no status; the poll goes on.
    @Test func fldigiUnavailable() async throws {
        let app = try await Self.make(nil)
        let digital: DigitalInterfaceModel = app.model.makeDigitalInterface()
        digital.open()
        await app.settle()
        #expect(digital.error?.czech == "fldigi nedostupné (127.0.0.1:1): null")
        #expect(digital.status.isEmpty)
        #expect(app.radioClock.pendingCount == 1)
        digital.close()
    }

    /// A new host or port restarts the loop at once on the new address (a new generation); the old address is not
    /// polled any more.
    @Test func newAddressRestartsTheLoop() async throws {
        let first = try FakeFldigiServer()
        let second = try FakeFldigiServer()
        let one = RxBuffer()
        one.receive("OK2AAA ")
        let two = RxBuffer(served: 7)
        two.receive("1234567OK2BBB ")
        Self.serve(first, one)
        Self.serve(second, two)
        let app = try await Self.make(first)
        let digital: DigitalInterfaceModel = app.model.makeDigitalInterface()
        digital.open()
        await app.settle()
        #expect(digital.text == "OK2AAA ")
        let generation: Int = digital.generation
        app.keying.fldigiPort = second.port
        app.model.config.config.digital.fldigiPort = second.port
        await eventually("restarted") { digital.generation == generation + 1 }
        await app.settle()
        #expect(digital.text == "OK2AAA OK2BBB ")
        let polled: Int = first.methods.count
        app.radioClock.advance(by: 300)
        await app.settle()
        #expect(first.methods.count == polled)
        #expect(second.methods.count == 7)
        // Another change that keeps engine, host and port does not restart.
        app.model.config.config.cwPitchHz = 650
        await runMainQueue()
        await runMainQueue()
        #expect(digital.generation == generation + 1)
        digital.close()
    }

    /// The underlined words: calls (not the own one) and the words the contest takes as exchange fields, routed by
    /// the call on their line; a click puts a call into the call field, an exchange word into its field.
    @Test func spansAndTaps() async throws {
        let server = try FakeFldigiServer()
        let buffer = RxBuffer()
        Self.serve(server, buffer)
        buffer.receive("OK1XOE DE DL1ABC 599 14\n")
        let app = try await Self.make(server, contest: true)
        let digital: DigitalInterfaceModel = app.model.makeDigitalInterface()
        digital.open()
        await app.settle()
        let spans: [DigitalInterfaceModel.Span] = digital.spans
        #expect(spans.contains(DigitalInterfaceModel.Span(start: 10, end: 16, kind: .call("DL1ABC"))))
        #expect(!spans.contains { if case .call("OK1XOE") = $0.kind { return true } else { return false } })
        #expect(spans.contains(DigitalInterfaceModel.Span(start: 21, end: 23,
                                                         kind: .exchange(fieldId: "zone", value: "14"))))
        digital.tap(offset: 12)
        #expect(app.entry.form.call == "DL1ABC")
        digital.tap(offset: 22)
        #expect(app.entry.form.contestExchange["zone"] == "14")
        // Outside any word: nothing.
        app.entry.callChanged("")
        digital.tap(offset: 6)
        #expect(app.entry.form.call.isEmpty)
        digital.take("OK2XYZ")
        #expect(app.entry.form.call == "OK2XYZ")
        digital.close()
    }

    private static func sends(_ app: KeyingApp) -> [String] {
        (app.keying.lastKeyer?.events ?? []).filter { $0.hasPrefix("send ") }
    }

    /// F1–F12 fire on the press (Shift = the opposite set), Enter and Esc on the release; every one of them is
    /// consumed. The keyer is a fake Winkeyer.
    @Test func keysGoToTheEntryWindow() async throws {
        let app = try await Self.make(nil, engine: .none)
        app.entry.setMode(.cw)
        let digital: DigitalInterfaceModel = app.model.makeDigitalInterface()
        // F3 („Tu"): S&P sends „tu", Shift the Run set's „tu {MYCALL} test".
        #expect(digital.key(.function(2), down: true, shift: false))
        await app.settle()
        #expect(Self.sends(app) == ["send TU@28"])
        #expect(digital.key(.function(2), down: false, shift: false))
        await app.settle()
        #expect(Self.sends(app) == ["send TU@28"])
        #expect(digital.key(.function(2), down: true, shift: true))
        await app.settle()
        #expect(Self.sends(app) == ["send TU@28", "send TU OK1XOE TEST@28"])
        app.model.operating.applyCqRepeat(true)
        #expect(digital.key(.escape, down: true, shift: false))
        #expect(app.model.operating.cqRepeat)
        #expect(digital.key(.escape, down: false, shift: false))
        #expect(!app.model.operating.cqRepeat)
        // Enter logs (without a contest the entry says so); the press alone does nothing.
        app.entry.setFrequency("14025")
        app.entry.callChanged("DL1ABC")
        #expect(!app.entry.esmActive)
        app.model.status.clear()
        #expect(digital.key(.enter, down: true, shift: false))
        #expect(app.status.isEmpty)
        #expect(digital.key(.enter, down: false, shift: false))
        await app.model.entry.settle()
        await runMainQueue()
        #expect(app.status == "Není aktivní závod — QSO se neuložilo. Založ nebo otevři závod.")
    }
}
