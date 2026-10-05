/// Maidenhead locator → coordinates and distance (haversine). Port of Java
/// `engine/Maidenhead.java`. Returns the centre of the square: for a 6-character locator the centre of the subsquare
/// (like N1MM/Hamlib), for a 4-character one the centre of the 2°×1° field. The Earth radius here is **6371.0**
/// (`GreatCircle` has 6371.0) — the two radii must not be unified.
public enum Maidenhead {

    private static let earthRadiusKm = 6371.0088

    /// Centre of the locator in degrees, or `nil` for an invalid locator. As in Java: `trim()`
    /// (characters ≤ U+0020) and `toUpperCase()`, then exactly `[A-R]{2}[0-9]{2}([A-X]{2})?`
    /// by UTF-16 units (an 8-character locator is thus invalid).
    public static func centerLatLon(_ grid: String?) -> (lat: Double, lon: Double)? {
        guard let grid else { return nil }
        let g = Array(JavaText.trim(grid).uppercased().utf16)
        guard g.count == 4 || g.count == 6 else { return nil }
        guard isLetter(g[0], upTo: 0x52), isLetter(g[1], upTo: 0x52),
              isDigit(g[2]), isDigit(g[3]) else { return nil }
        if g.count == 6 {
            guard isLetter(g[4], upTo: 0x58), isLetter(g[5], upTo: 0x58) else { return nil }
        }
        // The Java expression is computed in `int` and only then converts to double.
        let lonBase = Double(-180 + (Int(g[0]) - 0x41) * 20 + (Int(g[2]) - 0x30) * 2)
        let latBase = Double(-90 + (Int(g[1]) - 0x41) * 10 + (Int(g[3]) - 0x30))
        if g.count >= 6 {
            let lon = lonBase + Double(Int(g[4]) - 0x41) * (2.0 / 24) + (1.0 / 24)
            let lat = latBase + Double(Int(g[5]) - 0x41) * (1.0 / 24) + (0.5 / 24)
            return (lat, lon)
        }
        return (latBase + 0.5, lonBase + 1)
    }

    /// Distance between square centres in km; `-1` if either locator is invalid.
    public static func distanceKm(_ gridA: String?, _ gridB: String?) -> Double {
        guard let a = centerLatLon(gridA), let b = centerLatLon(gridB) else { return -1 }
        return GreatCircle.haversineKm(radius: earthRadiusKm, a.lat, a.lon, b.lat, b.lon)
    }

    private static func isLetter(_ unit: UInt16, upTo last: UInt16) -> Bool {
        unit >= 0x41 && unit <= last
    }

    private static func isDigit(_ unit: UInt16) -> Bool {
        unit >= 0x30 && unit <= 0x39
    }
}
