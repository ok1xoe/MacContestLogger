import Foundation
import Testing
@testable import MCLCore

/// The Statistics window's dimensions beyond Java v1.1.1's (N1MM Statistics): minute rows, band and mode, station,
/// points, new multipliers, the contest's exchange fields and multipliers, and leaving out dupes and X-QSOs.
@Suite struct StatsPivotTests {

    private static func qso(_ id: Int64, _ call: String, minute: Int, band freq: Int = 14_025_000, mode: Mode = .cw,
                            station: String = "", xqso: Bool = false) -> Qso {
        var qso = Qso()
        qso.id = id
        qso.call = call
        qso.freqHz = freq
        qso.mode = mode
        qso.stationId = station
        qso.xqso = xqso
        qso.timestampUtc = Date(timeIntervalSince1970: 1_699_999_200 + TimeInterval(minute * 60))
        return qso
    }

    @Test func minuteRowsAreChronologicalBuckets() {
        let qsos = [Self.qso(1, "A", minute: 3), Self.qso(2, "B", minute: 7), Self.qso(3, "C", minute: 12),
                    Self.qso(4, "D", minute: 14)]
        let five = StatsPivot.pivot(qsos, rows: .minutes(5), columns: .base(.NONE))
        #expect(five.rows.map { String($0.suffix(5)) } == ["22:00", "22:05", "22:10"])
        #expect(five.rows.map { five.rowTotal($0) } == [1, 1, 2])
        let fifteen = StatsPivot.pivot(qsos, rows: .minutes(15), columns: .base(.NONE))
        #expect(fifteen.rows.count == 1)
        #expect(fifteen.total == 4)
    }

    @Test func bandAndModeSortByBandAndStationsByCount() {
        let qsos = [Self.qso(1, "A", minute: 1, band: 14_025_000, mode: .cw, station: "RUN"),
                    Self.qso(2, "B", minute: 2, band: 7_025_000, mode: .ssb, station: "MULT"),
                    Self.qso(3, "C", minute: 3, band: 7_025_000, mode: .cw, station: "MULT")]
        let pivot = StatsPivot.pivot(qsos, rows: .modeBand, columns: .station)
        #expect(pivot.rows.first?.hasPrefix("40") == true)
        #expect(pivot.rows.last?.hasPrefix("20") == true)
        #expect(pivot.cols == ["MULT", "RUN"])
    }

    @Test func contestFactsAndTheDupesSwitch() {
        let qsos = [Self.qso(1, "A", minute: 1), Self.qso(2, "A", minute: 2), Self.qso(3, "B", minute: 3, xqso: true),
                    Self.qso(4, "C", minute: 4)]
        let facts: [Int64: StatsFact] = [
            1: StatsFact(points: 3, dupe: false, newMultiplier: true, exchange: ["zone": "14"],
                         multipliers: ["zones": "14"]),
            2: StatsFact(points: 0, dupe: true, newMultiplier: false, exchange: ["zone": "14"],
                         multipliers: ["zones": "14"]),
            4: StatsFact(points: 1, dupe: false, newMultiplier: true, exchange: ["zone": "5"],
                         multipliers: ["zones": "5"]),
        ]
        let all = StatsPivot.pivot(qsos, rows: .points, columns: .newMultiplier, facts: facts)
        #expect(all.total == 4)
        #expect(all.rows == ["0", "1", "3", "?"], "numbers in order, an unknown last")
        let counted = StatsPivot.pivot(qsos, rows: .exchange("zone"), columns: .base(.NONE), facts: facts,
                                       includeDupes: false)
        #expect(counted.total == 2)
        #expect(counted.rows == ["5", "14"])
        let mults = StatsPivot.pivot(qsos, rows: .multiplier(id: "zones", label: "CQ zone"), columns: .base(.NONE),
                                     facts: facts, includeDupes: false)
        #expect(mults.rows.sorted() == ["14", "5"])
        #expect(StatsPivot.key(.newMultiplier, qsos[0], facts[1]) == "MULT")
        #expect(StatsPivot.key(.newMultiplier, qsos[1], facts[2]) == "—")
    }

    @Test func theFixedDimensionsKeepJavasPivot() {
        let qsos = [Self.qso(1, "A", minute: 1), Self.qso(2, "B", minute: 2, band: 7_025_000)]
        #expect(StatsPivot.pivot(qsos, rows: .base(.BAND), columns: .base(.MODE))
            == LogStatistics.pivot(qsos, .BAND, .MODE))
    }

    @Test func theTableAsTabSeparatedText() {
        let qsos = [Self.qso(1, "A", minute: 1), Self.qso(2, "B", minute: 2, band: 7_025_000)]
        let table = StatsViews.statisticsTable(pivot: LogStatistics.pivot(qsos, .BAND, .MODE), rowHeader: "Band")
        #expect(table.tabSeparated == "Band\tCW\tCelkem\n40m\t1\t1\n20m\t1\t1\nCelkem\t2\t2\n")
        #expect(table.count(row: 0, column: 0) == 1)
        #expect(table.count(row: 5, column: 0) == 0)
    }
}
