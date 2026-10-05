import Testing
@testable import MCLCore

/// Port of the Java `AntennaSelectorTest` (2 tests, same names). `select`/`next` return
/// the **position in the table** (Java instance identity, see `AntennaSelector`), the test converts it
/// back to a row.
@Suite struct AntennaSelectorTests {

    private let yagiUs = AntennaEntry(code: 1, name: "Yagi USA", bands: "20m,15m", sector: "270-360")
    private let yagiJa = AntennaEntry(code: 2, name: "Yagi JA", bands: "14, 21", sector: "0-90")
    private let dipole = AntennaEntry(code: 9, name: "Dipól 40/30", bands: "7, 10", sector: "")
    private var all: [AntennaEntry] { [yagiUs, yagiJa, dipole] }

    private func select(_ band: Band, _ azimuth: Int?) -> AntennaEntry? {
        AntennaSelector.select(all, band: band, azimuth: azimuth).map { all[$0] }
    }

    @Test func byBandAndAzimuth() {
        #expect(select(.m20, 45) == yagiJa)
        #expect(select(.m20, 300) == yagiUs)
        #expect(select(.m20, 180) == yagiUs, "outside the sectors = the first")
        #expect(select(.m40, nil) == dipole)
        #expect(select(.m160, 0) == nil)
    }

    @Test func cycleAndSectorAcrossNorth() {
        // `yagiUs` is at position 0 in the table, `yagiJa` at position 1.
        #expect(AntennaSelector.next(all, band: .m15, currentIndex: 0).map { all[$0] } == yagiJa)
        #expect(AntennaSelector.next(all, band: .m15, currentIndex: 1).map { all[$0] } == yagiUs)
        #expect(AntennaSelector.inSector("300-60", 10))
        #expect(!AntennaSelector.inSector("300-60", 200))
    }
}
