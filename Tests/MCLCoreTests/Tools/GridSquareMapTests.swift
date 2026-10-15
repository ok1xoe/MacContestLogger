import Foundation
@testable import MCLCore
import Testing

@Suite struct GridSquareMapTests {

    private static func qso(_ call: String, _ exchange: String, _ band: Band, deleted: Bool = false,
                            xqso: Bool = false) -> Qso {
        var qso = Qso()
        qso.call = call
        qso.exchangeRcvd = exchange
        qso.band = band
        qso.deleted = deleted
        qso.xqso = xqso
        return qso
    }

    @Test func squareNormalisesLocators() {
        #expect(GridSquareMap.square("jn79ab") == "JN79")
        #expect(GridSquareMap.square(" JO60 ") == "JO60")
        #expect(GridSquareMap.square("JN7") == nil)
        #expect(GridSquareMap.square("ZZ00") == nil)
        #expect(GridSquareMap.square(nil) == nil)
    }

    @Test func neighboursStepAndWrapInLongitude() {
        #expect(GridSquareMap.neighbour("JN79", east: 1, north: 0) == "JN89")
        #expect(GridSquareMap.neighbour("JN79", east: -1, north: 1) == "JO60")
        #expect(GridSquareMap.neighbour("JN79", east: 0, north: -10) == "JM79")
        // Across the antimeridian: RR99 east → AR09.
        #expect(GridSquareMap.neighbour("RR99", east: 1, north: 0) == "AR09")
        #expect(GridSquareMap.neighbour("AA00", east: -1, north: 0) == "RA90")
        // Beyond a pole there is nothing.
        #expect(GridSquareMap.neighbour("JR09", east: 0, north: 1) == nil)
        #expect(GridSquareMap.neighbour("JA00", east: 0, north: -1) == nil)
    }

    @Test func matrixIsCentredOddAndNorthUp() {
        let matrix: [[String?]] = GridSquareMap.matrix(center: "JN79", columns: 3, rows: 4)
        #expect(matrix.count == 5)
        #expect(matrix.allSatisfy { $0.count == 3 })
        #expect(matrix[2][1] == "JN79")
        #expect(matrix[0][1] == "JO71")
        #expect(matrix[4][0] == "JN67")
        #expect(matrix[2][2] == "JN89")
        #expect(GridSquareMap.matrix(center: "bad", columns: 3, rows: 3).isEmpty)
        // At the pole the rows beyond are empty.
        let polar: [[String?]] = GridSquareMap.matrix(center: "JR09", columns: 1, rows: 3)
        #expect(polar == [[nil], ["JR09"], ["JR08"]])
    }

    @Test func fitGivesOddCounts() {
        #expect(GridSquareMap.fit(length: 100, cell: 20) == 5)
        #expect(GridSquareMap.fit(length: 80, cell: 20) == 3)
        #expect(GridSquareMap.fit(length: 5, cell: 20) == 1)
        #expect(GridSquareMap.oddCount(4) == 5)
        #expect(GridSquareMap.oddCount(0) == 1)
    }

    @Test func cellsPreferWorkedThenSpottedThenExpected() {
        let qsos: [Qso] = [
            Self.qso("OK1A", "59 JN79AB", .m2),
            Self.qso("OK1B", "59 JN89", .cm70),
            Self.qso("OK1C", "59 JO70", .m2, deleted: true),
            Self.qso("OK1D", "59 JO60", .m2, xqso: true),
        ]
        let spots: [GridSquareMap.SpotSquare] = [
            GridSquareMap.SpotSquare(square: "JN79", band: .m2, call: "DL1X", freqHz: 144_300_000),
            GridSquareMap.SpotSquare(square: "JN69", band: .m2, call: "DL2X", freqHz: 144_310_000),
            GridSquareMap.SpotSquare(square: "JN89", band: .m2, call: "DL3X", freqHz: 144_320_000),
        ]
        let all = GridSquareMap.cells(qsos: qsos, spots: spots, band: nil, expected: ["jn99", "JN69", "bad"])
        #expect(all["JN79"] == .worked)
        #expect(all["JN89"] == .worked)
        #expect(all["JN69"] == .spotted)
        #expect(all["JN99"] == .expected)
        #expect(all["JO70"] == nil)
        #expect(all["JO60"] == nil)
        #expect(GridSquareMap.workedCount(all) == 2)
        // On 2 m only, JN89 (worked on 70 cm) is only spotted.
        let twoMetres = GridSquareMap.cells(qsos: qsos, spots: spots, band: .m2, expected: [])
        #expect(twoMetres["JN89"] == .spotted)
        #expect(twoMetres["JN79"] == .worked)
        let seventy = GridSquareMap.cells(qsos: qsos, spots: spots, band: .cm70, expected: [])
        #expect(seventy == ["JN89": .worked])
        #expect(GridSquareMap.color(.expected) == GridSquareMap.expectedColor)
        #expect(GridSquareMap.color(.worked) == MultGridLayout.workedColor)
        #expect(GridSquareMap.color(.empty) == nil)
    }

    @Test func bandsAndQsosInASquare() {
        let qsos: [Qso] = [Self.qso("OK1A", "JN79", .cm70), Self.qso("OK1B", "JN79AA", .m2), Self.qso("OK1C", "", .m6)]
        let spots = [GridSquareMap.SpotSquare(square: "JN69", band: .cm23, call: "X", freqHz: 1_296_200_000)]
        #expect(GridSquareMap.bands(qsos: qsos, spots: spots) == [.m2, .cm70, .cm23])
        #expect(GridSquareMap.qsos(in: "jn79", qsos).map(\.call) == ["OK1A", "OK1B"])
    }

    @Test func exportListsSquaresWithBandsInMhz() {
        let qsos: [Qso] = [
            Self.qso("OK1A", "JN79", .cm70), Self.qso("OK1B", "JN79AA", .m2), Self.qso("OK1C", "JN69", .m2),
            Self.qso("OK1D", "JN59", .m2, deleted: true),
        ]
        #expect(GridSquareMap.export(qsos: qsos) == "JN69 144\nJN79 144 430\n")
        // The export reads back as an expected list.
        #expect(MultGridExtras.expected(GridSquareMap.export(qsos: qsos)) == ["JN69", "JN79"])
    }

    @Test func headingToTheSquareCentre() throws {
        let heading = try #require(GridSquareMap.heading(from: "JN79", to: "JN89"))
        #expect(heading.bearing == 90 || heading.bearing == 89)
        #expect((140...160).contains(heading.km))
        let north = try #require(GridSquareMap.heading(from: "JN79", to: "JO70"))
        #expect(north.bearing == 0)
        #expect(GridSquareMap.heading(from: "", to: "JN89") == nil)
        #expect(GridSquareMap.azimuth(from: "JN79", to: "bad") == nil)
        let azimuth = try #require(GridSquareMap.azimuth(from: "JN79", to: "JM79"))
        #expect(abs(azimuth - 180) < 0.001)
    }
}
