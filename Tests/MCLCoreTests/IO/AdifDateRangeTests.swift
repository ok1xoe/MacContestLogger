import Foundation
import Testing
@testable import MCLCore

@Suite struct AdifDateRangeTests {

    private static func utc(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0, _ s: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min, second: s))!
    }

    private static func qso(_ time: Date?) -> Qso {
        var q = Qso()
        q.timestampUtc = time
        q.call = "OK1ABC"
        return q
    }

    @Test func wholeUtcDaysAreIncludedAtBothEnds() throws {
        let range = try #require(AdifDateRange(firstDay: Self.utc(2026, 11, 28, 18, 30), lastDay: Self.utc(2026, 11, 29, 3)))
        #expect(range.start == Self.utc(2026, 11, 28))
        #expect(range.endExclusive == Self.utc(2026, 11, 30))
        let inside = [Self.qso(Self.utc(2026, 11, 28, 0, 0, 0)), Self.qso(Self.utc(2026, 11, 29, 23, 59, 59))]
        let outside = [Self.qso(Self.utc(2026, 11, 27, 23, 59, 59)), Self.qso(Self.utc(2026, 11, 30, 0, 0, 0)),
                       Self.qso(nil)]
        #expect(range.filter(inside + outside) == inside)
    }

    @Test func aSingleDayAndAReversedRange() throws {
        let day = try #require(AdifDateRange(firstDay: Self.utc(2026, 1, 5, 12), lastDay: Self.utc(2026, 1, 5, 1)))
        #expect(day.endExclusive == Self.utc(2026, 1, 6))
        #expect(AdifDateRange(firstDay: Self.utc(2026, 1, 6), lastDay: Self.utc(2026, 1, 5)) == nil)
    }

    @Test func fileNames() throws {
        let one = try #require(AdifDateRange(firstDay: Self.utc(2026, 11, 28), lastDay: Self.utc(2026, 11, 28)))
        let two = try #require(AdifDateRange(firstDay: Self.utc(2026, 11, 28), lastDay: Self.utc(2026, 12, 2)))
        #expect(one.fileName() == "maccontestlogger-2026-11-28.adi")
        #expect(two.fileName() == "maccontestlogger-2026-11-28-2026-12-02.adi")
        #expect(AdifDateRange.dayText(Self.utc(2026, 3, 9, 23)) == "2026-03-09")
    }
}
