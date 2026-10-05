import Foundation
import Testing
@testable import MCLCore

/// Port of `PaperTimeTest.java` — QSO time from a paper log (see `PaperTime.swift`).
@Suite struct PaperTimeTests {

    private static let day: Date = {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 11
        comps.day = 28
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: comps)!
    }()

    private func instant(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text)!
    }

    // MARK: - `PaperTimeTest.timeOnlyUsesBaseDateOrPreviousQsoDate`

    @Test func timeOnlyUsesBaseDateOrPreviousQsoDate() {
        #expect(PaperTime.parse("1432", previous: nil, baseDate: Self.day) == instant("2026-11-28T14:32:00Z"))
        #expect(PaperTime.parse("9:05", previous: nil, baseDate: Self.day) == instant("2026-11-28T09:05:00Z"))
        #expect(
            PaperTime.parse("1000", previous: instant("2026-11-29T09:58:00Z"), baseDate: Self.day)
                == instant("2026-11-29T10:00:00Z")
        )
    }

    // MARK: - `PaperTimeTest.crossingMidnightMovesToNextDay`

    @Test func crossingMidnightMovesToNextDay() {
        #expect(
            PaperTime.parse("0005", previous: instant("2026-11-28T23:55:00Z"), baseDate: Self.day)
                == instant("2026-11-29T00:05:00Z")
        )
    }

    // MARK: - `PaperTimeTest.slightlyOutOfOrderStaysOnSameDay`

    @Test func slightlyOutOfOrderStaysOnSameDay() {
        // A paper log is often slightly out of order — a few minutes back is not a new day.
        #expect(
            PaperTime.parse("1425", previous: instant("2026-11-28T14:30:00Z"), baseDate: Self.day)
                == instant("2026-11-28T14:25:00Z")
        )
    }

    // MARK: - `PaperTimeTest.explicitDate`

    @Test func explicitDate() {
        #expect(
            PaperTime.parse("2026-11-29 0110", previous: instant("2026-11-28T14:30:00Z"), baseDate: Self.day)
                == instant("2026-11-29T01:10:00Z")
        )
    }

    // MARK: - `PaperTimeTest.invalid`

    @Test func invalid() {
        #expect(PaperTime.parse("2460", previous: nil, baseDate: Self.day) == nil)
        #expect(PaperTime.parse("12", previous: nil, baseDate: Self.day) == nil)
        #expect(PaperTime.parse("2026-02-30 1000", previous: nil, baseDate: Self.day) == nil)
        #expect(PaperTime.parse(nil, previous: nil, baseDate: Self.day) == nil)
    }
}
