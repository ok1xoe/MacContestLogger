import Foundation

/// The options of the spectrum display (N1MM+ Spectrum Display: the right-click menu and the gear dialog). Kept as a
/// string map (`AppConfig.spectrumSetup`) like the QTC setup: a missing key is the default, a value equal to the
/// default is not stored, an unreadable value reads as the default.
public struct SpectrumSetup: Equatable, Sendable {

    public enum Key: String, CaseIterable, Sendable {
        /// `auto` / `horizontal` / `vertical` (N1MM „Spectrum Orientation").
        case orientation
        /// Vertical (bar chart) mode: the low frequencies at the top (N1MM „Reverse frequency scale").
        case reverseScale
        /// Horizontal mode: the instant levels as a line, the decaying levels above the threshold filled (N1MM „Show
        /// Noise Floor as Line"); otherwise columns.
        case noiseAsLine
        /// `slow` / `medium` / `fast` (N1MM „Signal Decay Speed").
        case decaySpeed
        /// `black` / `white` / `gray` (N1MM „Toggle Background Color").
        case background
        /// The share of the window the spectrum pane takes, 20…80 % (the rest is the waterfall).
        case sizeFactor
        /// Clear the spectrum when the frequency changes (N1MM „Reduce spectrum smearing while tuning").
        case reduceSmearing
        /// A click jumps to the centre of the nearest signal within 2 kHz (N1MM „Snap to Signal").
        case snapToSignal
        /// The waterfall pane (N1MM „Show Waterfall").
        case showWaterfall
        /// The instant levels below the threshold (N1MM „Show Instantaneous Signal Levels").
        case showInstant
        /// The signal threshold above the noise floor in dB (the mouse wheel; the blue dashed line).
        case thresholdDb
        /// The reference level offset in dB (Cmd + mouse wheel).
        case refDb
        /// The displayed dB range (Cmd+Shift + mouse wheel).
        case rangeDb
        /// N1MM „Show red signal markers": the markers at the detected signals.
        case showMarkers
        /// Which signals get a marker and which Shift+Up/Down stops on (`SpectrumMarkerFilter`).
        case markerFilter
        /// N1MM „Show these Spots": the spots over the spectrum.
        case showSpots
        /// N1MM „Show only spots you can hear": only spots with a detected signal within the tuning tolerance.
        case onlyHeardSpots
        /// N1MM „Static Sensitivity", 0 (off) … 100.
        case staticSensitivity
        /// Unknown signals go into the band map and the Available window as `@frequency` spots (off by default).
        case unknownAsSpots
    }

    /// The stored values (non-default ones).
    public private(set) var values: [String: String]

    public init(_ values: [String: String] = [:]) {
        var kept: [String: String] = [:]
        for (raw, value) in values {
            if let key = Key(rawValue: raw), value != Self.defaultValue(key) {
                kept[raw] = value
            }
        }
        self.values = kept
    }

    public static func defaultValue(_ key: Key) -> String {
        switch key {
        case .orientation: SpectrumOrientation.auto.rawValue
        case .reverseScale, .noiseAsLine, .reduceSmearing, .onlyHeardSpots, .unknownAsSpots: "false"
        case .snapToSignal, .showWaterfall, .showInstant, .showMarkers, .showSpots: "true"
        case .markerFilter: SpectrumMarkerFilter.all.rawValue
        case .staticSensitivity: "50"
        case .decaySpeed: SpectrumDecaySpeed.medium.rawValue
        case .background: SpectrumBackground.black.rawValue
        case .sizeFactor: "40"
        case .thresholdDb: String(SpectrumScale.defaultThresholdDb)
        case .refDb: "0"
        case .rangeDb: String(SpectrumScale.defaultRangeDb)
        }
    }

    public func text(_ key: Key) -> String {
        values[key.rawValue] ?? Self.defaultValue(key)
    }

    public func flag(_ key: Key) -> Bool {
        text(key) == "true"
    }

    /// An integer setting clamped to `range`; an unreadable value is the default.
    public func number(_ key: Key, in range: ClosedRange<Int>) -> Int {
        let parsed: Int = Int(text(key).trimmingCharacters(in: .whitespaces)) ?? Int(Self.defaultValue(key)) ?? 0
        return Swift.min(range.upperBound, Swift.max(range.lowerBound, parsed))
    }

    public mutating func set(_ key: Key, _ value: String) {
        if value == Self.defaultValue(key) {
            values.removeValue(forKey: key.rawValue)
        } else {
            values[key.rawValue] = value
        }
    }

    public mutating func set(_ key: Key, flag: Bool) {
        set(key, flag ? "true" : "false")
    }

    // MARK: - typed

    public var orientation: SpectrumOrientation {
        get { SpectrumOrientation(rawValue: text(.orientation)) ?? .auto }
        set { set(.orientation, newValue.rawValue) }
    }

    public var decaySpeed: SpectrumDecaySpeed {
        get { SpectrumDecaySpeed(rawValue: text(.decaySpeed)) ?? .medium }
        set { set(.decaySpeed, newValue.rawValue) }
    }

    public var background: SpectrumBackground {
        get { SpectrumBackground(rawValue: text(.background)) ?? .black }
        set { set(.background, newValue.rawValue) }
    }

    /// The spectrum pane's share of the window, 20…80 %.
    public var sizeFactor: Int {
        get { number(.sizeFactor, in: 20...80) }
        set { set(.sizeFactor, String(Swift.min(80, Swift.max(20, newValue)))) }
    }

    public var markerFilter: SpectrumMarkerFilter {
        get { SpectrumMarkerFilter(rawValue: text(.markerFilter)) ?? .all }
        set { set(.markerFilter, newValue.rawValue) }
    }

    /// N1MM „Static Sensitivity", 0 (off) … 100.
    public var staticSensitivity: Int {
        get { number(.staticSensitivity, in: 0...100) }
        set { set(.staticSensitivity, String(Swift.min(100, Swift.max(0, newValue)))) }
    }

    /// The display scale (threshold, reference, range) as stored.
    public var scale: SpectrumScale {
        get {
            SpectrumScale(thresholdDb: Double(number(.thresholdDb, in: SpectrumScale.thresholdRange)),
                          refDb: Double(number(.refDb, in: SpectrumScale.refRange)),
                          rangeDb: Double(number(.rangeDb, in: SpectrumScale.rangeRange)))
        }
        set {
            set(.thresholdDb, String(Int(newValue.thresholdDb.rounded())))
            set(.refDb, String(Int(newValue.refDb.rounded())))
            set(.rangeDb, String(Int(newValue.rangeDb.rounded())))
        }
    }
}

/// N1MM „Spectrum Orientation": `auto` is horizontal when the window is wider than tall.
public enum SpectrumOrientation: String, CaseIterable, Sendable {
    case auto, horizontal, vertical

    /// Horizontal (frequency across) for `auto` in a window at least as wide as tall.
    public func isHorizontal(width: Double, height: Double) -> Bool {
        switch self {
        case .horizontal: true
        case .vertical: false
        case .auto: width >= height
        }
    }
}

/// N1MM „Signal Decay Speed": how fast the decaying (blue) levels fall, in dB per second.
public enum SpectrumDecaySpeed: String, CaseIterable, Sendable {
    case slow, medium, fast

    public var dbPerSecond: Double {
        switch self {
        case .slow: 6
        case .medium: 15
        case .fast: 40
        }
    }
}

/// N1MM „Toggle Background Color".
public enum SpectrumBackground: String, CaseIterable, Sendable {
    case black, white, gray
}
