import Foundation
import Testing
@testable import MCLCore

/// Port of the Java `io/CabrilloReaderTest` (3 tests) + unit guards of edges that
/// the `io-edge-java.tsv` table covers only indirectly. Full match with Java over the edge files
/// and over the sample is in `CabrilloJavaParityTests`.
@Suite struct CabrilloReaderTests {

    /// Java `parsesStandardQsoLine`.
    @Test func parsesStandardQsoLine() throws {
        let log = """
            START-OF-LOG: 3.0
            CALLSIGN: OK1XOE
            QSO: 14042 CW 2026-06-17 1200 OK1XOE 599 14 DL1ABC 599 05
            END-OF-LOG:

            """
        let qsos = try CabrilloReader().read(log)
        #expect(qsos.count == 1)
        let q = try #require(qsos.first)
        #expect(q.call == "DL1ABC")          // the other station = the 2nd callsign
        #expect(q.freqHz == 14_042_000)
        #expect(q.band == .m20)
        #expect(q.mode == .cw)
        #expect(q.rstRcvd == "599")
        #expect(q.exchangeRcvd == "05")
        #expect(q.serialRcvd == 5)
    }

    /// Java `ignoresNonQsoLines`.
    @Test func ignoresNonQsoLines() throws {
        #expect(try CabrilloReader().read("START-OF-LOG: 3.0\nSOAPBOX: ahoj\n").isEmpty)
    }

    /// Java `xQsoLinesAreReadAndMarked`.
    @Test func xQsoLinesAreReadAndMarked() throws {
        // An own export may contain X-QSO rows; they must not be lost on import.
        let log = """
            START-OF-LOG: 3.0
            QSO:  14025 CW 2026-11-28 0001 OK1XOE 599 15 DL1ABC 599 14
            X-QSO: 14025 CW 2026-11-28 0002 OK1XOE 599 15 K1A    599 5
            END-OF-LOG:

            """
        let qsos = try CabrilloReader().read(log)

        #expect(qsos.count == 2)
        #expect(qsos[0].xqso == false)
        #expect(qsos[1].call == "K1A")
        #expect(qsos[1].xqso == true)
    }

    // MARK: - edge guards (measured:.3 and the `ProbeIoEdge` probe)

    /// An `int` overflow in the exchange brings down the whole import with a Java `NumberFormatException` (CR8).
    @Test func serialOverflowThrowsNumberFormatException() {
        let line = "QSO: 14025 CW 2026-11-28 0001 OK1XOE 599 15 DL1ABC 599 99999999999"
        #expect(throws: CabrilloReaderError.numberFormat(message: "For input string: \"99999999999\"")) {
            try CabrilloReader().read(line)
        }
    }

    /// A lone `\r` does not end a line, but `\s` takes it when splitting into tokens (CR10).
    @Test func loneCarriageReturnIsNotALineBreak() throws {
        let log = "QSO: 14025 CW 2026-11-28 0001 OK1XOE 599 15 DL1ABC 599 14\r"
            + "QSO: 14025 CW 2026-11-28 0002 OK1XOE 599 15 DL1ABD 599 14\n"
        let qsos = try CabrilloReader().read(log)
        #expect(qsos.count == 1)
        #expect(qsos.first?.exchangeRcvd == "14 QSO: 14025 CW 2026-11-28 0002 OK1XOE 599 15 DL1ABD 599 14")
        #expect(qsos.first?.serialRcvd == nil)
    }

    /// Java `toUpperCase()` turns `ſ` (U+017F) into `S`, so `qſo:` is a QSO row.
    @Test func longSIsUppercasedToS() throws {
        let qsos = try CabrilloReader().read("q\u{017F}o: 14025 CW 2026-11-28 0001 OK1XOE 599 15 DL1ABC 599 14")
        #expect(qsos.count == 1)
        #expect(qsos.first?.call == "DL1ABC")
    }

    /// SMART resolution of `LocalDate.parse` (30 Feb → 28 Feb) and strict field widths of `yyyy-MM-dd`.
    @Test func dateParsingFollowsJavaSmartResolver() {
        let feb28 = CabrilloReader.parseInstant("2026-02-30", "1200")
        #expect(feb28.map { Int64($0.timeIntervalSince1970) } == 1_772_280_000)
        #expect(CabrilloReader.parseInstant("2026-2-3", "1200") == nil)
        #expect(CabrilloReader.parseInstant("0000-01-01", "1200") == nil)
        #expect(CabrilloReader.parseInstant("+2026-11-28", "1200") == nil)
        // Java takes a `+` with more than four year digits, without the `+` it does not.
        #expect(CabrilloReader.parseInstant("+02026-11-28", "0001") != nil)
        #expect(CabrilloReader.parseInstant("02026-11-28", "0001") == nil)
        #expect(CabrilloReader.parseInstant("2026-11-28", "1:00").map { Int64($0.timeIntervalSince1970) }
                == 1_795_860_000)
    }

    /// Measured on JDK 21.0.2 (`QSO: 14025 CW <date> 0001 …`, epoch seconds; `nil` = Java null).
    /// Re-measurable: the same rows are the hand-made cases of the read arm of `JavaIoParityTests`
    /// (maintainer-only probe, `MANUAL`) — except `+999999999-12-31` below (`Date` is `Double`).
    private static let measuredDateCases: [(String, Int64?)] = [
        ("+02026-11-28", 1_795_824_060),
        ("02026-11-28", nil),
        ("-2026-11-28", nil),
        ("-02026-11-28", nil),
        ("+0000002026-11-28", 1_795_824_060),
        ("+1000000000-01-01", nil),
        ("2026-00-10", nil),
        ("2026-13-10", nil),
        ("2026-11-00", nil),
        ("2026-11-32", nil),
        ("2025-02-29", 1_740_700_860),
        ("2026-06-31", 1_782_777_660),
    ]

    @Test(arguments: measuredDateCases)
    func measuredDates(_ date: String, _ seconds: Int64?) {
        let instant = CabrilloReader.parseInstant(date, "0001")
        #expect(instant.map { Int64($0.timeIntervalSince1970) } == seconds)
    }

    /// The furthest year Java accepts (`+999999999-12-31` → 31,556,889,832,694,460 s). `Date`
    /// is `Double`, so it holds such a distant instant only approximately — it is enough that it is not `nil`.
    @Test func farthestYearIsAccepted() {
        #expect(CabrilloReader.parseInstant("+999999999-12-31", "0001") != nil)
    }
}
