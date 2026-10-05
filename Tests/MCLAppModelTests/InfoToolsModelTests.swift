import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// An app over a temporary data directory (never the user's) whose tool clock and wall clock are moved by hand.
@MainActor
struct ToolApp {
    let app: TestApp
    let clock: ManualClock
    let now: TestNow

    var model: AppModel { app.model }
    var tools: InfoTools { app.model.infoTools }

    static let start: Date = ISO8601DateFormatter().date(from: "2026-10-04T12:00:00Z") ?? Date()

    /// A DXCC directory whose `cty.dat` gives three entities a position (the test `dxcc.json` has none).
    static func positionedDxcc(in dir: TempDir) throws -> URL {
        let target: URL = dir.child("dxcc-positions")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: Fixtures.coreFixtures.appendingPathComponent("dxcc-test.json"),
                                         to: target.appendingPathComponent("dxcc.json"))
        let cty = """
        Germany:                  14:  28:  EU:   51.00:   -10.00:    -1.0:  DL:
            DA,DB,DC,DD,DF,DG,DH,DJ,DK,DL,DM,DN,DO,DP,DQ,DR;
        United States:            05:  08:  NA:   37.53:    91.67:     5.0:  K:
            AA,K,N,W;
        Czech Republic:           15:  28:  EU:   49.50:   -15.50:    -1.0:  OK:
            OK,OL;

        """
        try cty.write(to: target.appendingPathComponent("cty.dat"), atomically: true, encoding: .utf8)
        return target
    }

    static func make(mapData: any MapDataPort = EmptyMapData(), clipboard: RecordedClipboard? = nil,
                     positions: Bool = false,
                     configure: @escaping (inout AppConfig, URL) throws -> Void = { _, _ in }) async throws -> ToolApp {
        let clock = ManualClock()
        let now = TestNow(start)
        let app = try await TestApp.make(now: now, configure: configure, adjust: { environment in
            environment.toolClock = clock
            environment.mapData = mapData
            if positions, let dir = try? TempDir("mcl-dxcc") {
                environment.dxccDir = try? Self.positionedDxcc(in: dir)
                keep.append(dir)
            }
            if let clipboard {
                environment.clipboard = { text in clipboard.texts.append(text) }
            }
        })
        return ToolApp(app: app, clock: clock, now: now)
    }

    /// Creates and starts a contest of the fixture data.
    func start(_ definitionId: String) async throws {
        var setup = ContestSetup()
        setup.sentExchange = ["zone": "15"]
        let started: Bool = await model.contest.createAndStart(definitionId: definitionId, setup: setup)
        try #require(started, "activation failed: \(model.status.message)")
    }

    func log(_ call: String, freqKHz: String = "14025") async {
        await app.logContestQso(call: call, zone: "14", freqKHz: freqKHz)
        await model.logbook.settleMutations()
    }

    /// Stores a QSO of the active contest straight into the database (contests whose entry form the tests do not
    /// drive) and re-reads the log.
    func insert(call: String, serial: Int, minute: Int) async throws {
        var qso = Qso()
        qso.call = call
        qso.band = .m20
        qso.mode = .cw
        qso.freqHz = 14_025_000
        qso.serialRcvd = serial
        qso.contestId = model.logbook.activeContestId
        qso.timestampUtc = Self.start.addingTimeInterval(Double(minute) * 60)
        let stored: Qso = qso
        try await model.database.handle.run { access in
            var copy: Qso = stored
            _ = try access.repository.insert(&copy)
        }
        try await model.logbook.refresh()
    }
}

/// Directories of the tests' fixtures live until the process ends.
@MainActor private var keep: [TempDir] = []

@MainActor
final class RecordedClipboard {
    var texts: [String] = []
}

/// The Info window's model: tick, generation, timers, lines, menu and the goal files.
@MainActor @Suite struct InfoModelTests {

    @Test func theTickRunsOnlyWhileTheWindowIsOpen() async throws {
        let tool = try await ToolApp.make()
        let info: InfoModel = tool.tools.info
        let before: Int = tool.clock.pendingCount
        info.open()
        #expect(info.isOpen)
        #expect(tool.clock.pendingCount == before + 1)
        let first: JavaInstant = info.now
        tool.now.advance(seconds: 1)
        tool.clock.advance(by: 1_000)
        #expect(info.now.epochSecond == first.epochSecond + 1)
        // The tick schedules itself again.
        #expect(tool.clock.pendingCount == before + 1)
        info.close()
        #expect(!info.isOpen)
        #expect(tool.clock.pendingCount == before)
        tool.now.advance(seconds: 5)
        tool.clock.advance(by: 5_000)
        #expect(info.now.epochSecond == first.epochSecond + 1)
    }

    @Test func aSnapshotOvertakenByANewerLogIsDropped() async throws {
        let tool = try await ToolApp.make()
        try await tool.start("cq-ww-cw")
        let info: InfoModel = tool.tools.info
        info.open()
        await info.settle()
        await tool.log("DL1ABC")
        await info.settle()
        let one: ContestStats = ContestStats.of(tool.model.logbook.rows)
        #expect(info.stats == one)
        #expect(info.stats != ContestStats.of([]))

        // A slow job computes a stale (empty) snapshot; a second QSO starts a newer one that finishes first.
        let gate = DispatchSemaphore(value: 0)
        let normal = try #require(info.snapshotSource)
        info.snapshotSource = {
            { _ in
                _ = gate.wait(timeout: .now() + 10)
                return ContestStats.of([])
            }
        }
        let generation: Int = info.snapshotGeneration
        info.refreshSnapshot()
        #expect(info.snapshotGeneration == generation + 1)
        info.snapshotSource = normal
        await tool.log("DL2XYZ", freqKHz: "14026")
        await eventually("the newer snapshot") { info.stats == ContestStats.of(tool.model.logbook.rows) }
        let two: ContestStats = ContestStats.of(tool.model.logbook.rows)
        gate.signal()
        await info.settle()
        #expect(info.stats == two)
        #expect(info.stats != ContestStats.of([]))
        info.close()
    }

    @Test func aClosedWindowDropsTheSnapshotInFlight() async throws {
        let tool = try await ToolApp.make()
        let info: InfoModel = tool.tools.info
        info.open()
        await info.settle()
        let gate = DispatchSemaphore(value: 0)
        info.snapshotSource = {
            { _ in
                _ = gate.wait(timeout: .now() + 10)
                return ContestStats.of([Qso()])
            }
        }
        info.refreshSnapshot()
        info.close()
        gate.signal()
        await info.settle()
        #expect(info.stats == ContestStats.of([]))
    }

    /// `tunedSince` only follows the band while the window is open (Kotlin `LaunchedEffect`).
    @Test func theTimeOnTheBandStartsWhenTheTunedBandChanges() async throws {
        let tool = try await ToolApp.make()
        let info: InfoModel = tool.tools.info
        info.open()
        #expect(info.onBand == nil)
        tool.model.rig.updateTuned(14_025_000)
        await eventually("band timer") { info.onBand != nil }
        #expect(info.onBand?.label == "Na pásmu 20m")
        tool.now.advance(seconds: 65)
        tool.clock.advance(by: 1_000)
        #expect(info.onBand?.value == "1:05")
        info.close()
        // Closed: a band change is not seen; opening again starts from the open.
        tool.model.rig.updateTuned(7_010_000)
        await runMainQueue()
        tool.now.advance(seconds: 30)
        info.open()
        #expect(info.onBand?.label == "Na pásmu 40m")
        #expect(info.onBand?.value == "0:00")
        info.close()
    }

    @Test func theLinesFollowTheTypedCallAndTheSwitches() async throws {
        let tool = try await ToolApp.make()
        let info: InfoModel = tool.tools.info
        info.open()
        #expect(info.lines.isEmpty)
        tool.model.entry.callChanged("W1AW")
        tool.model.dxCluster.spots.add(DxSpot(spotter: "OK1RR", freqHz: 14_030_000, dxCall: "W1AW", comment: "up 2"))
        info.recompute()
        #expect(info.lines.first == "W1AW - 14030,00 [OK1RR @ 0 min] up 2")
        info.toggle(.callframeSpot)
        #expect(info.lines.first?.hasPrefix("W1AW - ") != true)
        #expect(!tool.app.model.config.config.infoWindow.showCallframeSpot)
        info.close()
    }

    @Test func theHeaderShowsTheStationAndTheOperator() async throws {
        let tool = try await ToolApp.make()
        let info: InfoModel = tool.tools.info
        info.open()
        #expect(info.header.stationCall == "OK1XOE")
        try await tool.start("cq-ww-cw")
        info.recompute()
        #expect(info.header.exchangeText != nil)
        info.close()
    }

    // MARK: - the menu

    @Test func theMenuHasKotlinsItemsAndChecks() async throws {
        let tool = try await ToolApp.make()
        let entries: [InfoMenuEntry] = tool.tools.info.menuEntries
        #expect(entries.count == 22)
        #expect(entries.first?.title == "✓ Spot rozepsané volačky")
        let titles: [String] = entries.map(\.title)
        #expect(titles.contains("  Průběh — 30min průměry"))
        #expect(titles.contains("✓ Průběh — 20min průměry"))
        #expect(titles.contains("✓ Časovač: čas od posledního QSO"))
        #expect(titles.contains("  Časovač: kumulativní off time"))
        #expect(titles.contains("Upravit cíle…"))
        #expect(titles.contains("Zobrazit RBN spoty této stanice"))
        let order: [String] = ["Spot rozepsané volačky", "Země a azimut", "Východ a západ slunce", "Zprávy WWV",
                               "Zobrazit cíle", "Upravit cíle…", "Cíle z dřívějšího deníku…",
                               "Importovat cíle ze souboru…", "Exportovat cíle do souboru…", "Okno zpráv",
                               "Kopírovat text zpráv", "Vyčistit okno zpráv", "Zobrazit RBN spoty této stanice",
                               "Zobrazit časovače QSO"]
        for (entry, expected) in zip(entries, order) {
            #expect(entry.title.hasSuffix(expected))
        }
    }

    @Test func aChoiceIsSavedSilently() async throws {
        let tool = try await ToolApp.make()
        let info: InfoModel = tool.tools.info
        info.toggle(.wwv)
        info.toggle(.trendMinutes(30))
        info.toggle(.offTimeMode("countUp"))
        info.perform(.option(.timers))
        let saved: AppConfig = await tool.app.savedConfigFlushed()
        #expect(!saved.infoWindow.showWwv)
        #expect(saved.infoWindow.trendMinutes == 30)
        #expect(saved.infoWindow.offTimeMode == "countUp")
        #expect(!saved.infoWindow.showTimers)
        #expect(tool.model.status.message.isEmpty)
        #expect(info.menuEntries.map(\.title).contains("✓ Časovač: náběh aktuálního intervalu"))
        #expect(info.menuEntries.map(\.title).contains("✓ Průběh — 30min průměry"))
    }

    @Test func theGoalEditorAndTheFromLogWindowOpenFromTheMenu() async throws {
        let tool = try await ToolApp.make()
        let info: InfoModel = tool.tools.info
        info.perform(.editGoals)
        info.perform(.goalsFromLog)
        #expect(info.showGoalEditor && info.showGoalFromLog)
    }

    // MARK: - messages

    @Test func theMessagesCopyAndClear() async throws {
        let clipboard = RecordedClipboard()
        let tool = try await ToolApp.make(clipboard: clipboard)
        let info: InfoModel = tool.tools.info
        info.copyMessages()
        #expect(tool.model.status.message == "Okno zpráv je prázdné.")
        #expect(clipboard.texts.isEmpty)
        tool.model.messages.add("Byl jsi spotnut", at: ToolApp.start)
        #expect(info.messageRows == ["1200Z  Byl jsi spotnut"])
        info.copyMessages()
        #expect(tool.model.status.message == "Text zpráv zkopírován do schránky.")
        #expect(clipboard.texts.count == 1)
        #expect(clipboard.texts.first?.contains("Byl jsi spotnut") == true)
        info.clearMessages()
        #expect(info.messageRows.isEmpty)
    }

    @Test func theRbnPageOpensThroughTheBrowserPort() async throws {
        let opener = RecordingUrlOpener()
        let clock = ManualClock()
        let app = try await TestApp.make(adjust: { environment in
            environment.toolClock = clock
            environment.network = NetworkPorts(makeSession: NetworkPorts.sessions(), http: FakeHttpGetter(),
                                               urlOpener: opener.opener)
        })
        app.model.info.openRbnSpots()
        await app.model.callbook.settle()
        #expect(opener.urls == ["https://www.reversebeacon.net/dxsd1/dxsd1.php?f=0&c=OK1XOE&t=dx"])
    }

    // MARK: - goals

    @Test func aGoalFileIsImported() async throws {
        let tool = try await ToolApp.make()
        let info: InfoModel = tool.tools.info
        let file: URL = tool.app.dir.child("goals.txt")
        try "100 40\n101 50\n".write(to: file, atomically: true, encoding: .utf8)
        info.importGoals(url: file)
        await info.settle()
        #expect(tool.model.status.message == "Načteno 2 cílů")
        #expect(tool.model.config.config.goals == ["100": 40, "101": 50])
        let saved: AppConfig = await tool.app.savedConfigFlushed()
        #expect(saved.goals == ["100": 40, "101": 50])
    }

    @Test func unrecognizedGoalLinesAreReported() async throws {
        let tool = try await ToolApp.make()
        let info: InfoModel = tool.tools.info
        let file: URL = tool.app.dir.child("goals.txt")
        try "100 40\nnonsense here\n".write(to: file, atomically: true, encoding: .utf8)
        info.importGoals(url: file)
        await info.settle()
        #expect(tool.model.status.message == "Načteno 1 cílů; 1 řádků nerozpoznáno: nonsense here")
    }

    @Test func aGoalFileThatCannotBeReadShowsTheJavaMessage() async throws {
        let tool = try await ToolApp.make()
        let info: InfoModel = tool.tools.info
        let file: URL = tool.app.dir.child("missing.txt")
        info.importGoals(url: file)
        await info.settle()
        #expect(tool.model.status.message
                == "Cíle se nepodařilo přečíst (\(file.path))")
        #expect(tool.model.config.config.goals.isEmpty)
    }

    @Test func aStatisticsExportWaitsForTheBand() async throws {
        let tool = try await ToolApp.make()
        let info: InfoModel = tool.tools.info
        let file: URL = tool.app.dir.child("stats.txt")
        let text = "Day Hr 20m 40m Tot Accum\n2026-10-03 22 5 7 12 12\n2026-10-03 23 6 1 7 19\n"
        try text.write(to: file, atomically: true, encoding: .utf8)
        info.importGoals(url: file)
        await info.settle()
        let pending = try #require(info.pendingImport)
        #expect(pending.bands == ["20m", "40m"])
        #expect(tool.model.config.config.goals.isEmpty)
        info.chooseImportBand("40m")
        await info.settle()
        #expect(info.pendingImport == nil)
        #expect(tool.model.status.message == "Načteno 2 cílů (pásmo 40m)")
        let goals: [Int] = tool.model.config.config.goals.values.sorted()
        #expect(goals == [1, 7])
    }

    @Test func aDismissedBandDialogImportsNothing() async throws {
        let tool = try await ToolApp.make()
        let info: InfoModel = tool.tools.info
        let file: URL = tool.app.dir.child("stats.txt")
        try "Day Hr 20m Tot Accum\n2026-10-03 22 5 5 5\n".write(to: file, atomically: true, encoding: .utf8)
        info.importGoals(url: file)
        await info.settle()
        #expect(info.pendingImport != nil)
        info.cancelImport()
        #expect(info.pendingImport == nil)
        #expect(tool.model.config.config.goals.isEmpty)
    }

    @Test func goalsAreExported() async throws {
        let tool = try await ToolApp.make(configure: { config, _ in })
        let info: InfoModel = tool.tools.info
        let file: URL = tool.app.dir.child("goals-out.txt")
        info.exportGoals(url: file)
        #expect(tool.model.status.message == "Není co exportovat — žádné cíle nejsou načtené.")
        #expect(!FileManager.default.fileExists(atPath: file.path))
        tool.model.config.config.goals = ["100": 40, "101": 50]
        info.exportGoals(url: file)
        await info.settle()
        #expect(tool.model.status.message == "Cíle uloženy do \(file.path)")
        let expected: String = GoalFileWriter.toText(GoalFileWriter.fromConfigMap(["100": 40, "101": 50]))
        #expect(try String(contentsOf: file, encoding: .utf8) == expected)
        // A failed write shows the Java text.
        let nowhere: URL = tool.app.dir.child("no-such-dir").appendingPathComponent("g.txt")
        info.exportGoals(url: nowhere)
        await info.settle()
        #expect(tool.model.status.message == "Export cílů selhal (\(nowhere.path))")
    }

    @Test func theGoalBecomesTheRateTitleAndTheLine() async throws {
        let tool = try await ToolApp.make()
        try await tool.start("cq-ww-cw")
        let info: InfoModel = tool.tools.info
        info.open()
        // No goals saved: the default of 50 per hour applies while the contest runs.
        let before: NearTermRates = info.nearTerm
        tool.model.config.config.goals = ["100": 7]
        info.recompute()
        #expect(info.nearTerm != before || before.title.contains("cíl"))
        info.toggle(.goals)
        #expect(info.nearTerm.title == "QSO/hod")
        #expect(info.nearTerm.goalLine == nil)
        info.close()
    }
}
