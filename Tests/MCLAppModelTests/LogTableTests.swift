import Foundation
import Testing
@testable import MCLAppModel
@testable import MCLCore

/// The log window's table model (`LogTableModel`, Kotlin `LogTable.kt` `LT:157-433`) and the log's view
/// changes for the table (`LogbookModel.ViewChange`, `LogViewDiff`).
@MainActor @Suite struct LogTableTests {

    /// CQ WW CW with three QSOs logged in this order.
    private func threeQsos() async throws -> (PortedApp, LogTableModel) {
        let app = try await PortedApp.make()
        try await app.startCqWw()
        await app.log(call: "W1AW", zone: "5")
        await app.log(call: "DL1ABC", zone: "14")
        await app.log(call: "OK1AA", zone: "15")
        await app.model.logbook.settle()
        return (app, LogTableModel(app: app.model))
    }

    private func id(_ app: PortedApp, _ call: String) throws -> Int64 {
        try #require(app.model.logbook.rows.first { $0.call == call }?.id)
    }

    private func stored(_ app: PortedApp) async throws -> [Qso] {
        try await app.model.database.handle.run { access in try access.service.findAll() }
    }

    // MARK: - edits

    @Test func editReplacesTheModelRowAtSubmitThenReloadsOnlyItsRow() async throws {
        let (app, table) = try await threeQsos()
        let logbook: LogbookModel = app.model.logbook
        let id: Int64 = try id(app, "DL1ABC")
        let before: [Qso] = logbook.displayed
        table.commitEdit(id: id, column: .call, text: "dl2xyz")
        // Kotlin edits the shared row before the write: the model row changes at once, and the view scheduled at
        // submit (time order = log order here) differs from the shown one in that row only.
        #expect(table.row(id)?.call == "DL2XYZ")
        #expect(LogViewDiff.change(from: before, to: logbook.rows) == .updated(indexes: [1]))
        await table.settle()
        #expect(logbook.displayed.map(\.call) == ["W1AW", "DL2XYZ", "OK1AA"])
        // The last view reloads at most that row: nothing when the submit-time view landed first (the written row
        // equals it), row 1 when the write overtook it.
        let last: LogbookModel.ViewChange = logbook.lastViewChange
        #expect(last == .updated(indexes: []) || last == .updated(indexes: [1]))
        #expect(try await stored(app).map(\.call) == ["W1AW", "DL2XYZ", "OK1AA"])
    }

    @Test func twoQuickEditsOfOneRowBothPersist() async throws {
        let (app, table) = try await threeQsos()
        let id: Int64 = try id(app, "W1AW")
        table.commitEdit(id: id, column: .note, text: " first ")
        table.commitEdit(id: id, column: .exchange, text: "zz 5")
        await table.settle()
        let row: Qso = try #require(try await stored(app).first { $0.id == id })
        #expect(row.comment == "first")
        #expect(row.exchangeRcvd == "ZZ 5")
        #expect(table.row(id) == row)
    }

    @Test func modePickAndXqsoToggle() async throws {
        let (app, table) = try await threeQsos()
        let id: Int64 = try id(app, "W1AW")
        table.pickMode(id: id, .ssb)
        table.toggleXqso(id: id)
        #expect(app.status == "W1AW: X-QSO, nepočítá se")
        await table.settle()
        let row: Qso = try #require(try await stored(app).first { $0.id == id })
        #expect(row.mode == .ssb)
        #expect(row.xqso)
        #expect(table.menuItems(forRow: id).first == .toggleXqso(isXqso: true))
        #expect(LogTableModel.MenuItem.toggleXqso(isXqso: true).title == ContestMessage("Zrušit X-QSO (počítat)"))
    }

    // MARK: - deleting

    @Test func deletingOneRowDoesNotAskAndRemovesOnlyThatRow() async throws {
        let (app, table) = try await threeQsos()
        let logbook: LogbookModel = app.model.logbook
        let status: String = app.status
        table.deleteOne(id: try id(app, "DL1ABC"))
        #expect(!table.confirmingDelete)
        await table.settle()
        #expect(logbook.displayed.map(\.call) == ["W1AW", "OK1AA"])
        #expect(logbook.lastViewChange == .removed(indexes: [1]))
        #expect(logbook.qsoCount == 2)
        // Kotlin `state.delete(qso)` sets no status.
        #expect(app.status == status)
    }

    @Test func deletingTheSelectionAsksThenDeletesTheChosenRows() async throws {
        let (app, table) = try await threeQsos()
        let logbook: LogbookModel = app.model.logbook
        table.select([try id(app, "W1AW"), try id(app, "OK1AA")])
        table.askDeleteSelection()
        #expect(table.confirmingDelete)
        #expect(table.deleteTitle == .verbatim("Smazat 2 QSO?"))
        #expect(table.deleteText == ContestMessage("Vybraná spojení se odstraní z deníku. Akci nelze vzít zpět."))
        #expect(logbook.rows.count == 3)
        table.confirmDeleteSelection()
        #expect(table.selected.isEmpty)
        await table.settle()
        #expect(logbook.displayed.map(\.call) == ["DL1ABC"])
        #expect(app.status == "Smazáno 2 QSO")
        #expect(try await stored(app).map(\.call) == ["DL1ABC"])
    }

    @Test func aFailedSelectionDeleteKeepsItsError() async throws {
        let (app, table) = try await threeQsos()
        try await app.model.database.handle.run { access in
            try access.repository.connection.execute("""
                CREATE TEMP TRIGGER fail_delete BEFORE DELETE ON qso
                BEGIN SELECT RAISE(ABORT, 'disk full'); END
                """)
        }
        table.select([try id(app, "W1AW"), try id(app, "OK1AA")])
        table.askDeleteSelection()
        table.confirmDeleteSelection()
        await table.settle()
        #expect(app.model.logbook.rows.count == 3)
        #expect(app.status.contains("disk full"))
        #expect(!app.status.contains("Smazáno"))
    }

    @Test func bulkEditsStartFromTheModelRows() async throws {
        let (app, table) = try await threeQsos()
        let w1aw: Int64 = try id(app, "W1AW")
        table.select([w1aw, try id(app, "OK1AA")])
        // An edit submitted just before: the view copy is still the old row, the model row is not.
        table.commitEdit(id: w1aw, column: .note, text: "fresh")
        #expect(table.chosen.first { $0.id == w1aw }?.comment == "fresh")
        table.runBulk(.xqso)
        await table.settle()
        let row: Qso = try #require(try await stored(app).first { $0.id == w1aw })
        #expect(row.comment == "fresh")
        #expect(row.xqso)
        #expect(table.row(w1aw) == row)
    }

    @Test func cancellingTheConfirmationKeepsEverything() async throws {
        let (app, table) = try await threeQsos()
        table.select([try id(app, "W1AW"), try id(app, "OK1AA")])
        table.askDeleteSelection()
        table.cancelDelete()
        table.confirmDeleteSelection()
        await table.settle()
        #expect(app.model.logbook.rows.count == 3)
        #expect(table.selected.count == 2)
    }

    // MARK: - selection and menu

    @Test func selectionBarShowsFromTwoRows() async throws {
        let (app, table) = try await threeQsos()
        table.select([try id(app, "W1AW")])
        #expect(!table.showsSelectionBar)
        table.select([try id(app, "W1AW"), try id(app, "DL1ABC")])
        #expect(table.showsSelectionBar)
        #expect(table.selectionText == ContestMessage("Vybráno %s z %s", .int(2), .int(3)))
        table.selectAll()
        #expect(table.selected.count == 3)
        table.clearSelection()
        #expect(table.selected.isEmpty)
    }

    @Test func menuOfOneRowAndOfASelection() async throws {
        let (app, table) = try await threeQsos()
        let w1aw: Int64 = try id(app, "W1AW")
        let dl: Int64 = try id(app, "DL1ABC")
        let single: [LogTableModel.MenuItem] = [.toggleXqso(isXqso: false), .playRecording, .deleteOne]
        #expect(table.menuItems(forRow: w1aw) == single)
        #expect(single.map(\.title) == [ContestMessage("Označit jako X-QSO (nepočítat)"),
                                        ContestMessage("Přehrát nahrávku QSO"), .verbatim("Smazat QSO")])
        #expect(single.map(\.isEnabled) == [true, true, true])
        table.select([w1aw, dl])
        let bulk: [LogTableModel.MenuItem] = BulkAction.allCases.map { .bulk($0) } + [.deleteSelection]
        #expect(table.menuItems(forRow: dl) == bulk)
        #expect(LogTableModel.MenuItem.deleteSelection.title == .verbatim("Smazat"))
        // A row outside the selection gets its own items.
        #expect(table.menuItems(forRow: try id(app, "OK1AA")) == single)
        table.perform(.deleteSelection, row: dl)
        #expect(table.confirmingDelete)
    }

    @Test func bulkActionsWorkOnTheDisplayedOrder() async throws {
        let (app, table) = try await threeQsos()
        let logbook: LogbookModel = app.model.logbook
        logbook.sort(by: .call)
        logbook.sort(by: .call)
        await logbook.settle()
        table.selectAll()
        #expect(table.chosen.map(\.call) == ["W1AW", "OK1AA", "DL1ABC"])
        table.runBulk(.operator)
        #expect(table.bulkPrompt == .operator)
        #expect(table.bulkTitle == BulkAction.operator.dialogTitle(count: 3))
        table.submitBulk("ok1abc")
        #expect(table.bulkPrompt == nil)
        #expect(app.status == "Operátor: upraveno 3 QSO")
        await table.settle()
        #expect(try await stored(app).map(\.operator) == ["OK1ABC", "OK1ABC", "OK1ABC"])
        // X-QSO runs at once; all set → cleared next time.
        table.runBulk(.xqso)
        #expect(table.bulkPrompt == nil)
        await table.settle()
        #expect(try await stored(app).allSatisfy(\.xqso))
        table.runBulk(.xqso)
        #expect(app.status == "Zrušení X-QSO: upraveno 3 QSO")
        await table.settle()
        #expect(try await stored(app).allSatisfy { !$0.xqso })
        // An invalid input: only the text.
        table.runBulk(.mode)
        table.submitBulk("xyz")
        #expect(app.status == "Mód: neznámý „xyz“")
    }

    @Test func aChangedSearchClearsTheSelection() async throws {
        let (app, table) = try await threeQsos()
        table.select([try id(app, "W1AW"), try id(app, "OK1AA")])
        table.setQuery("")
        #expect(table.selected.count == 2)
        table.setQuery("ok")
        #expect(table.selected.isEmpty)
        await app.model.logbook.settle()
        #expect(app.model.logbook.displayed.map(\.call) == ["OK1AA"])
        #expect(table.searchCaption == ContestMessage("%s z %s", .int(1), .int(3)))
    }

    @Test func ctrlFFillsTheSearchOnce() async throws {
        let (app, table) = try await threeQsos()
        app.model.windows.findInLog(" dl1abc ")
        #expect(table.takeSearchRequest())
        #expect(app.model.logbook.query == "call:DL1ABC")
        #expect(app.model.windows.logSearchRequest == nil)
        #expect(!table.takeSearchRequest())
        app.model.windows.findInLog("")
        table.takeSearchRequest()
        #expect(app.model.logbook.query == "")
    }

    // MARK: - warnings

    @Test func warningsFilterAndTexts() async throws {
        let app = try await PortedApp.make()
        try await app.startCqWw()
        await app.log(call: "W1AW", zone: "14")
        await app.log(call: "OK1AA", zone: "15")
        let logbook: LogbookModel = app.model.logbook
        await logbook.settle()
        let table = LogTableModel(app: app.model)
        let w1aw: Int64 = try id(app, "W1AW")
        #expect(logbook.warnings.containsKey(w1aw))
        #expect(!logbook.warnings.containsKey(try id(app, "OK1AA")))
        #expect(table.warningText(w1aw)?.contains("14") == true)
        #expect(table.warningsButton == ContestMessage("⚠ %s varování", .int(1)))
        #expect(table.searchCaption == ContestMessage("např. ok1 · 57 · ex:JN79 · nrrx:12 · band:20m"))
        table.toggleWarnings()
        await logbook.settle()
        #expect(logbook.displayed.map(\.call) == ["W1AW"])
        #expect(table.warningsButton == ContestMessage("⚠ všechna QSO"))
        #expect(table.searchCaption == ContestMessage("%s z %s", .int(1), .int(2)))
        // Fixing the zone empties the filtered view.
        table.commitEdit(id: w1aw, column: .exchange, text: "5")
        await table.settle()
        #expect(logbook.warnings.isEmpty)
        #expect(logbook.displayed.isEmpty)
        table.toggleWarnings()
        await logbook.settle()
        #expect(logbook.displayed.count == 2)
        #expect(table.warningsButton == nil)
    }

    // MARK: - menu

    @Test func postContestMenuItemCarriesItsState() async throws {
        let app = try await PortedApp.make()
        #expect(!MenuActions.isChecked("contest.postcontest", app: app.model))
        _ = MenuActions.perform("contest.postcontest", app: app.model)
        #expect(app.model.operating.postContest)
        #expect(MenuActions.isChecked("contest.postcontest", app: app.model))
        #expect(!MenuActions.isChecked("contest.rescore", app: app.model))
    }
}

/// `LogTableClick`: a click acts on the QSO pressed, never on a row index that a view applied in between moved.
@Suite struct LogTableClickTests {

    private func qso(_ id: Int64) -> Qso {
        var qso = Qso()
        qso.id = id
        return qso
    }

    @Test func aReorderBetweenMouseDownAndActionCannotHitAnotherQso() throws {
        let shown: [Qso] = [qso(1), qso(2), qso(3)]
        let pressed = try #require(LogTableClick.pressed(row: 1, column: .xqso, in: shown))
        #expect(pressed == LogTableClick(id: 2, column: .xqso))
        #expect(pressed.target(row: 1, column: .xqso, in: shown) == 2)
        // Time descending: a new QSO lands at the top while the button is down.
        let reordered: [Qso] = [qso(9), qso(1), qso(2), qso(3)]
        #expect(pressed.target(row: 1, column: .xqso, in: reordered) == nil)
        #expect(pressed.target(row: 2, column: .xqso, in: reordered) == 2)
        // A drag that ends in another cell or column does nothing.
        #expect(pressed.target(row: 0, column: .xqso, in: shown) == nil)
        #expect(pressed.target(row: 1, column: .call, in: shown) == nil)
        // The pressed row was deleted meanwhile.
        #expect(pressed.target(row: 1, column: .xqso, in: [qso(1), qso(3)]) == nil)
        #expect(pressed.target(row: 5, column: .xqso, in: shown) == nil)
    }

    @Test func noTargetOutsideQsoRows() {
        let shown: [Qso] = [qso(1), Qso()]
        #expect(LogTableClick.pressed(row: -1, column: .call, in: shown) == nil)
        #expect(LogTableClick.pressed(row: 0, column: nil, in: shown) == nil)
        #expect(LogTableClick.pressed(row: 1, column: .call, in: shown) == nil)
        #expect(LogTableClick.pressed(row: 2, column: .call, in: shown) == nil)
    }
}

/// `LogViewDiff`: an edit reloads only the changed rows, a delete removes only its rows; anything else reloads.
@Suite struct LogViewDiffTests {

    private func qso(_ id: Int64, _ call: String) -> Qso {
        var qso = Qso()
        qso.id = id
        qso.call = call
        return qso
    }

    @Test func sameOrderReportsTheChangedRows() {
        let old: [Qso] = [qso(1, "A"), qso(2, "B"), qso(3, "C")]
        let new: [Qso] = [qso(1, "A"), qso(2, "X"), qso(3, "C")]
        #expect(LogViewDiff.change(from: old, to: new) == .updated(indexes: [1]))
        #expect(LogViewDiff.change(from: old, to: old) == .updated(indexes: []))
    }

    @Test func removedRowsKeepTheOthersInOrder() {
        let old: [Qso] = [qso(1, "A"), qso(2, "B"), qso(3, "C"), qso(4, "D")]
        #expect(LogViewDiff.change(from: old, to: [qso(1, "A"), qso(4, "D")]) == .removed(indexes: [1, 2]))
        #expect(LogViewDiff.change(from: old, to: []) == .removed(indexes: [0, 1, 2, 3]))
    }

    @Test func anythingElseReloads() {
        let old: [Qso] = [qso(1, "A"), qso(2, "B"), qso(3, "C")]
        // Moved by a re-sort after the edit.
        #expect(LogViewDiff.change(from: old, to: [qso(2, "B"), qso(1, "Z"), qso(3, "C")]) == .reload)
        // A removed row next to a changed one.
        #expect(LogViewDiff.change(from: old, to: [qso(1, "Z"), qso(3, "C")]) == .reload)
        // More rows.
        #expect(LogViewDiff.change(from: old, to: old + [qso(4, "D")]) == .reload)
    }
}
