import Foundation
import Testing
@testable import MCLAppModel
@testable import MCLCore

/// N1MM „Grid Square Map": the centre, the cells from the log's locators, the band filter, the right-click items, the
/// expected list and the export. No rotator is configured; nothing transmits.
@MainActor @Suite struct GridSquareMapModelTests {

    private func insert(_ tool: ToolApp, call: String, exchange: String, band: Band, freqHz: Int) async throws {
        var qso = Qso()
        qso.call = call
        qso.freqHz = freqHz
        qso.band = band
        qso.mode = .cw
        qso.exchangeRcvd = exchange
        qso.contestId = tool.model.logbook.activeContestId
        qso.timestampUtc = ToolApp.start
        let stored: Qso = qso
        try await tool.model.database.handle.run { access in
            var copy: Qso = stored
            _ = try access.repository.insert(&copy)
        }
        try await tool.model.logbook.refresh()
    }

    @Test func withoutAnOwnLocatorThereIsNoMap() async throws {
        let tool = try await ToolApp.make()
        let map: GridSquareMapModel = tool.model.gridMap
        #expect(map.center == nil)
        #expect(map.matrix(columns: 3, rows: 3).isEmpty)
        #expect(!map.canTurnAntenna("JN79"))
        #expect(map.noGridText.contains("Nastavení"))
        // A picked centre works without one.
        map.setCenter("jo60")
        #expect(map.center == "JO60")
        map.resetCenter()
        #expect(map.center == nil)
    }

    @Test func cellsBandsDetailsAndExport() async throws {
        let tool = try await ToolApp.make { config, _ in
            config.station.gridSquare = "JN79AB"
        }
        try await tool.start("cq-ww-cw")
        let map: GridSquareMapModel = tool.model.gridMap
        map.open()
        #expect(map.isSubscribed)
        #expect(map.center == "JN79")
        let matrix: [[String?]] = map.matrix(columns: 3, rows: 3)
        #expect(matrix[1][1] == "JN79")
        #expect(matrix[0][1] == "JO70")

        try await insert(tool, call: "OK1AAA", exchange: "599 JN89", band: .m20, freqHz: 14_025_000)
        try await insert(tool, call: "OK1BBB", exchange: "599 JO70AA", band: .m40, freqHz: 7_025_000)
        #expect(map.cells["JN89"] == .worked)
        #expect(map.cells["JO70"] == .worked)
        #expect(map.bandChoices == [.m40, .m20])
        #expect(map.headline.contains("2"))
        map.band = .m40
        #expect(map.cells["JN89"] == nil)
        #expect(map.headline.hasSuffix("(40m)"))
        map.band = nil

        map.showCallsWorked("JN89")
        let details = try #require(map.details)
        #expect(details.lines.contains { $0.hasSuffix("OK1AAA") }, "\(details.lines)")
        map.showCallsWorked("JN59")
        #expect(map.details?.lines.count == 1)

        map.showHeading("JO70")
        let heading = try #require(map.details?.lines.first)
        #expect(heading.contains(" km"), "\(heading)")
        #expect(heading.contains("JN79AB"), "\(heading)")
        #expect(map.tooltip("JN89").hasPrefix("JN89 · "))
        #expect(map.canTurnAntenna("JN89"))

        #expect(map.workedExport == "JN89 14\nJO70 7\n")

        map.setExpectedText("jn99 # a comment\nnot-a-square\nJN69 144\n")
        #expect(map.expected == ["JN99", "JN69"])
        #expect(tool.model.config.config.multExpected[GridSquareMapModel.windowId] == "JN69\nJN99\n")
        #expect(map.cells["JN99"] == .expected)
        map.clearExpected()
        #expect(map.expected.isEmpty)
        #expect(tool.model.config.config.multExpected[GridSquareMapModel.windowId] == nil)

        map.setCenter("JN89")
        #expect(map.matrix(columns: 1, rows: 1) == [["JN89"]])
        map.close()
        #expect(!map.isSubscribed)
    }

    @Test func theMenuItemOpensTheWindow() async throws {
        let tool = try await ToolApp.make()
        #expect(MenuActions.perform("mult.gridmap", app: tool.model) == nil)
        #expect(tool.model.windows.isOpen("gridmap"))
        #expect(!tool.model.gridMap.canSetRover)
    }
}
