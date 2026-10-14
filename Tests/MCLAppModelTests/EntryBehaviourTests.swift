import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// N1MM Entry window behaviours: clearing the auto-populated exchange, the `?` selection, the serial sequence
/// warning, the sent CW in the status line and the warning when tuning away before logging.
@MainActor @Suite struct EntryBehaviourTests {

    @Test func questionMarksAreSelected() {
        #expect(EntryAssist.questionMarkSelection("DL?K?A") == NSRange(location: 2, length: 3))
        #expect(EntryAssist.questionMarkSelection("DL1A?C") == NSRange(location: 4, length: 1))
        #expect(EntryAssist.questionMarkSelection("DL1ABC") == nil)
    }

    @Test func messagesThatSendTheSerial() {
        #expect(EntryAssist.sendsSerial("5NN #", sentExchange: ""))
        #expect(EntryAssist.sendsSerial("{NR}", sentExchange: ""))
        #expect(EntryAssist.sendsSerial("TU {EXCH}", sentExchange: "#"))
        #expect(!EntryAssist.sendsSerial("TU {EXCH}", sentExchange: "15"))
        #expect(!EntryAssist.sendsSerial("TU {MYCALL}", sentExchange: "#"))
        let message = CwMessage(parts: [.text("5NN "), .speed(2), .text("001 "), .prosign("AR")], actions: [],
                                unknownMacros: [])
        #expect(EntryAssist.sentText(message) == "5NN 001 <AR>")
    }

    private func prefilled(_ app: TestApp) async throws -> EntryModel {
        try await app.startCqWwCw()
        let entry: EntryModel = app.model.entry
        entry.setFrequency("14025")
        entry.callChanged("DL1AB")
        var values = JavaLinkedMap<String>()
        values.put("zone", "14")
        entry.prefillExchange(values)
        #expect(entry.form.contestExchange["zone"] == "14")
        return entry
    }

    @Test func autoPopulatedExchangeIsClearedOnlyWithTheOption() async throws {
        let off = try await prefilled(try await TestApp.make())
        off.callChanged("DL1ABC")
        #expect(off.form.contestExchange["zone"] == "14")

        let on = try await prefilled(try await TestApp.make { config, _ in config.clearPrefilledExchange = true })
        on.callChanged("DL1ABC")
        #expect(on.form.contestExchange["zone"] == nil)
        // A value the operator typed stays.
        on.editContestField("zone", "15")
        on.callChanged("DL1ABD")
        #expect(on.form.contestExchange["zone"] == "15")
        // The call history prefill counts as auto-populated too.
        var form: EntryForm = on.form
        form.contestExchange.put("zone", "20")
        on.applyCallHistoryPrefill(form)
        on.callChanged("DL1AB")
        #expect(on.form.contestExchange["zone"] == nil)
    }

    @Test func aSerialSentBeforeAnotherQsoTookItIsReported() async throws {
        let app = try await TestApp.make()
        try await app.startCqWwCw()
        let entry: EntryModel = app.model.entry
        entry.setMode(.cw)
        entry.setFrequency("14025")
        entry.callChanged("DL1ABC")
        entry.editContestField("zone", "14")
        var messages: [FunctionKeyMessage] = app.model.config.config.cwKeyer.spMessages
        messages[1] = FunctionKeyMessage(label: "Exch", text: "5NN #")
        app.model.config.config.cwKeyer.spMessages = messages
        app.model.config.config.cwKeyer.runMessages[1] = FunctionKeyMessage(label: "Exch", text: "5NN #")
        _ = entry.handle(.functionKey(1, shift: false, ctrlShift: false))
        #expect(entry.serialSentInQso == 1)
        // Another station's QSO takes the number meanwhile.
        _ = app.model.logbook.reserveSerial()
        entry.submit()
        await entry.settle()
        #expect(app.model.logbook.rows.first?.serialSent == 2)
        #expect(app.model.status.message == "Pozor: odesláno číslo 1, zapsáno 2")
        #expect(entry.serialSentInQso == nil)
    }

    @Test func sentCwIsShownWithTheOption() async throws {
        let app = try await TestApp.make { config, _ in
            config.showSentCw = true
            config.cwKeyer.spMessages[0] = FunctionKeyMessage(label: "CQ", text: "TEST *")
            config.cwKeyer.runMessages[0] = FunctionKeyMessage(label: "CQ", text: "TEST *")
        }
        let entry: EntryModel = app.model.entry
        entry.setMode(.cw)
        _ = entry.handle(.functionKey(0, shift: false, ctrlShift: false))
        #expect(app.model.status.message == "CW: TEST OK1XOE")
    }

    @Test func tuningAwayBeforeLoggingWarns() async throws {
        let rigApp = try await RigApp.make { config, _ in config.dxCluster.selfSpotThresholdHz = 2_500 }
        await SelfSpotEntryTests.tune(rigApp, 14_025_000)
        rigApp.entry.callChanged("OK1ABC")
        await SelfSpotEntryTests.tune(rigApp, 14_030_000)
        #expect(rigApp.entry.form.call.isEmpty)
        #expect(rigApp.status == "OK1ABC nezapsán — odladěno, uložen do bandmapy")
    }
}
