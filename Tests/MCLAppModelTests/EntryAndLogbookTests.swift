import Foundation
import MCLCore
import Testing
@testable import MCLAppModel

/// `EntryModel.submit` (`K:EntryPanel.kt:468-567` `logQso`) end to end over a temporary database.
@MainActor @Suite struct EntryModelTests {

    @Test func contestQsoIsLoggedScoredAndWiped() async throws {
        let app = try await TestApp.make()
        try await app.startCqWwCw()
        let entry: EntryModel = app.model.entry
        entry.setFrequency("14025")
        entry.callChanged("DL1ABC")
        #expect(app.model.contest.lastPreview != nil)
        entry.editContestField("zone", "14")
        #expect(entry.contestReady)
        entry.submit()
        // Wiped at once, the report prefilled again.
        #expect(entry.form.call == "")
        #expect(entry.form.contestExchange["rst"] == "599")
        #expect(entry.form.contestExchange["zone"] == nil)
        await entry.settle()
        let rows: [Qso] = app.model.logbook.rows
        #expect(rows.count == 1)
        let qso: Qso = try #require(rows.first)
        #expect(qso.call == "DL1ABC")
        #expect(qso.band == .m20)
        #expect(qso.mode == .cw)
        #expect(qso.exchangeRcvd == "599 14")
        #expect(qso.rstSent == "599")
        #expect(qso.rstRcvd == "599")
        #expect(qso.exchangeSent == "599 15")
        #expect(qso.serialSent == 1)
        #expect(qso.operator == "OK1XOE")
        #expect(qso.runMode == .searchAndPounce)
        #expect(qso.contestId == app.model.contest.activeId)
        #expect(qso.dxccName == "Germany")
        #expect(app.model.logbook.qsoCount == 1)
        #expect(app.model.logbook.revision >= 1)
        #expect(app.model.contest.score?.qsoCount == 1)
        #expect(app.model.logbook.deferredEffects == [.plugin])
        // A dupe on the same band.
        entry.callChanged("DL1ABC")
        #expect(entry.isDupe)
        entry.setFrequency("7025")
        #expect(!entry.isDupe)
    }

    @Test func incompleteExchangeIsNotLogged() async throws {
        let app = try await TestApp.make()
        try await app.startCqWwCw()
        let entry: EntryModel = app.model.entry
        entry.setFrequency("14025")
        entry.callChanged("DL1ABC")
        entry.submit()
        await entry.settle()
        #expect(entry.form.call == "DL1ABC")
        #expect(app.model.logbook.rows.isEmpty)
    }

    @Test func emptyCallOnlyFocuses() async throws {
        let app = try await TestApp.make()
        let entry: EntryModel = app.model.entry
        let before: Int = entry.focusRequest
        entry.callChanged(" ")
        entry.submit()
        #expect(entry.focusRequest == before + 1)
        #expect(app.model.status.message == "")
    }

    @Test func qsoWithoutBandIsNotCounted() async throws {
        let app = try await TestApp.make()
        try await app.startCqWwCw()
        await app.logContestQso(call: "DL1ABC", zone: "14", freqKHz: "")
        #expect(app.model.logbook.rows.count == 1)
        #expect(app.model.status.message == "DL1ABC bez pásma — do skóre se nepočítá")
    }

    @Test func modeOutsideTheContestIsNotCounted() async throws {
        let app = try await TestApp.make()
        try await app.startCqWwCw()
        app.model.entry.setMode(.ssb)
        await app.logContestQso(call: "DL1ABC", zone: "14")
        #expect(app.model.status.message == "DL1ABC v módu SSB — závod ho nemá, nepočítá se")
    }

    /// Free logging: the QSO goes into the open logbook without a contest (Kotlin refused it).
    @Test func withoutAContestTheQsoIsStoredInTheOpenLogbook() async throws {
        let app = try await TestApp.make()
        let entry: EntryModel = app.model.entry
        entry.setFrequency("14025")
        entry.callChanged("DL1ABC")
        entry.setMode(.cw)
        entry.editExchange("579 Jan")
        entry.submit()
        await entry.settle()
        let qso: Qso = try #require(app.model.logbook.rows.first)
        #expect(app.model.logbook.rows.count == 1)
        #expect(qso.contestId == "")
        #expect(qso.call == "DL1ABC")
        #expect(qso.band == .m20)
        #expect(qso.mode == .cw)
        #expect(qso.exchangeRcvd == "579 Jan")
        #expect(qso.operator == "OK1XOE")
        #expect(qso.dxccName == "Germany")
        #expect(qso.points == 0)
        #expect(!qso.uuid.isEmpty)
        #expect(app.model.logbook.qsoCount == 1)
        #expect(app.model.status.message == "")
        let stored: [Qso] = try await app.model.database.handle.run { try $0.service.findAllIncludingDeleted() }
        #expect(stored.map(\.call) == ["DL1ABC"])
        #expect(stored.first?.contestId == "")
    }

    /// Free logging has no dupes: the same call on the same band is neither flagged nor blocked.
    @Test func freeLoggingHasNoDupes() async throws {
        let app = try await TestApp.make()
        let entry: EntryModel = app.model.entry
        entry.setFrequency("14025")
        entry.callChanged("DL1ABC")
        #expect(!entry.isDupe)
        entry.submit()
        await entry.settle()
        entry.callChanged("DL1ABC")
        #expect(!entry.isDupe)
        #expect(!app.model.logbook.isDupe(call: "DL1ABC", band: .m20))
        entry.submit()
        await entry.settle()
        #expect(app.model.logbook.rows.map(\.call) == ["DL1ABC", "DL1ABC"])
        #expect(ScoreLine.of(contest: app.model.contest) == nil)
    }

    /// „Žádný (volné logování)" after a contest: the log shows the free-logging QSOs only; opening the contest
    /// again shows its own QSOs only.
    @Test func freeLoggingAndTheContestKeepSeparateLogs() async throws {
        let app = try await TestApp.make()
        try await app.startCqWwCw()
        let id: String = try #require(app.model.contest.activeId)
        await app.logContestQso(call: "DL1ABC", zone: "14")
        app.model.contest.deactivate()
        await app.model.contest.settleActivations()
        #expect(app.model.logbook.rows.isEmpty)
        let entry: EntryModel = app.model.entry
        entry.setFrequency("7010")
        entry.callChanged("W1AW")
        entry.editExchange(" 42 ")
        entry.submit()
        await entry.settle()
        let qso: Qso = try #require(app.model.logbook.rows.first)
        #expect(app.model.logbook.rows.count == 1)
        #expect(qso.call == "W1AW")
        #expect(qso.contestId == "")
        #expect(qso.exchangeRcvd == " 42 ")
        #expect(qso.band == .m40)
        #expect(app.model.contest.score == nil)
        // A contest dupe is no free-logging dupe.
        entry.setFrequency("14025")
        entry.callChanged("DL1ABC")
        #expect(!entry.isDupe)
        entry.wipe()

        #expect(await app.model.contest.open(contestId: id))
        #expect(app.model.logbook.rows.map(\.call) == ["DL1ABC"])
        #expect(app.model.contest.score?.qsoCount == 1)

        // Free logging again shows the free-logging QSOs.
        app.model.contest.deactivate()
        await app.model.contest.settleActivations()
        #expect(app.model.logbook.rows.map(\.call) == ["W1AW"])
    }

    /// The ADIF export without a contest writes the free-logging QSOs (Cabrillo stays contest-only).
    @Test func freeLoggingQsosExportToAdif() async throws {
        let app = try await TestApp.make()
        try await app.startCqWwCw()
        await app.logContestQso(call: "DL1ABC", zone: "14")
        app.model.contest.deactivate()
        await app.model.contest.settleActivations()
        let entry: EntryModel = app.model.entry
        entry.setFrequency("7010")
        entry.callChanged("W1AW")
        entry.submit()
        await entry.settle()
        let file: URL = app.dir.child("free.adi")
        await app.model.exports.exportAdif(to: file)
        let text: String = try String(contentsOf: file, encoding: .utf8)
        #expect(text.contains("<CALL:4>W1AW"))
        #expect(!text.contains("DL1ABC"))
        #expect(!text.contains("CONTEST_ID"))
        await app.model.exports.exportCabrillo(to: app.dir.child("free.log"))
        #expect(app.model.status.message == "Cabrillo: není aktivní závod")
    }

    @Test func commonCallsignsAreNotCommands() throws {
        // Measured against `CallFieldCommands.parse`: ordinary callsigns stay callsigns.
        let calls: [String] = ["OK1XOE", "DL1ABC", "W1AW", "K1A", "VE3XYZ", "OK1XOE/P", "OK1XOE/MM", "9A1A",
                               "3DA0RU", "4X4AAA", "OH0X", "R1ANC", "RA9AA", "2E0AAA", "EA8/DL1ABC", "S50A"]
        for call in calls {
            #expect(try CallFieldCommands.parse(call, currentFreqHz: 14_025_000) == nil, "\(call)")
        }
    }

    @Test func textCommandIsNotLogged() async throws {
        let app = try await TestApp.make()
        try await app.startCqWwCw()
        let entry: EntryModel = app.model.entry
        entry.setFrequency("14025")
        entry.callChanged("14030")
        entry.editContestField("zone", "14")
        #expect(entry.contestReady)
        entry.submit()
        await entry.settle()
        #expect(app.model.logbook.rows.isEmpty)
        #expect(entry.form.call == "")
        // The command runs (a QSY), it is never logged.
        #expect(entry.form.freqKHz == "14030.00")
        #expect(app.model.status.message == "QSY na 14030.00 kHz")
    }

    @Test func serialFollowsTheLog() async throws {
        let app = try await TestApp.make()
        try await app.startCqWwCw()
        #expect(app.model.logbook.nextSerial == 1)
        await app.logContestQso(call: "DL1ABC", zone: "14")
        await app.logContestQso(call: "W1AW", zone: "5")
        #expect(app.model.logbook.rows.map(\.serialSent) == [1, 2])
        #expect(app.model.logbook.nextSerial == 3)
    }

    @Test func sentExchangeTextShowsTheStation() async throws {
        let app = try await TestApp.make()
        #expect(app.model.entry.sentExchangeText == "")
        try await app.startCqWwCw()
        #expect(app.model.entry.sentExchangeText == "599 15")
    }

    @Test func gridQsySetsFrequencyAndKeepsTheLockedMode() async throws {
        let app = try await TestApp.make()
        try await app.startCqWwCw()
        app.model.entry.qsy(toKHz: 7025, mode: .ssb)
        #expect(app.model.entry.form.freqKHz == "7025.00")
        #expect(app.model.entry.form.mode == .cw)
    }
}

/// `LogbookModel`: effects of the logging pipeline, the view (sort, search, generations) and the marks.
@MainActor @Suite struct LogbookModelTests {

    @Test func pipelineEffectsAreAppliedInOrder() async throws {
        let app = try await TestApp.make()
        try await app.startCqWwCw()
        let logbook: LogbookModel = app.model.logbook
        let revision: Int64 = logbook.revision
        var qso = Qso()
        qso.call = "DL1ABC"
        qso.band = .m20
        let effects: [LogEffect] = [.persist, .bumpRevision, .addDupe, .appendRow, .consumeReservedSerial,
                                    .refreshCount, .publishInsert, .plugin, .broadcast]
        let stored: Qso? = try await logbook.perform(qso, effects: effects)
        #expect(stored?.id != nil)
        #expect(logbook.revision == revision + 1)
        #expect(logbook.isDupe(call: "dl1abc", band: .m20))
        #expect(logbook.rows.map(\.call) == ["DL1ABC"])
        #expect(logbook.qsoCount == 1)
        #expect(logbook.deferredEffects == [.plugin, .broadcast])
        // A refused plan stores nothing.
        let refused: Qso? = try await logbook.perform(qso, effects: [.status("x")])
        #expect(refused == nil)
        #expect(logbook.rows.count == 1)
    }

    @Test func viewSortsAndSearchesOffTheMainThread() async throws {
        let app = try await TestApp.make()
        try await app.startCqWwCw()
        await app.logContestQso(call: "W1AW", zone: "5")
        await app.logContestQso(call: "DL1ABC", zone: "14")
        await app.logContestQso(call: "OK1AA", zone: "15")
        let logbook: LogbookModel = app.model.logbook
        await logbook.settle()
        #expect(logbook.displayed.map(\.call) == ["W1AW", "DL1ABC", "OK1AA"])
        logbook.sort(by: .call)
        await logbook.settle()
        #expect(logbook.displayed.map(\.call) == ["DL1ABC", "OK1AA", "W1AW"])
        logbook.sort(by: .call)
        await logbook.settle()
        #expect(!logbook.ascending)
        #expect(logbook.displayed.map(\.call) == ["W1AW", "OK1AA", "DL1ABC"])
        logbook.setQuery("call:OK")
        await logbook.settle()
        #expect(logbook.displayed.map(\.call) == ["OK1AA"])
        #expect(logbook.lastViewChange == .reload)
    }

    @Test func lateResultOfAnOlderGenerationIsDropped() async throws {
        let app = try await TestApp.make()
        try await app.startCqWwCw()
        await app.logContestQso(call: "W1AW", zone: "5")
        await app.logContestQso(call: "DL1ABC", zone: "14")
        let logbook: LogbookModel = app.model.logbook
        logbook.setQuery("call:W1")
        logbook.setQuery("call:DL")
        await logbook.settle()
        #expect(logbook.displayed.map(\.call) == ["DL1ABC"])
    }

    @Test func appendToTheDefaultViewInsertsOneRow() async throws {
        let app = try await TestApp.make()
        try await app.startCqWwCw()
        await app.logContestQso(call: "W1AW", zone: "5")
        let logbook: LogbookModel = app.model.logbook
        await logbook.settle()
        await app.logContestQso(call: "DL1ABC", zone: "14")
        #expect(logbook.lastViewChange == .appended(index: 1))
        #expect(logbook.displayed.map(\.call) == ["W1AW", "DL1ABC"])
    }

    @Test func marksFollowTheLog() async throws {
        let app = try await TestApp.make()
        try await app.startCqWwCw()
        await app.logContestQso(call: "DL1ABC", zone: "14")
        await app.logContestQso(call: "DL1ABC", zone: "14")
        let logbook: LogbookModel = app.model.logbook
        await logbook.settle()
        let ids: [Int64] = logbook.rows.compactMap(\.id)
        #expect(ids.count == 2)
        let first: QsoMarks.Mark = try #require(logbook.marks[ids[0]])
        let second: QsoMarks.Mark = try #require(logbook.marks[ids[1]])
        #expect(!first.dupe)
        #expect(first.isMultiplier)
        #expect(second.dupe)
        app.model.contest.deactivate()
        await logbook.settle()
        #expect(logbook.marks.isEmpty)
    }
}

/// Serial reservation, a failing insert, quit and database switch with work in flight, the closed handle.
@MainActor @Suite struct SubmissionLifecycleTests {

    /// Types one complete CQ WW CW QSO without submitting it.
    private static func type(_ entry: EntryModel, call: String, zone: String) {
        entry.setFrequency("14025")
        entry.callChanged(call)
        entry.editContestField("zone", zone)
    }

    /// Makes every insert into `qso` fail inside SQLite (a real failing repository, no seam).
    private static func failInserts(_ app: TestApp) async throws {
        try await app.model.database.handle.run { access in
            try access.repository.connection.execute(
                "CREATE TEMP TRIGGER fail_insert BEFORE INSERT ON qso BEGIN SELECT RAISE(ABORT, 'disk full'); END")
        }
    }

    @Test func backToBackSubmitsGetConsecutiveSerials() async throws {
        let app = try await TestApp.make()
        try await app.startCqWwCw()
        let entry: EntryModel = app.model.entry
        Self.type(entry, call: "DL1ABC", zone: "14")
        entry.submit()
        Self.type(entry, call: "W1AW", zone: "5")
        entry.submit()
        #expect(app.model.logbook.nextSerial == 3)
        await entry.settle()
        #expect(app.model.logbook.rows.map(\.serialSent) == [1, 2])
        #expect(app.model.logbook.reservedSerials == 0)
        #expect(app.model.logbook.nextSerial == 3)
    }

    @Test func threeSubmitsWithOneInFlight() async throws {
        let app = try await TestApp.make()
        try await app.startCqWwCw()
        let entry: EntryModel = app.model.entry
        Self.type(entry, call: "DL1ABC", zone: "14")
        entry.submit()
        await Task.yield()
        Self.type(entry, call: "W1AW", zone: "5")
        entry.submit()
        Self.type(entry, call: "OK1AA", zone: "15")
        entry.submit()
        await entry.settle()
        #expect(app.model.logbook.rows.map(\.serialSent) == [1, 2, 3])
        #expect(app.model.logbook.rows.map { $0.exchangeSent } == ["599 15", "599 15", "599 15"])
        #expect(app.model.logbook.nextSerial == 4)
    }

    @Test func failedInsertRestoresTheForm() async throws {
        let app = try await TestApp.make()
        try await app.startCqWwCw()
        try await Self.failInserts(app)
        let entry: EntryModel = app.model.entry
        Self.type(entry, call: "DL1ABC", zone: "14")
        entry.submit()
        #expect(entry.form.call == "")
        await entry.settle()
        #expect(app.model.logbook.rows.isEmpty)
        #expect(entry.form.call == "DL1ABC")
        #expect(entry.form.contestExchange["zone"] == "14")
        #expect(app.model.status.message.contains("disk full"))
        #expect(app.model.logbook.reservedSerials == 0)
        #expect(app.model.logbook.nextSerial == 1)
        #expect(app.model.contest.score?.qsoCount == 0)
    }

    @Test func failedInsertNamesTheCallWhenANewOneIsTyped() async throws {
        let app = try await TestApp.make()
        try await app.startCqWwCw()
        try await Self.failInserts(app)
        let entry: EntryModel = app.model.entry
        Self.type(entry, call: "DL1ABC", zone: "14")
        entry.submit()
        entry.callChanged("W1AW")
        await entry.settle()
        #expect(entry.form.call == "W1AW")
        #expect(app.model.status.message.hasPrefix("DL1ABC: "))
        #expect(app.model.status.message.contains("disk full"))
        #expect(app.model.logbook.nextSerial == 1)
    }

    @Test func failedSerialBecomesAGapNotARepeat() async throws {
        let app = try await TestApp.make()
        try await app.startCqWwCw()
        try await app.model.database.handle.run { access in
            try access.repository.connection.execute("""
                CREATE TEMP TRIGGER fail_one BEFORE INSERT ON qso WHEN NEW.call = 'DL1ABC'
                BEGIN SELECT RAISE(ABORT, 'disk full'); END
                """)
        }
        let entry: EntryModel = app.model.entry
        Self.type(entry, call: "DL1ABC", zone: "14")
        entry.submit()
        Self.type(entry, call: "W1AW", zone: "5")
        entry.submit()
        await entry.settle()
        #expect(app.model.logbook.rows.map(\.serialSent) == [2])
        #expect(app.model.logbook.nextSerial == 3)
        Self.type(entry, call: "OK1AA", zone: "15")
        entry.submit()
        await entry.settle()
        #expect(app.model.logbook.rows.map(\.serialSent) == [2, 3])
    }

    @Test func anotherContestStartsFromItsOwnCount() async throws {
        let app = try await TestApp.make()
        try await app.startCqWwCw()
        await app.logContestQso(call: "DL1ABC", zone: "14")
        await app.logContestQso(call: "W1AW", zone: "5")
        try await app.startCqWwCw()
        #expect(app.model.logbook.nextSerial == 1)
    }

    @Test func quitRightAfterASubmitKeepsTheQso() async throws {
        let app = try await TestApp.make()
        try await app.startCqWwCw()
        let entry: EntryModel = app.model.entry
        Self.type(entry, call: "DL1ABC", zone: "14")
        entry.submit()
        await app.model.shutdown()
        let dbFile: URL = app.dataDir.appendingPathComponent("databases/Deník.sqlite")
        let stored = try LogbookRepository(url: dbFile)
        #expect(try stored.count() == 1)
        stored.close()
        let backups: URL = app.dataDir.appendingPathComponent("backups")
        let name: String = try #require(try FileManager.default.contentsOfDirectory(atPath: backups.path).first)
        let backup = try LogbookRepository(url: backups.appendingPathComponent(name))
        #expect(try backup.findAllIncludingDeleted().map(\.call) == ["DL1ABC"])
        backup.close()
    }

    @Test func databaseSwitchWaitsForTheSubmit() async throws {
        let app = try await TestApp.make()
        try await app.startCqWwCw()
        let old: LogbookHandle = app.model.database.handle
        let entry: EntryModel = app.model.entry
        Self.type(entry, call: "DL1ABC", zone: "14")
        entry.submit()
        await app.model.database.create("Druhá")
        #expect(old.isClosed)
        #expect(app.model.status.message == "Otevřena databáze Druhá")
        let dbFile: URL = app.dataDir.appendingPathComponent("databases/Deník.sqlite")
        let stored = try LogbookRepository(url: dbFile)
        #expect(try stored.count() == 1)
        stored.close()
    }

    @Test func closedHandleThrowsInsteadOfTouchingSQLite() async throws {
        let dir = try TempDir()
        let handle = try LogbookHandle.open(name: "x", url: dir.child("x.sqlite"))
        _ = try await handle.run { access in try access.service.count() }
        await handle.close()
        #expect(handle.isClosed)
        await #expect(throws: LogbookError.self) {
            _ = try await handle.run { access in try access.service.count() }
        }
        #expect(throws: LogbookError.self) {
            _ = try handle.withDatabase { access in try access.service.count() }
        }
        await handle.close()
    }
}

/// Final review: no input while a contest activates; a submission belongs to the contest it was submitted in.
@MainActor @Suite struct ActivationInputTests {

    @Test func entryIsClosedWhileAContestActivates() async throws {
        let app = try await TestApp.make()
        try await app.startCqWwCw()
        await app.logContestQso(call: "DL1ABC", zone: "14")
        await app.logContestQso(call: "W1AW", zone: "5")
        #expect(app.model.acceptsEntryInput)
        let entry: EntryModel = app.model.entry
        var sawClosed = false
        app.model.contest.afterActivationReplay = {
            sawClosed = !app.model.acceptsEntryInput && app.model.contest.isActivating
            // A submit during the replay does nothing.
            entry.setFrequency("14025")
            entry.callChanged("OK1AA")
            entry.editContestField("zone", "15")
            entry.submit()
        }
        try await app.startCqWwCw()
        app.model.contest.afterActivationReplay = nil
        await entry.settle()
        #expect(sawClosed)
        #expect(!app.model.contest.isActivating)
        #expect(app.model.acceptsEntryInput)
        #expect(app.model.logbook.rows.isEmpty)
        #expect(app.model.logbook.nextSerial == 1)
        await app.logContestQso(call: "OK1AA", zone: "15")
        #expect(app.model.logbook.rows.map(\.serialSent) == [1])
    }

    @Test func aQsoOfThePreviousContestIsStoredThereNotInTheNewOne() async throws {
        let app = try await TestApp.make()
        try await app.startCqWwCw()
        let logbook: LogbookModel = app.model.logbook
        let revision: Int64 = logbook.revision
        var qso = Qso()
        qso.call = "DL1ABC"
        qso.band = .m20
        let effects: [LogEffect] = [.persist, .bumpRevision, .addDupe, .appendRow, .refreshCount]
        let stored: Qso? = try await logbook.perform(qso, effects: effects, contestId: "previous")
        #expect(stored?.contestId == "previous")
        #expect(logbook.rows.isEmpty)
        #expect(logbook.qsoCount == 0)
        #expect(!logbook.isDupe(call: "DL1ABC", band: .m20))
        #expect(logbook.revision == revision + 1)
        let there: [Qso] = try await app.model.database.handle.run { access in
            try access.repository.findAll(contestId: "previous")
        }
        #expect(there.map(\.call) == ["DL1ABC"])
        // The service's active contest is untouched.
        let active: String = try await app.model.database.handle.run { access in access.service.activeContestId }
        #expect(active == logbook.activeContestId)
    }
}
