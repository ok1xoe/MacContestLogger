import Foundation

/// Regular expression in the **Java** dialect (`java.util.regex.Pattern`, JDK 21),
/// executed via `NSRegularExpression` (ICU).
///
/// The pattern is not passed to ICU as is: `JavaRegexTranslator` parses it
/// by porting Java's parser and expresses every construct in ICU **explicitly**
/// (classes as an enumeration of code point intervals, anchors as lookarounds), so
/// dialect differences do not matter. It mainly compensates for:
/// - `\d \s \w` and `\b` are ASCII in Java, Unicode in ICU (`\d` accepts `٣`,
///   `\s` accepts U+00A0);
/// - Java's `.` does not match `\n \r \u0085    `, ICU additionally not `\u000B \u000C`;
/// - Java's `^`/`$`/`\Z` (also in `(?m)`) have a different set of line terminators and different
///   behavior around `\r\n` and at the end of input;
/// - `(?i)` is ASCII-only in Java (`k` does not match the Kelvin `K`, `ss` does not match `ß`);
/// - pattern validity: syntax errors are reported with the **Java** description and index.
///
/// What cannot be converted, the adapter **loudly rejects** (`JavaRegexError.Kind.unsupported`)
/// — these are deliberate divergences from Java v1.1.1.
///
/// Match positions are in **UTF-16 units** like Java's `Matcher.start()/end()`.
struct JavaRegex: Sendable {

    /// The original Java pattern.
    let pattern: String
    /// Number of capturing groups (Java `Matcher.groupCount()`).
    let groupCount: Int
    /// Named groups `(?<name>…)` → group number.
    let groupNames: [String: Int]
    /// The translated pattern for ICU (for debugging and tests).
    let icuPattern: String

    private let finder: NSRegularExpression
    private let whole: NSRegularExpression

    /// Equivalent of `Pattern.compile(pattern)`. The error carries the Java text
    /// (`PatternSyntaxException.getMessage()`), or the reason for rejection.
    init(_ pattern: String) throws(JavaRegexError) {
        let translated = try JavaRegexTranslator.translate(pattern)
        self.pattern = pattern
        self.groupCount = translated.groupCount
        self.groupNames = translated.groupNames
        self.icuPattern = translated.icu
        do {
            finder = try NSRegularExpression(pattern: "(?:\(translated.icu))")
            whole = try NSRegularExpression(pattern: "\\A(?:\(translated.icu))\\z")
        } catch {
            // The translated pattern is always syntactically fine; ICU rejects only what
            // it cannot execute (unbounded look-behind and the like).
            throw JavaRegexError(
                kind: .unsupported,
                reason: "přeložený vzor ICU odmítla (typicky look-behind bez omezené délky)",
                index: -1,
                pattern: pattern
            )
        }
    }

    /// Java `Pattern.matcher(text).matches()`: a match of the **whole** text.
    func matches(_ text: String) -> Bool {
        wholeMatch(text) != nil
    }

    /// Java `matcher.matches()` and then `group(n)`: a match of the whole text including groups.
    func wholeMatch(_ text: String) -> JavaRegexMatch? {
        let ns = text as NSString
        guard let result = whole.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        return JavaRegexMatch(result, in: ns, groupCount: groupCount)
    }

    /// Java's first `matcher.find()`.
    func firstMatch(in text: String) -> JavaRegexMatch? {
        let ns = text as NSString
        guard let result = finder.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        return JavaRegexMatch(result, in: ns, groupCount: groupCount)
    }

    /// All hits of repeated `matcher.find()`.
    func allMatches(in text: String) -> [JavaRegexMatch] {
        let ns = text as NSString
        return finder.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .map { JavaRegexMatch($0, in: ns, groupCount: groupCount) }
    }

    /// Java `matcher.replaceFirst(Matcher.quoteReplacement(replacement))`:
    /// the first hit is replaced **literally** (`$` and `\` are not interpreted).
    /// Without a hit it returns the text unchanged.
    func replaceFirst(in text: String, with replacement: String) -> String {
        guard let match = firstMatch(in: text) else { return text }
        let ns = text as NSString
        return ns.replacingCharacters(
            in: NSRange(location: match.range.lowerBound, length: match.range.count),
            with: replacement
        )
    }

    /// Java `Pattern.split(text, limit)` (= `String.split(regex, limit)`),
    /// ported 1:1 from JDK 21 including all quirks:
    /// - a zero-width match at the start of input does not produce a leading empty part,
    /// - without a usable match `[text]` is returned (also for empty text),
    /// - `limit > 0` limits the number of parts, `limit == 0` removes trailing empty parts.
    func split(_ text: String, limit: Int) -> [String] {
        let ns = text as NSString
        var index = 0
        let matchLimited = limit > 0
        var parts: [String] = []
        for match in allMatches(in: text) {
            if !matchLimited || parts.count < limit - 1 {
                if index == 0 && index == match.range.lowerBound && match.range.isEmpty {
                    continue
                }
                parts.append(ns.substring(with: NSRange(location: index, length: match.range.lowerBound - index)))
                index = match.range.upperBound
            } else if parts.count == limit - 1 {
                parts.append(ns.substring(from: index))
                index = match.range.upperBound
            }
        }
        if index == 0 {
            return [text]
        }
        if !matchLimited || parts.count < limit {
            parts.append(ns.substring(from: index))
        }
        if limit == 0 {
            while let last = parts.last, last.isEmpty {
                parts.removeLast()
            }
        }
        return parts
    }
}

/// A single hit of a Java regex. Ranges are in UTF-16 units.
struct JavaRegexMatch: Equatable, Sendable {
    /// Range of the whole match (`start()..<end()`).
    let range: Range<Int>
    /// Group 0 is the whole match; `nil` = the group did not participate.
    private let groups: [String?]

    fileprivate init(_ result: NSTextCheckingResult, in text: NSString, groupCount: Int) {
        range = result.range.location..<(result.range.location + result.range.length)
        groups = (0...groupCount).map { index in
            let r = result.range(at: index)
            return r.location == NSNotFound ? nil : text.substring(with: r)
        }
    }

    /// Java `matcher.group(index)`; outside the group range `nil`.
    func group(_ index: Int) -> String? {
        groups.indices.contains(index) ? groups[index] : nil
    }
}

/// Error translating a Java pattern.
struct JavaRegexError: Error, Equatable, Sendable {
    enum Kind: Sendable {
        /// Java rejects the pattern too: `reason` and `index` are Java's
        /// `PatternSyntaxException.getDescription()` and `getIndex()`.
        case syntax
        /// The adapter does not convert the construct (Java may accept it); `reason` is in Czech.
        case unsupported
    }

    let kind: Kind
    let reason: String
    /// Index in code points of the pattern after expanding `\Q…\E` as in Java; −1 = unknown.
    let index: Int
    let pattern: String

    /// Text for the user. For `syntax` character by character Java's `getMessage()`:
    /// the description, "near index N", the pattern and a line with a caret (tabs are repeated).
    var message: String {
        var text = reason
        if index >= 0 {
            text += kind == .syntax ? " near index \(index)" : " poblíž indexu \(index)"
        }
        text += "\n" + pattern
        let units = Array(pattern.utf16)
        if index >= 0 && index < units.count {
            text += "\n"
            for unit in units[0..<index] {
                text += unit == 0x09 ? "\t" : " "
            }
            text += "^"
        }
        return text
    }
}
