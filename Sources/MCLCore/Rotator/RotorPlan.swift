/// How a beam bearing becomes a rotor command (N1MM antenna table „Offset" / „Bidirectional", N1MM Rotor
/// calibration and limits), the heading typed in the call field and the bearing between two grids.
public enum RotorPlan {

    /// N1MM: a number typed in the call field (0–360, up to three digits) and Alt+J turns the rotor to that heading.
    public static func typedHeading(_ text: String) -> Int? {
        let trimmed: String = KotlinStrings.trim(text)
        guard (1...3).contains(trimmed.count), trimmed.allSatisfy({ $0.isASCII && $0.isNumber }),
              let value = Int(trimmed), value <= 360 else {
            return nil
        }
        return value
    }

    /// The whole-degree bearing from my grid to the station's grid (VHF: the locator is known, so the bearing is
    /// taken between the squares, not to the country's centre). Rounded like `GreatCircle.azimuth`; `nil` when either
    /// grid is not a locator.
    public static func gridBearing(from myGrid: String?, to theirGrid: String?) -> Int? {
        guard let origin = Maidenhead.centerLatLon(myGrid), let target = Maidenhead.centerLatLon(theirGrid) else {
            return nil
        }
        if origin.lat == target.lat && origin.lon == target.lon {
            return nil
        }
        let bearing: Double = GreatCircle.bearingDeg(origin.lat, origin.lon, target.lat, target.lon)
        return Int(Int32(truncatingIfNeeded: JavaMath.round(bearing)))
    }

    /// The rotor heading (0…<360) for a beam bearing: the antenna's `offset` is taken off; a bidirectional antenna
    /// uses whichever end of the beam is nearer to the rotor's `current` heading (so it turns at most 180°), the front
    /// when the position is unknown.
    public static func rotorHeading(bearing: Double, offset: Int, bidirectional: Bool, current: Double?) -> Double {
        let front: Double = RotctldClient.normalize(bearing - Double(offset))
        guard bidirectional, let current, current.isFinite else { return front }
        let back: Double = RotctldClient.normalize(front + 180)
        let here: Double = RotctldClient.normalize(current)
        return distance(here, back) < distance(here, front) ? back : front
    }

    /// The command for a rotor: the calibration is taken off and the heading is placed inside the rotor's limits
    /// (on an overlap rotor the turn nearer to the controller's `currentRaw` position wins). A heading the limits
    /// cannot reach goes to the nearer limit, `clamped` says so. Without limits the command is the normalised heading.
    public static func command(heading: Double, rotor: RotorEntry, currentRaw: Double?) -> (azimuth: Double,
                                                                                            clamped: Bool) {
        let raw: Double = RotctldClient.normalize(heading - Double(rotor.calibration))
        guard rotor.hasLimits else { return (raw, false) }
        let low = Double(rotor.minAzimuth)
        let high = Double(rotor.maxAzimuth)
        let candidates: [Double] = (-2...2).map { raw + Double($0) * 360 }.filter { $0 >= low && $0 <= high }
        if candidates.isEmpty {
            // The nearer limit (by the angle between the heading and each limit).
            let toLow: Double = distance(raw, RotctldClient.normalize(low))
            let toHigh: Double = distance(raw, RotctldClient.normalize(high))
            return (toLow <= toHigh ? low : high, true)
        }
        if let currentRaw, currentRaw.isFinite {
            let best: Double = candidates.min { abs($0 - currentRaw) < abs($1 - currentRaw) } ?? candidates[0]
            return (best, false)
        }
        let best: Double = candidates.min { abs($0 - raw) < abs($1 - raw) } ?? candidates[0]
        return (best, false)
    }

    /// The heading shown for what a controller reports: the calibration is added (and the result normalised);
    /// without a calibration the reported value is shown as it is.
    public static func reported(raw: Double, calibration: Int) -> Double {
        calibration == 0 ? raw : RotctldClient.normalize(raw + Double(calibration))
    }

    /// The angle between two headings (0…180).
    static func distance(_ a: Double, _ b: Double) -> Double {
        let d: Double = abs(RotctldClient.normalize(a) - RotctldClient.normalize(b))
        return d > 180 ? 360 - d : d
    }
}
