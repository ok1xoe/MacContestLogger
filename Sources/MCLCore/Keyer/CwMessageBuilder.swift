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
/// - control `{LOG}`, `{WIPE}`, `{RUN}`, `{S&P}`… → `CwMessage.Action`;
/// - `{F1}`…`{F12}` – text of another F-key (chaining, at most 3 levels of insertion).
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

        public init(
            myCall: String, hisCall: String, lastLogged: String, serial: Int, rst: String, exchange: String,
            cutNumbers: Bool, leadingZeros: Bool, roverQth: String = "", countyLine: [String] = [],
            cutStyle: CutStyle = .tn, station: StationData = .empty, functionKeys: [String] = [],
            now: Date? = Date()
        ) {
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
    ]

    /// Builds the message (`nil` template = empty message, like Java `null`).
    public static func build(_ template: String?, _ ctx: Context) -> CwMessage {
        guard let template else { return CwMessage(parts: []) }
        return build(units: expandFunctionKeys(Array(template.utf16), ctx, depth: 0), ctx)
    }

    /// `{F1}`…`{F12}` (Java regex `(?i)\{F(1[0-2]|[1-9])\}`): inserts `" " + text + " "` of another F-key,
    /// recursively to depth 2; at depth 3 the macro stays in the text (and is then unknown). An empty list
    /// of F-keys = template unchanged.
    static func expandFunctionKeys(_ template: [UInt16], _ ctx: Context, depth: Int) -> [UInt16] {
        if depth > 2 || ctx.functionKeys.isEmpty {
            return template
        }
        var out: [UInt16] = []
        var copied = 0
        var index = 0
        while index < template.count {
            guard let (keyIndex, end) = functionKeyMatch(template, at: index) else {
                index += 1
                continue
            }
            out.append(contentsOf: template[copied..<index])
            let inner: String = keyIndex < ctx.functionKeys.count ? ctx.functionKeys[keyIndex] : ""
            out.append(0x20)
            out.append(contentsOf: expandFunctionKeys(Array(inner.utf16), ctx, depth: depth + 1))
            out.append(0x20)
            index = end
            copied = end
        }
        out.append(contentsOf: template[copied...])
        return out
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

    private static func build(units t: [UInt16], _ ctx: Context) -> CwMessage {
        var parts: [CwMessage.Part] = []
        var actionList: [CwMessage.Action] = []
        var unknown: [String] = []
        var text: [UInt16] = []
        var i = 0
        while i < t.count {
            let c = t[i]
            if c == 0x7B { // {
                guard let end = t[i...].firstIndex(of: 0x7D) else {
                    i += 1
                    continue
                }
                let macro = upperRoot(Array(t[i...end]))
                i = end + 1
                if let action = actions[macro] {
                    actionList.append(action)
                    continue
                }
                if let value = macroValue(macro, ctx) {
                    text.append(contentsOf: value.utf16)
                } else {
                    unknown.append(macro)
                }
                continue
            }
            i += 1
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
        return CwMessage(parts: parts, actions: actionList, unknownMacros: unknown)
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
        default: nil
        }
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
