import Foundation

/// CW tone synthesis (Java `sim/CwSynth`): text → samples with soft edges (5 ms) so the tone does not click.
///
/// The dot and ramp length is computed in **`float`** as in Java (`Math.round(rate * 1.2f / max(5, wpm))`,
/// `JavaMath.round(Float)`). Samples go through Darwin libm `sin`/`cos`, which differ from the HotSpot intrinsics
/// by a few `double` ulps (a deliberate divergence from Java v1.1.1) → after conversion to `float` by at most 1 `float` ulp;
/// keying, length and envelope (which samples are zero) are exactly as in Java.
public enum CwSynth {

    /// Java `MORSE` table (key = UTF-16 unit, `char`).
    private static let morse: [UInt16: String] = {
        let pairs: [(Character, String)] = [
            ("A", ".-"), ("B", "-..."), ("C", "-.-."), ("D", "-.."), ("E", "."), ("F", "..-."), ("G", "--."),
            ("H", "...."), ("I", ".."), ("J", ".---"), ("K", "-.-"), ("L", ".-.."), ("M", "--"), ("N", "-."),
            ("O", "---"), ("P", ".--."), ("Q", "--.-"), ("R", ".-."), ("S", "..."), ("T", "-"), ("U", "..-"),
            ("V", "...-"), ("W", ".--"), ("X", "-..-"), ("Y", "-.--"), ("Z", "--.."),
            ("0", "-----"), ("1", ".----"), ("2", "..---"), ("3", "...--"), ("4", "....-"), ("5", "....."),
            ("6", "-...."), ("7", "--..."), ("8", "---.."), ("9", "----."),
            ("/", "-..-."), ("?", "..--.."), (".", ".-.-.-"), (",", "--..--"), ("=", "-...-"), ("+", ".-.-."),
        ]
        var map: [UInt16: String] = [:]
        for (char, code) in pairs {
            if let unit = char.utf16.first {
                map[unit] = code
            }
        }
        return map
    }()

    /// Keying envelope: `true` = tone, per sample (dot = 1200/wpm ms). Text via Java `toUpperCase()`
    /// (no locale — `ß` → `SS`); characters outside the table are skipped, a space = 4 units of silence (+ 3 after a character = 7).
    ///
    /// The length is `units × dot` in `Int` — Java multiplies it in `int` and above 2^31 samples throws
    /// (`NegativeArraySizeException`); unreachable from the UI (`SimAudioPlayer.sampleRate` is a fixed 12 kHz).
    static func keying(_ text: String, wpm: Int32, sampleRate: Float) -> [Bool] {
        let speed = Float(Swift.max(5, wpm))
        let dit: Int = Int(Swift.max(1, JavaMath.round(sampleRate * Float(1.2) / speed)))
        var units: [Bool] = []
        for c in JavaText.toUpperCase(text).utf16 {
            if c == 0x20 {
                units.append(contentsOf: [false, false, false, false]) // + 3 after a character = 7
                continue
            }
            guard let code = morse[c] else {
                continue
            }
            let count: Int = code.utf8.count
            for (k, symbol) in code.utf8.enumerated() {
                if symbol == UInt8(ascii: ".") {
                    units.append(true)
                } else {
                    units.append(contentsOf: [true, true, true])
                }
                if k < count - 1 {
                    units.append(false)
                } else {
                    units.append(contentsOf: [false, false, false])
                }
            }
        }
        var out = [Bool](repeating: false, count: units.count * dit)
        for (u, on) in units.enumerated() where on {
            for i in (u * dit)..<((u + 1) * dit) {
                out[i] = true
            }
        }
        return out
    }

    /// Samples of a CW message (amplitude 0–1).
    public static func render(_ text: String, wpm: Int32, pitchHz: Double, amplitude: Double,
                              sampleRate: Float) -> [Float] {
        let key: [Bool] = keying(text, wpm: wpm, sampleRate: sampleRate)
        var out = [Float](repeating: 0, count: key.count)
        let ramp: Int32 = Swift.max(1, JavaMath.round(sampleRate * Float(0.005)))
        var env = 0.0
        let step: Double = 1.0 / Double(ramp)
        let rate = Double(sampleRate)
        let omega: Double = 2 * Double.pi * pitchHz
        for i in 0..<key.count {
            env = key[i] ? JavaMath.min(1, env + step) : JavaMath.max(0, env - step)
            let shaped: Double = 0.5 - 0.5 * cos(Double.pi * env)
            let phase: Double = omega * Double(i) / rate
            out[i] = Float(amplitude * shaped * sin(phase))
        }
        return out
    }
}
