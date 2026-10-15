import Foundation
import Testing
@testable import MCLCore

/// The Region 2 bands 222 MHz (ADIF `1.25m`) and 902 MHz (ADIF `33cm`): ranges, ADIF names, Cabrillo 3.0
/// designators, EDI `PBand`, the frequency macro, the entry window rows, the database names, the spot groups and
/// the N1MM band names — plus sweeps over every band so that a band added later cannot be forgotten in a table.
@Suite struct RegionTwoBandsTests {

    static let table: [(band: Band, adif: String, hz: Int, cabrillo: String, edi: String, mhz: String, db: String)] = [
        (.m125, "1.25m", 222_100_000, "222", "222 MHz", "222", "M125"),
        (.cm33, "33cm", 903_100_000, "902", "902 MHz", "902", "CM33"),
    ]

    @Test func frequenciesAndAdifNamesResolve() {
        for row in Self.table {
            #expect(Band.from(frequencyHz: row.hz) == row.band, "\(row.adif)")
            #expect(Band.from(adif: row.adif) == row.band)
            #expect(Band.from(adif: row.adif.uppercased()) == row.band)
            #expect(!row.band.isMicrowave)
            #expect(!Band.javaV111Cases.contains(row.band))
            #expect(row.band.javaName == row.db)
            #expect(Band(javaName: row.db) == row.band)
        }
        // Band edges (ARRL: 222–225 MHz, 902–928 MHz); 1.25 m is not the 24 GHz 1.25 cm band.
        #expect(Band.from(frequencyHz: 222_000_000) == .m125 && Band.from(frequencyHz: 225_000_000) == .m125)
        #expect(Band.from(frequencyHz: 221_999_999) == nil && Band.from(frequencyHz: 225_000_001) == nil)
        #expect(Band.from(frequencyHz: 902_000_000) == .cm33 && Band.from(frequencyHz: 928_000_000) == .cm33)
        #expect(Band.from(frequencyHz: 901_999_999) == nil && Band.from(frequencyHz: 928_000_001) == nil)
        #expect(Band.from(adif: "1.25cm") == .cm125)
        Band.$javaV111Table.withValue(true) {
            #expect(Band.from(frequencyHz: 222_100_000) == nil)
            #expect(Band.from(adif: "33cm") == nil)
        }
    }

    /// In frequency order: between 2 m and 70 cm, and between 70 cm and 23 cm (band stepping, row order).
    @Test func bandsSitInFrequencyOrder() {
        let all = Band.allCases
        #expect(zip(all, all.dropFirst()).allSatisfy { $0.highHz < $1.lowHz })
        #expect(all.firstIndex(of: .m125) == (all.firstIndex(of: .m2) ?? 0) + 1)
        #expect(all.firstIndex(of: .cm33) == (all.firstIndex(of: .cm70) ?? 0) + 1)
    }

    @Test func cabrilloEdiAndMacroNames() throws {
        for row in Self.table {
            var q = Qso()
            q.freqHz = row.hz
            #expect(CabrilloExporter.frequency(q) == row.cabrillo, "\(row.adif)")
            #expect(EdiExporter.bandName(row.band) == row.edi)
            #expect(MacroFrequency.band(Int64(row.hz)) == row.mhz)
            #expect(BroadcastMapping.n1mmBandName(row.band) == row.mhz)
            #expect(BroadcastXml.n1mmBand(Int64(row.hz)) == row.mhz)
            #expect(ScoreCheck.band(row.cabrillo) == row.adif)
            var input = try CabrilloExporterTests.cqww([])
            input.category = CabrilloExporterTests.map(("BAND", row.adif.uppercased()))
            #expect(try CabrilloExporter.export(input).text.contains("CATEGORY-BAND: \(row.cabrillo)\n"), "\(row.adif)")
        }
    }

    @Test func adifRoundTrip() throws {
        for row in Self.table {
            var q = Qso()
            q.timestampUtc = ISO8601DateFormatter().date(from: "2026-06-13T18:00:00Z")
            q.call = "W1AW"
            q.freqHz = row.hz
            q.mode = .ssb
            let adif = AdifWriter().toAdif([q])
            #expect(adif.contains("<BAND:\(row.adif.utf8.count)>\(row.adif)"))
            let back = try #require(try AdifReader().read(adif).first)
            #expect(back.band == row.band)
            #expect(back.freqHz == row.hz)
        }
    }

    @Test func entryRowsAndTheSpotGroups() {
        #expect(BandRows.startKHz(band: .m125, column: .ph) == 222100.0)
        #expect(BandRows.startKHz(band: .cm33, column: .ph) == 902100.0)
        #expect(BandRows.startKHz(band: .m125, column: .ry) == nil)
        #expect(SpotFilter.Group.vhf.bands.contains(.m125))
        #expect(SpotFilter.Group.uhf.bands.contains(.cm33))
    }

    /// An N1MM UDC with points per band and a band factor in MHz maps both bands.
    @Test func udcImportKnowsTheBands() {
        let udc = """
            [Contest]
            Name=VHFTEST
            CabrilloName=VHF-TEST
            Mode=BOTH
            DupeType=3
            PointsPerContact = 1.25M, 2, 33CM, 3
            PointsMultByBand = 902, 2
            """
        let yaml: String = UdcImport.convert(UdcImport.parse(udc)) { _ in nil }.yaml
        #expect(yaml.contains("bandIn: [1.25m] }, value: { fixed: 2 }"), "\(yaml)")
        #expect(yaml.contains("bandIn: [33cm] }, value: { fixed: 3 }"), "\(yaml)")
        #expect(yaml.contains("bandIn: [33cm] }, factor: 2"), "\(yaml)")
    }

    // MARK: - sweeps over every band

    /// Every band has an entry row, sits in exactly one spot group and has unique names in every table that maps
    /// bands to text (a new band falling into a `default:` branch would collide or come out empty).
    @Test func everyBandHasDistinctNamesEverywhere() {
        let all = Band.allCases
        #expect(Set(BandRows.all.map(\.band)) == Set(all))
        #expect(BandRows.all.map(\.band) == all)
        let grouped: [Band] = SpotFilter.Group.allCases.flatMap(\.bands)
        #expect(grouped.count == all.count && Set(grouped) == Set(all))
        func distinct(_ names: [String], _ what: String) {
            #expect(Set(names).count == names.count, "\(what): \(names)")
            #expect(!names.contains(""), "\(what): \(names)")
        }
        distinct(all.map(\.javaName), "database")
        distinct(all.map(\.adif), "ADIF")
        distinct(all.map(EdiExporter.bandName), "EDI")
        distinct(all.map(BroadcastMapping.n1mmBandName), "score XML")
        distinct(all.map { MacroFrequency.band(Int64($0.lowHz)) }, "macro")
        distinct(all.map(MultGridExtras.header), "mult grid header")
        let vhfUp: [Band] = all.filter { $0.lowHz >= Band.m6.lowHz }
        let cabrillo: [String] = vhfUp.map { band -> String in
            var q = Qso()
            q.band = band
            return CabrilloExporter.frequency(q) ?? ""
        }
        distinct(cabrillo, "Cabrillo")
        // What the exporter writes, the score check reads back as the same band.
        for (band, text) in zip(vhfUp, cabrillo) {
            #expect(ScoreCheck.band(text) == band.adif, "\(text)")
        }
    }
}
