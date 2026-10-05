import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// End to end (post-port microwave bands): a UHF contest whose definition lists the
/// bands up to 3 cm — the entry grid, the category options, the dupe check per band, the km score and the exports.
/// The definition is a fixture of this repository; the app only reads it (a fake data dir, no radio, no network).
@MainActor @Suite struct MicrowaveContestTests {

    static var microwaveFixture: URL {
        Fixtures.coreFixtures.appendingPathComponent("microwave/contests/uhf-microwave.yaml")
    }

    /// The shipped definitions plus the fixture's UHF/microwave one, in a temporary copy (the app writes its own
    /// data files next to the definitions, the fixtures stay untouched).
    static func contestDataCopy(next dataDir: URL) throws -> URL {
        let copy: URL = dataDir.deletingLastPathComponent().appendingPathComponent("contest-data-microwave")
        try FileManager.default.copyItem(at: Fixtures.contestData, to: copy)
        try FileManager.default.copyItem(at: microwaveFixture,
                                         to: copy.appendingPathComponent("contests/uhf-microwave.yaml"))
        return copy
    }

    static func start(category: [String: String] = [:]) async throws -> TestApp {
        let app = try await TestApp.make { config, dataDir in
            config.contestDataDir = try contestDataCopy(next: dataDir).path
            config.station.gridSquare = "JN79FX"
        }
        var setup = ContestSetup()
        setup.sentExchange = ["loc": "JN79FX"]
        setup.category = category
        let started: Bool = await app.model.contest.createAndStart(definitionId: "uhf-microwave", setup: setup)
        try #require(started, "activation failed: \(app.model.status.message)")
        return app
    }

    static func log(_ app: TestApp, call: String, freqKHz: String, loc: String) async {
        let entry: EntryModel = app.model.entry
        entry.setFrequency(freqKHz)
        entry.callChanged(call)
        entry.editContestField("nr", "1")
        entry.editContestField("loc", loc)
        entry.submit()
        await entry.settle()
    }

    @Test func theGridAndTheCategoryListTheMicrowaveBands() async throws {
        let app = try await Self.start()
        let grid: EntryGrid = EntryGrid.of(app.model.contest)
        #expect(grid.rows.map(\.band) == [.cm70, .cm23, .cm13, .cm9, .cm6, .cm3])
        let definition: ContestDefinition = try #require(app.model.contest.definition)
        #expect(CategoryCatalog.bandOptions(definition) == ["ALL", "70CM", "23CM", "13CM", "9CM", "6CM", "3CM"])
        let cell = grid.cell(try #require(grid.rows.first { $0.band == .cm3 }), .PH, currentBand: .cm3,
                             currentMode: .ssb)
        #expect(cell == EntryGrid.Cell(kHz: 10_368_200.0, enabled: true, active: true))
        // 3 cm has no RTTY segment: the cell is not clickable.
        let rtty = grid.cell(try #require(grid.rows.first { $0.band == .cm3 }), .RY, currentBand: .cm3,
                             currentMode: .rtty)
        #expect(!rtty.enabled)
    }

    @Test func steppingGoesThroughTheContestBands() async throws {
        let app = try await Self.start()
        #expect(app.model.rig.bandsForStepping() == [.cm70, .cm23, .cm13, .cm9, .cm6, .cm3])
    }

    @Test func dupeIsPerBandAndTheScoreIsInKilometres() async throws {
        let app = try await Self.start()
        await Self.log(app, call: "OK1AAA", freqKHz: "1296200", loc: "JO70FC")
        await Self.log(app, call: "OK1AAA", freqKHz: "10368100", loc: "JO70FC")
        let entry: EntryModel = app.model.entry
        // The same station on 23 cm again is a dupe, on 13 cm it is not.
        entry.setFrequency("1296300")
        entry.callChanged("OK1AAA")
        entry.updatePreview()
        #expect(entry.isDupe)
        entry.setFrequency("2320200")
        entry.updatePreview()
        #expect(!entry.isDupe)
        entry.callChanged("")
        let rows: [Qso] = app.model.logbook.rows
        #expect(Set(rows.compactMap(\.band)) == [.cm23, .cm3])
        let score: ScoreState = try #require(app.model.contest.score)
        #expect(score.qsoCount == 2)
        let km: Int64 = Int64(Maidenhead.distanceKm("JN79FX", "JO70FC").rounded(.up))
        #expect(score.qsoPoints == 2 * km && km > 0)
    }

    @Test func cabrilloAndEdiCarryTheMicrowaveBands() async throws {
        let app = try await Self.start(category: ["BAND": "23CM", "MODE": "SSB"])
        await Self.log(app, call: "OK1AAA", freqKHz: "1296200", loc: "JO70FC")
        await Self.log(app, call: "OK1BBB", freqKHz: "432200", loc: "JO70FC")
        let log: URL = app.dir.child("uhf.log")
        await app.model.exports.exportCabrillo(to: log)
        let text: String = try String(contentsOf: log, encoding: .ascii)
        #expect(text.contains("CATEGORY-BAND: 1.2G\n"))
        #expect(text.contains("QSO: 1.2G "))
        let dir: URL = app.dir.child("edi")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        await app.model.exports.exportEdi(to: dir)
        let names: [String] = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        #expect(names == ["OK1XOE_23cm.edi", "OK1XOE_70cm.edi"])
        let edi23: String = try String(contentsOf: dir.appendingPathComponent("OK1XOE_23cm.edi"), encoding: .isoLatin1)
        #expect(edi23.contains("PBand=1,3 GHz"))
    }
}
