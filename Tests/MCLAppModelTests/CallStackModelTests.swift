import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// Single-operator call stacking in the entry window (N1MM): Ctrl+Alt+G, Alt+G, Alt+D, `{SOCALLSTACK}`,
/// `{LOGTHENPOP}` through the live (fake) Winkeyer, ESM's Next Call key, the multiplier order, dupes, the band
/// change, and the Digital Interface's Option+click and Digital Call Stacking.
@MainActor @Suite struct CallStackModelTests {

    private static func make(esm: Bool = false) async throws -> KeyingApp {
        let app = try await KeyingApp.make(configure: { config, _ in
            winkeyerConfig(&config)
            config.cwKeyer.runMessages[1] = FunctionKeyMessage(label: "Exch", text: "5NN 15")
            config.cwKeyer.runMessages[2] = FunctionKeyMessage(label: "TU", text: "TU *")
            config.cwKeyer.runMessages[4] = FunctionKeyMessage(label: "His", text: "!")
            config.cwKeyer.runMessages[10] = FunctionKeyMessage(label: "Stack", text: "{SOCALLSTACK}")
            config.cwKeyer.spMessages[10] = FunctionKeyMessage(label: "Stack", text: "{SOCALLSTACK}")
            config.cwKeyer.runMessages[11] = FunctionKeyMessage(label: "Next", text: "! {LOGTHENPOP} TU {F5}{F2}")
            config.esm.nextCallKey = 11
        })
        try await app.app.startCqWwCw()
        app.entry.setMode(.cw)
        app.entry.setFrequency("14025")
        app.model.operating.applyEsm(esm)
        app.model.operating.select(.run, freqHz: 14_025_000)
        return app
    }

    private static func sent(_ app: KeyingApp) -> [String] {
        (app.keying.lastKeyer?.events ?? []).filter { $0.hasPrefix("send ") }
    }

    private static func settleLog(_ app: KeyingApp) async {
        await app.model.entry.settle()
        await app.model.logbook.settle()
        await app.settle()
    }

    @Test func ctrlAltGStacksAndAltGTakesTheNextCall() async throws {
        let app = try await Self.make()
        app.entry.callChanged("DL1ABC")
        app.entry.editContestField("zone", "14")
        app.entry.runShortcut(.stackCall)
        #expect(app.entry.form.call.isEmpty, "the field is wiped for the next call")
        #expect((app.entry.form.contestExchange["zone"] ?? "").isEmpty)
        #expect(app.status == "Do zásobníku: DL1ABC")
        app.entry.callChanged("K1ZZ")
        app.entry.runShortcut(.stackCall)
        #expect(app.model.callStack.calls.contains("K1ZZ"))
        #expect(app.model.infoStrip.text.contains("ZÁSOBNÍK"))
        app.entry.callChanged("W1AW")
        app.entry.runShortcut(.grabStack)
        #expect(app.entry.form.call == "K1ZZ" || app.entry.form.call == "DL1ABC")
        #expect(app.model.callStack.calls.count == 1)
        app.entry.runShortcut(.popStack)
        #expect(app.model.callStack.calls.isEmpty)
        app.entry.runShortcut(.grabStack)
        #expect(app.status == "Zásobník volaček je prázdný")
    }

    /// The default order puts new multipliers first: a JA stacked later comes first. The dupe is the contest's own;
    /// the multiplier count is injected (the test environment has no DXCC data to tell countries and zones apart).
    @Test func multipliersComeFirstAndDupesAreNotStacked() async throws {
        let app = try await Self.make()
        let real = app.model.callStack.evaluate
        app.model.callStack.evaluate = { call in
            let base: CallStack.Evaluation = real(call)
            return CallStack.Evaluation(dupe: base.dupe, newMults: call == "JA1ABC" ? 2 : base.newMults)
        }
        await app.app.logContestQso(call: "DL1ABC", zone: "14")
        await Self.settleLog(app)
        app.entry.callChanged("DL1ABC")
        app.entry.runShortcut(.stackCall)
        #expect(app.status == "DL1ABC je dupe — do zásobníku nejde")
        #expect(app.entry.form.call == "DL1ABC", "a refused call stays in the field")
        app.entry.callChanged("DL2XYZ")
        app.entry.runShortcut(.stackCall)
        app.entry.callChanged("JA1ABC")
        app.entry.runShortcut(.stackCall)
        #expect(app.model.callStack.calls == ["JA1ABC", "DL2XYZ"])
        app.model.config.config.esm.callStackOrder = CallStack.Order.fifo.rawValue
        #expect(app.model.callStack.calls == ["DL2XYZ", "JA1ABC"])
        app.model.config.config.esm.callStackOrder = CallStack.Order.lifo.rawValue
        #expect(app.model.callStack.calls == ["JA1ABC", "DL2XYZ"])
    }

    @Test func altDWithAnEmptyFieldDeletesTheNextCall() async throws {
        let app = try await Self.make()
        app.model.callStack.push("K1ZZ")
        app.model.callStack.push("W1AW")
        app.entry.runShortcut(.removeSpot)
        #expect(app.model.callStack.calls == ["W1AW"])
        #expect(app.status == "Ze zásobníku smazána K1ZZ")
    }

    /// `{SOCALLSTACK}`: stacks the call, exchanges it with the stacked one, and takes it back into an empty field.
    @Test func soCallStackExchangesTheCall() async throws {
        let app = try await Self.make()
        app.entry.callChanged("K3CT")
        app.entry.handle(.functionKey(10, shift: false, ctrlShift: false))
        #expect(app.entry.form.call.isEmpty)
        #expect(app.model.callStack.calls == ["K3CT"])
        app.entry.callChanged("N2IC")
        app.entry.handle(.functionKey(10, shift: false, ctrlShift: false))
        #expect(app.entry.form.call == "K3CT")
        #expect(app.model.callStack.calls == ["N2IC"])
        app.entry.callChanged("")
        app.entry.handle(.functionKey(10, shift: false, ctrlShift: false))
        #expect(app.entry.form.call == "N2IC")
        #expect(app.model.callStack.calls.isEmpty)
        // Only in Run.
        app.model.operating.select(.searchAndPounce, freqHz: 14_025_000)
        app.entry.handle(.functionKey(10, shift: false, ctrlShift: false))
        #expect(app.status == "{SOCALLSTACK}: zásobník volaček jen v Run")
    }

    /// `{LOGTHENPOP}`: one message thanks the logged station and calls the next one; the QSO is logged, the next
    /// call is in the field and its exchange counts as sent.
    @Test func logThenPopLogsAndStartsTheNextQso() async throws {
        let app = try await Self.make()
        app.model.callStack.push("K1ZZ")
        app.entry.callChanged("DL1ABC")
        app.entry.editContestField("zone", "14")
        app.entry.handle(.functionKey(1, shift: false, ctrlShift: false))
        await app.settle()
        app.entry.handle(.functionKey(11, shift: false, ctrlShift: false))
        await Self.settleLog(app)
        #expect(app.model.logbook.rows.map(\.call) == ["DL1ABC"])
        #expect(app.entry.form.call == "K1ZZ")
        #expect(app.model.callStack.calls.isEmpty)
        #expect(app.entry.esmProgress.exchangeSent)
        let last: String = try #require(Self.sent(app).last)
        #expect(last.hasPrefix("send DL1ABC TU K1ZZ 5NN 15"), "\(last)")
    }

    @Test func logThenPopRefusesAnExchangeNotSent() async throws {
        let app = try await Self.make()
        app.model.callStack.push("K1ZZ")
        app.entry.callChanged("DL1ABC")
        app.entry.editContestField("zone", "14")
        app.entry.handle(.functionKey(11, shift: false, ctrlShift: false))
        await Self.settleLog(app)
        #expect(app.model.logbook.rows.isEmpty)
        #expect(app.entry.form.call == "DL1ABC")
        #expect(app.model.callStack.calls == ["K1ZZ"])
        #expect(app.status.contains("{LOGTHENPOP}"))
        #expect(Self.sent(app).isEmpty)
    }

    /// ESM: with a call waiting, the end of the QSO sends the Next Call key (F12) instead of TU; without one, TU.
    @Test func esmContinuesWithTheNextStackedCall() async throws {
        let app = try await Self.make(esm: true)
        app.model.callStack.push("K1ZZ")
        app.entry.callChanged("DL1ABC")
        app.entry.editContestField("zone", "14")
        #expect(app.entry.esmStep?.keys == [EsmEngine.f5, EsmEngine.f2])
        app.entry.handle(.enter(ctrl: false, step: .esm))
        await app.settle()
        #expect(app.entry.esmStep?.keys == [11])
        app.entry.handle(.enter(ctrl: false, step: .esm))
        await Self.settleLog(app)
        #expect(app.model.logbook.rows.map(\.call) == ["DL1ABC"])
        #expect(app.entry.form.call == "K1ZZ")
        // The stack is empty now: the next end of QSO is the normal TU and log.
        app.entry.editContestField("zone", "5")
        #expect(app.entry.esmStep?.keys == [EsmEngine.f3])
        #expect(app.entry.esmStep?.log == true)
    }

    @Test func aBandChangeClearsTheStack() async throws {
        let app = try await Self.make()
        app.model.callStack.push("K1ZZ")
        app.entry.setFrequency("7025")
        #expect(app.model.callStack.calls.isEmpty)
        #expect(app.status == "Jiné pásmo — zásobník volaček vymazán")
        app.model.config.config.esm.callStackClearOnBandChange = false
        app.model.callStack.push("W1AW")
        app.entry.setFrequency("14025")
        #expect(app.model.callStack.calls == ["W1AW"])
    }

    // MARK: - the Digital Interface

    @Test func optionClickStacksAndDigitalCallStackingKeepsTheField() async throws {
        let app = try await Self.make()
        let digital: DigitalInterfaceModel = app.model.makeDigitalInterface()
        digital.take("K1ZZ", click: .stack)
        #expect(app.model.callStack.calls == ["K1ZZ"])
        #expect(app.entry.form.call.isEmpty)
        // Without Digital Call Stacking a click replaces the field.
        app.entry.callChanged("DL1ABC")
        digital.take("W1AW")
        #expect(app.entry.form.call == "W1AW")
        // FIFO: the clicked call is stacked, the field stays.
        digital.setDigitalCallStacking(.fifo)
        digital.take("JA1ABC")
        #expect(app.entry.form.call == "W1AW")
        #expect(app.model.callStack.calls == ["K1ZZ", "JA1ABC"])
        // LIFO: the call in the field is stacked and the clicked one goes into the field.
        digital.setDigitalCallStacking(.lifo)
        digital.take("VK2ABC")
        #expect(app.entry.form.call == "VK2ABC")
        #expect(app.model.callStack.calls.first == "W1AW")
        #expect(digital.digitalCallStacking == .lifo)
        digital.setDigitalCallStacking(nil)
        #expect(digital.digitalCallStacking == nil)
    }

    // MARK: - SSB

    /// In SSB the stack macros run before the message plays: the QSO is logged, the next call is in the field, and
    /// the macro is neither played nor reported as unknown.
    @Test func voiceLogThenPopRunsBeforeTheAudio() async throws {
        let app = try await KeyingApp.make(configure: { config, dataDir in
            let wav: URL = dataDir.appendingPathComponent("wav")
            try FileManager.default.createDirectory(at: wav, withIntermediateDirectories: true)
            try Data([1]).write(to: wav.appendingPathComponent("tu.wav"))
            config.voiceKeyer.runMessages[1] = FunctionKeyMessage(label: "Exch", text: "tu.wav")
            config.voiceKeyer.runMessages[11] = FunctionKeyMessage(label: "Next", text: "{LOGTHENPOP},tu.wav")
            config.voiceKeyer.outputDevice = "Fake Out"
            config.voiceKeyer.pttDelayMs = 0
            config.voiceKeyer.pttViaCat = false
        })
        app.entry.setMode(.ssb)
        app.entry.setFrequency("14250")
        app.model.operating.select(.run, freqHz: 14_250_000)
        app.model.callStack.push("K1ZZ")
        app.entry.callChanged("DL1ABC")
        app.entry.handle(.functionKey(1, shift: false, ctrlShift: false))
        await eventually("exchange played") { app.keying.events.count == 1 && app.keyer.voice.playingKey == nil }
        app.entry.handle(.functionKey(11, shift: false, ctrlShift: false))
        await eventually("next played") { app.keying.events.count == 2 && app.keyer.voice.playingKey == nil }
        await Self.settleLog(app)
        #expect(app.model.logbook.rows.map(\.call) == ["DL1ABC"])
        #expect(app.entry.form.call == "K1ZZ")
        #expect(!app.status.contains("{LOGTHENPOP}"))
    }
}
