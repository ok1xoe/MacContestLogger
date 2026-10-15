import Foundation
import Testing
@testable import MCLCore

/// The millimetre bands (24 – 241 GHz, N1MM supports VHF and up to 241 GHz): ranges, ADIF names, Cabrillo 3.0
/// designators, REG1TEST `PBand`, the entry window rows and the database names.
@Suite struct MillimetreBandsTests {

    static let table: [(band: Band, adif: String, hz: Int, cabrillo: String, edi: String, mhz: String)] = [
        (.cm125, "1.25cm", 24_048_200_000, "24G", "24 GHz", "24048"),
        (.mm6, "6mm", 47_088_200_000, "47G", "47 GHz", "47088"),
        (.mm4, "4mm", 76_032_200_000, "75G", "76 GHz", "76032"),
        (.mm25, "2.5mm", 122_250_200_000, "122G", "122 GHz", "122250"),
        (.mm2, "2mm", 134_928_200_000, "134G", "134 GHz", "134928"),
        (.mm1, "1mm", 241_920_200_000, "241G", "248 GHz", "241920"),
    ]

    @Test func frequenciesAndAdifNamesResolve() {
        for row in Self.table {
            #expect(Band.from(frequencyHz: row.hz) == row.band, "\(row.adif)")
            #expect(Band.from(adif: row.adif) == row.band)
            #expect(Band.from(adif: row.adif.uppercased()) == row.band)
            #expect(row.band.isMicrowave)
            #expect(!Band.javaV111Cases.contains(row.band))
        }
        #expect(Band.from(frequencyHz: 30_000_000_000) == nil)
        Band.$javaV111Table.withValue(true) {
            #expect(Band.from(frequencyHz: 24_048_200_000) == nil)
        }
    }

    @Test func cabrilloEdiAndMacroNames() throws {
        for row in Self.table {
            var q = Qso()
            q.freqHz = row.hz
            #expect(CabrilloExporter.frequency(q) == row.cabrillo, "\(row.adif)")
            #expect(EdiExporter.bandName(row.band) == row.edi)
            #expect(MacroFrequency.band(Int64(row.hz)) == row.mhz)
            var input = try CabrilloExporterTests.cqww([])
            input.category = CabrilloExporterTests.map(("BAND", row.adif.uppercased()))
            #expect(try CabrilloExporter.export(input).text.contains("CATEGORY-BAND: \(row.cabrillo)\n"), "\(row.adif)")
        }
    }

    @Test func adifRoundTrip() throws {
        var q = Qso()
        q.timestampUtc = ISO8601DateFormatter().date(from: "2026-06-17T12:00:00Z")
        q.call = "DL1ABC"
        q.freqHz = 24_048_200_000
        q.mode = .cw
        let adif = AdifWriter().toAdif([q])
        #expect(adif.contains("<BAND:6>1.25cm"))
        let back = try #require(try AdifReader().read(adif).first)
        #expect(back.band == .cm125)
        #expect(back.freqHz == 24_048_200_000)
    }

    @Test func databaseNamesRoundTrip() {
        for row in Self.table {
            #expect(Band(javaName: row.band.javaName) == row.band)
        }
        #expect(Set(Band.allCases.map(\.javaName)).count == Band.allCases.count)
    }

    @Test func entryRowsAndTheSpotGroup() {
        for row in Self.table {
            let entry = BandRows.all.first { $0.band == row.band }
            #expect(entry != nil, "\(row.adif)")
            #expect(BandRows.startKHz(band: row.band, column: .cw).map { Int($0 * 1000) } == row.hz - 150_000)
            #expect(SpotFilter.Group.microwave.bands.contains(row.band))
        }
    }
}
