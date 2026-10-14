import Foundation
import Testing
@testable import MCLCore

/// The N1MM Multipliers window additions: bands displayed, the expected list, the rows shown, the prefix information
/// and the zone's countries.
@Suite struct MultGridExtrasTests {

    private static func row(_ key: String, prefix: String = "", continent: String = "",
                            cells: [String: MultCell] = [:]) -> MultGridRow {
        MultGridRow(key: key, label: key, prefix: prefix, continent: continent, cells: cells)
    }

    private static func entity(_ code: Int, _ prefix: String, _ name: String, cq: Int, itu: Int, lat: Double,
                               lon: Double) -> DxccEntity {
        DxccEntity(entityCode: code, name: name, countryCode: prefix, continents: ["EU"], cq: [cq], itu: [itu],
                   lat: lat, lon: lon, primaryPrefix: prefix)
    }

    private struct Lookup: DxccLookup {
        let all: [DxccEntity]
        func resolve(_ callsign: String?) -> DxccEntity? { nil }
        func entities() -> [DxccEntity] { all }
    }

    @Test func bandsAreSavedInBandOrderAndDefaultTo160To10() {
        #expect(MultGridExtras.bands(nil) == SpotAnalyzer.multGridBands)
        #expect(MultGridExtras.bands("junk") == SpotAnalyzer.multGridBands)
        #expect(MultGridExtras.bands("6m, 160m,30m") == [.m160, .m30, .m6])
        #expect(MultGridExtras.savedBands([.m6, .m160]) == "160m,6m")
        #expect(MultGridExtras.savedBands(SpotAnalyzer.multGridBands) == nil)
        #expect(MultGridExtras.header(.m160) == "160")
    }

    @Test func theExpectedListIsOnePerLineUpperCase() {
        let keys = MultGridExtras.expected("dl 14\n  CE0X  \n# comment\nOK, 7\n\n")
        #expect(keys == ["DL", "CE0X", "OK"])
        #expect(MultGridExtras.expectedText(keys) == "CE0X\nDL\nOK\n")
        #expect(MultGridExtras.isExpected(Self.row("230", prefix: "DL"), keys))
        #expect(!MultGridExtras.isExpected(Self.row("281", prefix: "EA"), keys))
    }

    @Test func theRowsShownAreWorkedSpottedOrExpectedUnlessAll() {
        let rows = [Self.row("A", continent: "EU", cells: ["20m": .worked]),
                    Self.row("B", continent: "EU", cells: ["6m": .spotted]),
                    Self.row("C", continent: "AS"),
                    Self.row("D", continent: "EU")]
        let all = Set(MultGridLayout.continents)
        let bands: [Band] = SpotAnalyzer.multGridBands
        #expect(MultGridExtras.visibleRows(rows, bands: bands, continents: all, expected: [], showAll: false)
            .map(\.key) == ["A"], "a spot on a band not shown does not count")
        #expect(MultGridExtras.visibleRows(rows, bands: bands + [.m6], continents: all, expected: ["D"],
                                           showAll: false).map(\.key) == ["A", "B", "D"])
        #expect(MultGridExtras.visibleRows(rows, bands: bands, continents: ["EU"], expected: [], showAll: true)
            .map(\.key) == ["A", "B", "D"])
    }

    @Test func theWorkedExportListsTheWorkedBandsInMHz() {
        let rows = [Self.row("230", prefix: "DL", cells: ["20m": .worked, "40m": .worked, "80m": .spotted]),
                    Self.row("291", prefix: "K")]
        #expect(MultGridExtras.workedExport(rows, bands: [.m80, .m40, .m20]) == "DL 7 14\n")
        #expect(MultGridExtras.expected(MultGridExtras.workedExport(rows, bands: [.m20])) == ["DL"])
    }

    @Test func prefixInformationAndTheZonesCountries() throws {
        let germany = Self.entity(230, "DL", "Germany", cq: 14, itu: 28, lat: 51, lon: 10)
        let czech = Self.entity(503, "OK", "Czech Republic", cq: 15, itu: 28, lat: 49.5, lon: 15.5)
        let lookup = Lookup(all: [germany, czech])
        let info = MultGridExtras.prefixInfo(kind: "dxcc", row: Self.row("230", prefix: "DL"), lookup: lookup,
                                             myLat: 50, myLon: 14.5)
        #expect(info?.hasPrefix("DL Germany · EU · CQ 14 · ITU 28 · SP ") == true, "\(info ?? "")")
        #expect(info?.hasSuffix(" km") == true)
        let noPosition = MultGridExtras.prefixInfo(kind: "dxcc", row: Self.row("230"), lookup: lookup,
                                                   myLat: .nan, myLon: .nan)
        #expect(noPosition == "DL Germany · EU · CQ 14 · ITU 28")
        #expect(MultGridExtras.prefixInfo(kind: "cq", row: Self.row("14"), lookup: lookup, myLat: 50,
                                          myLon: 14.5) == nil)
        let grid = MultGridExtras.prefixInfo(kind: "grid", row: Self.row("JO"), lookup: nil, myLat: 50, myLon: 14.5)
        #expect(grid?.hasPrefix("JO · SP ") == true)
        let west = try #require(MultGridExtras.azimuth(kind: "dxcc", row: Self.row("230"), lookup: lookup,
                                                       myLat: 50, myLon: 14.5))
        #expect(west > 270 && west < 300)
        #expect(MultGridExtras.azimuth(kind: "dxcc", row: Self.row("230"), lookup: lookup, myLat: .nan,
                                       myLon: 14.5) == nil)

        #expect(MultGridExtras.countriesInZone(kind: "itu", zone: "28", lookup: lookup)
            == ["DL Germany", "OK Czech Republic"])
        #expect(MultGridExtras.countriesInZone(kind: "cq", zone: "15", lookup: lookup) == ["OK Czech Republic"])
        #expect(MultGridExtras.countriesInZone(kind: "dxcc", zone: "15", lookup: lookup).isEmpty)
        #expect(MultGridExtras.roverKind("districts") && MultGridExtras.roverKind("grid"))
        #expect(!MultGridExtras.roverKind("dxcc"))
    }
}
