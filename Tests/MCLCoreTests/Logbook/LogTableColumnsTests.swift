import Foundation
import Testing
@testable import MCLCore

/// `LogTableColumns` against the private column model of the Kotlin `ui/LogTable.kt` (v1.1.1), read via
/// reflection (maintainer-only probe, rows `COL`, `SORT`, `CELL`).
@Suite struct LogTableColumnsTests {

    private typealias Column = LogTableColumns.Column

    /// The Kotlin columns (the Swift-only multi-op columns Op and Stn follow them).
    private static let kotlin: [Column] = Column.allCases.filter { !LogTableColumns.multiOpColumns.contains($0) }

    @Test func columnsMatchKotlin() {
        #expect(Column.allCases.suffix(2) == [.op, .station])
        #expect(Column.allCases.suffix(2).map(\.title) == ["Op", "Stn"])
        let titles: [String] = Self.kotlin.map(\.title)
        #expect(titles == [
            "Čas UTC", "Volačka", "Pásmo", "Mód", "RST tx", "RST rx", "Nr tx", "Nr rx",
            "Exchange", "Pozn.", "X", "⚠", "Body", "Mult",
        ])
        let weights: [Double] = Self.kotlin.map(\.weight)
        #expect(weights == [2.0, 1.3, 0.9, 0.9, 0.8, 0.8, 0.7, 0.7, 1.6, 1.4, 0.35, 0.35, 0.5, 1.0])
        #expect(Self.kotlin.map(\.rawValue) == Array(0..<14))
    }

    @Test func sortKeysMatchKotlin() {
        let keys: [QsoSort.Key] = Self.kotlin.map { LogTableColumns.sortKey(for: $0) }
        #expect(keys == [
            .time, .call, .band, .mode, .rstSent, .rstRcvd, .serialSent, .serialRcvd, .exchange, .note,
            .note, .note, .note, .note,
        ])
    }

    @Test func visibility() {
        let all = LogTableColumns.visible(usesSerial: true, usesExchangeBeyondRst: true, contestActive: true)
        #expect(all == Self.kotlin)
        let free = LogTableColumns.visible(usesSerial: false, usesExchangeBeyondRst: false, contestActive: false)
        #expect(free == [.time, .call, .band, .mode, .rstSent, .rstRcvd, .note, .xqso, .warning])
        let cqww = LogTableColumns.visible(usesSerial: false, usesExchangeBeyondRst: true, contestActive: true)
        #expect(cqww == [.time, .call, .band, .mode, .rstSent, .rstRcvd, .exchange, .note, .xqso, .warning, .points, .mult])
        let serialOnly = LogTableColumns.visible(usesSerial: true, usesExchangeBeyondRst: false, contestActive: false)
        #expect(serialOnly.contains(.serialSent) && serialOnly.contains(.serialRcvd) && !serialOnly.contains(.exchange))
    }

    @Test func hiddenSortColumnFallsBackToTime() {
        let free = LogTableColumns.visible(usesSerial: false, usesExchangeBeyondRst: false, contestActive: false)
        #expect(LogTableColumns.effectiveSort(.serialRcvd, visible: free) == .time)
        #expect(LogTableColumns.effectiveSort(.points, visible: free) == .time)
        #expect(LogTableColumns.effectiveSort(.call, visible: free) == .call)
    }

    private static func qso(_ iso: String?) throws -> Qso {
        var q = Qso()
        if let iso {
            let instant = try #require(JavaInstant.parseIsoInstant(iso))
            q.timestampUtc = instant.date
        }
        q.call = "ok1abc/p"
        q.freqHz = 14_025_000
        q.mode = .cw
        q.rstSent = "599"
        q.rstRcvd = "579"
        q.serialSent = 7
        q.serialRcvd = nil
        q.exchangeRcvd = "15"
        q.comment = "note"
        q.xqso = iso?.hasPrefix("2026") ?? false
        return q
    }

    /// (instant, `cellValue` col 0, `fullTimestamp`) measured; the remaining cells are the same for every row.
    private static let measuredTimes: [(String?, String, String)] = [
        (nil, "", ""),
        ("2026-10-02T12:34:56Z", "10-02 12:34:56", "2026-10-02 12:34:56"),
        ("2026-10-02T12:34:56.999Z", "10-02 12:34:56", "2026-10-02 12:34:56"),
        ("1969-12-31T23:59:59.500Z", "12-31 23:59:59", "1969-12-31 23:59:59"),
        ("+12026-01-05T00:00:00Z", "01-05 00:00:00", "+12026-01-05 00:00:00"),
        ("1500-03-01T01:02:03Z", "03-01 01:02:03", "1500-03-01 01:02:03"),
        ("0000-06-15T10:00:00Z", "06-15 10:00:00", "0001-06-15 10:00:00"),
        ("-0001-12-31T23:59:59Z", "12-31 23:59:59", "0002-12-31 23:59:59"),
        ("2024-02-29T23:59:59Z", "02-29 23:59:59", "2024-02-29 23:59:59"),
        ("1970-01-01T00:00:00Z", "01-01 00:00:00", "1970-01-01 00:00:00"),
    ]

    @Test func cellTextsMatchKotlin() throws {
        for (iso, time, full) in Self.measuredTimes {
            let q = try Self.qso(iso)
            let cells: [String] = Self.kotlin.map { LogTableColumns.cellText(q, column: $0, marks: nil) }
            let xqso: String = (iso?.hasPrefix("2026") ?? false) ? "X" : ""
            #expect(cells == [time, "OK1ABC/P", "20m", "CW", "599", "579", "7", "", "15", "note", xqso, "", "", ""],
                    "\(String(describing: iso))")
            #expect(LogTableColumns.timeText(q.timestampUtc) == time)
            #expect(LogTableColumns.editTimeText(q.timestampUtc) == full)
        }
        let empty: [String] = Column.allCases.map { LogTableColumns.cellText(Qso(), column: $0, marks: nil) }
        #expect(empty == Array(repeating: "", count: 16))
        var multi = Qso()
        multi.operator = "OK1XOE"
        multi.stationId = "OP2"
        #expect(LogTableColumns.cellText(multi, column: .op, marks: nil) == "OK1XOE")
        #expect(LogTableColumns.cellText(multi, column: .station, marks: nil) == "OP2")
    }

    /// The `date:` search and the edit text share one formatter (`QsoSearch.timestamp`).
    @Test func searchUsesTheEditTimeText() throws {
        for (iso, _, full) in Self.measuredTimes {
            let q = try Self.qso(iso)
            #expect(QsoSearch.timestamp(q) == (iso == nil ? nil : full))
        }
        let q = try Self.qso("+12026-01-05T00:00:00Z")
        #expect(QsoSearch.matches(q, "date:+12026-01-05"))
        #expect(!QsoSearch.matches(try Self.qso("0000-06-15T10:00:00Z"), "date:0000-06"))
        #expect(QsoSearch.matches(try Self.qso("0000-06-15T10:00:00Z"), "date:0001-06"))
    }

    /// Kotlin `LogRow`: points `"<n>"` or `"<n> D"` (dupe), multiplier `multText`.
    @Test func pointsAndMultiplierFromMarks() throws {
        let q = try Self.qso("2026-10-02T12:34:56Z")
        let mult = QsoMarks.Mark(points: 3, dupe: false, newMults: ["14", "DL"])
        #expect(LogTableColumns.cellText(q, column: .points, marks: mult) == "3")
        #expect(LogTableColumns.cellText(q, column: .mult, marks: mult) == "14 DL")
        let dupe = QsoMarks.Mark(points: 0, dupe: true, newMults: [])
        #expect(LogTableColumns.cellText(q, column: .points, marks: dupe) == "0 D")
        #expect(LogTableColumns.cellText(q, column: .mult, marks: dupe) == "")
        let negative = QsoMarks.Mark(points: -2, dupe: true, newMults: [])
        #expect(LogTableColumns.pointsText(negative) == "-2 D")
        #expect(LogTableColumns.cellText(q, column: .warning, marks: mult) == "")
    }
}
