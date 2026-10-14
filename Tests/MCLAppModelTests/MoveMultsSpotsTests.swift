import Foundation
import Testing
@testable import MCLAppModel
@testable import MCLCore

/// N1MM Move Multipliers over the spots: the rows, the saved options, Refresh, hiding a row and the clicks. The rig is
/// a fake; nothing transmits.
@MainActor @Suite struct MoveMultsSpotsTests {

    @Test func spottedStationsByBandAndTheOptions() async throws {
        let tool = try await ToolApp.make()
        try await tool.start("cq-ww-cw")
        let moves: MoveMultsModel = tool.model.moveMults
        let model: AppModel = tool.model
        #expect(moves.bands == [.m160, .m80, .m40, .m20, .m15, .m10], "the contest's bands")
        model.dxCluster.spots.add(DxSpot(spotter: "W3LPL", freqHz: 14_025_000, dxCall: "DL1ABC", comment: ""))
        model.dxCluster.spots.add(DxSpot(spotter: "W3LPL", freqHz: 14_250_000, dxCall: "K1ZZ", comment: "SSB"))
        await eventually("the spots reach the feed") { model.spotFeed.snapshot().count == 2 }
        moves.setShowSpots(true)
        #expect(moves.spotRows.map(\.call) == ["DL1ABC"], "a phone spot is outside a CW contest")
        let row = try #require(moves.visibleSpotRows.first)
        #expect(moves.cellText(row, band: .m20) == "M2", "a new country and zone")
        #expect(row.spottedBands(moves.bands) == [.m20])

        moves.setModes(.all)
        #expect(model.config.config.moveMultsModes == "ALL")
        #expect(moves.spotRows.count == 2)
        moves.setDisplay(.counts)
        #expect(model.config.config.moveMultsDisplay == "COUNTS")
        #expect(moves.cellText(row, band: .m20) == "-")
        moves.setRangeText("1-3")
        #expect(moves.visibleSpotRows.isEmpty, "nobody worked yet")
        moves.setRangeText("0")
        #expect(moves.visibleSpotRows.count == 2)
        moves.hide(row)
        #expect(moves.visibleSpotRows.map(\.call) == ["K1ZZ"])
        moves.refreshSpots()
        #expect(moves.visibleSpotRows.count == 2, "Refresh brings hidden rows back")
        moves.setBand(.m160, shown: false)
        #expect(model.config.config.moveMultsBands == "80m,40m,20m,15m,10m")

        moves.setModes(.contest)
        moves.setDisplay(.multipliers)
        let listed = try #require(moves.visibleSpotRows.first)
        #expect(moves.tuneNext(listed)?.freqHz == 14_025_000)
        #expect(model.rig.tuning.tunedFreqHz == 14_025_000)
        // A call spotted on two bands: a click on the call goes to each spotted band in turn.
        let spot40 = DxSpot(spotter: "W3LPL", freqHz: 7_025_000, dxCall: "DL2XYZ", comment: "")
        let spot20 = DxSpot(spotter: "W3LPL", freqHz: 14_026_000, dxCall: "DL2XYZ", comment: "")
        let dl = SpotMoveMults.Row(call: "DL2XYZ", mode: "CW", cells: [
            "40m": .init(newMults: 2, points: 3, count: 0, spot: spot40),
            "20m": .init(newMults: 2, points: 3, count: 0, spot: spot20),
        ])
        #expect(moves.tuneNext(dl)?.freqHz == 7_025_000)
        #expect(model.rig.tuning.tunedFreqHz == 7_025_000)
        #expect(moves.tuneNext(dl)?.freqHz == 14_026_000)
        #expect(moves.tuneNext(dl)?.freqHz == 7_025_000, "cycles")
        #expect(moves.tune(dl, band: .m15) == nil, "not spotted there")
        #expect(moves.tune(dl, band: .m20)?.freqHz == 14_026_000)
        #expect(model.rig.tuning.tunedFreqHz == 14_026_000)
        moves.tune(dl, band: .m40, otherVfo: true)
        #expect(model.rig.tuning.tunedFreqHz == 14_026_000, "Shift+click leaves VFO A")
    }
}
