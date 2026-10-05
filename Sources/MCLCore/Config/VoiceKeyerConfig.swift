import Foundation

/// Voice keyer (DVK) settings for phone: audio devices, PTT, directories of
/// wav files and messages F1–F12 separately for Run and S&P (like N1MM+). Mirrors
/// `VoiceKeyerConfig.java`.
///
/// Default messages match "SSB Default Messages.mc" from N1MM+, only with a slash
/// instead of a backslash.
public struct VoiceKeyerConfig: Codable, Equatable, Sendable {

    /// Number of F-keys in the set; shared also by `CwKeyerConfig` and `DigitalConfig`
    /// (in Java it is `VoiceKeyerConfig.KEYS`, which they refer to too).
    public static let keyCount = 12

    /// Default path to the letter and digit files (relative to the wav directory), like N1MM.
    public static let defaultLettersPath = "LettersFiles/{OPERATOR}"

    /// Output audio device (mixer name); empty = system default.
    public var outputDevice: String = ""
    /// Recording device for recording messages; empty = system default.
    public var inputDevice: String = ""
    /// Key the transmitter via CAT (rigctld `T 1`); otherwise rely on VOX.
    public var pttViaCat: Bool = true
    /// Delay between PTT and the start of audio; always clamped to `0...2000`.
    public var pttDelayMs: Int = 150 {
        didSet {
            let clamped = VoiceKeyerConfig.clampPttDelay(pttDelayMs)
            if clamped != pttDelayMs { pttDelayMs = clamped }
        }
    }
    /// Recording length safeguard; always clamped to `1...600`.
    public var maxRecordSeconds: Int = 30 {
        didSet {
            let clamped = VoiceKeyerConfig.clampMaxRecordSeconds(maxRecordSeconds)
            if clamped != maxRecordSeconds { maxRecordSeconds = clamped }
        }
    }
    /// Directory of wav files; empty = `<data>/wav`.
    public var wavDir: String = ""
    /// Path to letters and digits; empty/whitespace is replaced with `defaultLettersPath`.
    public var lettersPath: String = VoiceKeyerConfig.defaultLettersPath {
        didSet {
            let normalized = VoiceKeyerConfig.normalizedLettersPath(lettersPath)
            if normalized != lettersPath { lettersPath = normalized }
        }
    }
    /// Always exactly `keyCount` items.
    public var runMessages: [FunctionKeyMessage] = VoiceKeyerConfig.defaultRun() {
        didSet {
            let normalized = VoiceKeyerConfig.normalized(runMessages)
            if normalized != runMessages { runMessages = normalized }
        }
    }
    public var spMessages: [FunctionKeyMessage] = VoiceKeyerConfig.defaultSp() {
        didSet {
            let normalized = VoiceKeyerConfig.normalized(spMessages)
            if normalized != spMessages { spMessages = normalized }
        }
    }

    enum CodingKeys: String, CodingKey {
        case outputDevice, inputDevice, pttViaCat, pttDelayMs, maxRecordSeconds
        case wavDir, lettersPath, runMessages, spMessages
    }

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = VoiceKeyerConfig()
        outputDevice = c.value(.outputDevice, default: d.outputDevice)
        inputDevice = c.value(.inputDevice, default: d.inputDevice)
        pttViaCat = c.value(.pttViaCat, default: d.pttViaCat)
        pttDelayMs = VoiceKeyerConfig.clampPttDelay(c.value(.pttDelayMs, default: d.pttDelayMs))
        maxRecordSeconds = VoiceKeyerConfig.clampMaxRecordSeconds(
            c.value(.maxRecordSeconds, default: d.maxRecordSeconds))
        wavDir = c.value(.wavDir, default: d.wavDir)
        lettersPath = VoiceKeyerConfig.normalizedLettersPath(c.value(.lettersPath, default: d.lettersPath))
        runMessages = VoiceKeyerConfig.normalized(c.value(.runMessages, default: d.runMessages))
        spMessages = VoiceKeyerConfig.normalized(c.value(.spMessages, default: d.spMessages))
    }

    private static func clampPttDelay(_ v: Int) -> Int {
        max(0, min(v, 2000))
    }

    private static func clampMaxRecordSeconds(_ v: Int) -> Int {
        max(1, min(v, 600))
    }

    private static func normalizedLettersPath(_ v: String) -> String {
        JavaText.isBlank(v) ? defaultLettersPath : v // Java `isBlank()`
    }

    /// Pads/trims the message list to exactly `keyCount` items.
    private static func normalized(_ list: [FunctionKeyMessage]) -> [FunctionKeyMessage] {
        var out = Array(list.prefix(keyCount))
        while out.count < keyCount {
            out.append(FunctionKeyMessage(label: "Spare", text: ""))
        }
        return out
    }

    public static func defaultRun() -> [FunctionKeyMessage] {
        [
            FunctionKeyMessage(label: "CQ", text: "{OPERATOR}/CQ.wav"),
            FunctionKeyMessage(label: "Exch", text: "{OPERATOR}/Exchange.wav"),
            FunctionKeyMessage(label: "TU", text: "{OPERATOR}/Thanks.wav"),
            FunctionKeyMessage(label: "{MYCALL}", text: "{OPERATOR}/Mycall.wav"),
            FunctionKeyMessage(label: "His Call", text: ""),
            FunctionKeyMessage(label: "Spare", text: ""),
            FunctionKeyMessage(label: "QRZ?", text: "{OPERATOR}/QRZ.wav"),
            FunctionKeyMessage(label: "Agn?", text: "{OPERATOR}/AllAgain.wav"),
            FunctionKeyMessage(label: "Exch?", text: "{OPERATOR}/ExchangeQuery.wav"),
            FunctionKeyMessage(label: "Spare", text: ""),
            FunctionKeyMessage(label: "Spare", text: ""),
            FunctionKeyMessage(label: "Spare", text: ""),
        ]
    }

    public static func defaultSp() -> [FunctionKeyMessage] {
        [
            FunctionKeyMessage(label: "CQ", text: "{OPERATOR}/CQ.wav"),
            FunctionKeyMessage(label: "Exch", text: "{OPERATOR}/SPExchange.wav"),
            FunctionKeyMessage(label: "Spare", text: ""),
            FunctionKeyMessage(label: "{MYCALL}", text: "{OPERATOR}/Mycall.wav"),
            FunctionKeyMessage(label: "His Call", text: ""),
            FunctionKeyMessage(label: "{MYCALL}", text: "{OPERATOR}/Mycall.wav"),
            FunctionKeyMessage(label: "Rpt Exch", text: "{OPERATOR}/RepeatExchange.wav"),
            FunctionKeyMessage(label: "Agn?", text: "{OPERATOR}/AllAgain.wav"),
            FunctionKeyMessage(label: "Spare", text: ""),
            FunctionKeyMessage(label: "Spare", text: ""),
            FunctionKeyMessage(label: "Spare", text: ""),
            FunctionKeyMessage(label: "Spare", text: ""),
        ]
    }
}
