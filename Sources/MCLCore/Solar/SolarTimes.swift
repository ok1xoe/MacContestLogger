import Foundation

/// Sunrise and sunset for the given coordinates and day, both in UTC — the
/// `Sunrise:06:29Z Sunset:18:38Z` line of the Info window. Port of Java `solar/SolarTimes`.
///
/// Standard NOAA procedure via the equation of time and the sun's hour angle; sunrise and sunset
/// are taken as the moment when the centre of the sun is 0.833° below the horizon. The arithmetic is rewritten
/// step by step in Java's order of operations (`%` on `double` = `fmod`, `Math.round`,
/// `(int)` and `int %`). Raw `double` values differ from Java in the order of ulps (HotSpot `Math.sin`
/// vs Darwin libm), the sunrise and sunset seconds measurably do not.
public struct SolarTimes: Equatable, Sendable {

    /// Sunrise in UTC as a second of the day (`LocalTime.toSecondOfDay`, 0…86 399).
    public let sunrise: Int32
    /// Sunset in UTC as a second of the day.
    public let sunset: Int32

    public init(sunrise: Int32, sunset: Int32) {
        self.sunrise = sunrise
        self.sunset = sunset
    }

    /// Zenith angle of sunrise/sunset: the centre of the sun 0.833° below the horizon.
    private static let zenithDeg: Double = 90.833

    /// Computes sunrise and sunset for day `epochDay` (`LocalDate.toEpochDay`; only the day
    /// of the year is taken from the date). `nil` where the sun neither rises nor sets that day
    /// (polar day and night), and for `NaN` coordinates. Infinite coordinates pass through
    /// as in Java: `NaN` arithmetic and `Math.round(NaN) = 0` give `00:00`/`00:00`.
    ///
    /// A day outside the `LocalDate` range (`MIN`…`MAX`, ±999 999 999 years — Java does not even create it, it throws
    /// `DateTimeException`) → `nil`, so that the calendar arithmetic does not overflow.
    public static func forLocation(_ latDeg: Double, _ lonDeg: Double, epochDay: Int64) -> SolarTimes? {
        if latDeg.isNaN || lonDeg.isNaN {
            return nil
        }
        guard epochDay >= minEpochDay, epochDay <= maxEpochDay else {
            return nil
        }
        let dayOfYear: Int32 = Self.dayOfYear(epochDay)
        guard let rise = eventTimeUtc(latDeg, lonDeg, dayOfYear, sunrise: true),
              let set = eventTimeUtc(latDeg, lonDeg, dayOfYear, sunrise: false) else {
            return nil
        }
        return SolarTimes(sunrise: toSecondOfDay(rise), sunset: toSecondOfDay(set))
    }

    /// Convenience for the UI: the UTC day containing the instant `at` (Java
    /// `now.atZone(UTC).toLocalDate()`). An instant outside the `Int64` seconds range → `nil`.
    public static func forLocation(_ latDeg: Double, _ lonDeg: Double, at date: Date) -> SolarTimes? {
        guard let parts = JavaLocalDate.split(date) else { return nil }
        return forLocation(latDeg, lonDeg, epochDay: parts.epochDay)
    }

    /// `LocalDate.MIN.toEpochDay()` / `LocalDate.MAX.toEpochDay()` (JDK 21).
    static let minEpochDay: Int64 = -365_243_219_162
    static let maxEpochDay: Int64 = 365_241_780_471

    /// `LocalDate.ofEpochDay(epochDay).getDayOfYear()`.
    static func dayOfYear(_ epochDay: Int64) -> Int32 {
        let civil = JavaLocalDate.civil(epochDay: epochDay)
        let firstDay: Int64 = JavaLocalDate.epochDay(year: civil.year, month: 1, day: 1)
        return Int32(epochDay - firstDay + 1)
    }

    /// Event time in UTC hours, or `nil` if it does not occur that day.
    private static func eventTimeUtc(_ latDeg: Double, _ lonDeg: Double, _ dayOfYear: Int32,
                                     sunrise: Bool) -> Double? {
        let lat: Double = JavaMath.toRadians(latDeg)

        // Approximate event time so that the declination is computed close to reality.
        let approxHour: Double = sunrise ? 6.0 : 18.0
        let t: Double = Double(dayOfYear) + (approxHour - lonDeg / 15.0) / 24.0

        // Mean anomaly and ecliptic longitude of the sun (degrees).
        let meanAnomaly: Double = 0.9856 * t - 3.289
        let center1: Double = 1.916 * sin(JavaMath.toRadians(meanAnomaly))
        let center2: Double = 0.020 * sin(JavaMath.toRadians(2 * meanAnomaly))
        let longitudeSum: Double = meanAnomaly + center1 + center2 + 282.634
        let trueLongitude: Double = normalizeDeg(longitudeSum)

        // Right ascension, adjusted to the same quadrant as the ecliptic longitude.
        let raTan: Double = 0.91764 * tan(JavaMath.toRadians(trueLongitude))
        let raRaw: Double = normalizeDeg(JavaMath.toDegrees(atan(raTan)))
        let lQuadrant: Double = (trueLongitude / 90.0).rounded(.down) * 90.0
        let raQuadrant: Double = (raRaw / 90.0).rounded(.down) * 90.0
        let rightAscension: Double = (raRaw + (lQuadrant - raQuadrant)) / 15.0 // to hours

        let sinDec: Double = 0.39782 * sin(JavaMath.toRadians(trueLongitude))
        let cosDec: Double = cos(asin(sinDec))

        let numerator: Double = cos(JavaMath.toRadians(zenithDeg)) - sinDec * sin(lat)
        let cosHourAngle: Double = numerator / (cosDec * cos(lat))
        if cosHourAngle > 1 || cosHourAngle < -1 {
            return nil // polar night (never rises) or polar day (never sets)
        }

        var hourAngle: Double = JavaMath.toDegrees(acos(cosHourAngle))
        if sunrise {
            hourAngle = 360 - hourAngle
        }
        hourAngle /= 15.0

        let localMeanTime: Double = hourAngle + rightAscension - 0.06571 * t - 6.622
        return normalizeHours(localMeanTime - lonDeg / 15.0)
    }

    /// `(int) Math.round(hours * 3600) % 86_400`.
    private static func toSecondOfDay(_ hours: Double) -> Int32 {
        JavaMath.l2i(JavaMath.round(hours * 3600)) % 86_400
    }

    private static func normalizeDeg(_ deg: Double) -> Double {
        let d: Double = deg.truncatingRemainder(dividingBy: 360)
        return d < 0 ? d + 360 : d
    }

    private static func normalizeHours(_ hours: Double) -> Double {
        let h: Double = hours.truncatingRemainder(dividingBy: 24)
        return h < 0 ? h + 24 : h
    }
}
