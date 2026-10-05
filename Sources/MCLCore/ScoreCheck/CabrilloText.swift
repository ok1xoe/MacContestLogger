import Foundation

/// Cabrillo log text as a Java `String`: an array of UTF-16 units and line ranges. All
/// `ScoreCheck` operations (trims, `toUpperCase().startsWith`, `substring`, `split`) work
/// by UTF-16 units like Java; the text is converted once per log.
struct CabrilloText {

    static let qsoPrefix = Array("QSO:".utf16)
    private static let categoryPrefix = Array("CATEGORY".utf16)
    private static let checklog = Array("CHECKLOG".utf16)

    let units: [UInt16]
    /// Java `content.split("\\r?\\n")`: lines separated by `\n`, one `\r` before it belongs
    /// to the separator. A lone `\r` does **not** split a line. (Java's dropping of trailing empty
    /// lines is not done here — an empty line affects nothing.)
    let lines: [Range<Int>]

    init(_ content: String) {
        units = Array(content.utf16)
        var lines: [Range<Int>] = []
        var start = 0
        for (i, unit) in units.enumerated() where unit == 0x0A {
            let end = (i > start && units[i - 1] == 0x0D) ? i - 1 : i
            lines.append(start..<end)
            start = i + 1
        }
        lines.append(start..<units.count)
        self.lines = lines
    }

    func string(_ range: Range<Int>) -> String {
        String(decoding: units[range], as: UTF16.self)
    }

    // MARK: - trims

    /// Java `String.trim()`: characters ≤ U+0020 from both ends.
    func javaTrim(_ range: Range<Int>) -> Range<Int> {
        var lower = range.lowerBound
        var upper = range.upperBound
        while lower < upper && units[lower] <= 0x20 { lower += 1 }
        while upper > lower && units[upper - 1] <= 0x20 { upper -= 1 }
        return lower..<upper
    }

    /// Java `stripBlank`: edge characters `Character.isWhitespace || isSpaceChar || U+FEFF`.
    func stripBlank(_ range: Range<Int>) -> Range<Int> {
        var lower = range.lowerBound
        var upper = range.upperBound
        while lower < upper && Self.isBlank(units[lower]) { lower += 1 }
        while upper > lower && Self.isBlank(units[upper - 1]) { upper -= 1 }
        return lower..<upper
    }

    /// `isWhitespace(c) || isSpaceChar(c) || c == U+FEFF` for a Java `char`: U+0009…U+000D,
    /// U+001C…U+001F and categories Zs/Zl/Zp (JDK 21 = Unicode 15; U+180E is no longer Zs).
    /// Half of a surrogate pair, U+0085 and U+200B are not blank.
    static func isBlank(_ c: UInt16) -> Bool {
        switch c {
        case 0x09...0x0D, 0x1C...0x20, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF:
            return true
        default:
            return false
        }
    }

    // MARK: - upper case

    /// Java `string(range).toUpperCase().startsWith(prefix)` for an ASCII `prefix`.
    ///
    /// `toUpperCase` is a **full** mapping that can lengthen the text (`ﬆ` → `ST`, `ß` → `SS`),
    /// so `CONTEﬆ:` starts with `CONTEST:` — and Java then does `substring(prefix.length())`
    /// in the **original** text. The first `n` units of the result are determined by at most `n` units of the input
    /// (each character gives at least one), so it suffices to convert a window of `n + 1` units (+1 because of a
    /// surrogate pair at the boundary). Pure ASCII takes the fast path.
    func upperStartsWith(_ range: Range<Int>, _ prefix: [UInt16]) -> Bool {
        let window = range.lowerBound..<min(range.upperBound, range.lowerBound + prefix.count + 1)
        if units[window].allSatisfy({ $0 < 0x80 }) {
            guard window.count >= prefix.count else { return false }
            for (offset, expected) in prefix.enumerated()
            where JavaChar.toUpperCase(units[range.lowerBound + offset]) != expected {
                return false
            }
            return true
        }
        // port convention: `uppercased()` = Java `toUpperCase()`
        return string(window).uppercased().utf16.starts(with: prefix)
    }

    // MARK: - header

    /// Java `header(content, key)`: the **first** line that, after `stripBlank`, starts with `KEY:`
    /// (case-insensitive), value = `stripBlank` of the rest.
    ///
    /// The rest is taken in the original line from index `KEY:`.length — if the line is shorter (the key
    /// lengthened by a ligature: `CONTEﬆ:`), Java throws `StringIndexOutOfBoundsException`,
    /// which in `evaluate` brings down the whole log; copied as a `Failure` of the same category and message.
    func header(_ key: String) throws(ScoreCheck.Failure) -> String? {
        // port convention: `uppercased()` = Java `toUpperCase()`
        let prefix = Array((key.uppercased() + ":").utf16)
        for line in lines {
            let t = stripBlank(line)
            if upperStartsWith(t, prefix) {
                let begin = t.lowerBound + prefix.count
                if begin > t.upperBound {
                    throw ScoreCheck.Failure(javaClass: "StringIndexOutOfBoundsException",
                                             message: "Range [\(prefix.count), \(t.count)) out of bounds for length \(t.count)")
                }
                return string(stripBlank(begin..<t.upperBound))
            }
        }
        return nil
    }

    /// Java `isChecklog`: a line that, after `trim().toUpperCase()`, starts with `CATEGORY` and contains
    /// `CHECKLOG`.
    func isChecklog() -> Bool {
        for line in lines {
            let t = javaTrim(line)
            guard upperStartsWith(t, Self.categoryPrefix) else { continue }
            // port convention: `uppercased()` = Java `toUpperCase()`
            let upper = Array(string(t).uppercased().utf16)
            if Self.contains(upper, Self.checklog) {
                return true
            }
        }
        return false
    }

    private static func contains(_ haystack: [UInt16], _ needle: [UInt16]) -> Bool {
        guard haystack.count >= needle.count else { return false }
        for start in 0...(haystack.count - needle.count)
        where haystack[start..<(start + needle.count)].elementsEqual(needle) {
            return true
        }
        return false
    }

    /// Java `skipReason`: `checklog`, `bez CLAIMED-SCORE` (missing or unreadable), otherwise `nil`.
    func skipReason() -> String? {
        if isChecklog() {
            return "checklog"
        }
        // `CLAIMED-SCORE:` has no character from which the full `toUpperCase` would make more characters inside
        // the key, so `header` cannot throw here (Java would not catch the exception here at all).
        let claimed = (try? header("CLAIMED-SCORE")) ?? nil
        if ScoreCheck.parseLong(claimed) == nil {
            return "bez CLAIMED-SCORE"
        }
        return nil
    }

    // MARK: - QSO lines

    /// Java `rest.split("\\s+")` over the **trimmed** text (`trim` already removed the edge
    /// `\s`): parts between runs of ASCII `\s` (`[ \t\n\u{0B}\f\r]` — an NBSP does not split a token).
    /// Empty input gives one empty part like Java.
    func splitWhitespace(_ range: Range<Int>) -> [Range<Int>] {
        var parts: [Range<Int>] = []
        var start = range.lowerBound
        var i = range.lowerBound
        while i < range.upperBound {
            if JavaChar.isRegexSpace(units[i]) {
                if i > start {
                    parts.append(start..<i)
                }
                i += 1
                start = i
            } else {
                i += 1
            }
        }
        if start < range.upperBound || parts.isEmpty {
            parts.append(start..<range.upperBound)
        }
        return parts
    }

    /// Java `detectOwnGrid(content, sent)`: the first token matching
    /// `[A-R]{2}[0-9]{2}([A-X]{2})?` (CASE_INSENSITIVE without UNICODE_CASE = ASCII only) among the
    /// sent fields (`tok[5…4+sent]`) of the first `QSO:` line that has one; upper-cased.
    func detectOwnGrid(sent: Int) -> String? {
        for line in lines {
            let t = javaTrim(line)
            guard upperStartsWith(t, Self.qsoPrefix) else { continue }
            let tok = splitWhitespace(javaTrim(t.lowerBound + Self.qsoPrefix.count..<t.upperBound))
            var i = 5
            while i <= 4 + sent && i < tok.count {
                if isGrid(tok[i]) {
                    return String(decoding: units[tok[i]].map { JavaChar.toUpperCase($0) }, as: UTF16.self)
                }
                i += 1
            }
        }
        return nil
    }

    private func isGrid(_ range: Range<Int>) -> Bool {
        guard range.count == 4 || range.count == 6 else { return false }
        func letter(_ unit: UInt16, _ last: UInt16) -> Bool {
            let upper = unit >= 0x61 && unit <= 0x7A ? unit - 0x20 : unit
            return upper >= 0x41 && upper <= last
        }
        let u = range.lowerBound
        guard letter(units[u], 0x52), letter(units[u + 1], 0x52),           // A-R
              units[u + 2] >= 0x30 && units[u + 2] <= 0x39,
              units[u + 3] >= 0x30 && units[u + 3] <= 0x39 else {
            return false
        }
        return range.count == 4 || (letter(units[u + 4], 0x58) && letter(units[u + 5], 0x58)) // A-X
    }
}
