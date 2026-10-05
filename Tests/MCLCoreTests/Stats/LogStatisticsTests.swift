import Foundation
import Testing
@testable import MCLCore

/// Port of the Java `stats/LogStatisticsTest` (2 tests).
@Suite struct LogStatisticsTests {

    private static func qso(_ at: String, _ hz: Int, _ mode: Mode, _ cont: String) -> Qso {
        var q = Qso()
        q.timestampUtc = JavaInstant.parseIsoInstant(at)!.date
        q.call = "X"
        q.freqHz = hz
        q.mode = mode
        q.continent = cont
        return q
    }

    private let log: [Qso] = [
        qso("2026-11-28T12:05:00Z", 14_010_000, .cw, "EU"),
        qso("2026-11-28T12:40:00Z", 7_010_000, .cw, "EU"),
        qso("2026-11-28T13:10:00Z", 14_020_000, .cw, "NA"),
        qso("2026-11-28T13:20:00Z", 14_220_000, .ssb, "NA"),
    ]

    @Test func hourByBand() {
        let p = LogStatistics.pivot(log, .HOUR, .BAND)
        #expect(p.rows == ["11-28 12Z", "11-28 13Z"])
        #expect(p.cols == ["40m", "20m"], "bands by frequency")
        #expect(p.count("11-28 13Z", "20m") == 2)
        #expect(p.colTotal("20m") == 3)
        #expect(p.total == 4)
    }

    @Test func continentByModeSortedByCount() {
        var deleted = Self.qso("2026-11-28T14:00:00Z", 14_010_000, .cw, "AS")
        deleted.deleted = true
        let withDeleted: [Qso] = log + [deleted]
        let p = LogStatistics.pivot(withDeleted, .CONTINENT, .MODE)
        #expect(p.rows == ["EU", "NA"])
        #expect(p.cols == ["CW", "SSB"])
        #expect(LogStatistics.perHour(log) == JavaLinkedMap<Int>([("11-28 12Z", 2), ("11-28 13Z", 2)]))
    }
}
