import Foundation

/// One spectrum line from any source (the receiver audio, an external program over UDP): levels in dB per bin and
/// the frequency of each bin on the band. Bin `i` is at `startHz + i × stepHz`; `stepHz` is negative when the source
/// runs downwards in frequency (the receiver audio in LSB, CW-R and RTTY), so the display keeps the source's bin order
/// and every frequency question goes through `hz(atBin:)` / `bin(ofHz:)`.
public struct SpectrumFrame: Equatable, Sendable {
    public let startHz: Double
    public let stepHz: Double
    public let levelsDb: [Double]

    public init(startHz: Double, stepHz: Double, levelsDb: [Double]) {
        self.startHz = startHz
        self.stepHz = stepHz
        self.levelsDb = levelsDb
    }

    public var count: Int {
        levelsDb.count
    }

    /// The width of one bin in Hz.
    public var binWidthHz: Double {
        Swift.abs(stepHz)
    }

    /// The frequency of a (fractional) bin.
    public func hz(atBin bin: Double) -> Double {
        startHz + bin * stepHz
    }

    /// The (fractional) bin of a frequency; `nil` with a zero step.
    public func bin(ofHz hz: Double) -> Double? {
        guard stepHz != 0, stepHz.isFinite else { return nil }
        return (hz - startHz) / stepHz
    }

    /// The bin of a frequency when it lies on the frame (−0.5 … count − 0.5), otherwise `nil`.
    public func binInside(_ hz: Double) -> Int? {
        guard let bin = bin(ofHz: hz), bin >= -0.5, bin < Double(count) - 0.5 else { return nil }
        return Swift.min(count - 1, Swift.max(0, Int(bin.rounded())))
    }

    /// The lowest and highest frequency covered.
    public var lowHz: Double {
        Swift.min(hz(atBin: 0), hz(atBin: Double(Swift.max(0, count - 1))))
    }

    public var highHz: Double {
        Swift.max(hz(atBin: 0), hz(atBin: Double(Swift.max(0, count - 1))))
    }

    /// Same bins on the same frequencies (the decaying trace can go on).
    public func sameAxis(as other: SpectrumFrame) -> Bool {
        count == other.count && startHz == other.startHz && stepHz == other.stepHz
    }

    /// A line of the receiver audio waterfall (`Waterfall`, bin `i` at `i × maxHz / count` of audio) as frequencies
    /// on the band by the rig's mode (`AudioToRf`): in CW the CW pitch sits on the dial frequency, LSB, CW-R and RTTY
    /// run downwards. Without a dial frequency the bins are audio frequencies.
    public static func audio(levelsDb: [Double], maxHz: Double, dialHz: Int64, rawMode: String, cwPitch: Int32)
        -> SpectrumFrame {
        let count: Int = levelsDb.count
        let audioStep: Double = count > 0 ? maxHz / Double(count) : 0
        guard dialHz > 0 else {
            return SpectrumFrame(startHz: 0, stepHz: audioStep, levelsDb: levelsDb)
        }
        let base: Int64 = AudioToRf.rfHz(dialHz: dialHz, rawMode: rawMode, audioHz: 0, cwPitch: cwPitch)
        let probe: Int64 = AudioToRf.rfHz(dialHz: dialHz, rawMode: rawMode, audioHz: 1_000, cwPitch: cwPitch)
        let direction: Double = probe >= base ? 1 : -1
        return SpectrumFrame(startHz: Double(base), stepHz: direction * audioStep, levelsDb: levelsDb)
    }
}

/// The level axis of the spectrum pane (N1MM's mouse wheel): the signal threshold above the noise floor (the blue
/// dashed line), the reference offset and the displayed dB range. The bottom of the pane is 10 dB under the noise
/// floor shifted by the reference; the top is `rangeDb` above it.
public struct SpectrumScale: Equatable, Sendable {
    public static let defaultThresholdDb = 10
    public static let defaultRangeDb = 60
    public static let thresholdRange: ClosedRange<Int> = 1...60
    public static let refRange: ClosedRange<Int> = -60...60
    public static let rangeRange: ClosedRange<Int> = 20...120

    public var thresholdDb: Double
    public var refDb: Double
    public var rangeDb: Double

    public init(thresholdDb: Double = Double(defaultThresholdDb), refDb: Double = 0,
                rangeDb: Double = Double(defaultRangeDb)) {
        self.thresholdDb = thresholdDb
        self.refDb = refDb
        self.rangeDb = rangeDb
    }

    /// What the mouse wheel moves.
    public enum WheelTarget: Equatable, Sendable {
        /// Plain wheel: the signal threshold (N1MM noise floor line).
        case threshold
        /// Cmd + wheel (N1MM Ctrl): the reference level.
        case reference
        /// Cmd+Shift + wheel (N1MM Ctrl+Shift): the dB range.
        case range
    }

    /// One wheel notch (`steps` > 0 = up): the threshold and the reference by 1 dB, the range by 5 dB, clamped.
    public func wheel(_ steps: Int, _ target: WheelTarget) -> SpectrumScale {
        var next: SpectrumScale = self
        switch target {
        case .threshold:
            next.thresholdDb = Self.clamp(thresholdDb + Double(steps), Self.thresholdRange)
        case .reference:
            next.refDb = Self.clamp(refDb + Double(steps), Self.refRange)
        case .range:
            next.rangeDb = Self.clamp(rangeDb - Double(steps) * 5, Self.rangeRange)
        }
        return next
    }

    /// The absolute level of the threshold line over a noise floor.
    public func thresholdLevel(floorDb: Double) -> Double {
        floorDb + thresholdDb
    }

    /// The bottom of the pane in dB.
    public func bottomDb(floorDb: Double) -> Double {
        floorDb - 10 - refDb
    }

    /// A level as a fraction of the pane's height (0 = bottom, 1 = top), clamped.
    public func fraction(_ db: Double, floorDb: Double) -> Double {
        guard rangeDb > 0, db.isFinite else { return 0 }
        let value: Double = (db - bottomDb(floorDb: floorDb)) / rangeDb
        return Swift.min(1, Swift.max(0, value))
    }

    private static func clamp(_ value: Double, _ range: ClosedRange<Int>) -> Double {
        Swift.min(Double(range.upperBound), Swift.max(Double(range.lowerBound), value))
    }
}

/// Zoom of the spectrum (N1MM +/-): which bins of a frame are shown. The window keeps `count / zoom` bins centred on
/// the receive frequency when it lies on the frame (otherwise on the frame's centre) and is pushed back inside at the
/// edges.
public enum SpectrumZoom {

    public static let levels: [Int] = [1, 2, 4, 8, 16]

    /// The next zoom level in (`+`) or out (`-`), staying within `levels`.
    public static func step(_ zoom: Int, by direction: Int) -> Int {
        let index: Int = levels.firstIndex(of: zoom) ?? 0
        let next: Int = Swift.min(levels.count - 1, Swift.max(0, index + direction))
        return levels[next]
    }

    /// The visible bins (`lo..<hi`) of a frame of `count` bins.
    public static func window(count: Int, zoom: Int, centerBin: Double?) -> Range<Int> {
        guard count > 0 else { return 0..<0 }
        let width: Int = Swift.max(Swift.min(count, 8), count / Swift.max(1, zoom))
        if width >= count {
            return 0..<count
        }
        let center: Double = centerBin.flatMap { $0 >= 0 && $0 <= Double(count - 1) ? $0 : nil }
            ?? Double(count - 1) / 2
        var lo: Int = Int((center - Double(width) / 2).rounded())
        lo = Swift.min(count - width, Swift.max(0, lo))
        return lo..<(lo + width)
    }

    /// The (fractional) bin at a position along the frequency axis (0…1) of the visible window (bin `i` starts at
    /// `i / count`, as the waterfall image maps its pixels).
    public static func bin(atFraction fraction: Double, window: Range<Int>) -> Double {
        Double(window.lowerBound) + fraction * Double(window.count)
    }

    /// The position along the frequency axis (0…1) of a bin in the visible window (`nil` outside).
    public static func fraction(ofBin bin: Double, window: Range<Int>) -> Double? {
        guard !window.isEmpty else { return nil }
        let value: Double = (bin - Double(window.lowerBound)) / Double(window.count)
        return value >= 0 && value <= 1 ? value : nil
    }
}
