import Foundation

/// Building an F-key CW message from a template in N1MM+ format (CW Default Messages.mc). Mirrors Java
/// `keyer.CwMessageBuilder`.
///
/// Macros:
/// - `*`, `{MYCALL}` – my callsign; `!`, `{CALL}` – callsign from the callsign field, when empty the last
///   logged one;
/// - `#` – serial number (cut numbers and leading zeros options);
/// - `{SENTRST}` – sent report, `{SENTRSTCUT}` – the same with 9 → N, 0 → T;
/// - `{EXCH}` – sent exchange from the contest setup (the character `#` in it is the number);
/// - `{ROVERQTH}` – my county (rover), `{COUNTYLINE}` – county line counties separated by "/" (each is ignored in the
///   other mode);
/// - prosigns `]` SK, `[` AS, `+` AR, `=` BT; `<` / `>` speed ±2 WPM, `~` half space (sent as a space);
/// - control `{LOG}`, `{WIPE}`, `{RUN}`, `{S&P}`… → `CwMessage.Action`; the call stack `{SOCALLSTACK}`,
///   `{STACKANOTHER}`, `{CLRSTACK}` too (`{LOGTHENPOP}` is split off by `FunctionKeyRouter` before building), and
///   `{SPOTME}` (a self-spot to the DX cluster);
/// - `{F1}`…`{F12}` – text of another F-key (chaining, at most 3 levels of insertion);
/// - Swift-only N1MM macros: the last QSO `{LASTCALL}`, `{PREVNR}`, `{LASTEXCH}`, `{PREVTIME}`; names `{NAME}`
///   (the Name field, else the call history), `{NAMEANDSPACE}`, `{CHNAME}`; station `{GRID}`, `{CLUSTER}`;
///   frequency `{FREQ}` (R for the decimal point in CW), `{FREQROUND}`, `{LRMHZ}`, `{RRMHZ}`; his locator
///   `{GRIDSQUARE}`, `{GRIDBEARING}`, `{REVGRIDBEARING}`, `{KMGRIDDISTANCE}`; time `{TIME1}`, `{TIME2}`, `{TIMEGMT}`,
///   `{DATE}`, `{DATE1}`, `{DAYTIME}`, `{DATEGMT}`, `{TIMESTAMP}`; alternating `{VARYMSG1&a&b&n&}`; the actions
///   `{CQ}`, `{QSYCQ}`, `{EXCHSENT}`, `{CTRLHOME}`, `{FORCELOG}`, `{FORCELOGNOTE}`, `{SPACE}` and `{COMMENT text}`.
///
/// Other macros in `{}` are not transmitted and are returned in `CwMessage.unknownMacros`.
///
/// **Decision 6 (`null`):** the text fields of `Context` are non-optional. With `null` values Java sends
/// `*` as `NULL` and reports `{MYCALL}`/`{SENTRST}` as unknown macros; here `""` → empty text
/// (`null` never gets in from the app). Lists and style have the Java defaults (`null` = empty list,
/// `TN`, empty station data) — that behaviour is identical. `now` stays optional (`nil` → `{TIME}` = `""`).
public enum CwMessageBuilder {

    /// Speed change step of the `<` and `>` macros (N1MM: 2 WPM).
    static let speedStep = 2

    /// Station data for the macros `{MYNAME}`, `{MYGRID}`… (N1MM "Station data" macros).
    public struct StationData: Equatable, Sendable {
        public var name: String
        public var grid: String
        public var cqZone: String
        public var ituZone: String
        public var state: String
        public var `operator`: String

        public init(name: String, grid: String, cqZone: String, ituZone: String, state: String, operator: String) {
            self.name = name
            self.grid = grid
            self.cqZone = cqZone
            self.ituZone = ituZone
            self.state = state
            self.operator = `operator`
        }

        public static let empty = StationData(name: "", grid: "", cqZone: "", ituZone: "", state: "", operator: "")
    }

    /// Data for the macros (Java record `Context`; defaults = shortened Java constructors).
    public struct Context: Sendable {
        /// Station callsign.
        public var myCall: String
        /// Content of the callsign field.
        public var hisCall: String
        /// Last logged callsign (for `!` with an empty field).
        public var lastLogged: String
        /// Sent serial number (Java `int`).
        public var serial: Int
        /// Sent report.
        public var rst: String
        /// Sent exchange without the report; `#` = serial number.
        public var exchange: String
        /// Serial number with "cut" digits according to `cutStyle`.
        public var cutNumbers: Bool
        /// Serial number of at least three digits (007).
        public var leadingZeros: Bool
        /// My county (rover), otherwise "".
        public var roverQth: String
        /// County line counties (empty = no county line).
        public var countyLine: [String]
        public var cutStyle: CutStyle
        public var station: StationData
        /// Texts F1…F12 for chaining `{F1}`…; missing item = "".
        public var functionKeys: [String]
        /// Moment for `{TIME}` (`nil` → "").
        public var now: Date?
        /// `{LDIGFQ}` / `{RDIGFQ}`: the frequency of the left (VFO A / radio 1) and right (VFO B / radio 2) Digital
        /// Interface in kHz (`DigitalFrequency.macroText`); `""` = unknown.
        public var leftDigitalFrequency: String = ""
        public var rightDigitalFrequency: String = ""
        /// `{NAME}`: the other station's name from the call history.
        public var hisName: String = ""
        /// `{DI1}`…`{DI24}`: the texts of the Digital Interface's message buttons.
        public var digitalButtons: [String] = []
        /// `{FILE:name}`: the text of a file in the messages folder (`nil` = missing).
        public var fileText: @Sendable (String) -> String? = { _ in nil }
        /// `{FREQ}` / `{FREQROUND}`: the QSO frequency (Hz, 0 = unknown); `frequencyR`: R for the decimal point (CW).
        public var freqHz: Int64 = 0
        public var frequencyR: Bool = false
        /// `{NAME}`: the entry window's Name field (`nil` / blank = the call history's name instead).
        public var entryName: String?
        /// `{GRIDSQUARE}`…: the other station's locator from the entry window.
        public var hisGrid: String = ""
        /// `{PREVNR}`, `{LASTEXCH}`, `{PREVTIME}`: the serial sent, the exchange received and the time of the last
        /// logged QSO.
        public var lastSerial: String = ""
        public var lastExchange: String = ""
        public var lastTime: Date?
        /// `{CLUSTER}`: the DX cluster login.
        public var clusterCall: String = ""
        /// `{LRMHZ}` / `{RRMHZ}`: the whole MHz of the left (VFO A / radio 1) and right (VFO B / radio 2) rig.
        public var leftMHz: String = ""
        public var rightMHz: String = ""
        /// `{OTHERFREQ}`…: the frequency of the other (inactive) VFO / radio (Hz, 0 = unknown).
        public var otherFreqHz: Int64 = 0
        /// The local time zone of `{TIME1}`, `{DATE}`, `{DATE1}`, `{DAYTIME}` and the locale of the short dates.
        public var timeZone: TimeZone = .current
        public var locale: Locale = .current
        /// How many times `{VARYMSG1}` / `{VARYMSG2}` were sent before.
        public var varyCounts: [Int] = []
        /// The network log is connected: the N1MM multi-user macros (`{MESSAGE}`, `{PASS …}`, `{PASSMSG …}`,
        /// `{LASTPASSEDFREQ}`) are substituted only then.
        public var multiUser: Bool = false
        /// The other stations for `{PASS …}`.
        public var passTargets: [MacroPassTarget] = []
        /// `{LASTPASSEDFREQ}`: the pass frequency of the station last alerted to expect a pass (Hz, 0 = none).
        public var lastPassedFreqHz: Int = 0

        public init(
            myCall: String, hisCall: String, lastLogged: String, serial: Int, rst: String, exchange: String,
            cutNumbers: Bool, leadingZeros: Bool, roverQth: String = "", countyLine: [String] = [],
            cutStyle: CutStyle = .tn, station: StationData = .empty, functionKeys: [String] = [],
            now: Date? = Date(), leftDigitalFrequency: String = "", rightDigitalFrequency: String = ""
        ) {
            self.leftDigitalFrequency = leftDigitalFrequency
            self.rightDigitalFrequency = rightDigitalFrequency
            self.myCall = myCall
            self.hisCall = hisCall
            self.lastLogged = lastLogged
            self.serial = serial
            self.rst = rst
            self.exchange = exchange
            self.cutNumbers = cutNumbers
            self.leadingZeros = leadingZeros
            self.roverQth = roverQth
            self.countyLine = countyLine
            self.cutStyle = cutStyle
            self.station = station
            self.functionKeys = functionKeys
            self.now = now
        }
    }

    private static let prosigns: [UInt16: String] = [0x5D: "SK", 0x5B: "AS", 0x2B: "AR", 0x3D: "BT"]

    private static let actions: [String: CwMessage.Action] = [
        "{LOG}": .log, "{WIPE}": .wipe, "{RUN}": .run, "{S&P}": .searchAndPounce,
        "{CLEARRIT}": .clearRit, "{RITCLEAR}": .clearRit, "{CQFREQ}": .cqFrequency, "{NOSPLIT}": .splitOff,
        "{SOCALLSTACK}": .soCallStack, "{STACKANOTHER}": .stackAnother, "{CLRSTACK}": .clearStack,
        "{GRAB}": .grab, "{DELALL}": .grabDeleteAll, "{DELTOP}": .grabDeleteTop, "{DELSEL}": .grabDeleteSelected,
        "{SCQ}": .resumeCq, "{TX}": .digitalTx, "{RX}": .digitalRx, "{CLRRX}": .clearRx, "{CLRTX}": .clearTx,
        "{ALT-T}": .toggleTx, "{ALT-Q}": .jumpCq, "{ALIGN}": .align, "{ENABLEAFC}": .afcOn, "{DISABLEAFC}": .afcOff,
        "{ENABLENET}": .netOn, "{DISABLENET}": .netOff, "{SPOTME}": .spotMe,
        "{CQ}": .cq, "{QSYCQ}": .cqFrequency, "{EXCHSENT}": .exchangeSent, "{CTRLHOME}": .ctrlHome,
        "{FORCELOG}": .forceLog, "{FORCELOGNOTE}": .forceLogNote, "{SPACE}": .space,
        "{PGUP}": .pageUp, "{PGDN}": .pageDown, "{FREQUP}": .freqUp, "{FREQDN}": .freqDown,
        "{TURNROTOR}": .turnRotor, "{LONGPATH}": .longPath, "{STOPROTOR}": .stopRotor,
    ].merging(radioActions) { first, _ in first }

    /// The two-radio, audio and needed-QSO actions (N1MM), shared with the voice messages.
    public static let radioActions: [String: CwMessage.Action] = [
        "{JUMPRX}": .jumpRx, "{JUMPRXTX}": .jumpRxTx, "{CONDJUMP}": .condJump, "{STOPTX}": .stopTx,
        "{STEREOON}": .stereoOn, "{STEREOOFF}": .stereoOff,
        "{ACTIVEAUDIOTOGGLE}": .activeAudioToggle, "{ACTIVEAUDIOON}": .activeAudioOn,
        "{ACTIVEAUDIOOFF}": .activeAudioOff, "{INACTIVEAUDIOTOGGLE}": .inactiveAudioToggle,
        "{INACTIVEAUDIOON}": .inactiveAudioOn, "{INACTIVEAUDIOOFF}": .inactiveAudioOff,
        "{POPPREVNEEDEDQ}": .popPrevNeeded, "{POPNEXTNEEDEDQ}": .popNextNeeded,
    ]

    /// Builds the message (`nil` template = empty message, like Java `null`).
    public static func build(_ template: String?, _ ctx: Context) -> CwMessage {
        guard let template else { return CwMessage(parts: []) }
        let expanded: [UInt16] = expandFunctionKeys(Array(template.utf16), ctx, depth: 0)
        guard expanded.contains(0x7B) else { return build(units: expanded, ctx, varyUsed: []) }
        let vary = VaryMessage.expand(JavaChar.string(expanded), counts: ctx.varyCounts)
        return build(units: Array(vary.text.utf16), ctx, varyUsed: vary.used)
    }

    /// `{F1}`…`{F12}` (Java regex `(?i)\{F(1[0-2]|[1-9])\}`): inserts `" " + text + " "` of another F-key,
    /// recursively to depth 2; at depth 3 the macro stays in the text (and is then unknown). An empty list
    /// of F-keys = template unchanged.
    static func expandFunctionKeys(_ template: [UInt16], _ ctx: Context, depth: Int) -> [UInt16] {
        if depth > 2 || (ctx.functionKeys.isEmpty && ctx.digitalButtons.isEmpty) {
            return template
        }
        var out: [UInt16] = []
        var copied = 0
        var index = 0
        while index < template.count {
            let inner: String
            let end: Int
            if !ctx.functionKeys.isEmpty, let (keyIndex, keyEnd) = functionKeyMatch(template, at: index) {
                inner = keyIndex < ctx.functionKeys.count ? ctx.functionKeys[keyIndex] : ""
                end = keyEnd
            } else if !ctx.digitalButtons.isEmpty, let (button, buttonEnd) = digitalButtonMatch(template, at: index) {
                inner = button < ctx.digitalButtons.count ? ctx.digitalButtons[button] : ""
                end = buttonEnd
            } else {
                index += 1
                continue
            }
            out.append(contentsOf: template[copied..<index])
            out.append(0x20)
            out.append(contentsOf: expandFunctionKeys(Array(inner.utf16), ctx, depth: depth + 1))
            out.append(0x20)
            index = end
            copied = end
        }
        out.append(contentsOf: template[copied...])
        return out
    }

    /// Match of `{DI<n>}` (`n` 1…24, ASCII case-insensitive) at `start` → (button index from 0, end of match).
    private static func digitalButtonMatch(_ units: [UInt16], at start: Int) -> (Int, Int)? {
        guard start + 4 < units.count, units[start] == 0x7B, units[start + 1] | 0x20 == 0x64,
              units[start + 2] | 0x20 == 0x69 else { return nil }
        var end: Int = start + 3
        var number = 0
        while end < units.count, end - start < 6, units[end] >= 0x30, units[end] <= 0x39 {
            number = number * 10 + Int(units[end] - 0x30)
            end += 1
        }
        guard end > start + 3, end < units.count, units[end] == 0x7D, (1...24).contains(number) else { return nil }
        return (number - 1, end + 1)
    }

    /// Match of `{F<n>}` at position `start` → (F-key index from 0, end of match). `(?i)` without `UNICODE_CASE`
    /// = only ASCII `F`/`f`; the alternative `1[0-2]` takes precedence over `[1-9]`.
    private static func functionKeyMatch(_ units: [UInt16], at start: Int) -> (Int, Int)? {
        guard start + 3 < units.count, units[start] == 0x7B, units[start + 1] == 0x46 || units[start + 1] == 0x66 else {
            return nil
        }
        let first = units[start + 2]
        if first == 0x31, start + 4 < units.count, (0x30...0x32).contains(units[start + 3]), units[start + 4] == 0x7D {
            return (9 + Int(units[start + 3] - 0x30), start + 5)
        }
        if (0x31...0x39).contains(first), units[start + 3] == 0x7D {
            return (Int(first - 0x31), start + 4)
        }
        return nil
    }

    private static func build(units t: [UInt16], _ ctx: Context, varyUsed: [Int]) -> CwMessage {
        var parts: [CwMessage.Part] = []
        var actionList: [CwMessage.Action] = []
        var commands: [MacroCommand] = []
        var unknown: [String] = []
        var deferredActions: [CwMessage.Action] = []
        var deferredCommands: [MacroCommand] = []
        var afterEnd = false
        var text: [UInt16] = []
        // `{MESSAGE}`: the rest of the message is a network talk message, kept as written (not keyed).
        var network: [UInt16]?
        var i = 0
        while i < t.count {
            let c = t[i]
            if c == 0x7B { // {
                guard let end = macroEnd(t, from: i) else {
                    i += 1
                    continue
                }
                let raw: [UInt16] = Array(t[i...end])
                let macro = upperRoot(raw)
                i = end + 1
                if macro == "{END}" {
                    afterEnd = true
                    continue
                }
                if afterEnd {
                    // N1MM: after `{END}` only the macros that do not send run, once the message has been sent.
                    if let action = actions[macro] {
                        deferredActions.append(action)
                    } else if let command = MacroCommand.parse(JavaChar.string(raw)) {
                        deferredCommands.append(command)
                    }
                    continue
                }
                if macro == "{MESSAGE}" {
                    // Never keyed, even off the network (then the talk message is dropped).
                    if network == nil {
                        flush(&text, &parts)
                        network = []
                    }
                    continue
                }
                if let (name, argument) = MacroCommand.split(JavaChar.string(raw)), name == "PASS" {
                    var value: String = ""
                    if ctx.multiUser, let target = MultiUserMacro.target(argument, in: ctx.passTargets) {
                        value = MultiUserMacro.passText(target.targetHz)
                        commands.append(.passAlert(station: target.station, hz: target.targetHz))
                    }
                    if network != nil {
                        network?.append(contentsOf: value.utf16)
                    } else {
                        text.append(contentsOf: value.utf16)
                    }
                    continue
                }
                if network != nil, macro == "{ENTERLF}" || macro == "{ENTER}" {
                    network?.append(0x20)
                    continue
                }
                if macro == "{ENTERLF}" || macro == "{ENTER}" {
                    flush(&text, &parts)
                    parts.append(CwMessage.newline)
                    continue
                }
                if macro.hasPrefix("{FILE:") {
                    let name: String = JavaChar.string(Array(raw[6..<(raw.count - 1)]))
                    if let content = ctx.fileText(JavaText.trim(name)) {
                        let lines: [String] = JavaText.split(content.replacingOccurrences(of: "\r\n", with: "\n"),
                                                             unit: 0x0A)
                        for (index, line) in lines.enumerated() {
                            if index > 0 {
                                flush(&text, &parts)
                                parts.append(CwMessage.newline)
                            }
                            text.append(contentsOf: line.utf16)
                        }
                    } else {
                        unknown.append(macro)
                    }
                    continue
                }
                if let action = actions[macro] {
                    actionList.append(action)
                    continue
                }
                if let command = MacroCommand.parse(JavaChar.string(raw)) {
                    if case .passLastQso = command, !ctx.multiUser {
                        continue
                    }
                    commands.append(command)
                    continue
                }
                if let value = macroValue(macro, ctx) {
                    if network != nil {
                        network?.append(contentsOf: value.utf16)
                    } else {
                        text.append(contentsOf: value.utf16)
                    }
                } else {
                    unknown.append(macro)
                }
                continue
            }
            i += 1
            if afterEnd {
                continue
            }
            if network != nil {
                switch c {
                case 0x2A: network?.append(contentsOf: ctx.myCall.utf16) // *
                case 0x21: network?.append(contentsOf: hisCall(ctx).utf16) // !
                case 0x23: network?.append(contentsOf: serial(ctx).utf16) // #
                default: network?.append(c)
                }
                continue
            }
            switch c {
            case 0x2A: text.append(contentsOf: ctx.myCall.utf16) // *
            case 0x21: text.append(contentsOf: hisCall(ctx).utf16) // !
            case 0x23: text.append(contentsOf: serial(ctx).utf16) // #
            // No keyer can do a half space; N1MM writes it between words (cq~test~de~*) → space.
            case 0x7E: text.append(0x20)
            case 0x3C, 0x3E: // < >
                flush(&text, &parts)
                parts.append(.speed(c == 0x3C ? speedStep : -speedStep))
            default:
                if let prosign = prosigns[c] {
                    flush(&text, &parts)
                    parts.append(.prosign(prosign))
                } else {
                    text.append(c)
                }
            }
        }
        flush(&text, &parts)
        if let network {
            let message: String = JavaText.trim(JavaChar.string(network))
            if ctx.multiUser && !message.isEmpty {
                commands.append(.networkMessage(message))
            }
        }
        return CwMessage(parts: parts, actions: actionList, unknownMacros: unknown, commands: commands,
                         varyUsed: varyUsed, deferredActions: deferredActions, deferredCommands: deferredCommands)
    }

    /// The closing brace of the macro opened at `start`: the first `}`, or for a macro that may nest another
    /// (`{SETWAVDIR {OPERATOR}_2}`) the balancing one.
    private static func macroEnd(_ t: [UInt16], from start: Int) -> Int? {
        guard let first = t[start...].firstIndex(of: 0x7D) else { return nil }
        let head: String = upperRoot(Array(t[start..<min(t.count, start + 10)]))
        guard MacroCommand.nests(head) else { return first }
        var depth = 0
        for index in start..<t.count {
            if t[index] == 0x7B {
                depth += 1
            } else if t[index] == 0x7D {
                depth -= 1
                if depth == 0 {
                    return index
                }
            }
        }
        return first
    }

    /// Macro value, `nil` = unknown macro.
    private static func macroValue(_ macro: String, _ ctx: Context) -> String? {
        switch macro {
        case "{MYCALL}": ctx.myCall
        case "{CALL}": hisCall(ctx)
        case "{SENTRST}": ctx.rst
        case "{SENTRSTCUT}": cut(ctx.rst)
        case "{EXCH}": exchange(ctx)
        // N1MM: in county-line mode {ROVERQTH} is ignored and vice versa — one message file thus serves
        // both rover and county line without rewriting.
        case "{ROVERQTH}": ctx.countyLine.isEmpty ? ctx.roverQth : ""
        case "{COUNTYLINE}": ctx.countyLine.joined(separator: "/")
        case "{LOGGEDCALL}": ctx.lastLogged
        case "{NR}": serial(ctx)
        case "{MYNAME}": ctx.station.name
        case "{MYGRID}", "{MYLOC}": ctx.station.grid
        case "{MYCQZONE}", "{MYZONE}": ctx.station.cqZone
        case "{MYITUZONE}": ctx.station.ituZone
        case "{MYSTATE}": ctx.station.state
        case "{OPERATOR}": ctx.station.operator
        case "{TIME}": time(ctx.now)
        case "{NAME}": name(ctx)
        case "{LDIGFQ}": ctx.leftDigitalFrequency
        case "{RDIGFQ}": ctx.rightDigitalFrequency
        default: extendedValue(macro, ctx)
        }
    }

    /// The Swift-only N1MM text macros (`nil` = unknown).
    private static func extendedValue(_ macro: String, _ ctx: Context) -> String? {
        switch macro {
        case "{LASTCALL}": ctx.lastLogged
        case "{PREVNR}": ctx.lastSerial
        case "{LASTEXCH}": ctx.lastExchange
        case "{PREVTIME}": ctx.lastTime.map { MacroTime.format($0, "HHmm") } ?? ""
        case "{NAMEANDSPACE}": name(ctx).isEmpty ? "" : name(ctx) + " "
        case "{CHNAME}": ctx.hisName
        case "{GRID}": ctx.station.grid
        case "{CLUSTER}": ctx.clusterCall
        case "{FREQ}": MacroFrequency.text(ctx.freqHz, round: false, r: ctx.frequencyR)
        case "{FREQROUND}": MacroFrequency.text(ctx.freqHz, round: true, r: ctx.frequencyR)
        case "{LASTPASSEDFREQ}":
            ctx.multiUser ? MacroFrequency.text(Int64(ctx.lastPassedFreqHz), round: false, r: true) : ""
        case "{OTHERFREQ}": MacroFrequency.text(ctx.otherFreqHz, round: false, r: ctx.frequencyR)
        case "{OTHERFREQROUND}": MacroFrequency.text(ctx.otherFreqHz, round: true, r: ctx.frequencyR)
        case "{OTHERBAND}": MacroFrequency.band(ctx.otherFreqHz)
        case "{OTHERMHZ}": MacroFrequency.mhz(ctx.otherFreqHz, r: ctx.frequencyR)
        case "{OTHERFREQCUT}": MacroFrequency.cut(ctx.otherFreqHz, style: ctx.cutStyle)
        case "{LRMHZ}": ctx.leftMHz
        case "{RRMHZ}": ctx.rightMHz
        case "{GRIDSQUARE}": JavaText.toUpperCase(JavaText.trim(ctx.hisGrid))
        case "{GRIDBEARING}": MacroGrid.bearing(from: ctx.station.grid, to: ctx.hisGrid, reverse: false)
        case "{REVGRIDBEARING}": MacroGrid.bearing(from: ctx.station.grid, to: ctx.hisGrid, reverse: true)
        case "{KMGRIDDISTANCE}": MacroGrid.distance(from: ctx.station.grid, to: ctx.hisGrid)
        default: MacroTime.value(macro, ctx.now, timeZone: ctx.timeZone, locale: ctx.locale)
        }
    }

    /// `{NAME}`: the Name field when it holds something, otherwise the call history's name.
    private static func name(_ ctx: Context) -> String {
        let field: String = JavaText.trim(ctx.entryName ?? "")
        return field.isEmpty ? ctx.hisName : field
    }

    /// `DateTimeFormatter.ofPattern("HHmm").withZone(UTC)`; `nil` → "".
    private static func time(_ now: Date?) -> String {
        guard let now, let split = JavaLocalDate.split(now) else { return "" }
        let hours = JavaLocalDate.twoDigits(split.secondOfDay / 3600)
        return hours + JavaLocalDate.twoDigits(split.secondOfDay % 3600 / 60)
    }

    /// Java `toUpperCase(Locale.ROOT)` (full mapping: `ß` → `SS`, `ﬁ` → `FI`). Port convention:
    /// Swift `uppercased()`; verified against Java for the whole BMP where the result passes the filter
    /// of transmittable characters (`KFLT.unit`).
    private static func upperRoot(_ units: [UInt16]) -> String {
        JavaChar.string(units).uppercased()
    }

    private static func hisCall(_ ctx: Context) -> String {
        let call = JavaText.trim(ctx.hisCall)
        return call.isEmpty ? JavaText.trim(ctx.lastLogged) : call
    }

    private static func exchange(_ ctx: Context) -> String {
        replace(ctx.exchange, 0x23, with: serial(ctx))
    }

    private static func serial(_ ctx: Context) -> String {
        var s = String(ctx.serial)
        if ctx.leadingZeros && s.utf16.count < 3 {
            s = String(repeating: "0", count: 3 - s.utf16.count) + s
        }
        return ctx.cutNumbers ? ctx.cutStyle.apply(s) : s
    }

    /// Cut numbers: 0 → T, 9 → N (5NN, 1TN).
    static func cut(_ s: String) -> String {
        replace(replace(s, 0x39, with: "N"), 0x30, with: "T")
    }

    /// Java `String.replace` of a single character (UTF-16 unit) with a string.
    private static func replace(_ text: String, _ unit: UInt16, with replacement: String) -> String {
        var out: [UInt16] = []
        for u in text.utf16 {
            if u == unit {
                out.append(contentsOf: replacement.utf16)
            } else {
                out.append(u)
            }
        }
        return JavaChar.string(out)
    }

    /// Transmittable characters in uppercase (`[^A-Z0-9/?.,\- ]` removed), spaces collapsed; the first text without
    /// leading spaces; empty text is not added, only spaces just as `" "` except in the first text.
    private static func flush(_ text: inout [UInt16], _ parts: inout [CwMessage.Part]) {
        if text.isEmpty {
            return
        }
        var s: [UInt16] = []
        for u in upperRoot(text).utf16 where isSendable(u) && !(u == 0x20 && s.last == 0x20) {
            s.append(u)
        }
        text.removeAll()
        let first = !parts.contains { if case .text = $0 { true } else { false } }
        if first {
            s = Array(s.drop { $0 == 0x20 })
        }
        if s.contains(where: { $0 != 0x20 }) {
            parts.append(.text(JavaChar.string(s)))
        } else if !s.isEmpty && !first {
            parts.append(.text(" "))
        }
    }

    private static func isSendable(_ u: UInt16) -> Bool {
        switch u {
        case 0x41...0x5A, 0x30...0x39, 0x2F, 0x3F, 0x2E, 0x2C, 0x2D, 0x20: true
        default: false
        }
    }
}
