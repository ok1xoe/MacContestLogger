import Foundation

/// The options of the built-in RTTY modem (Swift-only `AppConfig.builtinModemSetup`), kept as a string map like the
/// SO2R setup: a missing key is the default, a value equal to the default is not stored, an unreadable value reads as
/// the default.
public struct BuiltinModemSetup: Equatable, Sendable {

    public enum Key: String, CaseIterable, Sendable {
        /// The two receivers (DI1 / radio 1 and DI2 / radio 2) share one tuning: a change of mark, shift, speed,
        /// AFC, NET or Rev on one is made on the other too. Off (default) = each receiver is tuned on its own.
        case linkedTuning
        /// PTT over CAT (the rig of the transmitting side); off = VOX / the rig keys itself on the audio.
        case pttViaCat
        /// The sound output of radio 1's transmit audio (AFSK; empty = the system default).
        case outputDevice
        /// The sound output of radio 2's transmit audio (SO2R; empty = radio 1's output).
        case outputDevice2
        /// The transmit audio level in percent (1…100).
        case outputLevel
        /// The audio input receiver 1 / 2 decodes (`Input`): radio 1's input (Settings → Audio) or radio 2's own.
        case input1
        case input2
        /// The channel of that input receiver 1 / 2 decodes (`Channel`). The usual setup is one stereo sound card
        /// input: left = radio 1, right = radio 2 (the defaults).
        case channel1
        case channel2
    }

    /// The audio input of a receiver.
    public enum Input: String, CaseIterable, Sendable {
        case radio1, radio2
    }

    /// The channel of a stereo input a receiver decodes.
    public enum Channel: String, CaseIterable, Sendable {
        case left, right, mix

        /// The receiver's mono samples from a block of both channels.
        public func pick(_ left: [Double], _ right: [Double]) -> [Double] {
            switch self {
            case .left: return left
            case .right: return right
            case .mix:
                var mixed = left
                for index in mixed.indices where index < right.count {
                    mixed[index] = (left[index] + right[index]) / 2
                }
                return mixed
            }
        }
    }

    public func input(side: Int) -> Input {
        Input(rawValue: text(side == 1 ? .input2 : .input1)) ?? .radio1
    }

    public func channel(side: Int) -> Channel {
        Channel(rawValue: text(side == 1 ? .channel2 : .channel1)) ?? (side == 1 ? .right : .left)
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
        case .linkedTuning: "false"
        case .pttViaCat: "true"
        case .outputDevice, .outputDevice2: ""
        case .outputLevel: "50"
        case .input1, .input2: Input.radio1.rawValue
        case .channel1: Channel.left.rawValue
        case .channel2: Channel.right.rawValue
        }
    }

    public func text(_ key: Key) -> String {
        values[key.rawValue] ?? Self.defaultValue(key)
    }

    public func flag(_ key: Key) -> Bool {
        text(key) == "true"
    }

    /// The transmit level as a factor 0.01…1.
    public var outputLevel: Double {
        let percent: Int = Int(text(.outputLevel).trimmingCharacters(in: .whitespaces)) ?? 50
        return Double(Swift.min(100, Swift.max(1, percent))) / 100
    }

    /// The sound output of a side (radio 2 falls back to radio 1's).
    public func outputDevice(side: Int) -> String {
        if side == 1, !text(.outputDevice2).isEmpty {
            return text(.outputDevice2)
        }
        return text(.outputDevice)
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
