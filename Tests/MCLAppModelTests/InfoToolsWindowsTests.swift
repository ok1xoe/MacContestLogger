import CryptoKit
import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// Goals from a log, statistics, score, dupesheet.
@MainActor @Suite struct StatisticsToolsTests {

    // MARK: - goals

    @Test func theEditorStartsFromTheSavedGoalsAndSavesTheDraft() async throws {
        let tool = try await ToolApp.make()
        let goals: GoalsModel = tool.tools.goals
        goals.openEditor()
        #expect(goals.needsContest)
        #expect(goals.noContestText.hasPrefix("Cíle se plánují po hodinách závodu"))

        var setup = ContestSetup()
        setup.startedAt = "2026-10-04 12:00:00"
        let started: Bool = await tool.model.contest.createAndStart(definitionId: "cq-ww-cw", setup: setup)
        try #require(started)
        tool.model.config.config.goals = ["112": 40, "100": 3]
        goals.openEditor()
        #expect(!goals.needsContest)
        #expect(goals.hours.count == 48)
        #expect(goals.draft.text(for: 113) == "")
        #expect(goals.draft.text(for: 112) == "40")
        goals.draft.setText("12x", for: 113)
        goals.bulk.fromKey = 114
        goals.bulk.toKey = 115
        goals.bulk.setValue("9")
        goals.applyBulk()
        let saved: Bool = await goals.save()
        #expect(saved)
        #expect(tool.model.status.message == "Cíle uloženy (4 hodin)")
        #expect(tool.model.config.config.goals == ["112": 40, "113": 12, "114": 9, "115": 9])
        let onDisk: AppConfig = await tool.app.savedConfigFlushed()
        #expect(onDisk.goals == tool.model.config.config.goals)
    }

    /// Another database is only read: the file's bytes do not change and no journal appears.
    @Test func goalsFromAnotherDatabaseLeaveItUntouched() async throws {
        let tool = try await ToolApp.make()
        let dir: URL = tool.model.database.databasesDir
        let file: URL = try DatabaseCatalog(databasesDir: dir).create("Stary")
        let repository = try LogbookRepository(url: file)
        let store = try ContestStore(repository)
        let started: Int64 = 1_791_000_000_000
        try store.insert(ContestStore.ContestRow(contestId: "c1", definitionId: "cq-ww-cw", name: "CQ WW 2025",
                                                 startedAt: started, endedAt: nil, definitionYaml: "",
                                                 setupJson: nil, stationJson: nil))
        let begin = Date(timeIntervalSince1970: Double(started) / 1000.0)
        for (offset, band) in [(600.0, Band.m20), (1_200.0, Band.m20), (3_900.0, Band.m40)] {
            var qso = Qso()
            qso.call = "DL1ABC"
            qso.band = band
            qso.mode = .cw
            qso.contestId = "c1"
            qso.timestampUtc = begin.addingTimeInterval(offset)
            try repository.insert(&qso)
        }
        repository.close()

        func digest() throws -> String {
            SHA256.hash(data: try Data(contentsOf: file)).map { String(format: "%02x", $0) }.joined()
        }
        let before: String = try digest()
        let goals: GoalsModel = tool.tools.goals
        await goals.openFromLog()
        #expect(goals.databases.contains("Stary"))
        await goals.selectDatabase("Stary")
        #expect(goals.contests.map(\.name) == ["CQ WW 2025"])
        #expect(goals.contests.first?.qsoCount == 3)
        goals.band = .m20
        await goals.importFrom(try #require(goals.contests.first))
        #expect(goals.imported)
        #expect(goals.error.isEmpty)
        #expect(tool.model.status.message == "Cíle převzaty ze závodu CQ WW 2025 (1 hodin, pásmo 20m)")
        #expect(tool.model.config.config.goals.values.sorted() == [2])
        goals.band = nil
        await goals.importFrom(try #require(goals.contests.first))
        #expect(tool.model.config.config.goals.count == 2)
        #expect(tool.model.status.message == "Cíle převzaty ze závodu CQ WW 2025 (2 hodin)")
        #expect(try digest() == before)
        let names: [String] = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(!names.contains { $0.hasSuffix("-journal") || $0.hasSuffix("-wal") || $0.hasSuffix("-shm") })
    }

    /// The private copy of a foreign database is removed after the read and carries a write-ahead log along.
    @Test func theForeignCopyCarriesTheWalAndIsRemoved() async throws {
        let tool = try await ToolApp.make()
        let dir: URL = tool.model.database.databasesDir
        let file: URL = try DatabaseCatalog(databasesDir: dir).create("Wal")
        let raw = try SQLiteDatabase.open(at: file.path)
        try raw.execute("PRAGMA journal_mode=WAL")
        raw.close()
        let repository = try LogbookRepository(url: file)
        defer { repository.close() }
        let store = try ContestStore(repository)
        try store.insert(ContestStore.ContestRow(contestId: "w1", definitionId: "cq-ww-cw", name: "Only in the log",
                                                 startedAt: 1_791_000_000_000, endedAt: nil, definitionYaml: "",
                                                 setupJson: nil, stationJson: nil))
        #expect(FileManager.default.fileExists(atPath: file.path + "-wal"))
        let scratch: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcl-goals-scratch-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let goals: GoalsModel = tool.tools.goals
        goals.scratchRoot = scratch
        await goals.openFromLog()
        await goals.selectDatabase("Wal")
        #expect(goals.contests.map(\.name) == ["Only in the log"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: scratch.path).isEmpty)
    }

    /// A quit that starts while the foreign database is being read: nothing is written to the config afterwards and
    /// the private copy is gone.
    @Test func aQuitDuringTheImportWritesNothingAndLeavesNoCopy() async throws {
        let tool = try await ToolApp.make()
        let dir: URL = tool.model.database.databasesDir
        let file: URL = try DatabaseCatalog(databasesDir: dir).create("Late")
        let repository = try LogbookRepository(url: file)
        let store = try ContestStore(repository)
        try store.insert(ContestStore.ContestRow(contestId: "l1", definitionId: "cq-ww-cw", name: "Late",
                                                 startedAt: 1_791_000_000_000, endedAt: nil, definitionYaml: "",
                                                 setupJson: nil, stationJson: nil))
        repository.close()
        let scratch: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcl-goals-scratch-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let goals: GoalsModel = tool.tools.goals
        goals.scratchRoot = scratch
        await goals.openFromLog()
        await goals.selectDatabase("Late")
        let summary = try #require(goals.contests.first)
        var calls = 0
        goals.isShuttingDown = {
            calls += 1
            return calls > 1 // not yet at the start, true once the read is over
        }
        let before = tool.model.config.config.goals
        await goals.importFrom(summary)
        #expect(calls == 2)
        #expect(!goals.imported)
        #expect(tool.model.config.config.goals == before)
        #expect(try FileManager.default.contentsOfDirectory(atPath: scratch.path).isEmpty)
    }

    /// A hot rollback journal next to a foreign database is copied along: the copy is rolled back like the original
    /// would be, so a half-written transaction is not read.
    @Test func theForeignCopyCarriesAHotJournal() async throws {
        #expect(GoalsModel.sidecarSuffixes.contains("-journal"))
        let tool = try await ToolApp.make()
        let dir: URL = tool.model.database.databasesDir
        let source: URL = dir.appendingPathComponent("Hot-source.sqlite")
        let target: URL = try DatabaseCatalog(databasesDir: dir).create("Hot")
        let repository = try LogbookRepository(url: source)
        _ = try ContestStore(repository)
        repository.close()
        // An open transaction with a tiny page cache spills pages to the file and keeps a journal; the two files are
        // copied at that moment, the transaction is rolled back afterwards.
        let raw = try SQLiteDatabase.open(at: source.path)
        try raw.execute("PRAGMA cache_size=1")
        try raw.execute("BEGIN")
        for index in 0..<60 {
            try raw.execute("INSERT INTO contests(contest_id, definition_id, name, started_at, definition_yaml) "
                + "VALUES ('h\(index)', 'cq-ww-cw', '\(String(repeating: "x", count: 2000))', 1, '')")
        }
        let journal: String = source.path + "-journal"
        try #require(FileManager.default.fileExists(atPath: journal))
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.copyItem(at: source, to: target)
        try FileManager.default.copyItem(atPath: journal, toPath: target.path + "-journal")
        try raw.execute("ROLLBACK")
        raw.close()
        let goals: GoalsModel = tool.tools.goals
        await goals.openFromLog()
        await goals.selectDatabase("Hot")
        #expect(goals.error.isEmpty)
        #expect(goals.contests.isEmpty)
    }

    @Test func aContestWithoutAStartDateCannotGiveGoals() async throws {
        let tool = try await ToolApp.make()
        let goals: GoalsModel = tool.tools.goals
        await goals.openFromLog()
        let summary = ContestStore.ContestSummary(contestId: "x", definitionId: "d", name: "X", startedAt: nil,
                                                   endedAt: nil, qsoCount: 0, bands: [], firstQso: nil, lastQso: nil)
        await goals.importFrom(summary)
        #expect(goals.error == "Závod nemá vyplněné datum startu, hodiny nejdou určit.")
        #expect(!goals.imported)
    }

    @Test func aDatabaseThatCannotBeOpenedShowsTheError() async throws {
        let tool = try await ToolApp.make()
        let dir: URL = tool.model.database.databasesDir
        try Data("not a database".utf8).write(to: dir.appendingPathComponent("Rozbita.sqlite"))
        let goals: GoalsModel = tool.tools.goals
        await goals.openFromLog()
        await goals.selectDatabase("Rozbita")
        #expect(goals.error.hasPrefix("Databázi se nepodařilo otevřít ("))
        #expect(goals.contests.isEmpty)
    }

    // MARK: - statistics

    @Test func theStatisticsFollowTheLogAndTheChoice() async throws {
        let tool = try await ToolApp.make()
        try await tool.start("cq-ww-cw")
        let stats: StatisticsModel = tool.tools.statistics
        stats.open()
        await stats.settle()
        let empty = try #require(stats.snapshot)
        #expect(empty.table.grandTotal == "0")
        await tool.log("DL1ABC")
        await eventually("statistics follow the log") { stats.snapshot?.table.grandTotal == "1" }
        stats.setRows(.BAND)
        stats.setColumns(.NONE)
        await stats.settle()
        #expect(stats.snapshot?.table.rows.map(\.label) == ["20m"])
        #expect(stats.snapshot?.reports.isEmpty == true)
        stats.setShowReports(true)
        await stats.settle()
        #expect(stats.snapshot?.reports.count == 3)
        stats.close()
        #expect(!stats.isOpen)
    }

    // MARK: - score

    @Test func theScoreWaitsForTheDebounceAndIsComputedOnce() async throws {
        let tool = try await ToolApp.make()
        try await tool.start("cq-ww-cw")
        let score: ScoreWindowModel = tool.tools.score
        score.open()
        #expect(score.breakdown == nil)
        #expect(score.statusText == "Počítám…")
        tool.clock.advance(by: 299)
        await score.settle()
        #expect(score.breakdown == nil)
        tool.clock.advance(by: 1)
        await score.settle()
        let first = try #require(score.breakdown)
        #expect(first.total.qsos == 0)

        // A series of writes is computed once, 300 ms after the last.
        await tool.log("DL1ABC")
        await tool.log("DL2XYZ", freqKHz: "14026")
        let runs: Int = score.generation
        tool.clock.advance(by: 299)
        #expect(score.generation == runs)
        tool.clock.advance(by: 1)
        await score.settle()
        #expect(score.generation == runs + 1)
        #expect(score.breakdown?.total.qsos == 2)
        let table = try #require(score.table)
        #expect(table.headers.prefix(2) == ["Pásmo", "Mód"])
        score.byMode = false
        #expect(score.table?.headers.first == "Pásmo")
        #expect(score.table?.headers.contains("Mód") == false)
        score.close()
    }

    @Test func theScoreOutsideAContestSaysSo() async throws {
        let tool = try await ToolApp.make()
        let score: ScoreWindowModel = tool.tools.score
        score.open()
        tool.clock.advance(by: 300)
        await score.settle()
        #expect(score.breakdown == nil)
        #expect(score.table == nil)
        #expect(score.statusText == "Rozpad skóre je jen v závodě (volné logování nemá body).")
        score.close()
    }

    // MARK: - dupesheet

    @Test func theDupesheetShowsTheWorkedCallsAndHighlightsTheTypedOne() async throws {
        let tool = try await ToolApp.make()
        try await tool.start("cq-ww-cw")
        await tool.log("DL1ABC")
        let sheet: DupesheetModel = tool.tools.dupesheet
        sheet.open()
        let view = try #require(sheet.view)
        #expect(view.title == "Dupesheet 20m — 1 volaček")
        let column = try #require(view.columns.first { $0.digit == "1" })
        #expect(column.header == "1 (1)")
        #expect(column.calls == [DupesheetColumn.Call(text: "DL1ABC", hit: false)])
        tool.model.entry.callChanged("DL1")
        await eventually("the typed call is highlighted") {
            sheet.view?.columns.first { $0.digit == "1" }?.calls.first?.hit == true
        }
        sheet.close()
    }

    @Test func aLargeLogIsBuiltOffTheMainThread() async throws {
        let tool = try await ToolApp.make()
        try await tool.start("cq-ww-cw")
        await tool.log("DL1ABC")
        let sheet: DupesheetModel = tool.tools.dupesheet
        sheet.inlineLimit = 0
        sheet.open()
        #expect(sheet.view == nil)
        await sheet.settle()
        #expect(sheet.view?.title == "Dupesheet 20m — 1 volaček")
        sheet.close()
    }

    /// An old-schema file is only read: its bytes stay, and no journal or file appears next to it.
    @Test func anOldSchemaFileIsNeverAltered() async throws {
        let tool = try await ToolApp.make()
        let dir: URL = tool.model.database.databasesDir
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file: URL = dir.appendingPathComponent("Pradavna.sqlite")
        // A database of the very first schema: a `qso` table without the later columns and no `contests` table.
        let old = try SQLiteDatabase.open(at: file.path)
        try old.execute("CREATE TABLE qso (id INTEGER PRIMARY KEY AUTOINCREMENT, call TEXT)")
        try old.execute("INSERT INTO qso (call) VALUES ('OK1ABC')")
        old.close()
        let before: Data = try Data(contentsOf: file)
        let namesBefore: [String] = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        let goals: GoalsModel = tool.tools.goals
        await goals.selectDatabase("Pradavna")
        let namesAfter: [String] = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        #expect(try Data(contentsOf: file) == before)
        #expect(namesAfter == namesBefore)
    }

    @Test func aMissingFileIsAnErrorAndNotCreated() async throws {
        let tool = try await ToolApp.make()
        let dir: URL = tool.model.database.databasesDir
        let goals: GoalsModel = tool.tools.goals
        await goals.selectDatabase("Neexistuje")
        #expect(goals.error.hasPrefix("Databázi se nepodařilo otevřít ("))
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("Neexistuje.sqlite").path))
    }

    @Test func nothingWritesAfterTheQuitStarted() async throws {
        let tool = try await ToolApp.make()
        try await tool.start("wae-cw")
        let model: AppModel = tool.model
        await model.shutdown()
        let file: URL = tool.app.dir.child("goals.txt")
        try "100 40\n".write(to: file, atomically: true, encoding: .utf8)
        tool.tools.info.importGoals(url: file)
        await tool.tools.info.settle()
        #expect(model.config.config.goals.isEmpty)
        let line = QtcPlanner.Line(time: "1200", call: "OK1AAA", serial: 1)
        #expect(await tool.tools.qtc.save(sent: false, partner: "DL1ABC", group: 1, lines: [line]) == false)
        #expect(model.contest.qtcs.isEmpty)
    }
}
