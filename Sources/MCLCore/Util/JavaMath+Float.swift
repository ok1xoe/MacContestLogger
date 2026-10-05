extension JavaMath {

    /// `Math.round(float)` → Java `int`: nearest integer, halves toward +∞
    /// (`-2.5f` → `-2`, `-0.5f` → `0`), `NaN` → 0, out of range saturating to
    /// `Integer.MIN_VALUE`/`MAX_VALUE` (`1e10f` → `2147483647`). Needed by `CwSynth`
    /// (`Math.round(rate * 1.2f / wpm)`). The table and a pass over 1,047,809 bit patterns
    /// against JDK 21: `HelpersTests.roundFloat*`.
    ///
    /// As with `round(Double)`, not `floor(x + 0.5)` (for `0.49999997f` the sum would
    /// round to `1`); the difference `x - floor(x)` is exact for `float` for the same reason.
    static func round(_ x: Float) -> Int32 {
        let floor: Float = x.rounded(.down)
        return f2i(x - floor >= 0.5 ? floor + 1 : floor)
    }

    /// `(int) float`: truncation toward zero, `NaN` → 0, out of range the extreme `int`.
    static func f2i(_ x: Float) -> Int32 {
        if x.isNaN { return 0 }
        // 2^31 is exactly representable; `Int32.max` as a `Float` rounds to 2^31.
        if x >= 2_147_483_648.0 { return Int32.max }
        if x <= -2_147_483_648.0 { return Int32.min }
        return Int32(x.rounded(.towardZero))
    }
}
