import Foundation
import Testing
@testable import MCLCore

/// Post-port microwave bands in the log formats (a deliberate divergence from Java v1.1.1): ADIF `BAND`, Cabrillo 3.0 band
/// designators, REG1TEST `PBand`.
@Suite struct MicrowaveFormatsTests {

    // MARK: - ADIF

    @Test func adifRoundTripOfAQo100DownlinkQso() throws {
        var q = Qso()
        q.timestampUtc = ISO8601DateFormatter().date(from: "2026-06-17T12:00:00Z")
        q.call = "DL1ABC"
        q.freqHz = 10_489_750_000
        q.mode = .ssb
        let adif = AdifWriter().toAdif([q])
        #expect(adif.contains("<BAND:3>3cm"))
        #expect(adif.contains("<FREQ:12>10489.750000"))
        let back = try #require(try AdifReader().read(adif).first)
        #expect(back.band == .cm3)
        #expect(back.freqHz == 10_489_750_000)
    }

    @Test func adifImportWithoutFreqTakesTheBandFromBandField() throws {
        let adif = "<CALL:6>OK1ABC <BAND:4>13cm <MODE:2>CW <QSO_DATE:8>20260617 <TIME_ON:4>1200 <EOR>"
        let q = try #require(try AdifReader().read(adif).first)
        #expect(q.band == .cm13)
    }

    // MARK: - Cabrillo

    @Test func cabrilloFrequencyIsTheBandDesignator() {
        let table: [(Band, String)] = [(.cm23, "1.2G"), (.cm13, "2.3G"), (.cm9, "3.4G"), (.cm6, "5.7G"),
                                       (.cm3, "10G"), (.cm70, "432"), (.m2, "144")]
        for (band, text) in table {
            var q = Qso()
            q.freqHz = band.lowHz + 1_000
            #expect(CabrilloExporter.frequency(q) == text, "\(band)")
        }
    }

    @Test func cabrilloQsoLinesCarryTheDesignators() throws {
        let qsos: [Qso] = [
            CabrilloExporterTests.qso("2026-03-28T10:00:00Z", "OK2A", 1_296_200_000, .ssb, "59", 7, "59 12"),
            CabrilloExporterTests.qso("2026-03-28T10:01:00Z", "OK2B", 10_368_100_000, .ssb, "59", 8, "59 3"),
        ]
        let lines = CabrilloExporterTests.qsoLines(try CabrilloExporter.export(try CabrilloExporterTests.cqwwSsb(qsos)).text)
        #expect(lines[0].hasPrefix("QSO: 1.2G PH 2026-03-28 1000 OK1XOE"))
        #expect(lines[1].hasPrefix("QSO:  10G PH 2026-03-28 1001 OK1XOE"))
    }

    @Test func cabrilloCategoryBandDesignators() throws {
        let expected: [(String, String)] = [("23CM", "1.2G"), ("13CM", "2.3G"), ("9CM", "3.4G"), ("6CM", "5.7G"),
                                            ("3CM", "10G")]
        for (value, designator) in expected {
            var input = try CabrilloExporterTests.cqww([])
            input.category = CabrilloExporterTests.map(("BAND", value))
            #expect(try CabrilloExporter.export(input).text.contains("CATEGORY-BAND: \(designator)\n"), "\(value)")
        }
    }

    /// Importing a Cabrillo log keeps the Java behaviour (known issue CR2): the designator is not a frequency.
    @Test func cabrilloReaderStillIgnoresTheDesignator() throws {
        let log = """
            START-OF-LOG: 3.0
            QSO: 1.2G PH 2026-03-28 1000 OK1XOE 59 7 OK2A 59 12
            END-OF-LOG:

            """
        let qsos = try CabrilloReader().read(log)
        let q = try #require(qsos.first)
        #expect(q.freqHz == 0)
        #expect(q.band == nil)
    }

    // MARK: - EDI

    @Test func ediBandNames() {
        let names: [(Band, String)] = [(.cm23, "1,3 GHz"), (.cm13, "2,3 GHz"), (.cm9, "3,4 GHz"),
                                       (.cm6, "5,7 GHz"), (.cm3, "10 GHz")]
        for (band, name) in names {
            #expect(EdiExporter.bandName(band) == name, "\(band)")
        }
    }

    @Test func ediWritesOneFilePerBandSortedByFrequency() throws {
        let def = try ExportsFixture.iaruVhf()
        let fields: (String) -> [ContestDefinition.ExchangeField] = { _ in ExportsFixture.received(def) }
        var station = StationConfig()
        station.call = "OK1XOE"
        station.gridSquare = "JO70FC"
        var log: [Qso] = []
        for (minute, hz) in [(0, 1_296_200_000), (1, 432_100_000), (2, 10_368_100_000)] {
            var q = ExportsFixture.edi(minute, "OK1AAA", .ssb, "59 1 JN79AA", minute + 1)
            q.freqHz = hz
            log.append(q)
        }
        let result = ExportJobs.edi(definition: def, station: station, setup: nil, qsos: log, fields: fields)
        guard case .success(let files) = result else { Issue.record("EDI export failed"); return }
        #expect(files.map(\.name) == ["OK1XOE_70cm.edi", "OK1XOE_23cm.edi", "OK1XOE_3cm.edi"])
        let text23 = String(decoding: files[1].bytes, as: UTF8.self)
        #expect(text23.contains("PBand=1,3 GHz"))
        #expect(String(decoding: files[2].bytes, as: UTF8.self).contains("PBand=10 GHz"))
    }
}
