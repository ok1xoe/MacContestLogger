import Foundation

/// The spectrum pane's levels over time (N1MM+ Spectrum Display): the instant line (white), the decaying line (blue,
/// it falls by the decay speed and jumps up with every stronger frame), the 60-second average (the CQ frequency
/// finder) and the reference noise floor. Pure value state, fed one frame at a time with the time since the last one.
///
/// Static crash rejection (N1MM „Static Sensitivity"): a crash lifts the whole band at once, so a frame whose median
/// level stands more than `SpectrumTrace.staticLimitDb(sensitivity)` above the reference noise floor is shown as the
/// instant line but not taken into the decaying line, the average or the floor. A broadband change that lasts
/// (`maxStaticFrames` frames in a row: another band, the AGC) is accepted and the floor follows it.
public struct SpectrumTrace: Equatable, Sendable {

    /// The average's time constant (N1MM: the CQ finder's 60 s decay).
    public static let averageSeconds = 60.0
    /// The reference noise floor's time constant.
    public static let floorSeconds = 2.0
    /// Frames of static in a row after which the level change is taken as real.
    public static let maxStaticFrames = 12

    /// The last frame's axis: its start and step (no levels) and its bin count.
    public private(set) var axis: SpectrumFrame?
    public private(set) var axisCount = 0
    public private(set) var instant: [Double] = []
    public private(set) var decayed: [Double] = []
    public private(set) var average: [Double] = []
    /// The reference noise floor (the smoothed median level), `nil` before the first frame.
    public private(set) var floorDb: Double?
    /// The last frame was a static crash (N1MM lights the „Static Sensitivity" label).
    public private(set) var isStatic = false
    /// Frames since the axis last changed (the average is meaningful after a while).
    public private(set) var frames = 0
    private var staticRun = 0

    public init() {}

    /// How far above the noise floor a frame's median may jump before it counts as static: sensitivity 0 = off,
    /// 1 → 40 dB … 100 → 3 dB.
    public static func staticLimitDb(sensitivity: Int) -> Double? {
        guard sensitivity > 0 else { return nil }
        let s: Double = Double(Swift.min(100, sensitivity))
        return 40 - (s - 1) * 37 / 99
    }

    /// Clears everything (a new source, the smearing option on a frequency change).
    public mutating func reset() {
        self = SpectrumTrace()
    }

    /// Adds a frame `seconds` after the previous one. A frame on other bins (another count, or another frequency
    /// when `resetOnRetune`) starts the trace over; the average always starts over on another axis.
    public mutating func add(_ frame: SpectrumFrame, seconds: Double, decayDbPerSecond: Double,
                             staticSensitivity: Int, resetOnRetune: Bool) {
        guard frame.count > 0 else { return }
        if let axis, axisCount != frame.count || axis.startHz != frame.startHz || axis.stepHz != frame.stepHz {
            if axisCount != frame.count || resetOnRetune {
                let keepFloor: Double? = floorDb
                reset()
                floorDb = keepFloor
            } else {
                average = frame.levelsDb
                frames = 0
            }
        }
        axis = SpectrumFrame(startHz: frame.startHz, stepHz: frame.stepHz, levelsDb: [])
        axisCount = frame.count
        instant = frame.levelsDb
        let median: Double = Self.median(frame.levelsDb)
        guard let floor = floorDb, !decayed.isEmpty else {
            decayed = frame.levelsDb
            average = frame.levelsDb
            floorDb = median
            isStatic = false
            frames = 1
            return
        }
        let dt: Double = Swift.max(0, seconds)
        if let limit = Self.staticLimitDb(sensitivity: staticSensitivity), median - floor > limit,
           staticRun < Self.maxStaticFrames {
            staticRun += 1
            isStatic = true
            return
        }
        if staticRun >= Self.maxStaticFrames {
            floorDb = median
        } else {
            floorDb = floor + (median - floor) * Swift.min(1, dt / Self.floorSeconds)
        }
        staticRun = 0
        isStatic = false
        let fall: Double = decayDbPerSecond * dt
        let weight: Double = average.count == frame.count ? Swift.min(1, dt / Self.averageSeconds) : 1
        if average.count != frame.count {
            average = frame.levelsDb
        }
        for i in 0..<frame.count {
            let level: Double = frame.levelsDb[i]
            decayed[i] = Swift.max(level, decayed[i] - fall)
            average[i] += (level - average[i]) * weight
        }
        frames += 1
    }

    /// The median of the levels (the noise floor of a frame; NaN sorts last).
    public static func median(_ levels: [Double]) -> Double {
        guard !levels.isEmpty else { return 0 }
        let sorted: [Double] = levels.sorted { a, b in
            if a.isNaN { return false }
            if b.isNaN { return true }
            return a < b
        }
        return sorted[sorted.count / 2]
    }
}

/// A signal found in the spectrum: a run of bins above the threshold.
public struct SpectrumSignal: Equatable, Sendable {
    /// The level-weighted centre.
    public let centerHz: Double
    public let lowHz: Double
    public let highHz: Double
    public let peakDb: Double

    public init(centerHz: Double, lowHz: Double, highHz: Double, peakDb: Double) {
        self.centerHz = centerHz
        self.lowHz = lowHz
        self.highHz = highHz
        self.peakDb = peakDb
    }
}

/// N1MM's automatic signal detection: every run of bins at or above the threshold (the noise floor plus the
/// mouse-wheel threshold) is a signal; runs split by a single bin below it are one signal. Its centre is weighted by
/// how far each bin stands above the threshold, so a click or a jump lands on the middle of the trace.
public enum SignalDetector {

    /// N1MM „Snap to Signal" looks this far either side of the click.
    public static let snapRangeHz = 2_000.0

    /// The signals of `levels` on `axis` (start/step), ascending by frequency.
    public static func detect(levels: [Double], axis: SpectrumFrame, thresholdDb: Double) -> [SpectrumSignal] {
        var signals: [SpectrumSignal] = []
        var i = 0
        let n: Int = levels.count
        while i < n {
            guard levels[i] >= thresholdDb else {
                i += 1
                continue
            }
            var end: Int = i
            var j: Int = i + 1
            while j < n {
                if levels[j] >= thresholdDb {
                    end = j
                    j += 1
                } else if j + 1 < n && levels[j + 1] >= thresholdDb {
                    j += 1
                } else {
                    break
                }
            }
            var weightSum = 0.0
            var binSum = 0.0
            var peak: Double = -Double.infinity
            for k in i...end {
                let w: Double = Swift.max(0, levels[k] - thresholdDb) + 0.1
                weightSum += w
                binSum += w * Double(k)
                peak = Swift.max(peak, levels[k])
            }
            let center: Double = axis.hz(atBin: binSum / weightSum)
            let a: Double = axis.hz(atBin: Double(i))
            let b: Double = axis.hz(atBin: Double(end))
            signals.append(SpectrumSignal(centerHz: center, lowHz: Swift.min(a, b), highHz: Swift.max(a, b),
                                          peakDb: peak))
            i = end + 1
        }
        return signals.sorted { $0.centerHz < $1.centerHz }
    }

    /// N1MM „Snap to Signal": the centre of the signal nearest to `hz` within `withinHz`, otherwise `nil`.
    public static func snap(_ hz: Double, signals: [SpectrumSignal], withinHz: Double = snapRangeHz) -> Double? {
        var best: Double?
        for signal in signals where Swift.abs(signal.centerHz - hz) <= withinHz {
            if let current = best, Swift.abs(current - hz) <= Swift.abs(signal.centerHz - hz) {
                continue
            }
            best = signal.centerHz
        }
        return best
    }
}
