import Foundation

/// Radix-2 FFT for the spectrum and waterfall (Java `audio/Fft`): `magnitudesDb` returns the levels of the frequency
/// bins in dB (0 … fs/2) after a Hann window.
///
/// Same order of operations as Java; `cos`/`sin`/`hypot`/`log10` however come from Darwin libm, not HotSpot,
/// so results may differ by a few ulps (dB with a tolerance, peak positions
/// and decoded text exactly).
public enum Fft {

    /// A length that is not a power of two (Java `IllegalArgumentException`).
    public struct InvalidLength: Error, Equatable, Sendable, CustomStringConvertible {
        public let length: Int
        public var description: String { "Délka FFT musí být mocnina dvou: \(length)" }
    }

    /// Bin levels 0 … n/2−1 in dB (n = input length, must be a power of two; length 1 returns an empty array).
    public static func magnitudesDb(_ samples: [Double]) throws(InvalidLength) -> [Double] {
        let n = samples.count
        if n == 0 || (n & (n - 1)) != 0 {
            throw InvalidLength(length: n)
        }
        var re = [Double](repeating: 0, count: n)
        var im = [Double](repeating: 0, count: n)
        let denominator = Double(n - 1)
        for i in 0..<n {
            let w: Double = 0.5 - 0.5 * cos(2 * Double.pi * Double(i) / denominator) // Hann
            re[i] = samples[i] * w
        }
        transform(&re, &im)
        let half = n / 2
        var out = [Double](repeating: 0, count: half)
        let quarter = Double(n) / 4.0
        for i in 0..<half {
            let mag = hypot(re[i], im[i]) / quarter
            out[i] = 20 * log10(JavaMath.max(mag, 1e-9))
        }
        return out
    }

    /// Frequency of a bin in Hz.
    public static func binHz(_ bin: Int, fftSize: Int, sampleRate: Double) -> Double {
        Double(bin) * sampleRate / Double(fftSize)
    }

    private static func transform(_ re: inout [Double], _ im: inout [Double]) {
        let n = re.count
        var j = 0
        var i = 1
        while i < n {
            var bit = n >> 1
            while (j & bit) != 0 {
                j ^= bit
                bit >>= 1
            }
            j ^= bit
            if i < j {
                re.swapAt(i, j)
                im.swapAt(i, j)
            }
            i += 1
        }
        var len = 2
        while len <= n {
            let ang: Double = -2 * Double.pi / Double(len)
            let wr = cos(ang)
            let wi = sin(ang)
            var start = 0
            while start < n {
                var cr = 1.0
                var ci = 0.0
                for k in 0..<(len / 2) {
                    let a = start + k
                    let b = a + len / 2
                    let tr: Double = re[b] * cr - im[b] * ci
                    let ti: Double = re[b] * ci + im[b] * cr
                    re[b] = re[a] - tr
                    im[b] = im[a] - ti
                    re[a] += tr
                    im[a] += ti
                    let nr: Double = cr * wr - ci * wi
                    ci = cr * wi + ci * wr
                    cr = nr
                }
                start += len
            }
            len <<= 1
        }
    }
}
