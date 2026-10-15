import Foundation

/// A spot as the spectrum display sees it (N1MM: telnet and local spots over the spectrum).
public struct SpectrumSpot: Equatable, Sendable {
    public let call: String
    public let freqHz: Double
    /// Worked on this band and mode.
    public let dupe: Bool
    /// A new multiplier.
    public let mult: Bool
    /// A Mark (Alt+M): the operator marked the frequency as busy or not workable.
    public let nonWorkable: Bool
    /// An `@frequency` spot this display made itself for an unknown signal.
    public let generated: Bool

    public init(call: String, freqHz: Double, dupe: Bool = false, mult: Bool = false, nonWorkable: Bool = false,
                generated: Bool = false) {
        self.call = call
        self.freqHz = freqHz
        self.dupe = dupe
        self.mult = mult
        self.nonWorkable = nonWorkable
        self.generated = generated
    }
}

/// N1MM „Show red signal markers": which detected signals get a marker (and which Shift+Up/Down stops on).
public enum SpectrumMarkerFilter: String, CaseIterable, Sendable {
    /// Every signal.
    case all
    /// Not within the tuning tolerance of a dupe or a non-workable (marked) spot.
    case nonDupes
    /// Only signals no spot covers (heard before the RBN spots them).
    case unknown
    /// Only signals with a new multiplier spot on them.
    case mults
}

/// A spot label over the spectrum.
public struct SpectrumOverlaySpot: Equatable, Sendable {
    public let spot: SpectrumSpot
    /// A detected signal lies within the tuning tolerance.
    public let heard: Bool
    /// The receive frequency is on the spot (N1MM frames it).
    public let tuned: Bool
}

/// The signal logic of N1MM+'s Spectrum Display over the detected signals and the spots: markers and their filter,
/// Shift+Up/Down to the next signal (skipping dupes and non-workables), the spots over the spectrum and the
/// `@frequency` spots of unknown signals. Pure.
public enum SpectrumSignals {

    /// The spotter of the `@frequency` spots the display makes.
    public static let unknownSpotter = "SPECTRUM"
    /// How long an `@frequency` spot stays without the signal being seen again.
    public static let unknownSpotSeconds = 90.0
    /// At most this many `@frequency` spots at once.
    public static let maxUnknownSpots = 40

    /// The spots within `toleranceHz` of a signal (of its centre, or inside its extent).
    public static func spots(near signal: SpectrumSignal, in spots: [SpectrumSpot], toleranceHz: Double)
        -> [SpectrumSpot] {
        spots.filter { spot in
            Swift.abs(spot.freqHz - signal.centerHz) <= toleranceHz
                || (spot.freqHz >= signal.lowHz && spot.freqHz <= signal.highHz)
        }
    }

    /// No spot (other than the display's own `@frequency` ones) covers the signal.
    public static func isUnknown(_ signal: SpectrumSignal, spots: [SpectrumSpot], toleranceHz: Double) -> Bool {
        Self.spots(near: signal, in: spots, toleranceHz: toleranceHz).allSatisfy(\.generated)
    }

    /// A dupe or a non-workable spot covers the signal (N1MM: Shift+Up/Down skips it).
    public static func isSkipped(_ signal: SpectrumSignal, spots: [SpectrumSpot], toleranceHz: Double) -> Bool {
        Self.spots(near: signal, in: spots, toleranceHz: toleranceHz).contains { $0.dupe || $0.nonWorkable }
    }

    /// The signals that get a red marker under `filter`.
    public static func markers(_ signals: [SpectrumSignal], spots: [SpectrumSpot], filter: SpectrumMarkerFilter,
                               toleranceHz: Double) -> [SpectrumSignal] {
        switch filter {
        case .all:
            return signals
        case .nonDupes:
            return signals.filter { !isSkipped($0, spots: spots, toleranceHz: toleranceHz) }
        case .unknown:
            return signals.filter { isUnknown($0, spots: spots, toleranceHz: toleranceHz) }
        case .mults:
            return signals.filter { signal in
                Self.spots(near: signal, in: spots, toleranceHz: toleranceHz).contains { $0.mult && !$0.dupe }
            }
        }
    }

    /// Shift+Up (`direction` +1, higher) / Shift+Down (−1): the centre of the nearest frequency in `targets` beyond
    /// `fromHz` by more than `minStepHz` (so the jump leaves the signal it is on); `nil` at the edge.
    public static func next(from fromHz: Double, direction: Int, targets: [Double], minStepHz: Double) -> Double? {
        if direction > 0 {
            return targets.filter { $0 > fromHz + minStepHz }.min()
        }
        return targets.filter { $0 < fromHz - minStepHz }.max()
    }

    /// The signals Shift+Up/Down stops on: the markers of `filter` without the dupes and non-workables.
    public static func jumpTargets(_ signals: [SpectrumSignal], spots: [SpectrumSpot], filter: SpectrumMarkerFilter,
                                   toleranceHz: Double) -> [Double] {
        markers(signals, spots: spots, filter: filter, toleranceHz: toleranceHz)
            .filter { !isSkipped($0, spots: spots, toleranceHz: toleranceHz) }
            .map(\.centerHz)
    }

    /// The spot labels between `lowHz` and `highHz` (N1MM „Show only spots you can hear" keeps those with a signal
    /// within the tolerance); the display's own `@frequency` spots are not drawn (their signals carry a marker).
    public static func overlay(_ spots: [SpectrumSpot], signals: [SpectrumSignal], lowHz: Double, highHz: Double,
                               onlyHeard: Bool, toleranceHz: Double, tunedHz: Double) -> [SpectrumOverlaySpot] {
        var out: [SpectrumOverlaySpot] = []
        for spot in spots where !spot.generated && spot.freqHz >= lowHz && spot.freqHz <= highHz {
            let heard: Bool = signals.contains { signal in
                Swift.abs(signal.centerHz - spot.freqHz) <= toleranceHz
                    || (spot.freqHz >= signal.lowHz && spot.freqHz <= signal.highHz)
            }
            if onlyHeard && !heard {
                continue
            }
            let tuned: Bool = tunedHz > 0 && Swift.abs(spot.freqHz - tunedHz) <= toleranceHz
            out.append(SpectrumOverlaySpot(spot: spot, heard: heard, tuned: tuned))
        }
        return out.sorted { $0.spot.freqHz < $1.spot.freqHz }
    }

    /// The `@frequency` call of an unknown signal: `@` and the kHz with one decimal (`@14025.3`).
    public static func unknownCall(_ hz: Double) -> String {
        "@" + JavaFormat.format("%.1f", .double((hz / 100).rounded() / 10))
    }

    /// The unknown signals (no spot within the tolerance) as `@frequency` calls with their frequency, at most
    /// `maxUnknownSpots` of the strongest.
    public static func unknownSpots(_ signals: [SpectrumSignal], spots: [SpectrumSpot], toleranceHz: Double)
        -> [(call: String, freqHz: Int)] {
        let unknown: [SpectrumSignal] = signals.filter { isUnknown($0, spots: spots, toleranceHz: toleranceHz) }
        let strongest: [SpectrumSignal] = unknown.sorted { $0.peakDb > $1.peakDb }.prefix(maxUnknownSpots)
            .sorted { $0.centerHz < $1.centerHz }
        var out: [(call: String, freqHz: Int)] = []
        var calls: Set<String> = []
        for signal in strongest {
            let call: String = unknownCall(signal.centerHz)
            guard calls.insert(call).inserted else { continue }
            out.append((call, Int(signal.centerHz.rounded())))
        }
        return out
    }
}

/// N1MM's CQ button: up to five frequencies with no signal above the threshold over the last minute (the 60-second
/// average), ranked 1…5 by how quiet they are, at least one CQ width apart.
public enum CqFrequencyFinder {

    /// How wide a free spot must be for a mode family (CW, phone, digital).
    public static func widthHz(cw: Bool, phone: Bool) -> Double {
        if cw { return 500 }
        if phone { return 3_000 }
        return 1_000
    }

    /// The centres (ranked best first) of up to `count` quietest windows of `widthHz` in the visible bins
    /// `window` of the averaged levels; an empty list when the window is narrower than one CQ width.
    public static func find(average: [Double], axis: SpectrumFrame, window: Range<Int>, thresholdDb: Double,
                            widthHz: Double, count: Int = 5) -> [Double] {
        let step: Double = axis.binWidthHz
        guard step > 0, !average.isEmpty, count > 0 else { return [] }
        let lo: Int = Swift.max(0, window.lowerBound)
        let hi: Int = Swift.min(average.count, window.upperBound)
        let width: Int = Swift.max(1, Int((widthHz / step).rounded(.up)))
        guard hi - lo >= width else { return [] }
        // Prefix sums of the excess over the threshold and of the level (the tie-break: the quieter window).
        var excess = [Double](repeating: 0, count: hi - lo + 1)
        var level = [Double](repeating: 0, count: hi - lo + 1)
        for i in lo..<hi {
            excess[i - lo + 1] = excess[i - lo] + Swift.max(0, average[i] - thresholdDb)
            level[i - lo + 1] = level[i - lo] + average[i]
        }
        var windows: [(start: Int, excess: Double, level: Double)] = []
        for start in lo...(hi - width) {
            let a: Int = start - lo
            windows.append((start, excess[a + width] - excess[a], level[a + width] - level[a]))
        }
        windows.sort { x, y in
            if x.excess != y.excess { return x.excess < y.excess }
            if x.level != y.level { return x.level < y.level }
            return x.start < y.start
        }
        var chosen: [Int] = []
        for candidate in windows {
            // Only free windows: no bin of the minute's average above the threshold.
            if chosen.count >= count || candidate.excess > 0 { break }
            if chosen.allSatisfy({ Swift.abs($0 - candidate.start) >= width }) {
                chosen.append(candidate.start)
            }
        }
        return chosen.map { axis.hz(atBin: Double($0) + Double(width - 1) / 2) }
    }
}
