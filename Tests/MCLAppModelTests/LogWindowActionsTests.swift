import Foundation
import Testing
@testable import MCLAppModel
@testable import MCLCore

/// The log window's N1MM row actions (Edit contact, Jump to this frequency, Rescore from this point on, Copy as ADIF),
/// its view options (only QSOs with a note, the mode column) and the deleted QSOs kept for a restore (DELETEDQS).
@MainActor @Suite struct LogWindowActionsTests {

    /// The row actions' ports, recorded.
    @MainActor final class Recorder {
        var edited: [Int64] = []
        var tuned: [(Int64, Mode?)] = []
        var rescoredFrom: [Date] = []
        var copied: [String] = []
        var modeColumn: [Bool] = []
        var contest: Bool = true

        var actions: LogTableModel.RowActions {
            var actions = LogTableModel.RowActions()
            actions.edit = { self.edited.append($0) }
            actions.tune = { self.tuned.append(($0, $1)) }
            actions.rescoreFrom = { self.rescoredFrom.append($0) }
            actions.copy = { self.copied.append($0) }
            actions.contestActive = { self.contest }
            actions.setModeColumn = { self.modeColumn.append($0) }
            return actions
        }
    }

    private func threeQsos() async throws -> (PortedApp, LogTableModel, Recorder) {
        let app = try await PortedApp.make()
        try await app.startCqWw()
        await app.log(call: "W1AW", zone: "5")
        await app.log(call: "DL1ABC", zone: "14")
        await app.log(call: "OK1AA", zone: "15")
        await app.model.logbook.settle()
        let recorder = Recorder()
        let table = LogTableModel(logbook: app.model.logbook, windows: app.model.windows, status: app.model.status,
                                  actions: recorder.actions)
        return (app, table, recorder)
    }

    private func id(_ app: PortedApp, _ call: String) throws -> Int64 {
        try #require(app.model.logbook.rows.first { $0.call == call }?.id)
    }

    // MARK: - row actions

    @Test func rowMenuOffersTheN1mmActions() async throws {
        let (app, table, recorder) = try await threeQsos()
        let id: Int64 = try id(app, "DL1ABC")
        let items: [LogTableModel.MenuItem] = table.menuItems(forRow: id)
        #expect(items == [.edit, .toggleXqso(isXqso: false), .playRecording, .jumpToFrequency, .rescoreFromHere,
                          .ratesToHere, .copyAdif, .deleteOne])
        recorder.contest = false
        #expect(!table.menuItems(forRow: id).contains(.rescoreFromHere), "rescoring needs an open contest")
        // A selection of two or more: its bulk actions with the ADIF copy.
        table.select([id, try self.id(app, "W1AW")])
        #expect(table.menuItems(forRow: id) == BulkAction.allCases.map { .bulk($0) } + [.copyAdif, .deleteSelection])
    }

    @Test func rowActionsReachTheirPorts() async throws {
        let (app, table, recorder) = try await threeQsos()
        let id: Int64 = try id(app, "DL1ABC")
        let qso: Qso = try #require(table.row(id))
        table.perform(.edit, row: id)
        #expect(recorder.edited == [id])
        table.perform(.jumpToFrequency, row: id)
        #expect(recorder.tuned.count == 1)
        #expect(recorder.tuned.first?.0 == Int64(qso.freqHz))
        #expect(recorder.tuned.first?.1 == qso.mode)
        table.perform(.rescoreFromHere, row: id)
        #expect(recorder.rescoredFrom == [try #require(qso.timestampUtc)])
    }

    @Test func copyAsAdifCopiesTheRowOrTheSelection() async throws {
        let (app, table, recorder) = try await threeQsos()
        let one: Int64 = try id(app, "DL1ABC")
        table.perform(.copyAdif, row: one)
        let single: String = try #require(recorder.copied.last)
        #expect(single.contains("<CALL:6>DL1ABC"))
        #expect(!single.contains("W1AW"))
        #expect(app.status == "Zkopírováno 1 QSO jako ADIF")
        table.select([one, try id(app, "OK1AA")])
        table.perform(.copyAdif, row: one)
        let both: String = try #require(recorder.copied.last)
        #expect(both.contains("<CALL:6>DL1ABC") && both.contains("<CALL:5>OK1AA"))
        #expect(both.components(separatedBy: "<EOR>").count - 1 == 2 || both.components(separatedBy: "<eor>").count - 1 == 2)
    }

    @Test func theStationOfTheSelectionChangesInBulk() async throws {
        let (app, table, _) = try await threeQsos()
        table.select([try id(app, "W1AW"), try id(app, "OK1AA")])
        table.runBulk(.station)
        table.submitBulk("MULT")
        await table.settle()
        let rows: [Qso] = try await app.model.database.handle.run { try $0.service.findAll() }
        #expect(rows.filter { $0.stationId == "MULT" }.map(\.call).sorted() == ["OK1AA", "W1AW"])
    }

    // MARK: - edit dialog

    @Test func theEditDialogMovesThroughTheLog() async throws {
        let (app, _, _) = try await threeQsos()
        let dialogs: DialogsModel = app.model.dialogs
        let first: Int64 = try id(app, "W1AW")
        let model = try #require(QsoEditModel.logged(id: first, logbook: app.model.logbook, dialogs: dialogs))
        dialogs.openQsoEdit(model)
        #expect(model.canStep)
        model.form.note = "first"
        model.step(1)
        let second = try #require(dialogs.qsoEdit)
        #expect(second.target == .logged(try id(app, "DL1ABC")))
        second.step(-1)
        #expect(dialogs.qsoEdit?.target == .logged(first))
        // Before the first row there is nothing: the dialog stays.
        dialogs.qsoEdit?.step(-1)
        #expect(dialogs.qsoEdit?.target == .logged(first))
        await app.model.logbook.settle()
        let rows: [Qso] = try await app.model.database.handle.run { try $0.service.findAll() }
        #expect(rows.first { $0.call == "W1AW" }?.comment == "first", "the step saved the change")
    }

    // MARK: - view options

    @Test func onlyQsosWithANote() async throws {
        let (app, table, _) = try await threeQsos()
        table.commitEdit(id: try id(app, "DL1ABC"), column: .note, text: "QSL via buro")
        await table.settle()
        table.toggleNotes()
        await app.model.logbook.settle()
        #expect(app.model.logbook.displayed.map(\.call) == ["DL1ABC"])
        #expect(table.searchCaption == ContestMessage("%s z %s", .int(1), .int(3)))
        table.toggleNotes()
        await app.model.logbook.settle()
        #expect(app.model.logbook.displayed.count == 3)
    }

    @Test func theModeColumnCanBeHiddenAndIsSaved() async throws {
        let (app, table, recorder) = try await threeQsos()
        #expect(app.model.logbook.visibleColumns.contains(.mode))
        table.setShowsModeColumn(false)
        #expect(!app.model.logbook.visibleColumns.contains(.mode))
        #expect(!table.showsModeColumn)
        #expect(recorder.modeColumn == [false])
        // A contest change keeps it hidden.
        app.model.logbook.setContestColumns(LogTableColumns.visible(usesSerial: true, usesExchangeBeyondRst: true,
                                                                    contestActive: true))
        #expect(!app.model.logbook.visibleColumns.contains(.mode))
        table.setShowsModeColumn(true)
        #expect(app.model.logbook.visibleColumns.contains(.mode))
    }

    @Test func theAppSavesTheModeColumnInTheConfiguration() async throws {
        let app = try await PortedApp.make()
        let table = LogTableModel(app: app.model)
        table.setShowsModeColumn(false)
        #expect(app.model.config.config.logShowModeColumn == false)
    }

    // MARK: - deleted QSOs

    @Test func aDeletedQsoIsKeptAndCanBeRestored() async throws {
        let (app, table, _) = try await threeQsos()
        let logbook: LogbookModel = app.model.logbook
        let id: Int64 = try id(app, "DL1ABC")
        let original: Qso = try #require(try await app.model.database.handle.run { try $0.service.findById(id) })
        table.deleteOne(id: id)
        await table.settle()
        #expect(!logbook.rows.contains { $0.call == "DL1ABC" })

        table.openDeleted()
        await table.settle()
        let kept = try #require(table.deleted)
        #expect(kept.map(\.qso.call) == ["DL1ABC"])
        #expect(kept.first?.qso.timestampUtc == original.timestampUtc)
        #expect(kept.first?.qso.exchangeRcvd == original.exchangeRcvd)

        table.deletedSelection = Set(kept.map(\.archiveId))
        table.restoreDeleted()
        await table.settle()
        await logbook.settle()
        let restored: Qso = try #require(try await app.model.database.handle.run { access in
            try access.service.findAll().first { $0.call == "DL1ABC" }
        })
        #expect(restored.timestampUtc == original.timestampUtc)
        #expect(restored.exchangeRcvd == original.exchangeRcvd)
        #expect(restored.uuid != original.uuid, "a new merge key: a cluster tombstone of the old one cannot hide it")
        #expect(table.deleted?.isEmpty == true)
        #expect(app.status == "Obnoveno 1 smazaných QSO")
        #expect(logbook.qsoCount == 3)
    }

    @Test func wipingTheLogKeepsEveryQso() async throws {
        let (app, table, _) = try await threeQsos()
        await app.model.logbook.wipeLog()
        #expect(app.model.logbook.rows.isEmpty)
        table.openDeleted()
        await table.settle()
        #expect(Set(table.deleted?.map(\.qso.call) ?? []) == ["W1AW", "DL1ABC", "OK1AA"])
    }
}
