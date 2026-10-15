import Foundation
import os

/// What the rig is tuned to when a frame is read: the receiver audio needs it to put its bins on the band.
public struct SpectrumTuning: Equatable, Sendable {
    public let dialHz: Int64
    public let rawMode: String
    public let cwPitch: Int32

    public init(dialHz: Int64, rawMode: String, cwPitch: Int32) {
        self.dialHz = dialHz
        self.rawMode = rawMode
        self.cwPitch = cwPitch
    }
}

/// A source of spectrum lines for the spectrum display (the receiver audio, an external program over UDP). Read from
/// the display's render lane; implementations are thread-safe.
public protocol SpectrumSource: AnyObject, Sendable {
    /// The newest line with a serial that grows with every new line; `nil` before the first one.
    func latestFrame(tuning: SpectrumTuning) -> (frame: SpectrumFrame, serial: Int)?
    /// The waterfall rows, newest first, 0…1 per bin in the frame's bin order.
    func waterfallRows() -> [[Float]]
    /// The time between two lines (the decay and the averages run on it).
    var secondsPerFrame: Double { get }
}

/// The receiver audio waterfall (`Waterfall`) as a spectrum source: its newest row with the bins put on the band by
/// the rig's mode (`SpectrumFrame.audio`).
public final class AudioSpectrumSource: SpectrumSource {
    public let waterfall: Waterfall
    private let sampleRate: Double

    public init(waterfall: Waterfall, sampleRate: Double) {
        self.waterfall = waterfall
        self.sampleRate = sampleRate
    }

    public func latestFrame(tuning: SpectrumTuning) -> (frame: SpectrumFrame, serial: Int)? {
        guard let row = waterfall.latestRow(), !row.levelsDb.isEmpty else { return nil }
        let frame: SpectrumFrame = SpectrumFrame.audio(levelsDb: row.levelsDb, maxHz: waterfall.maxHz,
                                                       dialHz: tuning.dialHz, rawMode: tuning.rawMode,
                                                       cwPitch: tuning.cwPitch)
        return (frame, row.serial)
    }

    public func waterfallRows() -> [[Float]] {
        waterfall.normalizedRows()
    }

    /// A row every half FFT (50 % overlap).
    public var secondsPerFrame: Double {
        Double(Waterfall.fftSize / 2) / sampleRate
    }
}

/// One refresh of the spectrum pane: the visible bins of the instant and decaying lines, the floor, the threshold and
/// the signals found on the whole frame.
public struct SpectrumPicture: Equatable, Sendable {
    /// The frame's axis (no levels) and bin count.
    public let axis: SpectrumFrame
    public let count: Int
    /// The visible bins (zoom).
    public let window: Range<Int>
    public let instant: [Double]
    public let decayed: [Double]
    public let floorDb: Double
    /// The absolute threshold level (floor + the wheel threshold).
    public let thresholdLevelDb: Double
    public let signals: [SpectrumSignal]
    public let isStatic: Bool

    public init(axis: SpectrumFrame, count: Int, window: Range<Int>, instant: [Double], decayed: [Double],
                floorDb: Double, thresholdLevelDb: Double, signals: [SpectrumSignal], isStatic: Bool) {
        self.axis = axis
        self.count = count
        self.window = window
        self.instant = instant
        self.decayed = decayed
        self.floorDb = floorDb
        self.thresholdLevelDb = thresholdLevelDb
        self.signals = signals
        self.isStatic = isStatic
    }

    /// The frequency at a position along the frequency axis (0…1).
    public func hz(atFraction fraction: Double) -> Double {
        axis.hz(atBin: SpectrumZoom.bin(atFraction: fraction, window: window))
    }

    /// The position of a frequency along the frequency axis (0…1), `nil` when it is not shown.
    public func fraction(ofHz hz: Double) -> Double? {
        guard let bin = axis.bin(ofHz: hz) else { return nil }
        return SpectrumZoom.fraction(ofBin: bin, window: window)
    }

    /// The width of one displayed bin in Hz (N1MM's Hz per pixel box shows it).
    public var binWidthHz: Double {
        axis.binWidthHz
    }
}

/// The shared pipeline of the spectrum display: whichever source feeds it, every new line goes through the same
/// trace (decay, average, floor, static rejection) and signal detection. Thread-safe (the render lane uses it).
public final class SpectrumPipeline: Sendable {

    /// What one step needs besides the source.
    public struct Settings: Equatable, Sendable {
        public var scale: SpectrumScale
        public var decay: SpectrumDecaySpeed
        public var staticSensitivity: Int
        public var resetOnRetune: Bool
        public var zoom: Int
        /// The receive frequency the zoom centres on.
        public var rxHz: Double?

        public init(scale: SpectrumScale = SpectrumScale(), decay: SpectrumDecaySpeed = .medium,
                    staticSensitivity: Int = 0, resetOnRetune: Bool = false, zoom: Int = 1, rxHz: Double? = nil) {
            self.scale = scale
            self.decay = decay
            self.staticSensitivity = staticSensitivity
            self.resetOnRetune = resetOnRetune
            self.zoom = zoom
            self.rxHz = rxHz
        }
    }

    private struct State {
        var trace = SpectrumTrace()
        var serial: Int?
        var source: ObjectIdentifier?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    public init() {}

    /// Takes the source's newest line (once) and returns the picture to draw; `nil` before any line.
    public func step(_ source: any SpectrumSource, tuning: SpectrumTuning, settings: Settings) -> SpectrumPicture? {
        let latest: (frame: SpectrumFrame, serial: Int)? = source.latestFrame(tuning: tuning)
        let id = ObjectIdentifier(source)
        let perFrame: Double = source.secondsPerFrame
        return state.withLock { s in
            if s.source != id {
                s = State()
                s.source = id
            }
            if let latest, latest.serial != s.serial {
                let lines: Int = s.serial.map { Swift.max(1, latest.serial - $0) } ?? 1
                s.trace.add(latest.frame, seconds: Double(lines) * perFrame,
                            decayDbPerSecond: settings.decay.dbPerSecond,
                            staticSensitivity: settings.staticSensitivity, resetOnRetune: settings.resetOnRetune)
                s.serial = latest.serial
            }
            return Self.picture(s.trace, settings: settings)
        }
    }

    /// N1MM's CQ button: up to five quietest frequencies of the visible bins over the last minute (the trace's
    /// 60-second average), best first; empty before a line or when the view is narrower than `widthHz`.
    public func cqFrequencies(settings: Settings, widthHz: Double) -> [Double] {
        state.withLock { s in
            guard let picture = Self.picture(s.trace, settings: settings), let axis = s.trace.axis else { return [] }
            return CqFrequencyFinder.find(average: s.trace.average, axis: axis, window: picture.window,
                                          thresholdDb: picture.thresholdLevelDb, widthHz: widthHz)
        }
    }

    /// The newest line taken in (the whole frame, for the relay); `nil` before one.
    public func currentFrame() -> SpectrumFrame? {
        state.withLock { s in
            guard let axis = s.trace.axis, !s.trace.instant.isEmpty else { return nil }
            return SpectrumFrame(startHz: axis.startHz, stepHz: axis.stepHz, levelsDb: s.trace.instant)
        }
    }

    /// Clears the trace (a new source).
    public func reset() {
        state.withLock { $0 = State() }
    }

    static func picture(_ trace: SpectrumTrace, settings: Settings) -> SpectrumPicture? {
        guard let axis = trace.axis, let floor = trace.floorDb, !trace.instant.isEmpty else { return nil }
        let count: Int = trace.instant.count
        let center: Double? = settings.rxHz.flatMap { axis.bin(ofHz: $0) }
        let window: Range<Int> = SpectrumZoom.window(count: count, zoom: settings.zoom, centerBin: center)
        let threshold: Double = settings.scale.thresholdLevel(floorDb: floor)
        let signals: [SpectrumSignal] = SignalDetector.detect(levels: trace.decayed, axis: axis,
                                                              thresholdDb: threshold)
        return SpectrumPicture(axis: axis, count: count, window: window, instant: Array(trace.instant[window]),
                               decayed: Array(trace.decayed[window]), floorDb: floor, thresholdLevelDb: threshold,
                               signals: signals, isStatic: trace.isStatic)
    }
}
