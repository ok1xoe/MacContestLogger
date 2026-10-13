import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// The Grab window (N1MM): filled from the received text without the call in the field, dupes or non-SCP calls;
/// Alt+G, `{GRAB}`, `{LOGTHENGRAB}`, `{DELTOP}`, the Insert key, Ctrl+Alt+G with Digital Call Stacking, and clearing
/// on CQ and QSY. Fake fldigi on loopback; nothing is keyed on a real rig.
@MainActor @Suite struct DigitalGrabTests {

    private typealias Fldigi = DigitalInterfaceRxTests.Fldigi

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
        app.entry.setMode(.rtty)
        app.entry.setFrequency("14080")
        let digital: DigitalInterfaceModel = app.model.makeDigitalInterface()
        digital.open()
        await app.settle()
        return (app, digital, server)
    }

    private static func poll(_ app: KeyingApp) async {
        app.radioClock.advance(by: 300)
        await app.settle()
    }

    /// The text fldigi was asked to transmit.
    private static func sent(_ server: FakeFldigiServer) -> [String] {
        server.requests.filter { $0.contains("text.add_tx") }
    }

    @Test func theGrabWindowSkipsTheFieldsCallDupesAndUnknownCalls() async throws {
        let fldigi = Fldigi()
        let (app, digital, server) = try await Self.make(fldigi, contest: true)
        await app.app.logContestQso(call: "DL2AAA", zone: "14", freqKHz: "14080")
        await app.model.logbook.settle()
        app.entry.callChanged("W1AW")
        fldigi.receive("DL2AAA W1AW DL1ABC OK2XYZ ")
        await Self.poll(app)
        #expect(digital.recentCalls == ["OK2XYZ", "DL1ABC"], "DL2AAA is a dupe, W1AW is in the call field")
        digital.setOption(\.grabOnlyScp, true)
        app.model.callData.adoptScp(.of(["JA1ABC"]))
        fldigi.receive("VK2ABC JA1ABC ")
        await Self.poll(app)
        #expect(digital.recentCalls == ["JA1ABC", "OK2XYZ", "DL1ABC"])
        // A call clicked in the text leaves the Grab window.
        let offset: Int = try #require(digital.spans.first { $0.kind == .call("OK2XYZ") }).start
        digital.tap(offset: offset)
        #expect(!digital.recentCalls.contains("OK2XYZ"))
        digital.close()
        _ = server
    }

    @Test func altGGrabsTheHighlightedCall() async throws {
        let fldigi = Fldigi()
        let (app, digital, server) = try await Self.make(fldigi) { config in
            config.digital.grabAddToBandmap = true
            config.digital.grabSendSpace = true
        }
        fldigi.receive("DL1ABC OK2XYZ ")
        await Self.poll(app)
        app.entry.callChanged("W1AW")
        let focus: Int = app.entry.exchangeFocusRequest
        app.entry.runShortcut(.grabStack)
        #expect(app.entry.form.call == "OK2XYZ")
        #expect(digital.recentCalls == ["DL1ABC"])
        #expect(app.entry.exchangeFocusRequest > focus, "Send Space on Using Grab")
        #expect(app.model.dxCluster.spots.find("W1AW") != nil, "the call in the field went into the bandmap")
        // {DELTOP} empties the list; Alt+G then falls back to the call stack.
        app.model.grabList.removeTop()
        #expect(digital.recentCalls.isEmpty)
        app.entry.runShortcut(.grabStack)
        #expect(app.status == "Zásobník volaček je prázdný")
        digital.close()
        _ = server
    }

    @Test func digitalCallStackingMovesGrabbedCallsOntoTheStack() async throws {
        let fldigi = Fldigi()
        let (app, digital, server) = try await Self.make(fldigi) { config in
            config.digital.digitalCallStacking = true
            config.esm.callStackOrder = CallStack.Order.fifo.rawValue
        }
        app.model.operating.select(.run, freqHz: 14_080_000)
        fldigi.receive("DL1ABC OK2XYZ ")
        await Self.poll(app)
        // Ctrl+Alt+G: the Grab window's call onto the stack, the field unchanged.
        app.entry.callChanged("W1AW")
        app.entry.runShortcut(.stackCall)
        #expect(app.model.callStack.calls == ["OK2XYZ"])
        #expect(app.entry.form.call == "W1AW")
        // Alt+G: the grabbed call into the field, the field's call onto the stack.
        app.entry.runShortcut(.grabStack)
        #expect(app.entry.form.call == "DL1ABC")
        #expect(app.model.callStack.calls == ["OK2XYZ", "W1AW"])
        digital.close()
        _ = server
    }

    /// `{LOGTHENGRAB}`: one transmission to both stations, the QSO logged, the grabbed call in the field.
    @Test func logThenGrabLogsAndCallsTheNextStation() async throws {
        let fldigi = Fldigi()
        let (app, digital, server) = try await Self.make(fldigi) { config in
            config.digital.runMessages[1] = FunctionKeyMessage(label: "Exch", text: "! 599 15")
            config.digital.runMessages[4] = FunctionKeyMessage(label: "His", text: "!")
            config.digital.runMessages[8] = FunctionKeyMessage(label: "Now", text: "! {LOGTHENGRAB} TU {F5}{F2}")
            config.digital.runMessages[9] = FunctionKeyMessage(label: "Grab", text: "{GRAB}")
        }
        app.model.operating.select(.run, freqHz: 14_080_000)
        fldigi.receive("DL1ABC OK2XYZ ")
        await Self.poll(app)
        app.entry.callChanged("W1AW")
        app.entry.handle(.functionKey(1, shift: false, ctrlShift: false))
        await app.settle()
        app.entry.handle(.functionKey(8, shift: false, ctrlShift: false))
        await app.model.entry.settle()
        await app.model.logbook.settle()
        await app.settle()
        #expect(app.model.logbook.rows.map(\.call) == ["W1AW"])
        #expect(app.entry.form.call == "OK2XYZ")
        #expect(digital.recentCalls == ["DL1ABC"])
        #expect(Self.sent(server).last?.contains("W1AW TU OK2XYZ OK2XYZ 599 15") == true)
        // {GRAB}: the next call.
        app.entry.handle(.functionKey(9, shift: false, ctrlShift: false))
        #expect(app.entry.form.call == "DL1ABC")
        digital.close()
    }

    /// Insert (Help on a Mac): an empty call field grabs, then F5+F2 go out.
    @Test func insertGrabsAndSendsHisCallAndExchange() async throws {
        let fldigi = Fldigi()
        let (app, digital, server) = try await Self.make(fldigi) { config in
            config.digital.runMessages[1] = FunctionKeyMessage(label: "Exch", text: "599 15")
            config.digital.runMessages[4] = FunctionKeyMessage(label: "His", text: "!")
        }
        app.model.operating.select(.run, freqHz: 14_080_000)
        fldigi.receive("DL1ABC ")
        await Self.poll(app)
        app.entry.runShortcut(.insertGrab)
        await app.settle()
        #expect(app.entry.form.call == "DL1ABC")
        #expect(Self.sent(server).last?.contains("DL1ABC 599 15") == true)
        digital.close()
    }

    @Test func cqAndQsyClearTheGrabWindow() async throws {
        let fldigi = Fldigi()
        let (app, digital, server) = try await Self.make(fldigi) { config in
            config.digital.grabClearOnCq = true
            config.digital.grabClearOnQsy = true
        }
        fldigi.receive("DL1ABC ")
        await Self.poll(app)
        app.entry.setFrequency("14080.3")
        #expect(digital.recentCalls == ["DL1ABC"], "300 Hz is not a QSY")
        app.entry.setFrequency("14085")
        #expect(digital.recentCalls.isEmpty)
        fldigi.receive("K1ZZ ")
        await Self.poll(app)
        #expect(digital.recentCalls == ["K1ZZ"])
        app.entry.handle(.functionKey(0, shift: false, ctrlShift: false))
        #expect(digital.recentCalls.isEmpty)
        digital.close()
        _ = server
    }
}
