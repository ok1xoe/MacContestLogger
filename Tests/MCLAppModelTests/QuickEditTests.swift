import Foundation
import MCLCore
import Testing
@testable import MCLAppModel

/// N1MM QuickEdit: Ctrl+Q / Ctrl+A walk the logged QSOs in the Entry window's fields, Enter saves, Esc cancels.
@MainActor @Suite struct QuickEditTests {

    private func logThree(_ app: TestApp) async throws {
        try await app.startCqWwCw()
        await app.logContestQso(call: "DL1ABC", zone: "14")
        await app.logContestQso(call: "OK1AA", zone: "15")
        await app.logContestQso(call: "G4XYZ", zone: "14")
    }

    @Test func ctrlQWalksBackCtrlAForward() async throws {
        let app = try await TestApp.make()
        try await logThree(app)
        let entry: EntryModel = app.model.entry
        #expect(ShortcutAction.quickEditBack.defaultKeys == "Ctrl+Q")
        #expect(ShortcutAction.quickEditForward.defaultKeys == "Ctrl+A")
        entry.callChanged("SP9")
        entry.runShortcut(.quickEditForward)
        #expect(entry.quickEdit == nil)
        entry.runShortcut(.quickEditBack)
        #expect(entry.form.call == "G4XYZ")
        #expect(entry.form.contestExchange["zone"] == "14")
        #expect(entry.quickEdit?.position == 1)
        #expect(entry.quickEdit?.count == 3)
        entry.runShortcut(.quickEditBack)
        #expect(entry.form.call == "OK1AA")
        #expect(entry.form.contestExchange["zone"] == "15")
        entry.runShortcut(.quickEditBack)
        entry.runShortcut(.quickEditBack)
        #expect(entry.form.call == "DL1ABC")
        #expect(app.model.status.message == "QuickEdit: první QSO deníku")
        entry.runShortcut(.quickEditForward)
        #expect(entry.form.call == "OK1AA")
        // Esc (a wipe) leaves the QSO and gives back what was typed.
        _ = entry.handle(.escape(.wipe))
        #expect(entry.quickEdit == nil)
        #expect(entry.form.call == "SP9")
        #expect(app.model.logbook.rows.map(\.call) == ["DL1ABC", "OK1AA", "G4XYZ"])
    }

    @Test func enterSavesTheChangedQso() async throws {
        let app = try await TestApp.make()
        try await logThree(app)
        let entry: EntryModel = app.model.entry
        entry.runShortcut(.quickEditBack)
        entry.runShortcut(.quickEditBack)
        entry.callChanged("OK1AB")
        entry.editContestField("zone", "16")
        let before: Int = app.model.logbook.rows.count
        _ = entry.handle(.enter(ctrl: false, step: .logQso(ctrlEnter: false)))
        #expect(entry.quickEdit == nil)
        #expect(entry.form.call == "")
        await app.model.logbook.settle()
        await entry.settle()
        let rows: [Qso] = app.model.logbook.rows
        #expect(rows.count == before)
        #expect(rows[1].call == "OK1AB")
        #expect(rows[1].exchangeRcvd == "599 16")
        #expect(rows[1].serialSent == 2)
    }

    @Test func logItSavesInsteadOfLogging() async throws {
        let app = try await TestApp.make()
        try await logThree(app)
        let entry: EntryModel = app.model.entry
        entry.runShortcut(.quickEditBack)
        entry.editContestField("zone", "40")
        entry.submit()
        await app.model.logbook.settle()
        await entry.settle()
        #expect(app.model.logbook.rows.count == 3)
        #expect(app.model.logbook.lastRow?.exchangeRcvd == "599 40")
    }

    @Test func anEmptyLogHasNoQuickEdit() async throws {
        let app = try await TestApp.make()
        app.model.entry.runShortcut(.quickEditBack)
        #expect(app.model.entry.quickEdit == nil)
        #expect(app.model.status.message == "Deník je prázdný")
        #expect(app.model.menu.isImplemented("edit.quickEdit"))
        #expect(MenuModel.shortcutActions["edit.quickEditForward"] == .quickEditForward)
    }
}
