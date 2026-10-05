import Foundation
import Testing
@testable import MCLCore

/// Port of the Java `SolarTimesTest` (7). Times are seconds of the day in UTC (`LocalTime.toSecondOfDay`).
@Suite struct SolarTimesTests {

    /// Tolerance 5 minutes — enough for a row in the Info window, but it exposes an error in the algorithm.
    private func assertNear(_ expected: String, _ actual: Int32, sourceLocation: SourceLocation = #_sourceLocation) {
        let parts: [Substring] = expected.split(separator: ":")
        let hours: Int32 = Int32(parts[0])!
        let minutes: Int32 = Int32(parts[1])!
        let expectedSeconds: Int32 = hours * 3600 + minutes * 60
        let diff: Int32 = abs(expectedSeconds - actual)
        #expect(diff <= 300, "expected \(expected) ± 5 min, got \(actual) s", sourceLocation: sourceLocation)
    }

    private func day(_ year: Int64, _ month: Int64, _ dayOfMonth: Int64) -> Int64 {
        JavaLocalDate.epochDay(year: year, month: month, day: dayOfMonth)
    }

    @Test func pragueOnSummerSolstice() throws {
        // Prague 21 Jun: sunrise 04:52 CEST = 02:52Z, sunset 21:16 CEST = 19:16Z.
        let t = try #require(SolarTimes.forLocation(50.088, 14.420, epochDay: day(2026, 6, 21)))
        assertNear("02:52", t.sunrise)
        assertNear("19:16", t.sunset)
    }

    @Test func pragueOnWinterSolstice() throws {
        // 21 Dec: sunrise 08:00 CET = 07:00Z, sunset 16:01 CET = 15:01Z.
        let t = try #require(SolarTimes.forLocation(50.088, 14.420, epochDay: day(2026, 12, 21)))
        assertNear("07:00", t.sunrise)
        assertNear("15:01", t.sunset)
    }

    @Test func equatorOnEquinoxIsRoughlySixToSix() throws {
        let t = try #require(SolarTimes.forLocation(0.0, 0.0, epochDay: day(2026, 3, 20)))
        assertNear("06:04", t.sunrise)
        assertNear("18:11", t.sunset)
    }

    @Test func southernHemisphereHasOppositeSeasons() throws {
        // Sydney 21 Jun is winter: sunrise 07:00 AEST, sunset 16:54 AEST (UTC+10).
        // In UTC the sunrise therefore falls on 21:00 of the previous day — times are without a date,
        // so the sunrise "follows" the sunset. The Info window shows them that way too.
        let t = try #require(SolarTimes.forLocation(-33.87, 151.21, epochDay: day(2026, 6, 21)))
        assertNear("21:00", t.sunrise)
        assertNear("06:54", t.sunset)
    }

    @Test func polarDayHasNoSunriseOrSunset() {
        // Longyearbyen in June — the sun does not set.
        #expect(SolarTimes.forLocation(78.22, 15.65, epochDay: day(2026, 6, 21)) == nil)
    }

    @Test func polarNightHasNoSunriseOrSunset() {
        #expect(SolarTimes.forLocation(78.22, 15.65, epochDay: day(2026, 12, 21)) == nil)
    }

    @Test func unknownCoordinatesGiveNothing() {
        #expect(SolarTimes.forLocation(Double.nan, 14.4, epochDay: day(2026, 6, 21)) == nil)
    }
}
