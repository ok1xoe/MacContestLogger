import Foundation

/// The N1MM+ **Check window** (https://n1mmwp.hamdocs.com/manual-windows/check-window/): the calls of one source (the
/// log, `master.scp`, the spotted calls, the call history) that could be the call being typed, each with its
/// characters marked against the typed text.
///
/// A candidate matches when it **contains** the typed text (a partial, as Check partial) or, from three characters,
/// when it differs from the typed text by **one edit** (a substitution, an insertion or an omission — a likely copying
/// error). The characters of a match are marked like N1MM's colours: `same` (typed), `extra` (green — characters that
/// complete the call) and `wrong` (red — where the typed text differs). An exact match is reported as such (N1MM
/// shows it bold italic).
///
/// Order: exact match, then calls starting with the typed text, then calls containing it, then the one-edit calls.
/// Within a group shorter calls first and then alphabetically; with **favour end-character differences** (N1MM
/// "Sorting: Favor end-character differences") a call whose first difference from the typed text lies further
/// towards its end ranks first, so `OK1XOE/P` and `OK1XOF` come before `OK1XDE` for `OK1XOE`.
public enum CheckMatcher {

    /// How a character of a candidate relates to the typed text.
    public enum Mark: Equatable, Sendable {
        /// A character of the typed text.
        case same
        /// A character the typed text does not have (N1MM green: it completes the call).
        case extra
        /// A character where the typed text has another one, or next to one the typed text has and the call lacks
        /// (N1MM red: where the copying error probably is).
        case wrong
    }

    /// A run of characters with the same mark.
    public struct Segment: Equatable, Sendable {
        public let text: String
        public let mark: Mark

        public init(text: String, mark: Mark) {
            self.text = text
            self.mark = mark
        }
    }

    /// The kind of match, best first.
    public enum Kind: Int, Comparable, Sendable {
        case exact, prefix, inner, oneEdit

        public static func < (lhs: Kind, rhs: Kind) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public struct Match: Equatable, Sendable {
        public let call: String
        public let kind: Kind
        public let segments: [Segment]

        public init(call: String, kind: Kind, segments: [Segment]) {
            self.call = call
            self.kind = kind
            self.segments = segments
        }

        public var isExact: Bool { kind == .exact }
    }

    /// The shortest typed text that is searched (as Check partial).
    public static let minQuery = 2
    /// One-edit matches are searched from this many characters (as N+1).
    public static let minOneEditQuery = 3

    /// The typed text as the matcher sees it: trimmed, upper case.
    public static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    /// The matches of `query` among `candidates` (normalized; duplicates dropped), best first, at most `limit`.
    public static func matches(_ query: String, candidates: [String], favorEnd: Bool = false,
                               limit: Int = 50) -> [Match] {
        let typed: [Character] = Array(normalized(query))
        guard typed.count >= minQuery, limit > 0 else { return [] }
        var seen: Set<String> = []
        var found: [(match: Match, firstDifference: Int, length: Int)] = []
        for raw in candidates {
            let call: String = normalized(raw)
            guard !call.isEmpty, seen.insert(call).inserted else { continue }
            let chars: [Character] = Array(call)
            guard let match = match(typed: typed, call: chars, text: call) else { continue }
            found.append((match, firstDifference(typed, chars), chars.count))
        }
        found.sort { left, right in
            if left.match.kind != right.match.kind { return left.match.kind < right.match.kind }
            if favorEnd && left.firstDifference != right.firstDifference {
                return left.firstDifference > right.firstDifference
            }
            if left.length != right.length { return left.length < right.length }
            return left.match.call < right.match.call
        }
        return found.prefix(limit).map(\.match)
    }

    /// The match of one candidate (`nil` = not a match).
    public static func match(_ query: String, call: String) -> Match? {
        let typed: [Character] = Array(normalized(query))
        let text: String = normalized(call)
        guard typed.count >= minQuery, !text.isEmpty else { return nil }
        return match(typed: typed, call: Array(text), text: text)
    }

    private static func match(typed: [Character], call: [Character], text: String) -> Match? {
        if call == typed {
            return Match(call: text, kind: .exact, segments: [Segment(text: text, mark: .same)])
        }
        if let start = index(of: typed, in: call) {
            var marks: [Mark] = Array(repeating: .extra, count: call.count)
            for offset in 0..<typed.count {
                marks[start + offset] = .same
            }
            return Match(call: text, kind: start == 0 ? .prefix : .inner, segments: segments(call, marks))
        }
        guard typed.count >= minOneEditQuery, let marks = oneEditMarks(typed, call) else { return nil }
        return Match(call: text, kind: .oneEdit, segments: segments(call, marks))
    }

    /// The marks of a call one edit away from the typed text; `nil` = further away.
    static func oneEditMarks(_ typed: [Character], _ call: [Character]) -> [Mark]? {
        let difference: Int = call.count - typed.count
        guard abs(difference) <= 1 else { return nil }
        var prefix = 0
        while prefix < typed.count && prefix < call.count && typed[prefix] == call[prefix] {
            prefix += 1
        }
        var marks: [Mark] = Array(repeating: .same, count: call.count)
        switch difference {
        case 0:
            // A substitution: the rest after it must be equal.
            guard prefix < call.count, Array(typed[(prefix + 1)...]) == Array(call[(prefix + 1)...]) else {
                return nil
            }
            marks[prefix] = .wrong
        case 1:
            // The call has one more character.
            guard Array(typed[prefix...]) == Array(call[(prefix + 1)...]) else { return nil }
            marks[prefix] = .extra
        default:
            // The call lacks one typed character: the character where it is missing is marked (the last one when
            // the omission is at the end).
            guard prefix < typed.count, Array(typed[(prefix + 1)...]) == Array(call[prefix...]) else { return nil }
            if !call.isEmpty {
                marks[min(prefix, call.count - 1)] = .wrong
            }
        }
        return marks
    }

    /// Where the call first differs from the typed text (the length of the common prefix).
    static func firstDifference(_ typed: [Character], _ call: [Character]) -> Int {
        var index = 0
        while index < typed.count && index < call.count && typed[index] == call[index] {
            index += 1
        }
        return index
    }

    private static func index(of needle: [Character], in haystack: [Character]) -> Int? {
        guard needle.count <= haystack.count else { return nil }
        for start in 0...(haystack.count - needle.count)
        where haystack[start..<(start + needle.count)].elementsEqual(needle) {
            return start
        }
        return nil
    }

    private static func segments(_ call: [Character], _ marks: [Mark]) -> [Segment] {
        var out: [Segment] = []
        var current = ""
        var mark: Mark = marks.first ?? .same
        for (index, character) in call.enumerated() {
            if marks[index] != mark && !current.isEmpty {
                out.append(Segment(text: current, mark: mark))
                current = ""
            }
            mark = marks[index]
            current.append(character)
        }
        if !current.isEmpty {
            out.append(Segment(text: current, mark: mark))
        }
        return out
    }
}
