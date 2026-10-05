import Foundation

/// Solar terminator (grey map): for a given time computes the subsolar point (where the Sun is
/// at the zenith) and decides whether a place is in day or night. A simplified model without the equation
/// of time. Port of Java `map/SolarTerminator`.
///
/// Calendar as `Instant.ofEpochMilli(ms).atZone(UTC)`: seconds by `floorDiv`, only whole seconds
/// are taken from the time (milliseconds are dropped). The raw elevation differs from Java in ulps
/// (HotSpot `Math.sin`/`Math.cos` vs Darwin libm), day/night measurably does not.
public enum SolarTerminator {

    /// Subsolar point in degrees: `lat` = solar declination, `lon` in −180…180
    /// (Java `double[] {decl, lon}`).
    public static func subsolar(epochMillis: Int64) -> (lat: Double, lon: Double) {
        let seconds: Int64 = JavaMath.floorDiv(epochMillis, 1_000)
        let epochDay: Int64 = JavaMath.floorDiv(seconds, 86_400)
        let secondOfDay: Int64 = seconds - epochDay * 86_400
        let dayOfYear: Int32 = SolarTimes.dayOfYear(epochDay)
        let hour: Double = Double(secondOfDay / 3_600)
        let minute: Double = Double(secondOfDay / 60 % 60)
        let second: Double = Double(secondOfDay % 60)
        let utcHours: Double = hour + minute / 60.0 + second / 3600.0
        // Solar declination (approximation).
        let dayAngle: Double = 360.0 / 365.0 * Double(dayOfYear + 10)
        let decl: Double = -23.44 * cos(JavaMath.toRadians(dayAngle))
        // Longitude of the subsolar point: at noon UTC it is above 0°, otherwise shifts −15°/h.
        let raw: Double = -15.0 * (utcHours - 12.0)
        // ((lon + 180) % 360 + 360) % 360 - 180: normalisation to −180..180, `%` = `fmod`.
        let shifted: Double = (raw + 180).truncatingRemainder(dividingBy: 360) + 360
        let lon: Double = shifted.truncatingRemainder(dividingBy: 360) - 180
        return (decl, lon)
    }

    /// Is the place (`lat`, `lon`) in the night (solar elevation < 0) at the given time?
    /// A `NaN` elevation (unknown coordinates) is day, as in Java.
    public static func isNight(_ lat: Double, _ lon: Double, epochMillis: Int64) -> Bool {
        elevation(lat, lon, subsolar(epochMillis: epochMillis)) < 0
    }

    /// Solar elevation (degrees) at a place relative to the subsolar point; the `sin` of the elevation is clamped
    /// to −1…1 by Java `Math.max`/`Math.min` (`NaN` passes).
    public static func elevation(_ lat: Double, _ lon: Double, _ subsolar: (lat: Double, lon: Double)) -> Double {
        let la: Double = JavaMath.toRadians(lat)
        let dec: Double = JavaMath.toRadians(subsolar.lat)
        let h: Double = JavaMath.toRadians(lon - subsolar.lon)
        let vertical: Double = sin(la) * sin(dec)
        let horizontal: Double = cos(la) * cos(dec) * cos(h)
        let sinEl: Double = vertical + horizontal
        let clamped: Double = JavaMath.max(-1, JavaMath.min(1, sinEl))
        return JavaMath.toDegrees(asin(clamped))
    }
}
