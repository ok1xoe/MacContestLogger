import Foundation
import Testing
@testable import MCLCore

/// Port of the Java `SolarTerminatorTest` (4).
@Suite struct SolarTerminatorTests {

    /// Epoch ms of the instant `year-month-day hour:00:00Z`.
    private func millis(_ year: Int64, _ month: Int64, _ day: Int64, _ hour: Int64) -> Int64 {
        let epochDay: Int64 = JavaLocalDate.epochDay(year: year, month: month, day: day)
        return (epochDay * 86_400 + hour * 3_600) * 1_000
    }

    // Spring equinox 2024, noon UTC → the subsolar point near 0°N, 0°E.
    private func equinoxNoon() -> Int64 {
        millis(2024, 3, 20, 12)
    }

    @Test func subsolarNearEquatorAtEquinoxNoon() {
        let ss = SolarTerminator.subsolar(epochMillis: equinoxNoon())
        #expect(abs(ss.lat) < 3.0, "declination at the equinox ~0°")
        #expect(abs(ss.lon) < 5.0, "subsolar lon at noon UTC ~0°")
    }

    @Test func daySideAndNightSide() {
        let t: Int64 = equinoxNoon()
        // Noon UTC: 0°E is day, 180° is night.
        #expect(!SolarTerminator.isNight(0, 0, epochMillis: t), "0°E noon = day")
        #expect(SolarTerminator.isNight(0, 180, epochMillis: t), "180° = night")
    }

    @Test func polarNightInWinter() {
        // December: the north pole is in night (polar night).
        let dec: Int64 = millis(2024, 12, 21, 12)
        #expect(SolarTerminator.isNight(85, 0, epochMillis: dec), "north pole in winter = night")
        #expect(!SolarTerminator.isNight(-85, 0, epochMillis: dec), "south pole in winter = day")
    }

    @Test func acceptsInstant() {
        // Just so it does not crash for the current time.
        let now: Int64 = Int64((Date().timeIntervalSince1970 * 1_000).rounded(.down))
        _ = SolarTerminator.isNight(50, 14, epochMillis: now)
    }
}
