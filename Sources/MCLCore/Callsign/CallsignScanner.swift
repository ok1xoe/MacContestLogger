import Foundation

/// Finding callsigns in decoded text — from the CW reader and from the digital interface
/// (fldigi). `scan(_:)` returns positions so that a callsign can be clicked in the window;
/// `recent(_:myCall:)` is just a list from the newest for the suggestion above the text.
///
/// Port of Java `callsign/CallsignScanner.java`.
///
/// Positions in `Hit` are offsets in **UTF-16 units**, because Java
/// `Matcher.start()/end()` counts exactly those. The regex is therefore evaluated via
/// `NSRegularExpression`, which works natively on UTF-16; Swift `Regex`
/// returns a `String.Index` over graphemes and the offsets would diverge from Java's
/// for combining characters.
public enum CallsignScanner {

    /// A callsign including a prefix/suffix such as `SP9/OK1XOE/P`.
    ///
    /// Literally the Java `Pattern CALLSIGN`; it is not a reconstruction of the
    /// "callsign" rule but the very same regex. It is matched case-sensitively, the input is
    /// upper-cased beforehand.
    public static let callsignPattern =
        "(?:[A-Z0-9]{1,3}/)?[A-Z0-9]{1,3}[0-9][A-Z0-9]{0,3}[A-Z](?:/[A-Z0-9]{1,4})?"

    /// A found callsign and its range in the original text (`start` inclusive,
    /// `end` exclusive — the Java `Matcher` convention).
    public struct Hit: Equatable, Sendable {
        public let start: Int
        public let end: Int
        public let call: String

        public init(start: Int, end: Int, call: String) {
            self.start = start
            self.end = end
            self.call = call
        }
    }

    /// Callsigns in the text with positions, in order of occurrence. The input is compared
    /// case-insensitively, returned in upper case. Takes only whole words, so
    /// no piece is picked out of a longer string.
    ///
    /// **Recorded divergence from Java.** Java matches over `text.toUpperCase()`,
    /// but then verifies the word boundary using indexes from the upper-cased text over the
    /// **original** text. When upper-casing changes the length (`ß→SS`, `ﬁ→FI`, `ΐ→Ϊ́`),
    /// the indexes diverge and Java fails with `StringIndexOutOfBoundsException`
    /// (measured: `scan("ß"*7 + " ok1xoe")` → `Index 14 out of bounds for
    /// length 14`) — and thereby discards even the hits it already had. Here such a
    /// hit, which cannot be verified against the original text, is just **dropped** and scan
    /// continues. In all cases where Java does not fail the result is identical.
    public static func scan(_ text: String?) -> [Hit] {
        var hits: [Hit] = []
        guard let text, !text.isEmpty else {
            return hits
        }
        // The word boundary must be verified by **UTF-16 units**, not by
        // graphemes: a combining character in Swift sticks to the preceding letter
        // into one grapheme, the regex offsets would then point elsewhere and the hit
        // would be lost. Pinned by the test `scanIndexesByUtf16UnitsNotGraphemes`.
        let original = Array(text.utf16)
        let upper = text.uppercased() as NSString
        let regex = finder
        for match in regex.matches(in: upper as String, range: NSRange(location: 0, length: upper.length)) {
            let start = match.range.location
            let end = start + match.range.length
            guard isWholeWord(original, start, end) else {
                continue
            }
            hits.append(Hit(start: start, end: end, call: upper.substring(with: match.range)))
        }
        return hits
    }

    /// Callsigns from the newest, without your own callsign, duplicates and obvious
    /// non-callsigns (reports, all digits, T/N abbreviations from CW).
    public static func recent(_ text: String?, myCall: String?) -> [String] {
        var found: [String] = []
        guard let text else {
            return found
        }
        // Java `text.toUpperCase().trim().split("\\s+")` — in this order.
        let words = splitOnSpaces(JavaText.trim(text.uppercased()))
        for word in words.reversed() {
            if word.isEmpty
                || JavaChar.equalsIgnoreCase(word, myCall)
                // Java `contains("*")` looks for a UTF-16 unit, Swift `contains`
                // a whole grapheme: `"DL1ABC*\u{0301}".contains("*")` is `false`
                // in Swift, `true` in Java. Today it is not observable (a word
                // with `*` does not pass the callsign pattern anyway), but exactness is free.
                || word.utf16.contains(0x2A)
                || isReportOrAbbreviation(word) {
                continue
            }
            if isWholeCallsign(word), !found.contains(word) {
                found.append(word)
            }
        }
        return found
    }

    // MARK: - Regexes

    /// Substring search (Java `Matcher.find()`).
    private static let finder = makeRegex(callsignPattern)

    /// Match of the whole input (Java `Matcher.matches()`). `\A…\z` is exactly what
    /// `matches()` means — `.anchored` binds only the start.
    private static let wholeMatcher = makeRegex("\\A(?:\(callsignPattern))\\z")

    /// Java `[0-9TN]+` on a whole word.
    private static let reportMatcher = makeRegex("\\A[0-9TN]+\\z")

    /// The patterns are constants in this file, so they can never fail to
    /// compile; `try!` here is an unintended programmer error, not an input error.
    private static func makeRegex(_ pattern: String) -> NSRegularExpression {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: pattern)
    }

    private static func isWholeCallsign(_ word: String) -> Bool {
        matchesWhole(wholeMatcher, word)
    }

    private static func isReportOrAbbreviation(_ word: String) -> Bool {
        matchesWhole(reportMatcher, word)
    }

    private static func matchesWhole(_ regex: NSRegularExpression, _ word: String) -> Bool {
        let text = word as NSString
        return regex.firstMatch(in: word, range: NSRange(location: 0, length: text.length)) != nil
    }

    // MARK: - Word boundary

    /// If a hit is adjacent to an alphanumeric character or `/`, it is not a standalone
    /// word. Indexes outside the original text mean the hit cannot be verified —
    /// Java throws `StringIndexOutOfBoundsException` there (see `scan`).
    private static func isWholeWord(_ text: [UInt16], _ start: Int, _ end: Int) -> Bool {
        if start != 0 {
            guard start - 1 < text.count else { return false }
            if isCallChar(text[start - 1]) { return false }
        }
        if end != text.count {
            guard end < text.count else { return false }
            if isCallChar(text[end]) { return false }
        }
        return true
    }

    /// Java `Character.isLetterOrDigit(c) || c == '/'`.
    private static func isCallChar(_ unit: UInt16) -> Bool {
        unit == 0x2F || JavaChar.isLetterOrDigit(unit)
    }

    // MARK: - Splitting into words

    /// Java `split("\\s+")`, where `\s` without `UNICODE_CHARACTER_CLASS` is only
    /// `[ \t\n\u{0B}\f\r]`. A no-break space U+00A0 therefore does **not** separate words
    /// (measured: `recent("DL1ABC\u{00A0}OK2XYZ", …)` returns an empty list),
    /// nor do U+001C…U+001F.
    ///
    /// For empty input Java returns a one-element array with an empty string;
    /// here an empty array results — the caller skips the empty word anyway.
    private static func splitOnSpaces(_ text: String) -> [String] {
        var out: [String] = []
        var current: [UInt16] = []
        for unit in text.utf16 {
            if JavaChar.isRegexSpace(unit) {
                if !current.isEmpty {
                    out.append(JavaChar.string(current))
                    current = []
                }
            } else {
                current.append(unit)
            }
        }
        if !current.isEmpty {
            out.append(JavaChar.string(current))
        }
        return out
    }
}
