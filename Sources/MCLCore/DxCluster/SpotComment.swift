import Foundation

/// The N1MM+ „Comment For All Spots" (Telnet window, Spot Comment tab): a fixed comment sent with every spot MCL makes
/// (Spot It, Ctrl+P's prefilled text, the automatic S&P spot), with the spot-comment macros filled from the QSO being
/// spotted:
///
/// | Macro | Value |
/// |---|---|
/// | `{GRIDSQUARE}` | the grid (locator) field of the exchange |
/// | `{MODE}` | the mode of the QSO |
/// | `{QTH}` | the QTH field: state, province, district, IOTA, national or a text field of the exchange |
/// | `{ZONE}` | the CQ or ITU zone field |
///
/// A macro without a value becomes empty; the result is one line (line ends never reach the cluster) with single
/// spaces.
public enum SpotComment {

    /// The values the macros take.
    public struct Fields: Equatable, Sendable {
        public var grid: String
        public var mode: String
        public var qth: String
        public var zone: String

        public init(grid: String = "", mode: String = "", qth: String = "", zone: String = "") {
            self.grid = grid
            self.mode = mode
            self.qth = qth
            self.zone = zone
        }

        public static let empty = Fields()
    }

    /// The macros in the order the Spot Comment tab lists them.
    public static let macros: [String] = ["{GRIDSQUARE}", "{MODE}", "{QTH}", "{ZONE}"]

    /// `template` with the macros replaced (case-insensitive), whitespace collapsed to single spaces and trimmed.
    public static func expand(_ template: String, _ fields: Fields) -> String {
        var text: String = template
        let values: [(String, String)] = [("{GRIDSQUARE}", fields.grid), ("{MODE}", fields.mode),
                                          ("{QTH}", fields.qth), ("{ZONE}", fields.zone)]
        for (macro, value) in values {
            text = text.replacingOccurrences(of: macro, with: value, options: .caseInsensitive)
        }
        return text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }

    /// Which macro a received exchange field fills.
    enum Slot {
        case grid, qth, zone
    }

    static func slot(_ type: ContestDefinition.FieldType?) -> Slot? {
        switch type {
        case .LOCATOR: .grid
        case .CQ_ZONE, .ITU_ZONE: .zone
        case .STATE, .PROVINCE, .DISTRICT, .IOTA, .NATIONAL, .TEXT: .qth
        default: nil
        }
    }

    /// The values of the entry window: the received exchange fields by id (`value(id)`) and the mode. The first field
    /// of each kind wins.
    public static func fields(received: [ContestDefinition.ExchangeField], mode: String,
                              value: (String) -> String?) -> Fields {
        var out = Fields(mode: mode)
        for field in received {
            guard let slot = slot(field.type), let id = field.id,
                  let raw = value(id).map({ KotlinText.trim($0).uppercased() }), !raw.isEmpty else { continue }
            out.set(slot, raw)
        }
        return out
    }

    /// The values of a logged QSO. Its received exchange is stored as the non-blank field values joined by spaces in
    /// field order: when the count matches the fields they are matched in order, otherwise only a token that looks like
    /// a grid fills `{GRIDSQUARE}`.
    public static func fields(received: [ContestDefinition.ExchangeField], qso: Qso) -> Fields {
        var out = Fields(mode: qso.mode?.rawValue ?? "")
        let tokens: [String] = qso.exchangeRcvd.split(whereSeparator: { $0 == " " }).map { String($0).uppercased() }
        if tokens.count == received.count {
            for (field, token) in zip(received, tokens) {
                if let slot = slot(field.type) { out.set(slot, token) }
            }
            return out
        }
        if received.contains(where: { $0.type == .LOCATOR }), let grid = tokens.first(where: isGrid) {
            out.grid = grid
        }
        return out
    }

    /// `JN79`, `JN79FX`: two letters A–R, two digits, optionally two letters A–X.
    static func isGrid(_ token: String) -> Bool {
        let chars: [Character] = Array(token.uppercased())
        guard chars.count == 4 || chars.count == 6 else { return false }
        let field: Bool = chars[0...1].allSatisfy { ("A"..."R").contains($0) }
        let square: Bool = chars[2...3].allSatisfy { $0.isASCII && $0.isNumber }
        let sub: Bool = chars.count == 4 || chars[4...5].allSatisfy { ("A"..."X").contains($0) }
        return field && square && sub
    }
}

extension SpotComment.Fields {
    fileprivate mutating func set(_ slot: SpotComment.Slot, _ value: String) {
        switch slot {
        case .grid where grid.isEmpty: grid = value
        case .qth where qth.isEmpty: qth = value
        case .zone where zone.isEmpty: zone = value
        default: break
        }
    }
}

/// N1MM+ Special Calls (Telnet window, Special Calls tab): bonus stations, club members, friends. A spot of one of them
/// is marked with a heart in the band map and the Available window. A call matches by its base (`W1AW` also matches
/// `W1AW/M`, `-n` skimmer suffixes are ignored).
public enum SpecialCalls {

    /// The mark of a special call.
    public static let mark: String = "\u{2665}"
    /// The first line of N1MM's file.
    public static let fileHeader: String = "Type=FAVORITES SubType="

    /// The calls of a file or a pasted list: N1MM's header and `#` comments are skipped, calls are separated by
    /// line ends, commas, semicolons or spaces; upper case, duplicates dropped (first kept).
    public static func parse(_ text: String) -> [String] {
        var out: [String] = []
        var seen: Set<String> = []
        for rawLine in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" || $0 == "\r\n" }) {
            let line: String = KotlinText.trim(String(rawLine))
            if line.isEmpty || line.hasPrefix("#") || line.uppercased().hasPrefix("TYPE=") { continue }
            for token in line.split(whereSeparator: { $0 == "," || $0 == ";" || $0 == " " || $0 == "\t" }) {
                guard let call = ClusterCommandFormat.cleanCall(String(token)) else { continue }
                if seen.insert(call).inserted { out.append(call) }
            }
        }
        return out
    }

    /// N1MM's file: the header, then one call per line.
    public static func export(_ calls: [String]) -> String {
        ([fileHeader] + calls).joined(separator: "\n") + "\n"
    }

    /// The base of a call: the longest `/`-separated part (`DL/W1AW/P` → `W1AW`), without a `-n` / `-#` suffix.
    public static func base(_ call: String) -> String {
        var text: String = KotlinText.trim(call).uppercased()
        if let dash = text.lastIndex(of: "-") {
            text = String(text[..<dash])
        }
        let parts: [Substring] = text.split(separator: "/")
        return String(parts.max(by: { $0.count < $1.count }) ?? "")
    }

    /// The bases of `calls` (blank ones dropped).
    public static func bases(_ calls: [String]) -> Set<String> {
        Set(calls.map(base).filter { !$0.isEmpty })
    }

    /// `call` is one of `bases`.
    public static func matches(_ call: String, bases: Set<String>) -> Bool {
        guard !bases.isEmpty else { return false }
        let key: String = base(call)
        return !key.isEmpty && bases.contains(key)
    }
}
