/// The waterfall colour of v1.1.1 (`WaterfallWindow.kt:130-136`, `heat(v: Float)`): noise dark blue, signal through
/// yellow to white. Kotlin `Float` arithmetic and `coerceIn` (NaN passes through and ends as 0), `(255 * x).toInt()`
/// truncation; the result is a `TYPE_INT_RGB` pixel `0x00RRGGBB`.
public enum WaterfallPalette {

    public static func heat(_ v: Float) -> UInt32 {
        let t = coerce01(v)
        let r = channel(t * 2 - 0.6)
        let g = channel(t * 1.6 - 0.3)
        let b = channel(0.25 + t * 1.5)
        return (r << 16) | (g << 8) | b
    }

    /// `(255 * x.coerceIn(0f, 1f)).toInt()`.
    static func channel(_ x: Float) -> UInt32 {
        let scaled: Float = 255 * coerce01(x)
        return UInt32(truncatingIfNeeded: JavaMath.f2i(scaled))
    }

    /// Kotlin `Float.coerceIn(0f, 1f)`: `if (this < min) min else if (this > max) max else this` — NaN stays NaN.
    static func coerce01(_ x: Float) -> Float {
        if x < 0 { return 0 }
        if x > 1 { return 1 }
        return x
    }
}
