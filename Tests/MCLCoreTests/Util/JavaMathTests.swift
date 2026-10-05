import Testing
@testable import MCLCore

/// Tests of `JavaMath` — Java arithmetic that Swift operators cannot give:
/// `Math.round`, `(int)`/`(long)` casts from `double`, `(int)` from `long`,
/// `Math.floorDiv` and wrapping `int`/`long` operations.
///
/// Values measured on JDK 21.0.2. Swift `.rounded()` rounds halves
/// away from zero (`-2.5` → `-3`), `Int64(Double)` / `Int32(Double)` on `NaN`,
/// towards infinity and out of range it **crashes**, and so do `+`/`*` on overflow.
@Suite struct JavaMathTests {

    /// `Math.round(double)`: halves toward +∞, `NaN` → 0, saturation to `long`.
    @Test func roundHalvesTowardPositiveInfinity() {
        let table: [(Double, Int64)] = [
            (0.5, 1),
            (-0.5, 0),
            (2.5, 3),
            (-2.5, -2),
            (1.5, 2),
            (-1.5, -1),
            (0.49999999999999994, 0),
            (-0.49999999999999994, 0),
            (1e19, Int64.max),
            (-1e19, Int64.min),
            (.nan, 0),
            (.infinity, Int64.max),
            (-.infinity, Int64.min),
            (4_503_599_627_370_497.0, 4_503_599_627_370_497),
            (-4_503_599_627_370_497.0, -4_503_599_627_370_497),
            (9.223372036854776e18, Int64.max),
            (-9.223372036854776e18, Int64.min),
            (-0.0, 0),
            (3.7, 4),
            (-3.7, -4),
            (-1e-20, 0),
        ]
        for (input, expected) in table {
            #expect(JavaMath.round(input) == expected, "round(\(input))")
        }
    }

    /// `(int) double` and `(long) double`: truncation toward zero, saturation, `NaN` → 0.
    @Test func doubleToIntegerCastsSaturate() {
        let table: [(Double, Int32, Int64)] = [
            (.nan, 0, 0),
            (.infinity, Int32.max, Int64.max),
            (-.infinity, Int32.min, Int64.min),
            (3e9, Int32.max, 3_000_000_000),
            (-3e9, Int32.min, -3_000_000_000),
            (3.5, 3, 3),
            (-3.5, -3, -3),
            (-0.0, 0, 0),
            (2_147_483_647.9, Int32.max, 2_147_483_647),
            (-2_147_483_648.9, Int32.min, -2_147_483_648),
            (1e19, Int32.max, Int64.max),
            (-1e19, Int32.min, Int64.min),
            (9.9999999998e21, Int32.max, Int64.max),
        ]
        for (input, asInt, asLong) in table {
            #expect(JavaMath.d2i(input) == asInt, "(int) \(input)")
            #expect(JavaMath.d2l(input) == asLong, "(long) \(input)")
        }
    }

    /// `(int) long` takes the low 32 bits (perKm with a huge factor).
    @Test func longToIntKeepsLowBits() {
        #expect(JavaMath.l2i(1_000_000_000_000) == -727_379_968)
        #expect(JavaMath.l2i(JavaMath.d2l(1e18)) == -1_486_618_624)
        #expect(JavaMath.l2i(Int64(Int32.max) + 1) == Int32.min)
        #expect(JavaMath.l2i(-5) == -5)
    }

    /// `Math.floorDiv(long, long)`: rounding toward −∞; `MIN / -1` wraps.
    @Test func floorDivRoundsTowardNegativeInfinity() {
        let table: [(Int64, Int64, Int64)] = [
            (7, 2, 3),
            (-7, 2, -4),
            (7, -2, -4),
            (-7, -2, 3),
            (-1, 60, -1),
            (-60, 60, -1),
            (-61, 60, -2),
            (0, 5, 0),
            (Int64.min, -1, Int64.min),
            (Int64.min, 2, -4_611_686_018_427_387_904),
            (Int64.max, -1, -Int64.max),
            (-3, 5, -1),
        ]
        for (x, y, expected) in table {
            #expect(JavaMath.floorDiv(x, y) == expected, "floorDiv(\(x), \(y))")
        }
    }

    /// A Java `int` wraps on overflow, it does not crash.
    @Test func intArithmeticWraps() {
        #expect(JavaMath.addInt(2_000_000_000, 2_000_000_000) == -294_967_296)
        #expect(JavaMath.addInt(Int32.max, 1) == Int32.min)
        #expect(JavaMath.multiplyInt(65_536, 65_536) == 0)
        #expect(JavaMath.multiplyInt(100_000, 100_000) == 1_410_065_408)
        #expect(JavaMath.addInt(2, 3) == 5)
    }

    /// A Java `long` too.
    @Test func longArithmeticWraps() {
        #expect(JavaMath.addLong(Int64.max, 1) == Int64.min)
        #expect(JavaMath.multiplyLong(Int64.max, 2) == -2)
        #expect(JavaMath.addLong(2, 3) == 5)
    }

    /// `Math.min/max(double, double)`: `NaN` propagates from either argument and −0.0 is
    /// less than +0.0 (measured via `min(-0, 0)` etc. in expressions).
    /// Swift `Swift.min` on `NaN` and zeros returns according to argument order.
    @Test func minMaxFollowJava() {
        #expect(JavaMath.min(1, 2) == 1 && JavaMath.max(1, 2) == 2)
        #expect(JavaMath.min(.nan, 1).isNaN && JavaMath.min(1, .nan).isNaN)
        #expect(JavaMath.max(.nan, 1).isNaN && JavaMath.max(1, .nan).isNaN)
        #expect(JavaMath.min(-0.0, 0.0).bitPattern == (-0.0).bitPattern)
        #expect(JavaMath.min(0.0, -0.0).bitPattern == (-0.0).bitPattern)
        #expect(JavaMath.max(-0.0, 0.0).bitPattern == 0)
        #expect(JavaMath.max(0.0, -0.0).bitPattern == 0)
        #expect(JavaMath.min(-.infinity, 5) == -.infinity && JavaMath.max(.infinity, 5) == .infinity)
    }

    /// `Math.abs(long)`: `Long.MIN_VALUE` stays negative (JLS; Swift `abs` would crash).
    @Test func absLongKeepsMinNegative() {
        #expect(JavaMath.abs(-5) == 5 && JavaMath.abs(5) == 5 && JavaMath.abs(0) == 0)
        #expect(JavaMath.abs(Int64.max) == Int64.max)
        #expect(JavaMath.abs(-Int64.max) == Int64.max)
        #expect(JavaMath.abs(Int64.min) == Int64.min)
    }
}
