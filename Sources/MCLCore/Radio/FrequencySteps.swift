/// Tuning from the keyboard and mouse wheel in the entry window (N1MM "Tune the Radio"):
/// - arrows / wheel: 20 Hz step in CW and digital, 100 Hz in phone;
/// - Alt+wheel: to the next whole 1 kHz, Ctrl+wheel 10 kHz, Ctrl+Alt+wheel 100 kHz;
/// - Ctrl+PgUp/PgDn: one band up / down (WARC is skipped in a contest).
///
/// Mirrors the Java `radio.FrequencySteps`. Frequencies are a Java `long` (`Int`), the numbers of
/// notches and the direction a Java `int`: arithmetic wraps as in Java,
/// measured in a maintainer-only probe (rows `FS.`).
public enum FrequencySteps {

    /// Arrow tuning step (N1MM default: 20 Hz CW, 100 Hz SSB); 100 Hz without a mode.
    public static func stepHz(_ mode: Mode?) -> Int {
        guard let mode else { return 100 }
        switch mode {
        case .ssb, .am, .fm: return 100
        default: return 20
        }
    }

    /// To the next "round" frequency in direction `direction` (+1 up, otherwise down):
    /// `14 025 300` with a 1 kHz step up → `14 026 000`, down → `14 025 000`.
    /// Rounds by `Math.floorDiv` (toward −∞: −50 Hz up → 0) and wraps as a `long`.
    /// A step of 0 is an `ArithmeticException` in Java, a trap here — `wheel` never sends it.
    public static func roundTo(_ freqHz: Int, unitHz: Int, direction: Int) -> Int {
        let down = Int(JavaMath.floorDiv(Int64(freqHz), Int64(unitHz))) &* unitHz
        if direction > 0 {
            return down &+ unitHz
        }
        return down == freqHz ? freqHz &- unitHz : down
    }

    /// Mouse wheel.
    ///
    /// - Parameters:
    ///   - notches: number of notches (+ up, − down), a Java `int`
    ///   - alt: Alt / Option held
    ///   - ctrl: Ctrl held
    ///
    /// With a modifier `roundTo` repeats `Math.abs(notches)` times — for `Integer.MIN_VALUE`
    /// that is a negative number and the loop does not run (frequency unchanged), as in Java.
    public static func wheel(_ freqHz: Int, mode: Mode?, notches: Int, alt: Bool, ctrl: Bool) -> Int {
        let clicks = Int32(truncatingIfNeeded: notches)
        if clicks == 0 {
            return freqHz
        }
        let unit: Int = ctrl && alt ? 100_000 : ctrl ? 10_000 : alt ? 1_000 : 0
        if unit == 0 {
            return freqHz &+ (Int(clicks) &* stepHz(mode))
        }
        var f = freqHz
        let direction = Int(clicks.signum())
        let count: Int32 = clicks == .min ? clicks : (clicks < 0 ? -clicks : clicks)
        var i: Int32 = 0
        while i < count {
            f = roundTo(f, unitHz: unit, direction: direction)
            i += 1
        }
        return f
    }

    /// WARC bands — not used in contests.
    public static func isWarc(_ band: Band) -> Bool {
        band == .m60 || band == .m30 || band == .m17 || band == .m12
    }

    /// Neighbouring band in direction `direction` from `allowed` (in enum order = by frequency),
    /// wrapping around like N1MM; `nil` if there is nowhere to go.
    ///
    /// Java quirks (measured): `direction 0` gives `nil` only if the current band
    /// is in `allowed`, otherwise it behaves like −1; without a current band `direction > 0` →
    /// the first, otherwise the last; `idx + direction` is a Java `int` and wraps
    /// (`20m` + `Integer.MAX_VALUE` in six bands → `160m`).
    public static func nextBand(_ current: Band?, allowed: [Band], direction: Int) -> Band? {
        let bands: [Band] = allowed.sorted { ordinal($0) < ordinal($1) }
        guard let first = bands.first, let last = bands.last else { return nil }
        guard let current else {
            return direction > 0 ? first : last
        }
        guard let idx = bands.firstIndex(of: current) else {
            // the current band is not among the allowed: nearest in the direction
            let currentOrdinal = ordinal(current)
            if direction > 0 {
                if let band = bands.first(where: { ordinal($0) > currentOrdinal }) { return band }
                return first
            }
            if let band = bands.last(where: { ordinal($0) < currentOrdinal }) { return band }
            return last
        }
        let sum = Int32(idx) &+ Int32(truncatingIfNeeded: direction)
        // `Math.floorMod(int, int)` with a positive divisor
        let remainder = Int(sum) % bands.count
        let next = remainder < 0 ? remainder + bands.count : remainder
        return next == idx ? nil : bands[next]
    }

    /// Java `Band.ordinal()` — order in `Band.allCases`.
    private static func ordinal(_ band: Band) -> Int {
        Band.allCases.firstIndex(of: band) ?? 0
    }
}
