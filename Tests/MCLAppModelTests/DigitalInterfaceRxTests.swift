import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// The Digital Interface's receive window (N1MM): calls of the own transmission are not grabbed, the pause bar and
/// the pause routines, Hover Mode, MouseOver / Letters-Figs, Cmd+click into the focused field, Shift+click with the
/// conversion, right click = Enter, the validity routines and the Master.scp search in garbage text. Fake fldigi
/// on loopback.
@MainActor @Suite struct DigitalInterfaceRxTests {

    /// fldigi whose transmit state the test switches.
    final class Fldigi: @unchecked Sendable {
        private let lock = NSLock()
        private var content: String = ""
        private var served = 0
        private var trx = "RX"

        func receive(_ text: String, trx state: String = "RX") {
            lock.withLock {
                content += text
                trx = state
            }
        }

        func answer(_ method: String) -> (status: Int, value: String) {
            lock.withLock {
                switch method {
                case "text.get_rx_length": return (200, String(content.utf16.count))
                case "text.get_rx":
                    let units = Array(content.utf16)
                    let part = String(decoding: units[served...], as: UTF16.self)
                    served = units.count
                    return (200, part)
                case "modem.get_name": return (200, "RTTY")
                case "main.get_trx_state": return (200, trx)
                default: return (200, "")
                }
            }
        }
    }

    private static func make(_ fldigi: Fldigi, contest: Bool = false,
                             configure: @escaping (inout AppConfig) -> Void = { _ in }) async throws
        -> (KeyingApp, DigitalInterfaceModel, FakeFldigiServer) {
        let server = try FakeFldigiServer()
        server.respond { fldigi.answer($0) }
        let app = try await KeyingApp.make(configure: { config, _ in
            config.digital.engine = .fldigi
            config.digital.fldigiHost = "127.0.0.1"
            config.digital.fldigiPort = server.port
            winkeyerConfig(&config)
            configure(&config)
        }, setUp: { keying in
            keying.fldigiPort = server.port
        })
        if contest {
            var setup = ContestSetup()
            setup.sentExchange = ["zone": "15"]
            #expect(await app.model.contest.createAndStart(definitionId: "cq-ww-rtty", setup: setup))
        }
        let digital: DigitalInterfaceModel = app.model.makeDigitalInterface()
        digital.open()
        await app.settle()
        return (app, digital, server)
    }

    private static func poll(_ app: KeyingApp) async {
        app.radioClock.advance(by: 300)
        await app.settle()
    }

    @Test func callsOfTheOwnTransmissionAreNotGrabbed() async throws {
        let fldigi = Fldigi()
        let (app, digital, server) = try await Self.make(fldigi)
        fldigi.receive("CQ TEST DE OK1XOE OK1XOE W1AW K ", trx: "TX")
        await Self.poll(app)
        fldigi.receive("DL1ABC DL1ABC ", trx: "RX")
        await Self.poll(app)
        #expect(digital.recentCalls == ["DL1ABC"])
        let w1aw = try #require(digital.spans.first { $0.kind == .call("W1AW") })
        #expect(w1aw.transmitted)
        #expect(digital.spans.contains { $0.kind == .call("DL1ABC") && !$0.transmitted })
        digital.close()
        _ = server
    }

    @Test func thePauseBarHoldsTheTextBack() async throws {
        let fldigi = Fldigi()
        let (app, digital, server) = try await Self.make(fldigi)
        fldigi.receive("DL1ABC ")
        await Self.poll(app)
        digital.togglePause()
        fldigi.receive("K1ZZ ")
        await Self.poll(app)
        #expect(digital.text == "DL1ABC ")
        #expect(digital.recentCalls == ["DL1ABC", "K1ZZ"], "the calls are still collected")
        digital.togglePause()
        #expect(digital.text == "DL1ABC K1ZZ ")
        digital.close()
        _ = server
    }

    @Test func hoverModeMouseOverAndPauseRoutines() async throws {
        let fldigi = Fldigi()
        let (app, digital, server) = try await Self.make(fldigi)
        fldigi.receive("TOO DL1ABC ")
        await Self.poll(app)
        digital.hover(offset: 1)
        #expect(digital.mouseOver == "TOO")
        #expect(digital.lettersFigs == "599")
        #expect(!digital.isPaused)
        digital.setOption(\.pauseOnCallHover, true)
        digital.hover(offset: 5)
        #expect(digital.hoverPaused, "the pointer over a call pauses while the call field is empty")
        fldigi.receive("K1ZZ ")
        await Self.poll(app)
        #expect(digital.text == "TOO DL1ABC ")
        digital.hover(offset: nil)
        #expect(!digital.isPaused)
        #expect(digital.text == "TOO DL1ABC K1ZZ ")
        #expect(app.entry.form.call.isEmpty)
        digital.setOption(\.hoverMode, true)
        digital.hover(offset: 5)
        #expect(app.entry.form.call == "DL1ABC")
        digital.close()
        _ = server
    }

    @Test func cmdClickShiftClickAndSendSpace() async throws {
        let fldigi = Fldigi()
        let (app, digital, server) = try await Self.make(fldigi, contest: true)
        fldigi.receive("DL1ABC TOO 14 XYZ\n")
        await Self.poll(app)
        // Cmd+click: the word into the field with the cursor.
        app.entry.focusedField = { .contest("zone") }
        digital.tap(offset: 15, click: .force)
        #expect(app.entry.form.contestExchange["zone"] == "XYZ")
        app.entry.focusedField = { .call }
        digital.tap(offset: 15, click: .force)
        #expect(app.entry.form.call == "XYZ")
        // Shift+click: TOO → 599 into the report.
        app.entry.callChanged("DL1ABC")
        digital.tap(offset: 8, click: .lettersFigures)
        let rst: String = app.entry.form.contestExchange["rst"] ?? app.entry.form.rstRcvd
        #expect(rst == "599")
        // Send Space on Callsign Mouse Click: the exchange gets the focus after the call.
        digital.setOption(\.sendSpaceOnClick, true)
        app.entry.callChanged("")
        let before: Int = app.entry.exchangeFocusRequest
        digital.tap(offset: 2)
        #expect(app.entry.form.call == "DL1ABC")
        #expect(app.entry.exchangeFocusRequest == before + 1)
        digital.close()
        _ = server
    }

    @Test func rightClickIsEnterOnlyWhenChosen() async throws {
        let fldigi = Fldigi()
        let (app, digital, server) = try await Self.make(fldigi)
        app.entry.setFrequency("14080")
        app.entry.callChanged("DL1ABC")
        #expect(!digital.rightClick())
        digital.setOption(\.rightClickReturn, true)
        #expect(digital.rightClick())
        await app.model.entry.settle()
        await runMainQueue()
        #expect(app.model.logbook.rows.map(\.call) == ["DL1ABC"])
        digital.close()
        _ = server
    }

    /// RESOURCES highlights only known calls (here: logged); COMBINED marks unknown ones; the garbage search finds a
    /// Master.scp call inside a word.
    @Test func validityRoutinesAndGarbageSearch() async throws {
        let fldigi = Fldigi()
        let (app, digital, server) = try await Self.make(fldigi) { config in
            config.digital.validateScp = false
            config.digital.validateCallHistory = false
            config.digital.validateSpotted = false
        }
        app.entry.setFrequency("14080")
        app.entry.callChanged("K1ZZ")
        app.entry.submit()
        await app.model.entry.settle()
        fldigi.receive("K1ZZ DL1ABC EEEEW1AWEEEE ")
        await Self.poll(app)
        #expect(digital.mark(for: "DL1ABC").unverified)
        #expect(!digital.mark(for: "K1ZZ").unverified)
        digital.setCallValidity(.resources)
        let calls: [String] = digital.spans.compactMap { if case .call(let c) = $0.kind { c } else { nil } }
        #expect(calls == ["K1ZZ"])
        digital.setCallValidity(.generic)
        app.model.callData.adoptScp(.of(["W1AW"]))
        digital.setOption(\.scpGarbageSearch, true)
        let hits: [String] = digital.callHits(digital.text).map(\.call)
        #expect(hits == ["K1ZZ", "DL1ABC", "W1AW"])
        digital.close()
        _ = server
    }
}
