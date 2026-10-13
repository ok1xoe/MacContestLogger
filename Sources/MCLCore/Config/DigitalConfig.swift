import Foundation

/// Digital modes (RTTY/PSK): where to transmit and messages F1–F12 separately for Run
/// and S&P (N1MM Digital Interface). Macros as with the CW keyer, numbers are not shortened.
/// Mirrors `DigitalConfig.java`.
public struct DigitalConfig: Codable, Equatable, Sendable {

    /// Who handles digital operation: nobody, or fldigi via XML-RPC.
    public enum Engine: String, Codable, Equatable, Sendable {
        case none = "NONE"
        case fldigi = "FLDIGI"
    }

    public var engine: Engine = .none
    /// Empty/whitespace is replaced with `"127.0.0.1"`; otherwise always trimmed.
    public var fldigiHost: String = "127.0.0.1" {
        didSet {
            let normalized = DigitalConfig.normalizedHost(fldigiHost)
            if normalized != fldigiHost { fldigiHost = normalized }
        }
    }
    /// Values `<= 0` are replaced with the default port `7362`.
    public var fldigiPort: Int = 7362 {
        didSet {
            if fldigiPort <= 0 { fldigiPort = 7362 }
        }
    }
    /// Always exactly `VoiceKeyerConfig.keyCount` items.
    public var runMessages: [FunctionKeyMessage] = DigitalConfig.defaultRun() {
        didSet {
            let normalized = DigitalConfig.normalized(runMessages)
            if normalized != runMessages { runMessages = normalized }
        }
    }
    public var spMessages: [FunctionKeyMessage] = DigitalConfig.defaultSp() {
        didSet {
            let normalized = DigitalConfig.normalized(spMessages)
            if normalized != spMessages { spMessages = normalized }
        }
    }

    /// N1MM Digital Interface → Setup → Digital Call Stacking: in Run, a click on a call while the call field holds
    /// another call stacks one of them (FIFO: the clicked call; LIFO: the call in the field) instead of replacing it.
    /// Alt+click always stacks. Swift-only key.
    public var digitalCallStacking: Bool = false

    /// N1MM AutoTRXUpdate: with the rig in USB/LSB (AFSK, PSK) the logged and spotted frequency is the dial ± fldigi's audio frequency (FSK RTTY: the dial already is the mark). Swift-only key.
    public var autoTrxUpdate: Bool = true
    /// fldigi's modem for RTTY (typing RTTY in the call field, the Op Mode default). Swift-only key.
    public var rttyModem: String = "RTTY"
    /// fldigi's modem for PSK (typing PSK in the call field). Swift-only key.
    public var pskModem: String = "BPSK31"

    /// N1MM Callsign Validity and Highlight: `GENERIC` (anything that looks like a call), `RESOURCES` (only calls found in the chosen resources) or `COMBINED` (generic, unverified calls marked yellow). Swift-only key.
    public var callValidity: String = DigitalCallValidity.combined.rawValue
    /// A call in Master.scp counts as verified. Swift-only key.
    public var validateScp: Bool = true
    /// A call in the call history file counts as verified. Swift-only key.
    public var validateCallHistory: Bool = true
    /// A spotted call (the DX cluster buffer) counts as verified. Swift-only key.
    public var validateSpotted: Bool = true
    /// A call logged in this log counts as verified. Swift-only key.
    public var validateLogged: Bool = true
    /// N1MM „Use Search routine to find Master.scp in Garbage Text": Master.scp calls inside words that are not calls. Swift-only key.
    public var scpGarbageSearch: Bool = false
    /// N1MM „Highlight Background of Text": the status colour behind the call instead of its text colour. Swift-only key.
    public var highlightBackground: Bool = false
    /// N1MM Window Scroll Type „Non Scrolling": the received text does not move while new text arrives. Swift-only key.
    public var nonScrollingRx: Bool = false
    /// N1MM „Use RX Window Callsign Pause Routines": the pointer over a call (empty call field) pauses the window. Swift-only key.
    public var pauseOnCallHover: Bool = false
    /// N1MM Hover Mode: the pointer over a call puts it into the call field. Swift-only key.
    public var hoverMode: Bool = false
    /// N1MM „Rt Click = Return NOT menu": a right click in the received text is Enter (ESM). Swift-only key.
    public var rightClickReturn: Bool = false
    /// N1MM „Send Space on Callsign Mouse Click": after a call is clicked the cursor moves on to the exchange. Swift-only key.
    public var sendSpaceOnClick: Bool = false
    /// N1MM „Display Radio Freq and not Exact Freq in DI Caption" (also `{LDIGFQ}`/`{RDIGFQ}`). Swift-only key.
    public var captionRadioFrequency: Bool = false

    enum CodingKeys: String, CodingKey {
        case engine, fldigiHost, fldigiPort, runMessages, spMessages, digitalCallStacking
        case autoTrxUpdate, rttyModem, pskModem
        case callValidity, validateScp, validateCallHistory, validateSpotted, validateLogged, scpGarbageSearch, highlightBackground, nonScrollingRx, pauseOnCallHover, hoverMode, rightClickReturn, sendSpaceOnClick, captionRadioFrequency
    }

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = DigitalConfig()
        engine = c.value(.engine, default: d.engine)
        fldigiHost = DigitalConfig.normalizedHost(c.value(.fldigiHost, default: d.fldigiHost))
        let rawPort = c.value(.fldigiPort, default: d.fldigiPort)
        fldigiPort = rawPort <= 0 ? 7362 : rawPort
        runMessages = DigitalConfig.normalized(c.value(.runMessages, default: d.runMessages))
        spMessages = DigitalConfig.normalized(c.value(.spMessages, default: d.spMessages))
        digitalCallStacking = c.value(.digitalCallStacking, default: d.digitalCallStacking)
        autoTrxUpdate = c.value(.autoTrxUpdate, default: d.autoTrxUpdate)
        rttyModem = DigitalConfig.modemName(c.value(.rttyModem, default: d.rttyModem), fallback: d.rttyModem)
        pskModem = DigitalConfig.modemName(c.value(.pskModem, default: d.pskModem), fallback: d.pskModem)
        callValidity = DigitalCallValidity.from(c.value(.callValidity, default: d.callValidity)).rawValue
        validateScp = c.value(.validateScp, default: d.validateScp)
        validateCallHistory = c.value(.validateCallHistory, default: d.validateCallHistory)
        validateSpotted = c.value(.validateSpotted, default: d.validateSpotted)
        validateLogged = c.value(.validateLogged, default: d.validateLogged)
        scpGarbageSearch = c.value(.scpGarbageSearch, default: d.scpGarbageSearch)
        highlightBackground = c.value(.highlightBackground, default: d.highlightBackground)
        nonScrollingRx = c.value(.nonScrollingRx, default: d.nonScrollingRx)
        pauseOnCallHover = c.value(.pauseOnCallHover, default: d.pauseOnCallHover)
        hoverMode = c.value(.hoverMode, default: d.hoverMode)
        rightClickReturn = c.value(.rightClickReturn, default: d.rightClickReturn)
        sendSpaceOnClick = c.value(.sendSpaceOnClick, default: d.sendSpaceOnClick)
        captionRadioFrequency = c.value(.captionRadioFrequency, default: d.captionRadioFrequency)
    }

    /// A modem name as fldigi knows it: trimmed; blank → `fallback`.
    public static func modemName(_ value: String, fallback: String) -> String {
        JavaText.isBlank(value) ? fallback : JavaText.trim(value)
    }

    /// The fldigi modem for an entry-window mode: RTTY and PSK by the configuration, `nil` for other modes.
    public func modem(for mode: Mode) -> String? {
        switch mode {
        case .rtty: rttyModem
        case .psk: pskModem
        default: nil
        }
    }

    private static func normalizedHost(_ v: String) -> String {
        // Java `isBlank() ? "127.0.0.1" : trim()` — `isBlank` by `Character.isWhitespace`, `trim` up to U+0020.
        JavaText.isBlank(v) ? "127.0.0.1" : JavaText.trim(v)
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
            FunctionKeyMessage(label: "Cq", text: "CQ TEST {MYCALL} {MYCALL} CQ"),
            FunctionKeyMessage(label: "Exch", text: "! {SENTRST} {EXCH} {EXCH} !"),
            FunctionKeyMessage(label: "Tu", text: "TU {MYCALL} TEST"),
            FunctionKeyMessage(label: "{MYCALL}", text: "{MYCALL}"),
            FunctionKeyMessage(label: "His Call", text: "!"),
            FunctionKeyMessage(label: "Repeat", text: "{EXCH} {EXCH}"),
            FunctionKeyMessage(label: "Empty", text: ""),
            FunctionKeyMessage(label: "Agn?", text: "AGN AGN"),
            FunctionKeyMessage(label: "Nr?", text: "NR? NR?"),
            FunctionKeyMessage(label: "Call?", text: "CALL? CALL?"),
            FunctionKeyMessage(label: "Empty", text: ""),
            FunctionKeyMessage(label: "Wipe", text: "{WIPE}"),
        ]
    }

    public static func defaultSp() -> [FunctionKeyMessage] {
        [
            FunctionKeyMessage(label: "Qrl?", text: "QRL? DE {MYCALL}"),
            FunctionKeyMessage(label: "Exch", text: "TU {SENTRST} {EXCH} {EXCH}"),
            FunctionKeyMessage(label: "Tu", text: "TU"),
            FunctionKeyMessage(label: "{MYCALL}", text: "{MYCALL} {MYCALL}"),
            FunctionKeyMessage(label: "His Call", text: "!"),
            FunctionKeyMessage(label: "Repeat", text: "{EXCH} {EXCH}"),
            FunctionKeyMessage(label: "Empty", text: ""),
            FunctionKeyMessage(label: "Agn?", text: "AGN AGN"),
            FunctionKeyMessage(label: "Nr?", text: "NR? NR?"),
            FunctionKeyMessage(label: "Call?", text: "CALL? CALL?"),
            FunctionKeyMessage(label: "Empty", text: ""),
            FunctionKeyMessage(label: "Wipe", text: "{WIPE}"),
        ]
    }
}
