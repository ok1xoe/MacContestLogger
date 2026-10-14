import Foundation
import MCLCore
import Testing
@testable import MCLAppModel

/// N1MM Edit Last Contact (Ctrl+Y, the Edit button), Edit Current Contact and Find Again.
@MainActor @Suite struct QsoEditTests {

    @Test func ctrlYEditsTheLastQsoAndRescores() async throws {
        let app = try await TestApp.make()
        try await app.startCqWwCw()
        await app.logContestQso(call: "DL1ABC", zone: "14")
        await app.logContestQso(call: "OK1AA", zone: "15")
        let entry: EntryModel = app.model.entry
        #expect(EntryActionAvailability.area(of: .editLast) == .local)
        #expect(ShortcutAction.editLast.defaultKeys == "Ctrl+Y")
        entry.runShortcut(.editLast)
        let model: QsoEditModel = try #require(app.model.dialogs.qsoEdit)
        #expect(app.model.dialogs.isOpen(.qsoEdit))
        #expect(model.form.call == "OK1AA")
        #expect(model.editsLoggedQso)
        model.form.call = "OK1AB"
        model.form.exchange = "599 16"
        model.form.freqKHz = "7025"
        model.save()
        #expect(app.model.dialogs.qsoEdit == nil)
        await app.model.logbook.settle()
        let last: Qso = try #require(app.model.logbook.lastRow)
        #expect(last.call == "OK1AB")
        #expect(last.exchangeRcvd == "599 16")
        #expect(last.band == .m40)
        #expect(app.model.logbook.rows.first?.call == "DL1ABC")
    }

    @Test func aBadFieldKeepsTheDialogOpen() async throws {
        let app = try await TestApp.make()
        try await app.startCqWwCw()
        await app.logContestQso(call: "DL1ABC", zone: "14")
        app.model.entry.editLastContact()
        let model: QsoEditModel = try #require(app.model.dialogs.qsoEdit)
        model.form.time = "yesterday"
        model.save()
        #expect(app.model.dialogs.qsoEdit === model)
        #expect(model.problem == QsoEditForm.Problem.time("yesterday").message)
        model.cancel()
        #expect(app.model.dialogs.qsoEdit == nil)
        #expect(app.model.logbook.lastRow?.call == "DL1ABC")
    }

    @Test func anEmptyLogHasNothingToEdit() async throws {
        let app = try await TestApp.make()
        app.model.entry.editLastContact()
        #expect(app.model.dialogs.qsoEdit == nil)
        #expect(app.model.status.message == "Deník je prázdný")
    }

    @Test func editCurrentContactWritesBackIntoTheEntryWindow() async throws {
        let app = try await TestApp.make()
        try await app.startCqWwCw()
        let entry: EntryModel = app.model.entry
        entry.setFrequency("14025")
        entry.callChanged("DL1ABC")
        entry.editCurrentContact()
        let model: QsoEditModel = try #require(app.model.dialogs.qsoEdit)
        #expect(model.target == .current)
        #expect(!model.editsLoggedQso)
        #expect(model.showsExchangeFields)
        #expect(model.form.call == "DL1ABC")
        let zone: Int = try #require(model.exchangeFields.firstIndex { $0.id == "zone" })
        model.setExchangeField(zone, "14")
        model.form.call = "DL1ABD"
        model.form.note = "op Hans"
        model.save()
        #expect(app.model.dialogs.qsoEdit == nil)
        #expect(entry.form.call == "DL1ABD")
        #expect(entry.form.contestExchange["zone"] == "14")
        #expect(entry.pendingNote == "op Hans")
        #expect(entry.contestReady)
    }

    @Test func menuItemsRunTheEdits() async throws {
        let app = try await TestApp.make()
        try await app.startCqWwCw()
        await app.logContestQso(call: "DL1ABC", zone: "14")
        #expect(app.model.menu.isImplemented("edit.editLast"))
        #expect(app.model.menu.isImplemented("edit.editCurrent"))
        _ = MenuActions.perform("edit.editLast", app: app.model)
        #expect(app.model.dialogs.qsoEdit?.target == .logged(try #require(app.model.logbook.lastRow?.id)))
        _ = MenuActions.perform("edit.editCurrent", app: app.model)
        #expect(app.model.dialogs.qsoEdit?.target == .current)
    }

    @Test func ctrlFAgainSelectsTheNextQsoOfTheCall() async throws {
        let app = try await TestApp.make()
        try await app.startCqWwCw()
        await app.logContestQso(call: "DL1ABC", zone: "14")
        await app.logContestQso(call: "OK1AA", zone: "15")
        await app.logContestQso(call: "DL1ABC", zone: "14", freqKHz: "7025")
        let entry: EntryModel = app.model.entry
        let table = LogTableModel(app: app.model)
        entry.callChanged("DL1ABC")
        entry.runShortcut(.find)
        #expect(app.model.windows.isOpen("log"))
        table.takeSearchRequest()
        await app.model.logbook.settle()
        #expect(app.model.logbook.displayed.count == 2)
        let before: Int = app.model.windows.logFindNextRequest
        entry.runShortcut(.find)
        #expect(app.model.windows.logFindNextRequest == before + 1)
        let ids: [Int64] = app.model.logbook.displayed.compactMap(\.id)
        table.findNext()
        #expect(table.selected == [ids[0]])
        table.findNext()
        #expect(table.selected == [ids[1]])
        table.findNext()
        #expect(table.selected == [ids[0]])
        // Another call searches again.
        entry.callChanged("OK1AA")
        entry.runShortcut(.find)
        #expect(app.model.windows.logSearchRequest == "call:OK1AA")
    }
}
