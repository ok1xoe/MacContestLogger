import Foundation

/// The window behaviour options (Swift-only `AppConfig.windowSetup`), kept as a string map like the SO2R setup: a
/// missing key is the default, a value equal to the default is not stored, an unreadable value reads as the default.
/// Both options are off by default.
public struct WindowSetup: Equatable, Sendable {

    public enum Key: String, CaseIterable, Sendable {
        /// N1MM Config → „Grab Focus From Other Apps When Radio Is Tuned": tuning a radio with its knob brings the
        /// logger to the front.
        case grabFocusOnTune
        /// N1MM „Snap windows to edges": a window dragged near a screen edge or another of the logger's windows
        /// snaps to it.
        case snapWindows
        /// The snapping distance in points.
        case snapDistance
    }

    /// The range of the snapping distance (points).
    public static let distanceRange: ClosedRange<Int> = 2...40

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
        case .grabFocusOnTune, .snapWindows: "false"
        case .snapDistance: "12"
        }
    }

    public func text(_ key: Key) -> String {
        values[key.rawValue] ?? Self.defaultValue(key)
    }

    public func flag(_ key: Key) -> Bool {
        text(key) == "true"
    }

    /// The snapping distance clamped to `distanceRange`; an unreadable value is the default.
    public var snapDistance: Int {
        let parsed: Int = Int(text(.snapDistance).trimmingCharacters(in: .whitespaces))
            ?? Int(Self.defaultValue(.snapDistance)) ?? 12
        return Swift.min(Self.distanceRange.upperBound, Swift.max(Self.distanceRange.lowerBound, parsed))
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
}
