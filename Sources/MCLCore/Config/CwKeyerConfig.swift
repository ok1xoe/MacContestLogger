import Foundation

/// CW keyer settings: keying method, speed, number format and messages
/// F1–F12 separately for Run and S&P. Default messages match
/// "CW Default Messages.mc" from N1MM+. Mirrors `CwKeyerConfig.java`.
public struct CwKeyerConfig: Codable, Equatable, Sendable {

    /// Keying method.
    public enum Method: String, Codable, Equatable, Sendable {
        /// No CW keyer.
        case none = "NONE"
        /// Rig keyer over CAT (rigctld send_morse).
        case cat = "CAT"
        /// K1EL Winkeyer on a serial port.
        case winkeyer = "WINKEYER"
    }

    public static let minWpm = 5
    public static let maxWpm = 60

    public var method: Method = .cat
    public var winkeyerPort: String = ""
    /// CW speed in WPM; always clamped to `minWpm...maxWpm`.
    public var speed: Int = 28 {
        didSet {
            let clamped = CwKeyerConfig.clamp(speed)
            if clamped != speed { speed = clamped }
        }
    }
    public var cutNumbers: Bool = false
    public var leadingZeros: Bool = false
    public var cutStyle: CutStyle = .tn
    /// Always exactly `VoiceKeyerConfig.keyCount` items.
    public var runMessages: [FunctionKeyMessage] = CwKeyerConfig.defaultRun() {
        didSet {
            let normalized = CwKeyerConfig.normalized(runMessages)
            if normalized != runMessages { runMessages = normalized }
        }
    }
    public var spMessages: [FunctionKeyMessage] = CwKeyerConfig.defaultSp() {
        didSet {
            let normalized = CwKeyerConfig.normalized(spMessages)
            if normalized != spMessages { spMessages = normalized }
        }
    }

    enum CodingKeys: String, CodingKey {
        case method, winkeyerPort, speed, cutNumbers, leadingZeros, cutStyle, runMessages, spMessages
    }

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = CwKeyerConfig()
        method = c.value(.method, default: d.method)
        winkeyerPort = c.value(.winkeyerPort, default: d.winkeyerPort)
        speed = CwKeyerConfig.clamp(c.value(.speed, default: d.speed))
        cutNumbers = c.value(.cutNumbers, default: d.cutNumbers)
        leadingZeros = c.value(.leadingZeros, default: d.leadingZeros)
        cutStyle = c.value(.cutStyle, default: d.cutStyle)
        runMessages = CwKeyerConfig.normalized(c.value(.runMessages, default: d.runMessages))
        spMessages = CwKeyerConfig.normalized(c.value(.spMessages, default: d.spMessages))
    }

    /// Clamps the speed to the range `minWpm...maxWpm`.
    public static func clamp(_ wpm: Int) -> Int {
        max(minWpm, min(maxWpm, wpm))
    }

    /// Pads/trims the message list to exactly `VoiceKeyerConfig.keyCount` items.
    private static func normalized(_ list: [FunctionKeyMessage]) -> [FunctionKeyMessage] {
        var out = Array(list.prefix(VoiceKeyerConfig.keyCount))
        while out.count < VoiceKeyerConfig.keyCount {
            out.append(FunctionKeyMessage(label: "Empty", text: ""))
        }
        return out
    }

    public static func defaultRun() -> [FunctionKeyMessage] {
        [
            FunctionKeyMessage(label: "Cq", text: "cq test {MYCALL} {MYCALL} test"),
            FunctionKeyMessage(label: "Exch", text: "{SENTRSTCUT} {EXCH}"),
            FunctionKeyMessage(label: "Tu", text: "tu {MYCALL} test"),
            FunctionKeyMessage(label: "{MYCALL}", text: "{MYCALL}"),
            FunctionKeyMessage(label: "His Call", text: "!"),
            FunctionKeyMessage(label: "Repeat", text: "{SENTRSTCUT} {EXCH} {EXCH}"),
            FunctionKeyMessage(label: "Empty", text: ""),
            FunctionKeyMessage(label: "Agn?", text: "agn?"),
            FunctionKeyMessage(label: "Nr?", text: "nr?"),
            FunctionKeyMessage(label: "Call?", text: "cl?"),
            FunctionKeyMessage(label: "Empty", text: ""),
            FunctionKeyMessage(label: "Wipe", text: "{WIPE}"),
        ]
    }

    public static func defaultSp() -> [FunctionKeyMessage] {
        [
            FunctionKeyMessage(label: "Qrl?", text: "qrl? de {MYCALL}"),
            FunctionKeyMessage(label: "Exch", text: "{SENTRSTCUT} {EXCH}"),
            FunctionKeyMessage(label: "Tu", text: "tu"),
            FunctionKeyMessage(label: "{MYCALL}", text: "{MYCALL}"),
            FunctionKeyMessage(label: "His Call", text: "!"),
            FunctionKeyMessage(label: "Repeat", text: "{SENTRSTCUT} {EXCH} {EXCH}"),
            FunctionKeyMessage(label: "Empty", text: ""),
            FunctionKeyMessage(label: "Agn?", text: "agn?"),
            FunctionKeyMessage(label: "Nr?", text: "nr?"),
            FunctionKeyMessage(label: "Call?", text: "cl?"),
            FunctionKeyMessage(label: "Empty", text: ""),
            FunctionKeyMessage(label: "Wipe", text: "{WIPE}"),
        ]
    }
}
