/// Result of loading a goals file (Java record `goals/GoalImport`).
public struct GoalImport: Equatable, Sendable {
    /// The loaded set.
    public let goals: GoalSet
    /// Lines the parser did not understand (verbatim, untrimmed) — nothing is dropped silently, the operator should see
    /// what did not make it into the plan (UI: "…; %s řádků nerozpoznáno: <první>").
    public let ignoredLines: [String]
    /// Band columns found in the file (only for an export from the statistics), so that importing a single band can be offered.
    public let bands: [String]

    public init(goals: GoalSet, ignoredLines: [String], bands: [String]) {
        self.goals = goals
        self.ignoredLines = ignoredLines
        self.bands = bands
    }
}

/// Loads goals files in all shapes that N1MM accepts (Java `goals/GoalFileParser`):
/// 1. export from `View → Statistics` — the table `Day Hr <bands> Tot Accum`;
/// 2. hand-written pairs `hour goal` separated by whitespace;
/// 3. the same separated by a comma (CSV);
/// 4. export from the `Edit Goals` dialog — the header `Type=GOAL` and pairs.
///
/// Empty lines and lines starting with `#` (after `trim()`) are skipped. A key below 100 is taken as the hour
/// of the first day of the contest, from 100 up as `dhh`. What the parser does not understand ends up in `ignoredLines`.
///
/// Java details that are kept (measured by the maintainer-only probe):
/// - tokens = `trim()` (characters ≤ U+0020) and splitting by the regex `\s+` — ASCII only `[ \t\n\x0B\f\r]`, so
///   `"1\u{A0}2"` (NBSP) is one token and the line ends up in `ignoredLines`;
/// - numbers `Integer.valueOf(s.trim())` — a sign and **any Unicode decimal digits** by UTF-16
///   units (`"٣ 50"` → 103 = 50), `int` overflow → unrecognised;
/// - the header `Type=` is recognised after `trim().toUpperCase().startsWith("TYPE=")` — `"type = goal"` (with spaces)
///   is not a header and is reported as unrecognised; a line with a BOM (`"\u{FEFF}Type=GOAL"`) too;
/// - `toUpperCase()` in Java uses the default locale, Swift none (`JavaText.toUpperCase`) — they differ only
///   under a Turkish/Azerbaijani/Lithuanian locale (section 31: not emulated);
/// - the date in the table `LocalDate.parse` (ISO, strict: `+2026-08-10` and `2026-8-10` are invalid, `-2026-08-10`
///   is valid), day = difference of calendar dates from the first valid row + 1 (`int`, wraps).
public enum GoalFileParser {

    /// - Parameter band: band from the table columns, or `nil`/empty for the sum of all (ignored for the other shapes). A band that
    ///   is not in the table gives the sum column, as in Java.
    public static func parse(_ lines: [String], _ band: String?) -> GoalImport {
        let bands: [String] = bandColumns(lines)
        return bands.isEmpty ? parsePairs(lines) : parseTable(lines, bands, band)
    }

    /// Band columns from the first table header; empty when it is not a table.
    private static func bandColumns(_ lines: [String]) -> [String] {
        for line in lines {
            let t: [String] = tokens(line)
            guard t.count > 3, JavaChar.equalsIgnoreCase(t[0], "Day"), JavaChar.equalsIgnoreCase(t[1], "Hr") else {
                continue
            }
            var bands: [String] = []
            var i = 2
            while i < t.count && !JavaChar.equalsIgnoreCase(t[i], "Tot") {
                bands.append(t[i])
                i += 1
            }
            return bands
        }
        return []
    }

    private static func parseTable(_ lines: [String], _ bands: [String], _ band: String?) -> GoalImport {
        var goals: [Int32: Int32] = [:]
        var ignored: [String] = []
        let column: Int = columnIndex(bands, band)
        var firstDay: Int64?

        for line in lines {
            if skippable(line) {
                continue
            }
            let t: [String] = tokens(line)
            if t.count > 1 && (JavaChar.equalsIgnoreCase(t[0], "Day") || JavaChar.equalsIgnoreCase(t[0], "Total")) {
                continue   // header and total row
            }
            let date: Int64? = parseDate(t.isEmpty ? "" : t[0])
            let hour: Int32? = date == nil ? nil : parseInt(t.count > 1 ? t[1] : "")
            // 2 fixed columns (date, hour) + bands + Tot + Accum
            guard let date, let hour, t.count >= 3 + bands.count else {
                ignored.append(line)
                continue
            }
            let first: Int64 = firstDay ?? date
            firstDay = first
            let valueIndex: Int = column < 0 ? 2 + bands.count : 2 + column
            guard let value = parseInt(t[valueIndex]) else {
                ignored.append(line)
                continue
            }
            goals[GoalSet.key(GoalSet.contestDay(first, date), hour)] = value
        }
        return GoalImport(goals: GoalSet.of(goals), ignoredLines: ignored, bands: bands)
    }

    /// `band == null || band.isBlank() ? -1 : bands.indexOf(band)` (match by UTF-16 like `equals`).
    private static func columnIndex(_ bands: [String], _ band: String?) -> Int {
        guard let band, !JavaText.isBlank(band) else { return -1 }
        return bands.firstIndex { JavaText.equals($0, band) } ?? -1
    }

    private static func parsePairs(_ lines: [String]) -> GoalImport {
        var goals: [Int32: Int32] = [:]
        var ignored: [String] = []

        for line in lines {
            if skippable(line) || isTypeHeader(line) {
                continue
            }
            let t: [String] = tokens(commasToSpaces(line))
            let key: Int32? = t.isEmpty ? nil : parseInt(t[0])
            let value: Int32? = t.count > 1 ? parseInt(t[1]) : nil
            guard let key, let value else {
                ignored.append(line)
                continue
            }
            // Below 100 it is the hour of the first day, from 100 up directly the key dhh.
            goals[key < 100 ? GoalSet.key(1, key) : key] = value
        }
        return GoalImport(goals: GoalSet.of(goals), ignoredLines: ignored, bands: [])
    }

    /// `line.trim().toUpperCase().startsWith("TYPE=")` by UTF-16 units.
    private static func isTypeHeader(_ line: String) -> Bool {
        let upper: String = JavaText.toUpperCase(JavaText.trim(line))
        return upper.utf16.starts(with: "TYPE=".utf16)
    }

    /// `line.replace(',', ' ')`.
    private static func commasToSpaces(_ line: String) -> String {
        var out = String.UnicodeScalarView()
        for scalar in line.unicodeScalars {
            out.append(scalar == "," ? " " : scalar)
        }
        return String(out)
    }

    private static func skippable(_ line: String) -> Bool {
        let s: String = JavaText.trim(line)
        return s.isEmpty || s.utf16.first == 0x23 // '#'
    }

    /// `trim()` and `split("\\s+")`: after trimming it neither starts nor ends with a regex whitespace character, so empty
    /// parts do not arise; an empty line → no token.
    static func tokens(_ line: String) -> [String] {
        let s: String = JavaText.trim(line)
        var result: [String] = []
        var current = String.UnicodeScalarView()
        for scalar in s.unicodeScalars {
            if isRegexSpace(scalar) {
                if !current.isEmpty {
                    result.append(String(current))
                    current = String.UnicodeScalarView()
                }
            } else {
                current.append(scalar)
            }
        }
        if !current.isEmpty {
            result.append(String(current))
        }
        return result
    }

    /// Java regex `\s` = `[ \t\n\x0B\f\r]`.
    private static func isRegexSpace(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x20, 0x09, 0x0A, 0x0B, 0x0C, 0x0D: return true
        default: return false
        }
    }

    /// `Integer.valueOf(s.trim())`, error → `nil`.
    private static func parseInt(_ s: String) -> Int32? {
        JavaInteger.parseInt(JavaText.trim(s))
    }

    /// `LocalDate.parse(s.trim())` → epoch day, error → `nil`.
    private static func parseDate(_ s: String) -> Int64? {
        isoLocalDate(JavaText.trim(s))
    }
}
