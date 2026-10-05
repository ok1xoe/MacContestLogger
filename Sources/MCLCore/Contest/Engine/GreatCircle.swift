import Foundation

/// Azimuth and distance of two points along a great circle. Port of Java `engine/GreatCircle.java`.
///
/// Bit-exact `double` agreement with Java is unattainable: `Math.sin`/`Math.cos` are HotSpot
/// intrinsics and Darwin libm differs from them by units to tens of ulp (a deliberate divergence
/// from Java v1.1.1). Whole kilometres after `ceil`/`round` do agree, though.
/// The conversion to radians is `JavaMath.toRadians` (`x * (π/180)`, constant precomputed), not `x * π / 180`.
public enum GreatCircle {

    /// Earth radius for `distanceKm` (`Maidenhead` uses a different one: 6371.0088).
    private static let earthRadiusKm = 6371.0

    /// Initial azimuth from point 1 to point 2 in degrees `[0, 360)`.
    public static func bearingDeg(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let phi1 = JavaMath.toRadians(lat1)
        let phi2 = JavaMath.toRadians(lat2)
        let dLon = JavaMath.toRadians(lon2 - lon1)
        let y = sin(dLon) * cos(phi2)
        let x = cos(phi1) * sin(phi2) - sin(phi1) * cos(phi2) * cos(dLon)
        let deg = JavaMath.toDegrees(atan2(y, x))
        // Java `%` on a double is `fmod`.
        return (deg + 360.0).truncatingRemainder(dividingBy: 360.0)
    }

    /// Distance of two points in km (haversine).
    public static func distanceKm(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        haversineKm(radius: earthRadiusKm, lat1, lon1, lat2, lon2)
    }

    /// Shared haversine with an array of radians; the order of operations is the same as in Java.
    static func haversineKm(radius: Double, _ lat1: Double, _ lon1: Double,
                            _ lat2: Double, _ lon2: Double) -> Double {
        let la1 = JavaMath.toRadians(lat1)
        let la2 = JavaMath.toRadians(lat2)
        let dLat = JavaMath.toRadians(lat2 - lat1)
        let dLon = JavaMath.toRadians(lon2 - lon1)
        let sinLat = sin(dLat / 2)
        let sinLon = sin(dLon / 2)
        let h = sinLat * sinLat + cos(la1) * cos(la2) * sinLon * sinLon
        return 2 * radius * asin(JavaMath.min(1, h.squareRoot()))
    }
}
