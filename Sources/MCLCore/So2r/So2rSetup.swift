import Foundation

/// The N1MM Config → SO2R / SO2V options (Swift-only `AppConfig.so2rSetup`), kept as a string map like the spectrum
/// setup: a missing key is the default, a value equal to the default is not stored, an unreadable value reads as the
/// default. N1MM remembers these „sticky" options between runs; so does the app.
public struct So2rSetup: Equatable, Sendable {

    public enum Key: String, CaseIterable, Sendable {
        /// N1MM „Set Radio Swap Transmit Lead Time (msec)": the pause after the transmit focus moved to the other
        /// radio before it is keyed (station accessories see the change).
        case swapLeadMs
        /// N1MM „Set Radio Swap Transmit Tail Time (msec)": the pause after an interrupted transmission on one
        /// radio before the transmit focus moves to the other one.
        case swapTailMs
        /// N1MM „Set Dueling CQ Repeat Time (msec)": the pause between the end of a CQ on one radio and the start
        /// on the other.
        case duelingCqMs
        /// N1MM „Focus on Other Radio" (Ctrl+Shift+K).
        case focusOther
        /// N1MM „FocusOther Always Swap".
        case focusOtherAlwaysSwap
        /// N1MM „Toggle CTRLFx Macro" (Ctrl+Shift+L): `{CTRLFx}` sends on the other radio; off = ignored.
        case ctrlFx
        /// N1MM „Toggle Stereo/OTRSP Macro": `{STEREOON}` / `{STEREOOFF}` and `{OTRSP RX}` / `{OTRSPOTHER RX}`
        /// are performed; off = ignored.
        case stereoMacros
        /// N1MM Winkeyer „Use 2nd Output" in SO2R: radio 2 is keyed on Winkeyer's KEY OUT 2.
        case winkeyerSecondOutput
        /// N1MM „Repeating CQ Ends With VFOB Window Entry" (SO2V dual receive).
        case so2vRepeatEndsWithVfoB
        /// The audio input of radio 2 (the second CW Reader and spectrum window; empty = none chosen).
        case rx2AudioDevice
        /// N1MM SO2R DVK: the channel radio 1's / radio 2's voice messages play on (`VoiceChannel`).
        case voiceChannel1
        case voiceChannel2
    }

    /// N1MM SO2R DVK routing: both channels (as recorded), only the left or only the right one.
    public enum VoiceChannel: String, CaseIterable, Sendable {
        case both, left, right

        /// 0 = both, 1 = left, 2 = right (`SoundCard.routed`).
        public var index: Int {
            switch self {
            case .both: 0
            case .left: 1
            case .right: 2
            }
        }
    }

    /// The range of the swap and dueling times (ms).
    public static let millisRange: ClosedRange<Int> = 0...2_000

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
        case .swapLeadMs, .swapTailMs: "0"
        case .duelingCqMs: "100"
        case .focusOther, .focusOtherAlwaysSwap, .winkeyerSecondOutput, .so2vRepeatEndsWithVfoB: "false"
        case .ctrlFx, .stereoMacros: "true"
        case .rx2AudioDevice: ""
        case .voiceChannel1, .voiceChannel2: VoiceChannel.both.rawValue
        }
    }

    public func text(_ key: Key) -> String {
        values[key.rawValue] ?? Self.defaultValue(key)
    }

    public func flag(_ key: Key) -> Bool {
        text(key) == "true"
    }

    /// A time in ms clamped to `millisRange`; an unreadable value is the default.
    public func millis(_ key: Key) -> Int {
        let parsed: Int = Int(text(key).trimmingCharacters(in: .whitespaces)) ?? Int(Self.defaultValue(key)) ?? 0
        return Swift.min(Self.millisRange.upperBound, Swift.max(Self.millisRange.lowerBound, parsed))
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

    public mutating func set(_ key: Key, millis: Int) {
        set(key, String(Swift.min(Self.millisRange.upperBound, Swift.max(Self.millisRange.lowerBound, millis))))
    }

    /// A typed time: blank = the default, otherwise a whole number of ms in `millisRange`; `nil` = invalid.
    public static func parseMillis(_ text: String) -> Int? {
        let trimmed: String = text.trimmingCharacters(in: .whitespaces)
        guard let value = Int(trimmed), millisRange.contains(value) else { return nil }
        return value
    }
}
