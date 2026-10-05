import Foundation

/// Java integer arithmetic and `double` conversions that Swift operators
/// do not provide (measured on JDK 21):
///
/// - Swift's `.rounded()` rounds halves **away from zero** (`-2.5` → `-3`),
///   Java's `Math.round` **toward +∞** (`-2.5` → `-2`, `-0.5` → `0`);
/// - `Int32(Double)` / `Int64(Double)` on `NaN`, infinity and out of range
///   **trap**, Java's `(int)`/`(long)` saturates and turns `NaN` into 0;
/// - Swift's `+`/`*` **trap** on overflow, Java's `int`/`long` wrap around;
/// - `/` rounds toward zero, `Math.floorDiv` toward −∞.
///
/// Java's `int` is `Int32` here and `long` is `Int64` — the domain is kept explicit
/// so that nothing silently widens to 64 bits.
enum JavaMath {

    /// `Math.round(double)`: nearest `long`, halves toward +∞, `NaN` → 0,
    /// out of range saturates (`1e19` → `Long.MAX_VALUE`).
    ///
    /// It cannot be done as `floor(x + 0.5)` — for `0.49999999999999994` the sum would
    /// round to `1.0`. The difference `x - floor(x)` is, on the other hand, exact everywhere
    /// it matters (for `x` in `(-1, -0.5]` by Sterbenz's lemma,
    /// for `x` in `(-0.5, 0)` it comes out at least `0.5` and the result 0 is correct).
    static func round(_ x: Double) -> Int64 {
        let floor = x.rounded(.down)
        return d2l(x - floor >= 0.5 ? floor + 1 : floor)
    }

    /// `(int) double`: truncation toward zero, `NaN` → 0, out of range the extreme `int`.
    static func d2i(_ x: Double) -> Int32 {
        if x.isNaN { return 0 }
        if x >= 2_147_483_647.0 { return Int32.max }
        if x <= -2_147_483_648.0 { return Int32.min }
        return Int32(x.rounded(.towardZero))
    }

    /// `(long) double`: truncation toward zero, `NaN` → 0, out of range the extreme `long`.
    static func d2l(_ x: Double) -> Int64 {
        if x.isNaN { return 0 }
        // 2^63 is exactly representable; `Int64.max` as a `Double` would
        // round to 2^63, so the comparison is made against it.
        if x >= 9_223_372_036_854_775_808.0 { return Int64.max }
        if x <= -9_223_372_036_854_775_808.0 { return Int64.min }
        return Int64(x.rounded(.towardZero))
    }

    /// `(int) long`: the low 32 bits (`1_000_000_000_000` → `-727379968`).
    static func l2i(_ x: Int64) -> Int32 {
        Int32(truncatingIfNeeded: x)
    }

    /// `Math.floorDiv(long, long)`: quotient rounded toward −∞;
    /// `Long.MIN_VALUE / -1` wraps to `Long.MIN_VALUE`.
    ///
    /// Division by zero is `ArithmeticException` in Java; here it is a program
    /// error (trap). The caller (`Tour.session`) divides by the session length, which
    /// the `Tour` constructor keeps at no less than 5 minutes.
    static func floorDiv(_ x: Int64, _ y: Int64) -> Int64 {
        precondition(y != 0, "/ by zero")
        let (quotient, overflow) = x.dividedReportingOverflow(by: y)
        if overflow { return quotient } // MIN / -1: Java returns MIN
        if (x % y != 0) && ((x ^ y) < 0) {
            return quotient - 1
        }
        return quotient
    }

    /// Java `int + int` (wraps around).
    static func addInt(_ a: Int32, _ b: Int32) -> Int32 { a &+ b }

    /// Java `int * int` (wraps around).
    static func multiplyInt(_ a: Int32, _ b: Int32) -> Int32 { a &* b }

    /// Java `long + long` (wraps around).
    static func addLong(_ a: Int64, _ b: Int64) -> Int64 { a &+ b }

    /// Java `long * long` (wraps around).
    static func multiplyLong(_ a: Int64, _ b: Int64) -> Int64 { a &* b }

    /// `Math.min(double, double)`: `NaN` from either argument wins
    /// and −0.0 is smaller than +0.0. Swift's `Swift.min` resolves both by argument order.
    static func min(_ a: Double, _ b: Double) -> Double {
        if a.isNaN { return a }
        if a == 0 && b == 0 && b.bitPattern == (-0.0).bitPattern { return b }
        return a <= b ? a : b
    }

    /// `Math.max(double, double)`: `NaN` from either argument wins
    /// and +0.0 is greater than −0.0.
    static func max(_ a: Double, _ b: Double) -> Double {
        if a.isNaN { return a }
        if a == 0 && b == 0 && a.bitPattern == (-0.0).bitPattern { return b }
        return a >= b ? a : b
    }
}
