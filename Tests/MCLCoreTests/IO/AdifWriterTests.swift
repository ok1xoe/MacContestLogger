import Foundation
import Testing
@testable import MCLCore

/// Port of `AdifWriterTest.java` (4 tests) + measured edge cases of `AdifWriter` (measured on
/// Java v1.1.1). The expected texts of the AW* cases are verbatim the probe output
/// a maintainer-only probe (`out.tsv`, Java v1.1.1 / JDK 21,
/// `en_US`) over the **same inputs** — the IDs in comments are rows of `out.tsv`.
@Suite struct AdifWriterTests {

    private static func at(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text)!
    }

    // MARK: - `AdifWriterTest.producesHeaderAndRecordWithCorrectFieldLengths`

    @Test func producesHeaderAndRecordWithCorrectFieldLengths() {
        var q = Qso()
        q.timestampUtc = Self.at("2026-06-17T12:00:00Z")
        q.call = "DL1ABC"
        q.freqHz = 14_074_000
        q.mode = .ssb
        q.rstSent = "59"
        q.rstRcvd = "59"
        q.serialSent = 1
        q.serialRcvd = 42

        let adif = AdifWriter().toAdif([q])

        #expect(adif.contains("<EOH>"), "end of header missing")
        #expect(adif.contains("<EOR>"), "end of record missing")
        #expect(adif.contains("<CALL:6>DL1ABC"), "wrong CALL field: \(adif)")
        #expect(adif.contains("<QSO_DATE:8>20260617"), "wrong date")
        #expect(adif.contains("<TIME_ON:6>120000"), "wrong time")
        #expect(adif.contains("<BAND:3>20m"), "wrong band")
        #expect(adif.contains("<MODE:3>SSB"), "wrong mode")
        #expect(adif.contains("<SRX:2>42"), "wrong received number")
    }

    // MARK: - `AdifWriterTest.headerContainsStationData`

    @Test func headerContainsStationData() throws {
        var q = Qso()
        q.call = "DL1ABC"
        q.freqHz = 14_074_000

        let station = Station(call: "OK1XOE", operator: "OK1ABC", gridSquare: "JO70", name: "Tomas")
        let adif = AdifWriter().toAdif([q], station: station)

        #expect(adif.contains("<STATION_CALLSIGN:6>OK1XOE"), "STATION_CALLSIGN missing: \(adif)")
        #expect(adif.contains("<OPERATOR:6>OK1ABC"), "OPERATOR missing in the header")
        #expect(adif.contains("<MY_GRIDSQUARE:4>JO70"), "MY_GRIDSQUARE missing")
        #expect(adif.contains("<MY_NAME:5>Tomas"), "MY_NAME missing")
        let station0 = try #require(adif.range(of: "STATION_CALLSIGN"))
        let eoh = try #require(adif.range(of: "<EOH>"))
        #expect(station0.lowerBound < eoh.lowerBound, "station data must be in the header")
    }

    // MARK: - `AdifWriterTest.contestFieldsAndExchangeStrings`

    @Test func contestFieldsAndExchangeStrings() {
        var q = Qso()
        q.timestampUtc = Self.at("2026-11-28T12:00:00Z")
        q.call = "W1AW"
        q.freqHz = 14_025_000
        q.mode = .cw
        q.exchangeSent = "599 15"
        q.exchangeRcvd = "599 5 "
        q.dxccEntity = 291
        q.dxccName = "United States"
        q.continent = "NA"
        q.runMode = .run
        let adif = AdifWriter(contestId: "CQ-WW-CW").toAdif([q])
        #expect(adif.contains("<CONTEST_ID:8>CQ-WW-CW"), "\(adif)")
        #expect(adif.contains("<STX_STRING:6>599 15"), "\(adif)")
        #expect(adif.contains("<SRX_STRING:5>599 5"), "\(adif)")
        #expect(adif.contains("<DXCC:3>291"), "\(adif)")
        #expect(adif.contains("<CONT:2>NA"), "\(adif)")
        #expect(adif.contains("<APP_N1MM_RUNNING:1>Y"), "\(adif)")
        #expect(!AdifWriter().toAdif([q]).contains("CONTEST_ID"))
    }

    // MARK: - `AdifWriterTest.exchangeStringsRoundTripThroughReader`

    @Test func exchangeStringsRoundTripThroughReader() throws {
        var q = Qso()
        q.timestampUtc = Self.at("2026-11-28T12:00:00Z")
        q.call = "W1AW"
        q.freqHz = 14_025_000
        q.mode = .cw
        q.rstRcvd = "599"
        q.exchangeRcvd = "599 5"
        let adif = AdifWriter(contestId: "CQ-WW-CW").toAdif([q])
        let back = try #require(try AdifReader().read(adif).first)
        #expect(back.exchangeRcvd == "5")
        #expect(back.rstRcvd == "599")
    }

    // MARK: - Measured on Java (`adif-writer/out.tsv`, IDs AW*)

    /// AW1: field length = UTF-16 units (emoji 2, decomposed `e` + U+0301 2 — 9 graphemes,
    /// 11 units), seconds are truncated, callsign without conversion to ASCII.
    @Test func nonAsciiLengthsAreUtf16Units() {
        var q = Qso()
        q.timestampUtc = Date(timeIntervalSince1970: 1_781_654_459.999)
        q.call = "ok1\u{017E}\u{00E1}"
        q.freqHz = 14_025_500
        q.mode = .cw
        q.rstSent = "599"
        q.operator = "OK1XOE"
        q.comment = "Tom\u{00E1}\u{0161} \u{1F600} e\u{0301}"
        q.runMode = .searchAndPounce
        let expected = "<QSO_DATE:8>20260617 <TIME_ON:6>000059 <CALL:5>OK1\u{017D}\u{00C1} <BAND:3>20m "
            + "<FREQ:9>14.025500 <MODE:2>CW <RST_SENT:3>599 <APP_N1MM_RUNNING:1>N <OPERATOR:6>OK1XOE "
            + "<COMMENT:11>Tom\u{00E1}\u{0161} \u{1F600} e\u{0301} <EOR>\n"
        #expect(AdifWriter().record(q) == expected)
    }

    /// AW2: without time, frequency 0 is always written; AW8-blank/AW8-null: a blank `contestId` = no contest.
    @Test func minimalRecordAndBlankContest() {
        var q = Qso()
        q.call = "W1AW"
        let expected = "<CALL:4>W1AW <FREQ:8>0.000000 <APP_N1MM_RUNNING:1>Y <EOR>\n"
        #expect(AdifWriter().record(q) == expected)
        #expect(AdifWriter(contestId: "  ").record(q) == expected)
        #expect(AdifWriter(contestId: nil).record(q) == expected)
    }

    /// AW4, AW5b: `%.6f` of large (above the 3 cm band, so no band) and negative frequencies (the band stays from
    /// the earlier frequency).
    @Test func frequencyFormatting() {
        var q = Qso()
        q.call = "W1AW"
        q.freqHz = 12_000_000_123
        #expect(AdifWriter().record(q) == "<CALL:4>W1AW <FREQ:12>12000.000123 <APP_N1MM_RUNNING:1>Y <EOR>\n")
        q.freqHz = 7_000_000
        q.freqHz = -5
        #expect(AdifWriter().record(q) == "<CALL:4>W1AW <BAND:3>40m <FREQ:9>-0.000005 <APP_N1MM_RUNNING:1>Y <EOR>\n")
    }

    /// AW7: empty station fields are omitted in the header; AW6 without a station.
    @Test func headerSkipsEmptyStationFields() {
        let station = Station(call: "OK1XOE", operator: "", gridSquare: "", name: "Tom\u{00E1}\u{0161}")
        let expected = "ADIF export z MacContestLogger\n<ADIF_VER:5>3.1.4 <PROGRAMID:16>MacContestLogger "
            + "<STATION_CALLSIGN:6>OK1XOE <MY_NAME:5>Tom\u{00E1}\u{0161} <EOH>\n"
        #expect(AdifWriter().toAdif([], station: station) == expected)
        let bare = "ADIF export z MacContestLogger\n<ADIF_VER:5>3.1.4 <PROGRAMID:16>MacContestLogger <EOH>\n"
        #expect(AdifWriter().toAdif([]) == bare)
    }

    /// AW9: exchanges by Java `trim()` (a tab inside stays), an empty `COUNTRY` omitted.
    @Test func exchangeTrimAndEmptyCountry() {
        var q = Qso()
        q.call = "W1AW"
        q.exchangeSent = " 59 15 "
        q.exchangeRcvd = "59\t5"
        q.dxccName = ""
        q.dxccEntity = 291
        q.continent = "NA"
        let expected = "<CALL:4>W1AW <FREQ:8>0.000000 <STX_STRING:5>59 15 <SRX_STRING:4>59\t5 "
            + "<CONTEST_ID:9>CQ-WW-SSB <DXCC:3>291 <CONT:2>NA <APP_N1MM_RUNNING:1>Y <EOR>\n"
        #expect(AdifWriter(contestId: "CQ-WW-SSB").record(q) == expected)
    }

    /// AW10–13: `yyyyMMdd` (year of era, `+` over 4 digits) and `HHmmss` from an instant truncated down.
    @Test func dateEdges() {
        let cases: [(Date, String)] = [
            // 0999-01-01T00:00:00Z proleptic Gregorian (`ISO8601DateFormatter` would count Julian)
            (Date(timeIntervalSince1970: -30_641_760_000), "<QSO_DATE:8>09990101 <TIME_ON:6>000000 "),
            (Date(timeIntervalSince1970: 253_402_300_800), "<QSO_DATE:10>+100000101 <TIME_ON:6>000000 "),
        // -0001-12-31T23:59:59Z: year −1 = 2 BC → year of era 2
            (Date(timeIntervalSince1970: -62_167_219_201), "<QSO_DATE:8>00021231 <TIME_ON:6>235959 "),
            (Date(timeIntervalSince1970: -0.5), "<QSO_DATE:8>19691231 <TIME_ON:6>235959 "),
        ]
        for (date, prefix) in cases {
            var q = Qso()
            q.call = "W1AW"
            q.timestampUtc = date
            let expected = prefix + "<CALL:4>W1AW <FREQ:8>0.000000 <APP_N1MM_RUNNING:1>Y <EOR>\n"
            #expect(AdifWriter().record(q) == expected)
        }
    }

    /// AW14: values are not sanitised; the number 0 and negative; 50 Hz (`%.6f` exactly).
    @Test func valuesAreNotSanitized() {
        var q = Qso()
        q.call = "W1AW"
        q.freqHz = 14_025_050
        q.serialSent = 0
        q.serialRcvd = -3
        q.comment = "a<b>c\nd"
        let expected = "<CALL:4>W1AW <BAND:3>20m <FREQ:9>14.025050 <STX:1>0 <SRX:2>-3 "
            + "<APP_N1MM_RUNNING:1>Y <COMMENT:7>a<b>c\nd <EOR>\n"
        #expect(AdifWriter().record(q) == expected)
    }

    /// `writeToFile`: UTF-8 without BOM, content = `toAdif`; a write error → `UncheckedIOError`.
    @Test func writeToFile() throws {
        var q = Qso()
        q.call = "OK1\u{017D}"
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("adif-writer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("log.adi")
        let station = Station(call: "OK1XOE")
        try AdifWriter().writeToFile([q], station: station, to: file)
        #expect(try Data(contentsOf: file) == Data(AdifWriter().toAdif([q], station: station).utf8))

        let missing = dir.appendingPathComponent("chybi/log.adi")
        let error = try #require(throws: UncheckedIOError.self) {
            try AdifWriter().writeToFile([q], to: missing)
        }
        #expect(error.message == "Nelze zapsat ADIF: " + missing.path)
    }
}
