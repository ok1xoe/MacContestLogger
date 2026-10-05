/// Splitting decoded text into words with positions (Java `digital/TextTokens`) — so that in the window one can
/// click exactly the word the user is aiming at.
///
/// Positions are in **UTF-16 units** (`😀` = 2) like Java `int` indexes; the separator is Java
/// `Character.isWhitespace(char)` per unit (NBSP, U+2007, U+202F, U+200B and U+0085 are not whitespace;
/// U+2003, U+001C–U+001F, U+2028 are).
public enum TextTokens {

    /// A word and its range in the text.
    public struct Token: Equatable, Sendable {
        public let start: Int
        public let end: Int
        public let word: String

        public init(start: Int, end: Int, word: String) {
            self.start = start
            self.end = end
            self.word = word
        }
    }

    /// Words by lines (split only on `\n`, `\r` is a whitespace character within a line); empty lines are skipped, positions
    /// are valid in the whole text. An exchange belongs to the station whose callsign is on the same line.
    public static func byLine(_ text: String?) -> [[Token]] {
        var out: [[Token]] = []
        guard let text, !text.isEmpty else { return out }
        let units = Array(text.utf16)
        var lineStart = 0
        while lineStart <= units.count {
            let newline = units[lineStart...].firstIndex(of: 0x0A)
            let lineEnd = newline ?? units.count
            let line = words(units, from: lineStart, to: lineEnd)
            if !line.isEmpty {
                out.append(line)
            }
            guard let newline else { break }
            lineStart = newline + 1
        }
        return out
    }

    /// Words separated by whitespace, in order of occurrence.
    public static func words(_ text: String?) -> [Token] {
        guard let text, !text.isEmpty else { return [] }
        let units = Array(text.utf16)
        return words(units, from: 0, to: units.count)
    }

    private static func words(_ units: [UInt16], from: Int, to: Int) -> [Token] {
        var out: [Token] = []
        var i = from
        while i < to {
            while i < to && JavaChar.isWhitespace(units[i]) {
                i += 1
            }
            let start = i
            while i < to && !JavaChar.isWhitespace(units[i]) {
                i += 1
            }
            if i > start {
                out.append(Token(start: start, end: i, word: JavaChar.string(Array(units[start..<i]))))
            }
        }
        return out
    }
}
