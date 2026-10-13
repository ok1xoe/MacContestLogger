import Foundation

/// N1MM+ call history features beyond Java v1.1.1 (Swift-only): import directives, merging several files into one
/// table, the Loc1/Loc2 alternate grid and the `#CONTEST` association of a file with contests.
extension CallHistory {

    /// The import directives of a file (N1MM `!!…!!` lines). Without any, a file parses like Java v1.1.1.
    public struct ImportOptions: Equatable, Sendable {
        /// `!!MapStateToSect!!`: an empty Sect takes the State.
        public var mapStateToSect: Bool = false
        /// `!!FourCharGridSq!!`: 6-character grids are cut to 4.
        public var fourCharGrid: Bool = false
        /// `!!AppendUserText!!` (default) / `!!NoAppendUserText!!`: a repeated callsign appends its UserText.
        public var appendUserText: Bool = true
        /// `!!Validate50State!!`: a State that is not one of the 50 US states is dropped.
        public var validate50State: Bool = false
        /// Default / `!!NoLoc2AltGrid!!`: a different Loc1 of a repeated callsign moves the previous one to Loc2.
        public var loc2AltGrid: Bool = true
        /// `!!MapOnSection!!`: GTE, GTA, ONN, ONE and ONS become ON.
        public var mapOnSection: Bool = false
        /// `!!ValidateArrlSection!!`: a Sect that is not an ARRL/RAC section is dropped.
        public var validateArrlSection: Bool = false
        /// The recognised directives in file order (canonical spelling, each once), written back by `toLines()`.
        public var directives: [String] = []

        public init() {}

        /// Whether the file had a directive (N1MM's import rules for repeated callsigns apply).
        public var present: Bool {
            !directives.isEmpty
        }

        /// The canonical directive names, by their upper-case spelling.
        static let known: [String: String] = {
            let names: [String] = ["MapStateToSect", "FourCharGridSq", "AppendUserText", "NoAppendUserText",
                                   "Validate50State", "NoLoc2AltGrid", "MapOnSection", "ValidateArrlSection"]
            var out: [String: String] = [:]
            for name in names {
                out[name.uppercased()] = name
            }
            return out
        }()

        /// Takes the directives of one line (upper-case names without the `!!`); unknown ones are ignored.
        mutating func apply(_ names: [String]) {
            for raw in names {
                guard let name = Self.known[raw] else { continue }
                switch name {
                case "MapStateToSect": mapStateToSect = true
                case "FourCharGridSq": fourCharGrid = true
                case "AppendUserText": appendUserText = true
                case "NoAppendUserText": appendUserText = false
                case "Validate50State": validate50State = true
                case "NoLoc2AltGrid": loc2AltGrid = false
                case "MapOnSection": mapOnSection = true
                case "ValidateArrlSection": validateArrlSection = true
                default: break
                }
                if !directives.contains(name) {
                    directives.append(name)
                }
            }
        }
    }

    // MARK: - directives and delimiter

    /// The names of a directive line (upper case, without the `!!`): every token separated by `,` or `;` is
    /// `!!Name!!`; `nil` for any other line (the `!!Order!!` header included).
    static func directiveNames(_ stripped: String) -> [String]? {
        guard stripped.hasPrefix("!!"), !isOrderHeader(stripped) else { return nil }
        var names: [String] = []
        for token in stripped.split(whereSeparator: { $0 == "," || $0 == ";" }) {
            let text: String = token.trimmingCharacters(in: .whitespaces)
            if text.isEmpty {
                continue
            }
            guard text.count > 4, text.hasPrefix("!!"), text.hasSuffix("!!") else { return nil }
            let name: String = String(text.dropFirst(2).dropLast(2))
            guard !name.isEmpty, !name.contains("!") else { return nil }
            names.append(name.uppercased())
        }
        return names.isEmpty ? nil : names
    }

    /// The delimiter of an `!!Order!!` line: its first `,` or `;` after `!!Order!!` (comma when it has neither).
    static func orderDelimiter(_ stripped: String) -> UInt16 {
        for unit in stripped.utf16.dropFirst(9) where unit == 0x2C || unit == 0x3B {
            return unit
        }
        return 0x2C
    }

    // MARK: - records

    /// One record after the directives: Validate50State, MapStateToSect, FourCharGridSq, MapOnSection,
    /// ValidateArrlSection (in that order). A column it fills is added to `order`.
    static func normalized(_ record: JavaLinkedMap<String>, options: ImportOptions,
                           order: inout [String]) -> JavaLinkedMap<String> {
        var out: JavaLinkedMap<String> = record
        if options.validate50State, let state = out["state"], !usStates.contains(state.uppercased()) {
            out = out.removing("state")
        }
        if options.mapStateToSect, out["sect"] == nil, let state = out["state"] {
            out.put("sect", state)
            if indexOf(order, "sect") == nil {
                order.append("sect")
            }
        }
        if options.fourCharGrid {
            for column in ["loc1", "loc2"] {
                if let grid = out[column], grid.utf16.count == 6 {
                    out.put(column, String(grid.prefix(4)))
                }
            }
        }
        if options.mapOnSection, let sect = out["sect"], ontarioSections.contains(sect.uppercased()) {
            out.put("sect", "ON")
        }
        if options.validateArrlSection, let sect = out["sect"], !arrlSections.contains(sect.uppercased()) {
            out = out.removing("sect")
        }
        return out
    }

    /// N1MM's import of a callsign that is already in the table: the non-empty fields of `add` overlay `base`;
    /// UserText is appended (`appendUserText`) unless it is already there; a different Loc1 moves the previous one
    /// into Loc2 (`loc2AltGrid`) before a Loc2 of `add` is taken. Without `base` it is `add`.
    static func overlay(_ base: JavaLinkedMap<String>?, _ add: JavaLinkedMap<String>, options: ImportOptions,
                        order: inout [String]) -> JavaLinkedMap<String> {
        guard var record = base else { return add }
        var addedLoc2: String?
        for (key, value) in add.entries {
            guard let column = key, let value, !value.isEmpty else { continue }
            switch column {
            case "usertext":
                if options.appendUserText, let old = record["usertext"], !old.isEmpty {
                    if !old.contains(value) {
                        record.put("usertext", old + " " + value)
                    }
                } else {
                    record.put("usertext", value)
                }
            case "loc1":
                putGrid(value, into: &record, altGrid: options.loc2AltGrid, order: &order)
            case "loc2":
                addedLoc2 = value
            default:
                record.put(column, value)
            }
        }
        if let addedLoc2 {
            record.put("loc2", addedLoc2)
        }
        return record
    }

    /// Writes `grid` to Loc1 by N1MM's rules: the same grid, or one of the same square that is not shorter, replaces
    /// Loc1 in place (a 4-character grid is never written over a 6-character one of its square); another grid moves
    /// the previous Loc1 into Loc2 when `altGrid` (the older Loc2 dropped), otherwise overwrites it.
    static func putGrid(_ grid: String, into record: inout JavaLinkedMap<String>, altGrid: Bool,
                        order: inout [String]) {
        guard let old = record["loc1"], !JavaText.isBlank(old) else {
            record.put("loc1", grid)
            return
        }
        let oldKey: String = old.uppercased()
        let newKey: String = grid.uppercased()
        if oldKey == newKey {
            record.put("loc1", grid)
            return
        }
        if oldKey.count >= 4, newKey.count >= 4, oldKey.prefix(4) == newKey.prefix(4) {
            if newKey.count >= oldKey.count {
                record.put("loc1", grid)
            }
            return
        }
        if altGrid {
            record.put("loc2", old)
            if indexOf(order, "loc2") == nil {
                order.append("loc2")
            }
        }
        record.put("loc1", grid)
    }

    // MARK: - merging files

    /// N1MM's import of several files into one table: `other`'s records overlay this history's by `overlay` with
    /// `other`'s directives; new columns and callsigns are appended; comments are joined (each once). The directives
    /// of the result stay this history's (the primary file's).
    public func merging(_ other: CallHistory) -> CallHistory {
        var order: [String] = columns
        for column in other.columns where Self.indexOf(order, column) == nil {
            order.append(column)
        }
        var map: JavaLinkedMap<JavaLinkedMap<String>> = byCall
        for (key, record) in other.byCall.entries {
            guard let call = key, let record else { continue }
            map.put(call, Self.overlay(map[call], record, options: other.options, order: &order))
        }
        var joined: [String] = comments
        for comment in other.comments where !joined.contains(comment) {
            joined.append(comment)
        }
        return CallHistory(columns: order, byCall: map, options: options, comments: joined)
    }

    /// The primary file merged with the additional ones, in order (`load` of each; a missing file adds nothing).
    public static func load(primary: String?, extras: [String]) -> CallHistory {
        extras.reduce(load(primary)) { history, path in history.merging(load(path)) }
    }

    // MARK: - contest association

    /// N1MM `#CONTEST` lines: every comment's text after the `#`, normalised by `contestKey` (empty ones and the
    /// header `toLines()` writes left out, each once). Which of them name a contest is decided against the contest catalog (`lookupDecision`).
    public var contestTags: [String] {
        var tags: [String] = []
        for comment in comments where !comment.hasPrefix(Self.savedHeader) {
            let tag: String = Self.contestKey(String(comment.dropFirst()))
            if !tag.isEmpty && !tags.contains(tag) {
                tags.append(tag)
            }
        }
        return tags
    }

    /// A contest name or id compared with a `#CONTEST` line: upper case, letters and digits only (`# QSO Party PA`,
    /// `QSOPARTYPA`, `cq-ww-cw` and `CQWWCW` compare equal).
    public static func contestKey(_ text: String) -> String {
        String(text.uppercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
            .map(Character.init))
    }

    /// N1MM: when a contest opens, a file whose comments name known contests enables the lookup if one of them is
    /// this contest and disables it otherwise; a file that names no known contest leaves the switch alone (`nil`).
    ///
    /// - Parameters:
    ///   - contest: the keys of the opened contest (`contestKey` of its id and name)
    ///   - known: the keys of every contest of the catalog
    public static func lookupDecision(tags: [String], contest: Set<String>, known: Set<String>) -> Bool? {
        let named: [String] = tags.filter { known.contains($0) || contest.contains($0) }
        if named.isEmpty {
            return nil
        }
        return named.contains { contest.contains($0) }
    }

    // MARK: - reference lists

    /// The 50 US states (`!!Validate50State!!`; DC is not a state).
    static let usStates: Set<String> = [
        "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "FL", "GA", "HI", "ID", "IL", "IN", "IA", "KS", "KY", "LA",
        "ME", "MD", "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH", "NJ", "NM", "NY", "NC", "ND", "OH", "OK",
        "OR", "PA", "RI", "SC", "SD", "TN", "TX", "UT", "VT", "VA", "WA", "WV", "WI", "WY",
    ]

    /// `!!MapOnSection!!`: the Ontario sections mapped to ON.
    static let ontarioSections: Set<String> = ["GTE", "GTA", "ONN", "ONE", "ONS"]

    /// ARRL and RAC sections (`!!ValidateArrlSection!!`; PR and VI included, ON not), with the older GTA and NT.
    static let arrlSections: Set<String> = [
        // New England, Hudson, Atlantic
        "CT", "EMA", "ME", "NH", "RI", "VT", "WMA", "ENY", "NLI", "NNJ", "NNY", "SNJ", "WNY", "DE", "EPA", "MDC", "WPA",
        // Southeastern, Roanoke, Delta
        "AL", "GA", "KY", "NFL", "SC", "SFL", "WCF", "PR", "VI", "NC", "TN", "VA", "AR", "LA", "MS",
        // West Gulf, Pacific, Southwestern
        "NM", "NTX", "OK", "STX", "WTX", "EB", "NV", "PAC", "SCV", "SF", "SJV", "SV", "AZ", "LAX", "ORG", "SB", "SDG",
        // Northwestern, Rocky Mountain, Great Lakes, Central, Dakota, Midwest
        "AK", "EWA", "ID", "MT", "OR", "WWA", "CO", "UT", "WY", "MI", "OH", "WV", "IL", "IN", "WI", "MN", "ND", "SD",
        "IA", "KS", "MO", "NE",
        // Canada (RAC)
        "AB", "BC", "GH", "MB", "NB", "NL", "NS", "ONE", "ONN", "ONS", "PE", "QC", "SK", "TER", "GTA", "NT",
    ]
}

extension JavaLinkedMap {

    /// The map without `key` (the order of the rest kept).
    func removing(_ key: String?) -> JavaLinkedMap {
        guard containsKey(key) else { return self }
        var out = JavaLinkedMap()
        for (k, v) in entries where !(JavaStringKey(k) == JavaStringKey(key)) {
            out.put(k, v)
        }
        return out
    }
}
