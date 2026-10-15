import Foundation

/// Digital modes (RTTY/PSK): where to transmit and messages F1–F12 separately for Run
/// and S&P (N1MM Digital Interface). Macros as with the CW keyer, numbers are not shortened.
/// Mirrors `DigitalConfig.java`.
public struct DigitalConfig: Codable, Equatable, Sendable {

    /// Who handles digital operation: nobody, fldigi via XML-RPC, or the built-in RTTY modem (MMTTY).
    public enum Engine: String, Codable, Equatable, Sendable {
        case none = "NONE"
        case fldigi = "FLDIGI"
        case builtin = "BUILTIN"
    }

    /// The stored `engine` (the Java values only, so profiles stay compatible with v1.1.1).
    enum StoredEngine: String, Codable, Equatable, Sendable {
        case none = "NONE"
        case fldigi = "FLDIGI"
    }

    /// The pseudo-host of the built-in modem's endpoints (port 1 = DI1's receiver, 2 = DI2's): the keyer lane hands
    /// these to the built-in modem instead of opening an XML-RPC client.
    public static let builtinHost = "builtin-modem"

    var storedEngine: StoredEngine = .none
    /// The built-in RTTY modem replaces fldigi (`engine == .builtin`); `engine` itself is then stored as `FLDIGI`, so
    /// a configuration read without this key still has a modem. Swift-only key.
    public var builtinModem: Bool = false

    public var engine: Engine {
        get {
            if builtinModem {
                return .builtin
            }
            return storedEngine == .fldigi ? .fldigi : .none
        }
        set {
            builtinModem = newValue == .builtin
            storedEngine = newValue == .none ? .none : .fldigi
        }
    }
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

    /// The Grab window's sort order (N1MM right-click → Sort Order): `LIFO` (the newest call first) or `FIFO`. Swift-only key.
    public var grabOrder: String = GrabList.Order.lifo.rawValue
    /// N1MM „Do Not add Dupes to Grab Window". Swift-only key.
    public var grabNoDupes: Bool = true
    /// N1MM „Only Grab Master.scp Calls". Swift-only key.
    public var grabOnlyScp: Bool = false
    /// N1MM „QSY will clear Grab Window" (a frequency change of more than 500 Hz). Swift-only key.
    public var grabClearOnQsy: Bool = false
    /// N1MM „Clear Grab Window On CQ" (F1 sent). Swift-only key.
    public var grabClearOnCq: Bool = false
    /// N1MM „Send Space on Using Grab": after a grab the cursor moves on to the exchange. Swift-only key.
    public var grabSendSpace: Bool = false
    /// N1MM „Add Callsign to Bandmap on Alt+G": the call in the field is stored in the bandmap (Alt+O) before a grab replaces it. Swift-only key.
    public var grabAddToBandmap: Bool = false

    /// N1MM CWID: after every digital message fldigi sends `cwIdText` in CW (its CW modem), then returns to the previous modem. Swift-only key.
    public var cwIdEnabled: Bool = false
    /// The CWID text (`*` / `{MYCALL}` = my call). Swift-only key.
    public var cwIdText: String = "DE {MYCALL}"
    /// N1MM's extra Digital Interface message buttons DI1…DI24 (`{DI1}`…`{DI24}`); always 24 items. Swift-only key.
    public var diMessages: [FunctionKeyMessage] = DigitalConfig.emptyButtons() {
        didSet {
            let normalized = DigitalConfig.buttons(diMessages)
            if normalized != diMessages { diMessages = normalized }
        }
    }
    /// N1MM's extra Digital Interface message buttons: 0, 8, 16 or 24. Swift-only key.
    public var diButtonCount: Int = 0
    /// N1MM „Output Main RX Window to Text File": received text appended to `ExportFiles/<MMddyyyy>DigitalInterface1Output.txt`. Swift-only key.
    public var rxOutputToFile: Bool = false

    /// N1MM Alignment Frequency for RTTY in fldigi (fldigi's cursor is the centre: mark 2125 + 85). Swift-only key.
    public var alignRttyHz: Int = 2210
    /// N1MM Alignment Frequency for the other modes (PSK…). Swift-only key.
    public var alignOtherHz: Int = 1500
    /// N1MM „AFC On/Off with CQ": the CQ and TU messages turn fldigi's AFC on (to tune in off-frequency callers). Swift-only key.
    public var afcOnCq: Bool = false
    /// N1MM „NET On/Off with Run Change": NET (fldigi: Lock off) in S&P, NET off (Lock on) in Run. Swift-only key.
    public var netWithRunChange: Bool = false
    /// N1MM Shift Frequency Compensation: in FSK RTTY (rig mode RTTY/RTTYR) the offset is added to the logged and shown frequency. Swift-only key.
    public var shiftCompEnabled: Bool = false
    /// The compensation offset (Hz, may be negative). Swift-only key.
    public var shiftCompHz: Int = 170

    /// SO2V/SO2R: the second fldigi of the Digital Interface 2 (VFO B / rig 2). Swift-only key.
    public var fldigi2Host: String = "127.0.0.1"
    /// Its XML-RPC port; 0 = no second fldigi (DI2 uses DI1's). Swift-only key.
    public var fldigi2Port: Int = 0
    /// N1MM's additional RX windows: further fldigi instances decoding the same audio (`host:port`, up to 4, separated by spaces), attached to the Digital Interface 1. Swift-only key.
    public var extraRx: String = ""
    /// N1MM „RX Windows add to Grab window". Swift-only key.
    public var extraRxToGrab: Bool = true

    /// N1MM Config → SO2R „TX lockout (digital)": what happens when one Digital Interface transmits and the other one
    /// starts — `OFF` (both may transmit), `FIRST` (first wins: the second is refused), `LAST` (last wins: the first
    /// is stopped). Swift-only key.
    public var so2rTxLockout: String = DigitalTxLockout.off.rawValue
    /// N1MM „Default RTTY Interface": FLDIGI, TNC, TINYFSK or WINKEYER (PSK always fldigi). Swift-only key.
    public var rttyInterface: String = RttyInterface.fldigi.rawValue
    /// The TU/TNC (PK232, KAM, DXP38, OTHER) — the presets of its commands. Swift-only key.
    public var tncType: String = TncType.pk232.rawValue
    /// The TNC's serial port. Swift-only key.
    public var tncPort: String = ""
    /// The TNC's serial speed (8N1). Swift-only key.
    public var tncBaud: Int = 9600
    /// The TNC's {TX} command (empty = the type's preset; `{CTRL-C}`, `{ENTER}`, `{ESC}` …). Swift-only key.
    public var tncTx: String = ""
    /// The TNC's {RX} command (empty = the preset). Swift-only key.
    public var tncRx: String = ""
    /// The TNC's abort command for Esc (empty = the preset). Swift-only key.
    public var tncEsc: String = ""
    /// TinyFSK's serial port (9600 8N1). Swift-only key.
    public var tinyFskPort: String = ""
    /// WinKeyer 3.1 RTTY speed: 45 (45.45), 50, 75 or 100 baud. Swift-only key.
    public var wkRttyBaud: Int = 45
    /// WinKeyer 3.1 RTTY: mark and space reversed. Swift-only key.
    public var wkRttyReverse: Bool = false
    /// WinKeyer 3.1 RTTY FSKMAP: FSK on KEY, PTT keys the transmitter (default FSK on PTT). Swift-only key.
    public var wkRttyFskOnKey: Bool = false
    /// The Digital Interface's font (empty = the system monospaced font). Swift-only key.
    public var diFontName: String = ""
    /// The Digital Interface's text colour `#RRGGBB` (empty = the system's). Swift-only key.
    public var diTextColor: String = ""
    /// The Digital Interface's background `#RRGGBB` (empty = none). Swift-only key.
    public var diBackgroundColor: String = ""

    enum CodingKeys: String, CodingKey {
        case storedEngine = "engine", builtinModem, fldigiHost, fldigiPort, runMessages, spMessages, digitalCallStacking
        case autoTrxUpdate, rttyModem, pskModem
        case callValidity, validateScp, validateCallHistory, validateSpotted, validateLogged, scpGarbageSearch, highlightBackground, nonScrollingRx, pauseOnCallHover, hoverMode, rightClickReturn, sendSpaceOnClick, captionRadioFrequency
        case grabOrder, grabNoDupes, grabOnlyScp, grabClearOnQsy, grabClearOnCq, grabSendSpace, grabAddToBandmap
        case cwIdEnabled, cwIdText, diButtonCount, rxOutputToFile, diMessages
        case alignRttyHz, alignOtherHz, afcOnCq, netWithRunChange, shiftCompEnabled, shiftCompHz
        case fldigi2Host, fldigi2Port, extraRx, extraRxToGrab
        case so2rTxLockout
        case rttyInterface, tncType, tncPort, tncBaud, tncTx, tncRx, tncEsc, tinyFskPort, wkRttyBaud, wkRttyReverse, wkRttyFskOnKey, diFontName, diTextColor, diBackgroundColor
    }

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = DigitalConfig()
        storedEngine = c.value(.storedEngine, default: d.storedEngine)
        builtinModem = c.value(.builtinModem, default: d.builtinModem)
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
        grabOrder = GrabList.Order.from(c.value(.grabOrder, default: d.grabOrder)).rawValue
        grabNoDupes = c.value(.grabNoDupes, default: d.grabNoDupes)
        grabOnlyScp = c.value(.grabOnlyScp, default: d.grabOnlyScp)
        grabClearOnQsy = c.value(.grabClearOnQsy, default: d.grabClearOnQsy)
        grabClearOnCq = c.value(.grabClearOnCq, default: d.grabClearOnCq)
        grabSendSpace = c.value(.grabSendSpace, default: d.grabSendSpace)
        grabAddToBandmap = c.value(.grabAddToBandmap, default: d.grabAddToBandmap)
        cwIdEnabled = c.value(.cwIdEnabled, default: d.cwIdEnabled)
        cwIdText = c.value(.cwIdText, default: d.cwIdText)
        diButtonCount = DigitalConfig.buttonCount(c.value(.diButtonCount, default: d.diButtonCount))
        diMessages = DigitalConfig.buttons(c.value(.diMessages, default: d.diMessages))
        rxOutputToFile = c.value(.rxOutputToFile, default: d.rxOutputToFile)
        alignRttyHz = DigitalConfig.audioHz(c.value(.alignRttyHz, default: d.alignRttyHz), fallback: d.alignRttyHz)
        alignOtherHz = DigitalConfig.audioHz(c.value(.alignOtherHz, default: d.alignOtherHz), fallback: d.alignOtherHz)
        afcOnCq = c.value(.afcOnCq, default: d.afcOnCq)
        netWithRunChange = c.value(.netWithRunChange, default: d.netWithRunChange)
        shiftCompEnabled = c.value(.shiftCompEnabled, default: d.shiftCompEnabled)
        shiftCompHz = max(-5000, min(5000, c.value(.shiftCompHz, default: d.shiftCompHz)))
        fldigi2Host = c.value(.fldigi2Host, default: d.fldigi2Host)
        fldigi2Port = max(0, min(65535, c.value(.fldigi2Port, default: d.fldigi2Port)))
        extraRx = c.value(.extraRx, default: d.extraRx)
        extraRxToGrab = c.value(.extraRxToGrab, default: d.extraRxToGrab)
        rttyInterface = RttyInterface.from(c.value(.rttyInterface, default: d.rttyInterface)).rawValue
        so2rTxLockout = DigitalTxLockout.from(c.value(.so2rTxLockout, default: d.so2rTxLockout)).rawValue
        tncType = TncType.from(c.value(.tncType, default: d.tncType)).rawValue
        tncPort = c.value(.tncPort, default: d.tncPort)
        tncBaud = c.value(.tncBaud, default: d.tncBaud) > 0 ? c.value(.tncBaud, default: d.tncBaud) : d.tncBaud
        tncTx = c.value(.tncTx, default: d.tncTx)
        tncRx = c.value(.tncRx, default: d.tncRx)
        tncEsc = c.value(.tncEsc, default: d.tncEsc)
        tinyFskPort = c.value(.tinyFskPort, default: d.tinyFskPort)
        wkRttyBaud = c.value(.wkRttyBaud, default: d.wkRttyBaud)
        wkRttyReverse = c.value(.wkRttyReverse, default: d.wkRttyReverse)
        wkRttyFskOnKey = c.value(.wkRttyFskOnKey, default: d.wkRttyFskOnKey)
        diFontName = c.value(.diFontName, default: d.diFontName)
        diTextColor = c.value(.diTextColor, default: d.diTextColor)
        diBackgroundColor = c.value(.diBackgroundColor, default: d.diBackgroundColor)
    }

    /// An audio frequency for fldigi's cursor (100…4000 Hz), else `fallback`.
    public static func audioHz(_ value: Int, fallback: Int) -> Int {
        (100...4000).contains(value) ? value : fallback
    }

    /// The Align target for a modem (RTTY or the others).
    public func alignHz(modem: String) -> Int {
        KotlinStrings.uppercase(modem).hasPrefix("RTTY") ? alignRttyHz : alignOtherHz
    }

    /// fldigi of a side: DI1 = `fldigiHost:fldigiPort`, DI2 = `fldigi2Host:fldigi2Port` when configured
    /// (`fldigi2Port > 0`), else DI1's.
    public func endpoint(_ side: Int) -> (host: String, port: Int) {
        if engine == .builtin {
            return (Self.builtinHost, side == 1 ? 2 : 1)
        }
        if side == 1, fldigi2Port > 0 {
            return (DigitalConfig.normalizedHost(fldigi2Host), fldigi2Port)
        }
        return (fldigiHost, fldigiPort)
    }

    /// A second fldigi is configured, or the built-in modem runs (DI2 has its own modem).
    public var hasSecondFldigi: Bool {
        engine == .builtin || fldigi2Port > 0
    }

    /// The TNC's TX / RX / abort commands: the configured ones, a blank one from the type's preset.
    public var tncCommands: (tx: String, rx: String, esc: String) {
        let preset = TncType.from(tncType).defaultCommands
        func pick(_ value: String, _ fallback: String) -> String {
            JavaText.isBlank(value) ? fallback : value
        }
        return (pick(tncTx, preset.tx), pick(tncRx, preset.rx), pick(tncEsc, preset.esc))
    }

    /// The WinKeyer 3.1 RTTY mode.
    public var winkeyerRtty: WinkeyerRtty.Settings {
        WinkeyerRtty.Settings(baud: wkRttyBaud == 45 ? 45.45 : Double(wkRttyBaud), reverse: wkRttyReverse,
                              fskOnKey: wkRttyFskOnKey)
    }

    /// The interface RTTY goes through.
    public var rttyRoute: RttyInterface {
        RttyInterface.from(rttyInterface)
    }

    public static let buttonSlots = 24

    /// 24 empty buttons.
    public static func emptyButtons() -> [FunctionKeyMessage] {
        Array(repeating: FunctionKeyMessage(label: "", text: ""), count: buttonSlots)
    }

    /// Exactly 24 buttons (missing ones empty).
    public static func buttons(_ list: [FunctionKeyMessage]) -> [FunctionKeyMessage] {
        var out = Array(list.prefix(buttonSlots))
        while out.count < buttonSlots {
            out.append(FunctionKeyMessage(label: "", text: ""))
        }
        return out
    }

    /// 0, 8, 16 or 24 (anything else → the nearest lower one, at least 0).
    public static func buttonCount(_ value: Int) -> Int {
        max(0, min(24, value / 8 * 8))
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

/// N1MM Config → SO2R „TX lockout (digital)" between the two Digital Interfaces.
public enum DigitalTxLockout: String, CaseIterable, Sendable {
    case off = "OFF"
    case firstWins = "FIRST"
    case lastWins = "LAST"

    /// A stored value; anything unknown is `off`.
    public static func from(_ text: String) -> DigitalTxLockout {
        DigitalTxLockout(rawValue: text.uppercased()) ?? .off
    }
}
