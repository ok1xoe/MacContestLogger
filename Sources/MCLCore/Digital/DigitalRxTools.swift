/// N1MM „Callsign Validity and Highlight Routines" of the Digital Interface.
public enum DigitalCallValidity: String, CaseIterable, Sendable {
    /// Anything that looks like a call is highlighted (by its multiplier status).
    case generic = "GENERIC"
    /// Only calls found in at least one chosen resource (Master.scp, call history, spotted, logged).
    case resources = "RESOURCES"
    /// Generic highlighting; calls not found in the resources are additionally marked yellow.
    case combined = "COMBINED"

    public static func from(_ raw: String) -> DigitalCallValidity {
        DigitalCallValidity(rawValue: raw) ?? .combined
    }

    /// How a call is shown: `nil` = not highlighted (and not clickable); otherwise whether it carries the yellow
    /// „unverified" mark.
    public func highlight(verified: Bool) -> Bool? {
        switch self {
        case .generic: false
        case .resources: verified ? false : nil
        case .combined: !verified
        }
    }
}

/// RTTY's Letters/Figures shift (ITA2 with the US-TTY figures, as MMTTY and fldigi print them): a word copied in the
/// wrong shift (`TOO` for `599`, `UE` for `73`) converted to the other case.
public enum LettersFigures {

    private static let pairs: [(Character, Character)] = [
        ("Q", "1"), ("W", "2"), ("E", "3"), ("R", "4"), ("T", "5"), ("Y", "6"), ("U", "7"), ("I", "8"), ("O", "9"),
        ("P", "0"), ("A", "-"), ("S", "'"), ("D", "$"), ("F", "!"), ("G", "&"), ("H", "#"), ("J", "\u{07}"),
        ("K", "("), ("L", ")"), ("Z", "\""), ("X", "/"), ("C", ":"), ("V", ";"), ("B", "?"), ("N", ","), ("M", "."),
    ]

    private static let toFigure: [Character: Character] = Dictionary(uniqueKeysWithValues: pairs)
    private static let toLetter: [Character: Character] = Dictionary(uniqueKeysWithValues: pairs.map { ($1, $0) })

    /// Every character swapped to the other shift (upper case); characters without a pair (space, `=`) stay.
    public static func convert(_ word: String) -> String {
        String(word.uppercased().map { toFigure[$0] ?? toLetter[$0] ?? $0 })
    }
}

/// N1MM „Use Search routine to find Master.scp in Garbage Text": a known call inside a word that is not a call
/// (`XXDL1ABCQQ`). When a word holds several, the last one wins and at one end position the longest one.
public enum ScpGarbageSearch {

    public static let minLength = 3
    public static let maxLength = 12

    /// The call found in `word` (UTF-16 offsets within the word, `end` exclusive), `nil` when there is none.
    public static func find(_ word: String, contains: (String) -> Bool) -> (start: Int, end: Int, call: String)? {
        let units: [UInt16] = Array(word.uppercased().utf16)
        guard units.count > minLength else { return nil }
        var end: Int = units.count
        while end >= minLength {
            var start: Int = Swift.max(0, end - maxLength)
            while end - start >= minLength {
                let candidate: String = String(decoding: units[start..<end], as: UTF16.self)
                if contains(candidate) {
                    return (start, end, candidate)
                }
                start += 1
            }
            end -= 1
        }
        return nil
    }
}
