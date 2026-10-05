import Foundation

/// Simplified HF propagation forecast (similar to the HamCAP / VOACAP graph in N1MM, but without an
/// ionospheric model): F2 layer critical frequency from the Sun's elevation and solar flux,
/// MUF at the path control points (1000 km from both ends), absorption on the low bands by day
/// (LUF). Port of Java `propagation/PropagationModel`.
///
/// Raw `double` values (MUF, LUF, distance) differ from Java by ulps (`Math.sin`/`Math.cos` in
/// HotSpot vs Darwin libm), band levels measurably do not. `Math.min`/
/// `Math.max` are Java's (`NaN` wins); a `NaN` MUF gives level `marginal` as in Java.
public enum PropagationModel {

    /// Band state on the path (order = Java `ordinal`).
    public enum Level: Int, CaseIterable, Sendable {
        case closed
        case marginal
        case open
    }

    private static let earthKm: Double = 6371.0
    private static let hopKm: Double = 3500.0

    /// Sunspot number from the solar flux index (SFI 10.7 cm).
    public static func ssnFromSfi(_ sfi: Double) -> Double {
        JavaMath.max(0, (sfi - 63.7) / 0.728)
    }

    /// Critical frequency foF2 (MHz) at a point given the Sun elevation (°) and SSN.
    static func foF2(_ sunElevationDeg: Double, _ ssn: Double) -> Double {
        let day: Double = 5.0 + 0.055 * ssn // noon at high activity ~12 MHz
        let night: Double = 2.3 + 0.012 * ssn // night minimum
        if sunElevationDeg <= -12 {
            return night
        }
        let cosChi: Double = JavaMath.max(0, sin(JavaMath.toRadians(sunElevationDeg)))
        var f: Double = night + (day - night) * pow(cosChi, 0.5)
        if sunElevationDeg < 0 { // twilight: smooth transition to night
            let fade: Double = 1 + sunElevationDeg / 12.0
            f = night + (f - night) * fade
        }
        return f
    }

    /// Great-circle path length (km).
    static func distanceKm(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let p1: Double = JavaMath.toRadians(lat1)
        let p2: Double = JavaMath.toRadians(lat2)
        let dl: Double = JavaMath.toRadians(lon2 - lon1)
        let along: Double = sin(p1) * sin(p2)
        let across: Double = cos(p1) * cos(p2) * cos(dl)
        let c: Double = acos(JavaMath.max(-1, JavaMath.min(1, along + across)))
        return earthKm * c
    }

    /// Point on the great circle at distance `km` from the start.
    static func pointAt(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double,
                        km: Double) -> (lat: Double, lon: Double) {
        let brg: Double = JavaMath.toRadians(GreatCircle.bearingDeg(lat1, lon1, lat2, lon2))
        let d: Double = km / earthKm
        let p1: Double = JavaMath.toRadians(lat1)
        let l1: Double = JavaMath.toRadians(lon1)
        let sinP2: Double = sin(p1) * cos(d) + cos(p1) * sin(d) * cos(brg)
        let p2: Double = asin(sinP2)
        let y: Double = sin(brg) * sin(d) * cos(p1)
        let x: Double = cos(d) - sin(p1) * sin(p2)
        let l2: Double = l1 + atan2(y, x)
        return (JavaMath.toDegrees(p2), JavaMath.toDegrees(l2))
    }

    /// Path MUF (MHz) at the given instant.
    public static func muf(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double,
                           epochMillis: Int64, ssn: Double) -> Double {
        let dist: Double = distanceKm(lat1, lon1, lat2, lon2)
        let ss = SolarTerminator.subsolar(epochMillis: epochMillis)
        let hop: Double = JavaMath.min(dist, hopKm)
        // M(3000)F2 factor ~ 3; a shorter hop has a lower MUF (steeper angle).
        let m: Double = 1.0 + 2.0 * JavaMath.min(1.0, hop / 3000.0)
        let ctl: Double = JavaMath.min(1000, dist / 2)
        let a = pointAt(lat1, lon1, lat2, lon2, km: ctl)
        let b = pointAt(lat1, lon1, lat2, lon2, km: dist - ctl)
        let fa: Double = foF2(SolarTerminator.elevation(a.lat, a.lon, ss), ssn)
        let fb: Double = foF2(SolarTerminator.elevation(b.lat, b.lon, ss), ssn)
        return JavaMath.min(fa, fb) * m
    }

    /// Lowest usable frequency (MHz): D layer absorption by day at both ends.
    public static func luf(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double,
                           epochMillis: Int64) -> Double {
        let ss = SolarTerminator.subsolar(epochMillis: epochMillis)
        let e1: Double = SolarTerminator.elevation(lat1, lon1, ss)
        let e2: Double = SolarTerminator.elevation(lat2, lon2, ss)
        let e: Double = JavaMath.max(e1, e2)
        if e <= 0 {
            return 1.6
        }
        let dist: Double = distanceKm(lat1, lon1, lat2, lon2)
        let damping: Double = 10.0 * sin(JavaMath.toRadians(e)) * JavaMath.min(1.5, dist / 6000.0)
        return 2.0 + damping
    }

    /// Band state: open below 85 % of MUF and above LUF, marginal up to MUF.
    public static func level(_ band: Band, muf: Double, luf: Double) -> Level {
        let f: Double = Double(band.lowHz) / 1e6
        if f < luf || f > muf {
            return .closed
        }
        return f <= 0.85 * muf ? .open : .marginal
    }

    /// Forecast for the 24 hours of the day containing `from` (index = UTC hour; the sample
    /// is always at the half hour). Like Java it counts from `from.truncatedTo(DAYS)`, not from `from`.
    /// An instant outside the epoch ms range (`Instant.toEpochMilli` would throw) → empty list.
    public static func forecast(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double,
                                from: Date, ssn: Double, bands: [Band]) -> [[Band: Level]] {
        guard let parts = JavaLocalDate.split(from) else { return [] }
        let (dayMillis, overflow) = parts.epochDay.multipliedReportingOverflow(by: 86_400_000)
        if overflow { return [] }
        var out: [[Band: Level]] = []
        for h in 0..<24 {
            let offset: Int64 = Int64(h) * 3_600_000 + 1_800_000
            let (t, late) = dayMillis.addingReportingOverflow(offset)
            if late { return [] }
            let mufValue: Double = muf(lat1, lon1, lat2, lon2, epochMillis: t, ssn: ssn)
            let lufValue: Double = luf(lat1, lon1, lat2, lon2, epochMillis: t)
            var row: [Band: Level] = [:]
            for b in bands {
                row[b] = level(b, muf: mufValue, luf: lufValue)
            }
            out.append(row)
        }
        return out
    }
}
