import Foundation

/// Band conditions of the pileup simulator beyond the Java version (N1MM's MorseRunner link has QSB and QRM; MCL has
/// its own simulator): **QSB** — every caller fades slowly in and out — and **QRM** — another station calls CQ or
/// finishes a QSO near the frequency while the callers answer. Both are off by default; they never consume the
/// simulator's `PileupRandom` (the callers, their speeds and the Java-parity sequence stay exactly as they were):
/// the fading of a caller follows from its call, the QRM stations come in a fixed rotation.
public enum SimConditions {

    /// How deep a fade goes (0 = none, 1 = to silence).
    public static let qsbDepth: Double = 0.85
    /// The shortest and the longest fading period.
    public static let qsbPeriodRange: ClosedRange<Double> = 2.5...9.0
    /// The QRM station's amplitude (weaker than the weakest caller, 0.1).
    public static let qrmAmplitude: Double = 0.08
    /// The QRM station's speed.
    public static let qrmWpm: Int32 = 26

    /// A caller's fading: the period in seconds and the phase (radians), the same for the same call every time.
    public static func qsbParameters(call: String) -> (periodSeconds: Double, phase: Double) {
        let hash: UInt64 = fnv1a(call.uppercased())
        let span: Double = qsbPeriodRange.upperBound - qsbPeriodRange.lowerBound
        let period: Double = qsbPeriodRange.lowerBound + span * Double(hash % 1_000) / 999
        let phase: Double = 2 * Double.pi * Double((hash >> 20) % 1_000) / 1_000
        return (period, phase)
    }

    /// The fading gain at `seconds` (between `1 − depth` and 1).
    public static func qsbGain(seconds: Double, periodSeconds: Double, phase: Double, depth: Double = qsbDepth) -> Double {
        let wave: Double = 0.5 - 0.5 * cos(2 * Double.pi * seconds / periodSeconds + phase)
        return 1 - depth * wave
    }

    /// The samples of `call`'s signal with its fading applied (`startSeconds` = where in the fade the signal begins).
    public static func applyQsb(_ samples: [Float], call: String, sampleRate: Float, startSeconds: Double = 0,
                                depth: Double = qsbDepth) -> [Float] {
        let parameters = qsbParameters(call: call)
        let rate = Double(sampleRate)
        var out: [Float] = samples
        for index in out.indices {
            let gain: Double = qsbGain(seconds: startSeconds + Double(index) / rate,
                                       periodSeconds: parameters.periodSeconds, phase: parameters.phase, depth: depth)
            out[index] = Float(Double(out[index]) * gain)
        }
        return out
    }

    /// The interfering stations, in rotation.
    public static let qrmCalls: [String] = ["DL5QRM", "G4QRM", "I2QRM", "SP9QRM", "UA3QRM", "EA7QRM", "F5QRM", "S57QRM"]

    /// One interfering transmission: the text, its pitch offset from the CW pitch and the delay after the replies
    /// start.
    public struct Qrm: Equatable, Sendable {
        public let text: String
        public let pitchOffsetHz: Int
        public let delayMs: Int64
    }

    /// The `index`-th interfering transmission (`index` ≥ 0 counts the reply batches of a session): a CQ, a short
    /// „TU" or a report, 150–450 Hz above or below the pitch.
    public static func qrm(_ index: Int) -> Qrm {
        let n: Int = Swift.max(0, index)
        let call: String = qrmCalls[n % qrmCalls.count]
        let texts: [String] = ["CQ TEST " + call + " " + call, "TU " + call + " TEST", "5NN " + String(100 + (n * 37) % 900)]
        let text: String = texts[n % texts.count]
        let magnitude: Int = 150 + (n * 110) % 301
        let offset: Int = n % 2 == 0 ? magnitude : -magnitude
        return Qrm(text: text, pitchOffsetHz: offset, delayMs: Int64((n * 170) % 600))
    }

    /// FNV-1a over the UTF-8 bytes (stable across runs, unlike `Hasher`).
    static func fnv1a(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }
}
