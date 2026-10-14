import Foundation

/// An F-key macro with a parameter (N1MM `{COMMENT text}`…): a program action like `CwMessage.Action`, carried
/// beside the message's actions and performed by the app. Swift-only.
public enum MacroCommand: Equatable, Sendable {
    /// `{COMMENT text}`: the text goes to the note of the QSO in progress, or of the last logged QSO when the call
    /// field is empty.
    case comment(String)

    /// The command of a parameterized macro (`raw` = the whole macro with its braces); `nil` = not a parameterized
    /// macro this app knows.
    static func parse(_ raw: String) -> MacroCommand? {
        guard let (name, argument) = split(raw) else { return nil }
        switch name {
        case "COMMENT":
            return argument.isEmpty ? nil : .comment(argument)
        default:
            return nil
        }
    }

    /// `{NAME argument}` → (`NAME` in upper case, the argument as written, trimmed); `nil` without a space.
    static func split(_ raw: String) -> (String, String)? {
        guard raw.hasPrefix("{"), raw.hasSuffix("}") else { return nil }
        let inner: Substring = raw.dropFirst().dropLast()
        guard let space = inner.firstIndex(of: " ") else { return nil }
        let name: String = String(inner[..<space]).uppercased()
        let argument: String = String(inner[inner.index(after: space)...]).trimmingCharacters(in: .whitespaces)
        return (name, argument)
    }
}

/// N1MM `{VARYMSG1&Primary&Alternate&N&}` / `{VARYMSG2…}`: an alternating message. `N` = 0 sends the primary text
/// every time, 1 the alternate every time, N > 1 the alternate every N-th time. The counter of each macro is kept by
/// the app (`counts[0]` for VARYMSG1, `counts[1]` for VARYMSG2: how many times the macro was sent before).
public enum VaryMessage {

    /// The text with every VARYMSG macro replaced by the text chosen for this send, and the macros used (1, 2).
    public static func expand(_ text: String, counts: [Int]) -> (text: String, used: [Int]) {
        var out: String = ""
        var used: [Int] = []
        var rest: Substring = Substring(text)
        while let match = nextMacro(in: rest) {
            out += rest[..<match.start]
            let count: Int = match.number - 1 < counts.count ? counts[match.number - 1] : 0
            out += alternate(every: match.every, sendNumber: count + 1) ? match.alternate : match.primary
            if !used.contains(match.number) {
                used.append(match.number)
            }
            rest = rest[match.end...]
        }
        out += rest
        return (out, used)
    }

    /// Whether send number `sendNumber` (from 1) takes the alternate text.
    static func alternate(every: Int, sendNumber: Int) -> Bool {
        if every <= 0 {
            return false
        }
        return every == 1 || sendNumber % every == 0
    }

    private struct Match {
        let start: Substring.Index
        let end: Substring.Index
        let number: Int
        let primary: Substring
        let alternate: Substring
        let every: Int
    }

    /// The first well-formed `{VARYMSG<1|2> &a&b&n&}` (ASCII case-insensitive name, spaces before the first `&` and
    /// before `}` allowed). A malformed one is left in the text (and reported as an unknown macro later).
    private static func nextMacro(in text: Substring) -> Match? {
        var search: Substring.Index = text.startIndex
        while let range = text[search...].range(of: "{VARYMSG", options: [.caseInsensitive]) {
            if let match = parse(text, from: range) {
                return match
            }
            search = range.upperBound
        }
        return nil
    }

    private static func parse(_ text: Substring, from range: Range<Substring.Index>) -> Match? {
        var index: Substring.Index = range.upperBound
        guard index < text.endIndex, let number = Int(String(text[index])), number == 1 || number == 2 else {
            return nil
        }
        index = text.index(after: index)
        while index < text.endIndex, text[index] == " " {
            index = text.index(after: index)
        }
        guard index < text.endIndex, text[index] == "&" else { return nil }
        var fields: [Substring] = []
        var fieldStart: Substring.Index = text.index(after: index)
        var cursor: Substring.Index = fieldStart
        while fields.count < 3, cursor < text.endIndex {
            if text[cursor] == "&" {
                fields.append(text[fieldStart..<cursor])
                fieldStart = text.index(after: cursor)
            }
            cursor = text.index(after: cursor)
        }
        guard fields.count == 3 else { return nil }
        cursor = fieldStart
        while cursor < text.endIndex, text[cursor] == " " {
            cursor = text.index(after: cursor)
        }
        guard cursor < text.endIndex, text[cursor] == "}",
              let every = Int(fields[2].trimmingCharacters(in: .whitespaces)), every >= 0 else { return nil }
        return Match(start: range.lowerBound, end: text.index(after: cursor), number: number, primary: fields[0],
                     alternate: fields[1], every: every)
    }
}
