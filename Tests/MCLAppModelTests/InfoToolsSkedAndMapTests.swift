import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// Skeds, the watchers, QTC and band notes: the watchers only report; nothing transmits.
@MainActor @Suite struct SkedAndQtcToolsTests {

    // MARK: - skeds

    @Test func aSkedIsValidatedInKotlinsOrder() async throws {
        let tool = try await ToolApp.make()
        try await tool.start("cq-ww-cw")
        let skeds: SkedModel = tool.tools.skeds
        let status: () -> String = { tool.model.status.message }
        #expect(await skeds.add(call: " ", freqText: "14025", mode: "CW", timeText: "1203", note: "") == false)
        #expect(status() == "Sked: chybí volačka")
        #expect(await skeds.add(call: "OK1ABC", freqText: "14025", mode: "CW", timeText: "xx", note: "") == false)
        #expect(status() == "Sked: neplatný čas „xx“ (HHmm nebo 2026-11-28 1430)")
        #expect(await skeds.add(call: "OK1ABC", freqText: "0", mode: "CW", timeText: "1203", note: "") == false)
        #expect(status() == "Sked: neplatná frekvence")
        #expect(skeds.skeds.isEmpty)
    }

    @Test func aSkedIsStoredInTheContestSetupAndRemoved() async throws {
        let tool = try await ToolApp.make()
        try await tool.start("cq-ww-cw")
        let skeds: SkedModel = tool.tools.skeds
        #expect(skeds.emptyText == "Žádné skedy")
        #expect(await skeds.add(call: "ok1abc", freqText: "14025", mode: "CW", timeText: "1203", note: " test "))
        #expect(tool.model.status.message == "Sked OK1ABC v 1203 UTC na 14025.0 kHz")
        let stored = try #require(skeds.skeds.first)
        #expect(stored.call == "OK1ABC" && stored.freqHz == 14_025_000 && stored.note == "test")
        #expect(stored.atUtc == "2026-10-04T12:03:00Z")
        #expect(skeds.skedTime(stored) == "1203")
        #expect(await skeds.add(call: "OK2XYZ", freqText: "7010", mode: "CW", timeText: "1150", note: ""))
        // Sorted by time; 11:50 today has passed, so it is tomorrow's.
        #expect(skeds.skeds.map(\.call) == ["OK1ABC", "OK2XYZ"])
        await skeds.remove(stored.id)
        #expect(skeds.skeds.map(\.call) == ["OK2XYZ"])
    }

    @Test func aSkedOutsideAContestIsRefused() async throws {
        let tool = try await ToolApp.make()
        let skeds: SkedModel = tool.tools.skeds
        #expect(await skeds.add(call: "OK1ABC", freqText: "14025", mode: "CW", timeText: "1203", note: "") == false)
        #expect(tool.model.status.message == "Není aktivní závod")
        #expect(skeds.emptyText == "Skedy patří k závodu — otevři závod")
        #expect(!skeds.contestActive)
    }

    @Test func aDueSkedIsRemindedOnce() async throws {
        let tool = try await ToolApp.make()
        try await tool.start("cq-ww-cw")
        let skeds: SkedModel = tool.tools.skeds
        #expect(await skeds.add(call: "OK1ABC", freqText: "14025", mode: "CW", timeText: "1203", note: "pozdrav"))
        #expect(tool.tools.skedWatcher.isRunning)
        // 12:00:00, three minutes ahead: not due.
        tool.clock.advance(by: 15_000)
        #expect(tool.model.messages.lines.isEmpty)
        // 12:02:30: due (one minute before to five after).
        tool.now.advance(seconds: 150)
        tool.clock.advance(by: 15_000)
        let text = "SKED OK1ABC v 1203 UTC na 14025.0 kHz CW — pozdrav (okno Skedy: klik = QSY)"
        #expect(tool.model.messages.lines.map(\.text) == [text])
        #expect(tool.model.status.message == "⏰ " + text)
        #expect(tool.tools.skedWatcher.reminded.count == 1)
        // The next checks do not repeat it.
        tool.now.advance(seconds: 30)
        tool.clock.advance(by: 15_000)
        tool.clock.advance(by: 15_000)
        #expect(tool.model.messages.lines.count == 1)
    }

    @Test func theInfoStripShowsTheNextSkedWithinTenMinutes() async throws {
        let tool = try await ToolApp.make()
        try await tool.start("cq-ww-cw")
        let skeds: SkedModel = tool.tools.skeds
        #expect(await skeds.add(call: "OK1ABC", freqText: "14025", mode: "CW", timeText: "1203", note: ""))
        #expect(await skeds.add(call: "OK2XYZ", freqText: "7010", mode: "CW", timeText: "1300", note: ""))
        #expect(tool.model.infoStrip.text.contains("SKED 1203 OK1ABC"))
        // Eleven minutes before: nothing within ten minutes.
        tool.now.advance(seconds: -15 * 60)
        #expect(!tool.model.infoStrip.text.contains("SKED"))
        // After the first sked is past its grace the next one is not near either.
        tool.now.advance(seconds: 15 * 60 + 10 * 60)
        #expect(!tool.model.infoStrip.text.contains("SKED 1203"))
    }

    /// A click tunes the rig model (frequency, the call into the entry field); nothing transmits.
    @Test func aClickOnASkedTunes() async throws {
        let tool = try await ToolApp.make()
        try await tool.start("cq-ww-cw")
        let skeds: SkedModel = tool.tools.skeds
        #expect(await skeds.add(call: "OK1ABC", freqText: "14025", mode: "CW", timeText: "1203", note: ""))
        skeds.tune(try #require(skeds.skeds.first))
        #expect(tool.model.rig.tuning.tunedFreqHz == 14_025_000)
        #expect(tool.model.entry.form.call == "OK1ABC")
    }

    // MARK: - TOUR

    @Test func aNewTourSessionIsAnnouncedOnlyInAContest() async throws {
        let tool = try await ToolApp.make()
        let watcher: TourWatcher = tool.tools.tourWatcher
        #expect(watcher.isRunning)
        let tour = try Tour(startMinute: 12 * 60, durationMinutes: 30)
        // No contest: the tour is known but a change is not reported.
        tool.model.contest.setSessionExtras(tour: tour, bonusStations: [])
        watcher.check()
        tool.now.advance(seconds: 31 * 60)
        watcher.check()
        #expect(tool.model.messages.lines.isEmpty)

        try await tool.start("cq-ww-cw")
        tool.model.contest.setSessionExtras(tour: tour, bonusStations: [])
        // The first check remembers the session, the next in the same one reports nothing.
        watcher.check()
        tool.now.advance(seconds: 60)
        tool.clock.advance(by: 5_000)
        #expect(tool.model.messages.lines.isEmpty)
        // The next session: reported once, in the status line and the messages.
        tool.now.advance(seconds: 31 * 60)
        tool.clock.advance(by: 5_000)
        let text = try #require(tool.model.messages.lines.first?.text)
        #expect(text.hasPrefix("Nové sezení závodu "))
        #expect(text.hasSuffix(" — stanice z minulého sezení jdou pracovat znovu"))
        #expect(tool.model.status.message == "⏱ " + text)
        tool.clock.advance(by: 5_000)
        #expect(tool.model.messages.lines.count == 1)
    }

    @Test func theWatchersStopWithTheQuit() async throws {
        let tool = try await ToolApp.make()
        #expect(tool.tools.skedWatcher.isRunning && tool.tools.tourWatcher.isRunning)
        tool.tools.info.open()
        tool.tools.worldMap.open()
        let grid: MultGridModel = tool.tools.multGrid(kind: "dxcc")
        grid.open()
        await tool.model.shutdown()
        #expect(!tool.tools.skedWatcher.isRunning && !tool.tools.tourWatcher.isRunning)
        #expect(!tool.tools.info.isOpen && !tool.tools.worldMap.isOpen && !grid.isOpen)
    }

    // MARK: - QTC

    private static func lines(_ count: Int) -> [QtcPlanner.Line] {
        (0..<count).map { QtcPlanner.Line(time: "12\(String(format: "%02d", $0))", call: "OK\($0)AAA", serial: $0 + 1) }
    }

    @Test func aReceivedSeriesIsStoredAndCountsIntoTheScore() async throws {
        let tool = try await ToolApp.make()
        try await tool.start("wae-cw")
        let qtc: QtcModel = tool.tools.qtc
        #expect(qtc.config != nil)
        let saved: Bool = await qtc.save(sent: false, partner: "dl1abc", group: 1, lines: Self.lines(3))
        #expect(saved)
        #expect(qtc.qtcs.count == 3)
        #expect(tool.model.contest.runtime.qtcCount == 3)
        #expect(tool.model.status.message == "QTC přijato: 1/3 se stanicí DL1ABC (celkem 3)")
        let record = try #require(qtc.qtcs.first)
        #expect(record.partnerCall == "DL1ABC" && record.mode == "CW" && !record.sent)
        #expect(qtc.remainingText == nil || qtc.remainingText?.contains("zbývá") == true)
        // Stored in the database: a re-read gives the same.
        let handle: LogbookHandle = tool.model.database.handle
        let contestId: String = tool.model.logbook.activeContestId
        let stored: [QtcRecord] = try await handle.run { access in
            try access.repository.findQtcs(contestId: contestId)
        }
        #expect(stored.count == 3)
    }

    @Test func theLimitPerStationIsKept() async throws {
        let tool = try await ToolApp.make()
        try await tool.start("wae-cw")
        let qtc: QtcModel = tool.tools.qtc
        #expect(await qtc.save(sent: false, partner: "DL1ABC", group: 1, lines: Self.lines(8)))
        #expect(await qtc.save(sent: false, partner: "DL1ABC", group: 2, lines: Self.lines(3)) == false)
        #expect(tool.model.status.message == "QTC: se stanicí DL1ABC zbývá už jen 2 QTC (limit 10)")
        #expect(qtc.qtcs.count == 8)
        #expect(tool.model.contest.runtime.qtcCount == 8)
        // Another station has its own limit.
        #expect(await qtc.save(sent: true, partner: "DL2XYZ", group: 1, lines: Self.lines(3)))
        #expect(tool.model.status.message == "QTC odesláno: 1/3 se stanicí DL2XYZ (celkem 11)")
        #expect(qtc.nextGroup == 2)
    }

    @Test func aSeriesNeedsAPartnerLinesAndAContestWithQtc() async throws {
        let tool = try await ToolApp.make()
        try await tool.start("cq-ww-cw")
        let qtc: QtcModel = tool.tools.qtc
        #expect(await qtc.save(sent: false, partner: "DL1ABC", group: 1, lines: Self.lines(1)) == false)
        #expect(tool.model.status.message == "QTC: aktivní závod QTC nemá")
        #expect(qtc.config == nil)
        try await tool.start("wae-cw")
        #expect(await qtc.save(sent: false, partner: " ", group: 1, lines: Self.lines(1)) == false)
        #expect(tool.model.status.message == "QTC: chybí stanice nebo řádky")
        #expect(await qtc.save(sent: false, partner: "DL1ABC", group: 1, lines: []) == false)
        #expect(qtc.qtcs.isEmpty)
    }

    @Test func aQtcIsDeletedAndTheCountFollows() async throws {
        let tool = try await ToolApp.make()
        try await tool.start("wae-cw")
        let qtc: QtcModel = tool.tools.qtc
        #expect(await qtc.save(sent: false, partner: "DL1ABC", group: 1, lines: Self.lines(3)))
        let id = try #require(qtc.qtcs.first?.id)
        await qtc.delete(id)
        #expect(qtc.qtcs.count == 2)
        #expect(tool.model.contest.runtime.qtcCount == 2)
    }

    @Test func receivedLinesAreParsedAndSavedFromTheForm() async throws {
        let tool = try await ToolApp.make()
        try await tool.start("wae-cw")
        let qtc: QtcModel = tool.tools.qtc
        qtc.setPartner("dl1abc")
        qtc.group = "3/10"
        qtc.received = "1234 OK1AAA 56\nbroken line\n"
        #expect(qtc.badLinesText == "Nečitelné řádky: broken line")
        #expect(await qtc.saveReceived() == false)
        qtc.received = "1234 OK1AAA 56\n1236 OK2BBB 57\n"
        #expect(qtc.badLinesText == nil)
        #expect(await qtc.saveReceived())
        #expect(qtc.qtcs.map(\.groupNr) == [3, 3])
        #expect(qtc.qtcs.map(\.qsoCall) == ["OK1AAA", "OK2BBB"])
        #expect(qtc.received.isEmpty && qtc.group.isEmpty)
    }

    @Test func theNextSeriesComesFromTheLog() async throws {
        let tool = try await ToolApp.make()
        try await tool.start("wae-cw")
        let qtc: QtcModel = tool.tools.qtc
        try await tool.insert(call: "DL1ABC", serial: 12, minute: 1)
        try await tool.insert(call: "DL2XYZ", serial: 13, minute: 2)
        qtc.setPartner("OK1AAA")
        #expect(qtc.candidateLines.map(\.call) == ["DL1ABC", "DL2XYZ"])
        #expect(qtc.candidateLines.map(\.serial) == [12, 13])
        #expect(qtc.seriesTitle(count: 2) == "Série 1/2:")
        #expect(await qtc.saveSent())
        #expect(qtc.qtcs.count == 2 && qtc.qtcs.allSatisfy(\.sent))
        // Reported QSOs are not offered again.
        #expect(qtc.candidateLines.isEmpty)
    }

    // MARK: - band notes

    @Test func aBandNoteIsAddedShownInTheStripAndRemoved() async throws {
        let tool = try await ToolApp.make()
        let notes: BandNotesModel = tool.tools.bandNotes
        #expect(notes.add(freq: "xyz", text: "nothing") == false)
        #expect(tool.model.status.message == BandNotesEditing.invalidText(tool.model.language.translator))
        #expect(notes.add(freq: "14025", text: "CW beacon"))
        #expect(notes.add(freq: "20m", text: "DX window"))
        #expect(notes.notes.count == 2)
        let saved: AppConfig = await tool.app.savedConfigFlushed()
        #expect(saved.bandNotes.map(\.text).sorted() == ["CW beacon", "DX window"])
        #expect(tool.model.config.config.bandNotes.count == 2)

        tool.model.rig.updateTuned(14_025_000)
        #expect(notes.stripNote() == "CW beacon")
        #expect(tool.model.infoStrip.text.contains("📝 CW beacon"))
        tool.model.rig.updateTuned(14_030_000)
        #expect(notes.stripNote() == nil)
        let beacon = try #require(notes.notes.first { $0.text == "CW beacon" })
        notes.remove(beacon)
        #expect(notes.notes.map(\.text) == ["DX window"])
        // The Bandmap reads the same config.
        tool.model.rig.updateTuned(14_100_000)
        #expect(tool.model.bandmap.notes.map(\.text) == ["DX window"])
    }
}

/// Propagation, the world map and the multiplier grids: no data is fetched; the map reads a
/// fixture file only.
@MainActor @Suite struct MapAndGridToolsTests {

    static let geojson = """
    {"type":"FeatureCollection","features":[
     {"type":"Feature","geometry":{"type":"Polygon","coordinates":[[[0,0],[10,0],[10,10],[0,10],[0,0]]]}},
     {"type":"Feature","geometry":{"type":"MultiPolygon","coordinates":[[[[20,20],[30,20],[30,30],[20,20]]],[[[40,40],[50,40],[50,50],[40,40]]]]}}
    ]}
    """

    static func fixture(in dir: TempDir) throws -> URL {
        let file: URL = dir.child("dxcc.geojson")
        try geojson.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    // MARK: - propagation

    @Test func theSfiComesFromTheLastWwv() async throws {
        let clock = ManualClock()
        let spot = try await SpotApp.make(adjust: { $0.toolClock = clock })
        let propagation: PropagationWindowModel = spot.model.propagation
        propagation.open()
        #expect(propagation.sfiText == "120")
        await spot.connectMain(spot.server.favorite(name: "Fake"))
        spot.server.push("WWV de VE7CC <18Z> :   SFI=142, A=8, K=3, No Storms -> No Storms")
        await eventually("wwv") { spot.dx.lastWwv != nil }
        propagation.open()
        #expect(propagation.sfiText == "142")
        propagation.setSfi("1a5x9")
        #expect(propagation.sfiText == "159")
    }

    @Test func theViewNeedsAGridAndATarget() async throws {
        let tool = try await ToolApp.make(positions: true, configure: { config, _ in config.station.gridSquare = "JN89" })
        let propagation: PropagationWindowModel = tool.tools.propagation
        propagation.open()
        guard case .message(let hint) = propagation.view else {
            Issue.record("expected a message")
            return
        }
        #expect(hint == "Zadej volačku nebo prefix země.")
        propagation.setTarget("w1aw")
        #expect(propagation.target == "W1AW")
        guard case .table(let table) = propagation.view else {
            Issue.record("expected a table")
            return
        }
        #expect(table.hourLabels.count == 24)
        #expect(table.rows.map(\.band) == [.m10, .m15, .m20, .m40, .m80, .m160])
        #expect(table.title.contains("SSN"))
        #expect(table.nowHour == 12)
        // The same inputs give the same (cached) table.
        #expect(propagation.view == .table(table))
    }

    @Test func withoutAGridTheWindowAsksForIt() async throws {
        let tool = try await ToolApp.make(configure: { config, _ in config.station.gridSquare = "" })
        let propagation: PropagationWindowModel = tool.tools.propagation
        propagation.open()
        propagation.setTarget("W1AW")
        #expect(propagation.view == .message("Doplň lokátor stanice (Nastavení → Stanice)."))
    }

    // MARK: - world map

    @Test func theMapReadsTheFixtureOnTheIoLane() async throws {
        let dir = try TempDir()
        let tool = try await ToolApp.make(mapData: FileMapData(file: try Self.fixture(in: dir)))
        let map: WorldMapWindowModel = tool.tools.worldMap
        #expect(map.geo.rings.isEmpty)
        map.open()
        await map.settle()
        #expect(map.geoLoaded)
        #expect(map.geo.rings.count == 3)
        #expect(map.geo.ringGroups == [0, 1, 1])
        map.close()
    }

    @Test func aMissingMapFileGivesAnEmptyMap() async throws {
        let dir = try TempDir()
        let tool = try await ToolApp.make(mapData: FileMapData(file: dir.child("nothing.geojson")))
        let map: WorldMapWindowModel = tool.tools.worldMap
        map.open()
        await map.settle()
        #expect(map.geoLoaded)
        #expect(map.geo.rings.isEmpty)
        #expect(map.dxccMode)
        map.close()
    }

    @Test func theMapFollowsTheSpotsAndUnsubscribesOnClose() async throws {
        let tool = try await ToolApp.make(positions: true)
        try await tool.start("cq-ww-cw")
        // A QSO without a stored entity is resolved from its call (the dots compare the resolver's own codes).
        try await tool.insert(call: "DL1ABC", serial: 1, minute: 1)
        let feed: SpotFeed = tool.model.spotFeed
        let baseline: Int = feed.observerCount
        let map: WorldMapWindowModel = tool.tools.worldMap
        map.open()
        #expect(feed.observerCount == baseline + 1)
        #expect(map.isSubscribed)
        tool.model.dxCluster.spots.add(DxSpot(spotter: "OK1RR", freqHz: 14_030_000, dxCall: "W1AW", comment: ""))
        await eventually("the spot reaches the map") { map.spots.count == 1 }
        await map.settle()
        #expect(map.dots.contains { $0.state == .worked })
        #expect(map.dots.contains { $0.state == .spotted })
        map.close()
        #expect(feed.observerCount == baseline)
        #expect(!map.isSubscribed)
        // A closed window ignores the spots.
        tool.model.dxCluster.spots.add(DxSpot(spotter: "OK1RR", freqHz: 14_031_000, dxCall: "K1ABC", comment: ""))
        await runMainQueue()
        #expect(map.spots.count == 1)
    }

    @Test func theSquaresModeNeedsAContestAndShowsTheWorkedFields() async throws {
        let tool = try await ToolApp.make()
        let map: WorldMapWindowModel = tool.tools.worldMap
        map.open()
        // No contest: DXCC mode, and the squares say so.
        #expect(map.dxccMode)
        map.dxccMode = false
        #expect(map.needsContest)
        #expect(map.noContestText == "Čtverce jsou násobiče gridového závodu — žádný aktivní závod.")
        map.close()

        try await tool.start("ww-digi")
        var exchange = JavaLinkedMap<String>()
        exchange.put("grid", "JN49")
        tool.model.contest.log(call: "DL1ABC", band: "20m", mode: "FT8", exchange: exchange, ownQth: nil,
                               at: ToolApp.start)
        map.open()
        #expect(!map.dxccMode)
        #expect(map.fieldStates["JN"] == .worked)
        #expect(map.title == "Čtverce v mapě — 1 mults worked")
        map.close()
        map.startDxcc = true
        map.open()
        #expect(map.dxccMode)
        map.close()
    }

    @Test func theNightLayerIsRecomputedEverySixtySeconds() async throws {
        let tool = try await ToolApp.make()
        let map: WorldMapWindowModel = tool.tools.worldMap
        map.open()
        map.setCanvas(width: 360, height: 165)
        await map.settle()
        #expect(!map.night.isEmpty)
        let first: Int64 = map.nowMillis
        tool.now.advance(seconds: 60)
        tool.clock.advance(by: 59_000)
        #expect(map.nowMillis == first)
        tool.clock.advance(by: 1_000)
        #expect(map.nowMillis == first + 60_000)
        await map.settle()
        #expect(!map.night.isEmpty)
        map.close()
        let closedAt: Int64 = map.nowMillis
        tool.now.advance(seconds: 120)
        tool.clock.advance(by: 120_000)
        #expect(map.nowMillis == closedAt)
    }

    @Test func aClickOnTheMapTunesToTheSpotOfTheField() async throws {
        let tool = try await ToolApp.make(configure: { config, _ in config.station.gridSquare = "JN89" })
        try await tool.start("cq-ww-cw")
        let map: WorldMapWindowModel = tool.tools.worldMap
        map.open()
        tool.model.dxCluster.spots.add(DxSpot(spotter: "OK1RR", freqHz: 14_030_000, dxCall: "W1AW", comment: ""))
        await eventually("spot") { map.spots.count == 1 }
        let projection: WorldMapModel = map.projection
        let x: Float = projection.px(lon: -72, width: 360)
        let y: Float = projection.py(lat: 45, height: 165)
        // Without a known grid for the call nothing is tuned.
        #expect(map.tap(x: x, y: y, width: 360, height: 165) == nil)
        #expect(tool.model.rig.tuning.tunedFreqHz != 14_030_000)
        // With the callbook's grid the field FN holds the spot.
        let record = HamQthRecord(grid: "FN31", name: "", cqZone: "", ituZone: "")
        tool.model.callbook.cache.store("W1AW", record, generation: tool.model.callbook.cache.generation)
        #expect(map.tap(x: x, y: y, width: 360, height: 165)?.dxCall == "W1AW")
        #expect(tool.model.rig.tuning.tunedFreqHz == 14_030_000)
        map.close()
    }

    // MARK: - multiplier grids

    @Test func aGridWindowFollowsTheSpotsAndTunesByAClick() async throws {
        let tool = try await ToolApp.make()
        try await tool.start("cq-ww-cw")
        let grid: MultGridModel = tool.tools.multGrid(kind: "dxcc")
        #expect(tool.tools.multGrid(kind: "dxcc") === grid)
        #expect(grid.title == "DXCC")
        let feed: SpotFeed = tool.model.spotFeed
        let baseline: Int = feed.observerCount
        grid.open()
        #expect(feed.observerCount == baseline + 1)
        #expect(grid.grid.available)
        #expect(grid.grid.spotAt.isEmpty)
        tool.model.dxCluster.spots.add(DxSpot(spotter: "W3LPL", freqHz: 14_030_000, dxCall: "W1AW", comment: ""))
        await eventually("the spot reaches the grid") { grid.spots.count == 1 }
        let key = try #require(grid.grid.spotAt.keys.first)
        #expect(key.band == "20m")
        let tuned = grid.tune(key: key.key, band: .m20)
        #expect(tuned?.dxCall == "W1AW")
        #expect(tool.model.rig.tuning.tunedFreqHz == 14_030_000)
        #expect(grid.tune(key: "nothing", band: .m20) == nil)
        grid.close()
        #expect(feed.observerCount == baseline)
        #expect(!grid.isSubscribed)
    }

    @Test func theContinentFilterAndTheEmptyStates() async throws {
        let tool = try await ToolApp.make()
        let grid: MultGridModel = tool.tools.multGrid(kind: "grid")
        #expect(!grid.contestActive)
        #expect(grid.noContestText == "Žádný aktivní závod.")
        #expect(grid.selected == Set(MultGridLayout.continents))
        grid.toggle(continent: "EU")
        #expect(!grid.selected.contains("EU"))
        grid.toggleAll()
        #expect(grid.selected == Set(MultGridLayout.continents))
        try await tool.start("cq-ww-cw")
        #expect(!grid.grid.available)
        #expect(grid.unavailableText.contains("Velké čtverce"))
    }
}
