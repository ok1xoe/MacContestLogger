/// `java.util.Random` (JDK 21) for tests — the port of `CwDecoderTest` generates the noise
/// `new Random(1).nextGaussian()` and the decoder's result depends on the exact formulas.
///
/// A 48-bit LCG (`seed * 0x5DEECE66D + 0xB`), the seed scrambled with `^ 0x5DEECE66D`;
/// `nextInt(bound)` with rejection of over-represented values (a power of two via multiplication),
/// `nextDouble` from 26 + 27 bits, `nextGaussian` by the polar method with the second value of the pair in reserve.
/// `nextGaussian` calls `StrictMath.log` and `StrictMath.sqrt`: `sqrt` is exact everywhere in IEEE 754,
/// `log` here is a port of fdlibm `e_log.c` from `java.lang.FdLibm.Log` — Darwin `log` may
/// differ from it by an ulp, so the match with Java would not be bitwise. Verified against JDK 21.0.2 (`JavaRandomTests`).
struct JavaRandom {

    private static let multiplier: Int64 = 0x5_DEEC_E66D
    private static let addend: Int64 = 0xB
    private static let mask: Int64 = (1 << 48) - 1

    private var seed: Int64
    private var nextNextGaussian = 0.0
    private var haveNextNextGaussian = false

    /// `new Random(seed)`.
    init(seed: Int64) {
        self.seed = (seed ^ Self.multiplier) & Self.mask
    }

    /// `Random.next(bits)`.
    private mutating func next(_ bits: Int) -> Int32 {
        seed = (seed &* Self.multiplier &+ Self.addend) & Self.mask
        return Int32(truncatingIfNeeded: seed >> (48 - bits))
    }

    /// `nextInt()`.
    mutating func nextInt() -> Int32 {
        next(32)
    }

    /// `nextInt(bound)`; `bound <= 0` is `IllegalArgumentException("bound must be positive")` in Java.
    mutating func nextInt(bound: Int32) -> Int32 {
        precondition(bound > 0, "bound must be positive")
        var r = next(31)
        let m = bound &- 1
        if bound & m == 0 {
            return Int32(truncatingIfNeeded: (Int64(bound) &* Int64(r)) >> 31)
        }
        var u = r
        while true {
            r = u % bound
            if u &- r &+ m >= 0 { break }
            u = next(31)
        }
        return r
    }

    /// `nextDouble()`.
    mutating func nextDouble() -> Double {
        let high = Int64(next(26)) << 27
        let low = Int64(next(27))
        return Double(high + low) * 0x1p-53
    }

    /// `nextGaussian()`.
    mutating func nextGaussian() -> Double {
        if haveNextNextGaussian {
            haveNextNextGaussian = false
            return nextNextGaussian
        }
        var v1: Double
        var v2: Double
        var s: Double
        repeat {
            v1 = 2 * nextDouble() - 1
            v2 = 2 * nextDouble() - 1
            s = v1 * v1 + v2 * v2
        } while s >= 1 || s == 0
        let multiplier: Double = (-2 * Self.strictLog(s) / s).squareRoot()
        nextNextGaussian = v2 * multiplier
        haveNextNextGaussian = true
        return v1 * multiplier
    }

    // MARK: - StrictMath.log (fdlibm e_log.c, `java.lang.FdLibm.Log`)

    private static let ln2Hi: Double = 0x1.62e42feep-1
    private static let ln2Lo: Double = 0x1.a39ef35793c76p-33
    private static let lg1: Double = 0x1.5555555555593p-1
    private static let lg2: Double = 0x1.999999997fa04p-2
    private static let lg3: Double = 0x1.2492494229359p-2
    private static let lg4: Double = 0x1.c71c51d8e78afp-3
    private static let lg5: Double = 0x1.7466496cb03dep-3
    private static let lg6: Double = 0x1.39a09d078c69fp-3
    private static let lg7: Double = 0x1.2f112df3e5244p-3
    private static let two54: Double = 0x1p54

    private static func high(_ x: Double) -> Int32 {
        Int32(truncatingIfNeeded: Int64(bitPattern: x.bitPattern) >> 32)
    }

    private static func low(_ x: Double) -> Int32 {
        Int32(truncatingIfNeeded: Int64(bitPattern: x.bitPattern))
    }

    private static func withHigh(_ x: Double, _ high: Int32) -> Double {
        let lowBits: UInt64 = x.bitPattern & 0x0000_0000_FFFF_FFFF
        let highBits: UInt64 = UInt64(UInt32(bitPattern: high)) << 32
        return Double(bitPattern: highBits | lowBits)
    }

    /// Java `StrictMath.log(x)` bit by bit.
    static func strictLog(_ input: Double) -> Double {
        var x = input
        var hx: Int32 = high(x)
        let lx: Int32 = low(x)
        var k: Int32 = 0
        if hx < 0x0010_0000 { // x < 2^-1022
            if (hx & 0x7FFF_FFFF) | lx == 0 {
                return -two54 / 0.0 // log(±0) = -∞
            }
            if hx < 0 {
                return (x - x) / 0.0 // log(negative) = NaN
            }
            k -= 54
            x *= two54 // subnormal: scale up
            hx = high(x)
        }
        if hx >= 0x7FF0_0000 {
            return x + x
        }
        k += (hx >> 20) - 1023
        hx &= 0x000F_FFFF
        var i: Int32 = (hx &+ 0x9_5F64) & 0x10_0000
        x = withHigh(x, hx | (i ^ 0x3FF0_0000)) // normalise x or x/2
        k += i >> 20
        let f: Double = x - 1.0
        let dk = Double(k)
        if (0x000F_FFFF & (2 &+ hx)) < 3 { // |f| < 2^-20
            if f == 0.0 {
                return k == 0 ? 0.0 : dk * ln2Hi + dk * ln2Lo
            }
            let r: Double = f * f * (0.5 - 0.33333333333333333 * f)
            return k == 0 ? f - r : dk * ln2Hi - ((r - dk * ln2Lo) - f)
        }
        let s: Double = f / (2.0 + f)
        let z: Double = s * s
        i = hx &- 0x6_147A
        let w: Double = z * z
        let j: Int32 = 0x6B851 &- hx
        let t1: Double = w * (lg2 + w * (lg4 + w * lg6))
        let t2: Double = z * (lg1 + w * (lg3 + w * (lg5 + w * lg7)))
        i |= j
        let r: Double = t2 + t1
        if i > 0 {
            let hfsq: Double = 0.5 * f * f
            if k == 0 {
                return f - (hfsq - s * (hfsq + r))
            }
            return dk * ln2Hi - ((hfsq - (s * (hfsq + r) + dk * ln2Lo)) - f)
        }
        if k == 0 {
            return f - s * (f - r)
        }
        return dk * ln2Hi - ((s * (f - r) - dk * ln2Lo) - f)
    }
}
