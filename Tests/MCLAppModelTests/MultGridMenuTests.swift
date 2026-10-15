import Foundation
import Testing
@testable import MCLAppModel
@testable import MCLCore

/// The N1MM Multipliers window: the bands displayed, the expected list, „show all", the right-click menu and a click
/// that sets the multiplier's mode. Fake rig; nothing transmits.
@MainActor @Suite struct MultGridMenuTests {

    @Test func bandsExpectedListAndShowAllAreSaved() async throws {
        let tool = try await ToolApp.make()
        try await tool.start("cq-ww-cw")
        let grid: MultGridModel = tool.tools.multGrid(kind: "dxcc")
        grid.open()
        #expect(grid.bands == SpotAnalyzer.multGridBands)
        grid.setBand(.m30, shown: true)
        grid.setBand(.m160, shown: false)
        #expect(grid.bands == [.m80, .m40, .m30, .m20, .m15, .m10])
        #expect(grid.bandHeaders.first == "80")
        #expect(tool.model.config.config.multGridBands["dxcc"] == "80m,40m,30m,20m,15m,10m")
        #expect(grid.grid.rows.first?.cells.keys.contains("30m") == true)

        await tool.log("DL1ABC")
        await eventually("the QSO reaches the grid") {
            grid.grid.rows.contains { $0.cells["20m"] == .worked }
        }
        let worked = try #require(grid.grid.rows.first { $0.cells["20m"] == .worked })
        #expect(grid.visibleRows.map(\.key) == [worked.key])
        grid.setExpectedText("ok\nOK\n")
        #expect(tool.model.config.config.multExpected["dxcc"] == "OK\n")
        #expect(grid.expected == ["OK"])
        #expect(grid.visibleRows.count == 2, "\(grid.visibleRows.map(\.prefix))")
        #expect(grid.workedExport.hasSuffix(" 14\n"))
        grid.setShowAll(true)
        #expect(tool.model.config.config.multGridShowAll == ["dxcc"])
        #expect(grid.visibleRows.count == grid.grid.rows.count)
        grid.setShowAll(false)
        #expect(tool.model.config.config.multGridShowAll.isEmpty)

        grid.showCallsWorked(worked)
        let details = try #require(grid.details)
        #expect(details.lines.contains { $0.hasSuffix("DL1ABC") }, "\(details.lines)")
        grid.close()
    }

    @Test func theModesShownAreSavedPerKind() async throws {
        let tool = try await ToolApp.make()
        try await tool.start("rdxc")
        let grid: MultGridModel = tool.tools.multGrid(kind: "dxcc")
        #expect(grid.contestModes == ["CW", "SSB"])
        #expect(grid.shownModes == ["CW"])
        grid.setMode("SSB", shown: true)
        #expect(grid.shownModes == ["CW", "SSB"])
        #expect(tool.model.config.config.multGridBands["dxcc/modes"] == "CW,SSB")
        grid.setMode("CW", shown: false)
        #expect(grid.shownModes == ["SSB"])
        grid.setMode("SSB", shown: false)        // the last mode stays
        #expect(grid.shownModes == ["SSB"])
        grid.setMode("CW", shown: true)
        grid.setMode("SSB", shown: false)
        #expect(tool.model.config.config.multGridBands["dxcc/modes"] == nil)
        #expect(tool.tools.multGrid(kind: "cq").shownModes == ["CW"])
    }

    @Test func zoneCountriesAndTheTurnAntennaItem() async throws {
        let tool = try await ToolApp.make(positions: true) { config, _ in
            config.station.latitude = "50.0"
            config.station.longitude = "14.5"
        }
        try await tool.start("cq-ww-cw")
        let cq: MultGridModel = tool.tools.multGrid(kind: "cq")
        #expect(cq.isZoneKind)
        let zone14 = try #require(cq.grid.rows.first { $0.key == "14" })
        cq.showCountries(zone14)
        #expect(cq.details?.lines.contains { $0.hasPrefix("DL") } == true, "\(cq.details?.lines ?? [])")
        #expect(!cq.canSetRover)

        let dxcc: MultGridModel = tool.tools.multGrid(kind: "dxcc")
        #expect(!dxcc.isZoneKind)
        let germany = try #require(dxcc.grid.rows.first { $0.prefix == "DL" })
        #expect(dxcc.canTurnAntenna(germany))
        #expect(dxcc.prefixInfo(germany)?.contains("Germany") == true)
    }

    @Test func aClickSetsTheMultipliersMode() async throws {
        let tool = try await ToolApp.make()
        try await tool.start("rdxc")
        let model: AppModel = tool.model
        #expect(!model.config.config.dxCluster.spotModeOnTune)
        let grid: MultGridModel = tool.tools.multGrid(kind: "dxcc")
        grid.open()
        model.entry.setMode(.ssb)
        model.dxCluster.spots.add(DxSpot(spotter: "W3LPL", freqHz: 14_030_000, dxCall: "W1AW", comment: "CW"))
        await eventually("the spot reaches the grid") { grid.spots.count == 1 }
        let key = try #require(grid.grid.spotAt.keys.first)
        grid.tune(key: key.key, band: .m20)
        await runMainQueue()
        #expect(model.entry.form.mode == .cw)
        grid.close()
    }
}
