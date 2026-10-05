import Foundation
import MCLCore

/// What an entry field does with typed text (Kotlin `onValueChange` of the entry fields): the call, the exchange and
/// the contest fields are uppercased (`it.uppercase()`), the frequency keeps only digits, `.` and `,`
/// (`it.filter { c -> c.isDigit() || c == '.' || c == ',' }`), the post-contest time field only digits, `:`, `-` and
/// the space (`EP:1093`), the reports are kept as typed.
///
/// Both transforms work per code point, so the transform of the text before the caret is the text before the
/// caret's new position (the field keeps the caret where it was).
public enum EntryTextTransform: Equatable, Sendable {
    case none
    case uppercase
    case frequency
    case paperTime

    public func apply(_ text: String) -> String {
        switch self {
        case .none:
            return text
        case .uppercase:
            return KotlinStrings.uppercase(text)
        case .frequency:
            return Self.filter(text) { $0 == "." || $0 == "," }
        case .paperTime:
            return Self.filter(text) { $0 == ":" || $0 == "-" || $0 == " " }
        }
    }

    /// Keeps Kotlin `Char.isDigit()` (Unicode `Nd`, for a UTF-16 unit — supplementary digits are two surrogates,
    /// which Kotlin drops) and the characters `extra` accepts.
    private static func filter(_ text: String, _ extra: (Unicode.Scalar) -> Bool) -> String {
        var out = String.UnicodeScalarView()
        for scalar in text.unicodeScalars where extra(scalar) || isDigit(scalar) {
            out.append(scalar)
        }
        return String(out)
    }

    private static func isDigit(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value <= 0xFFFF && scalar.properties.generalCategory == .decimalNumber
    }
}

extension EntryGrid {

    /// Kotlin `DIGI_MODES`: the concrete digital modes offered by the mode picker of a digital contest.
    public static let digiModes: [Mode] = [.ft8, .ft4, .jt65, .rtty, .psk, .digital]

    /// Kotlin `isDigiContest`: in a contest whose primary mode is DIGITAL, or while a digital mode (PSK, FT8, FT4,
    /// DIGITAL) is set, the mode can be picked from `digiModes`.
    @MainActor
    public static func digiPickable(_ contest: ContestModel, mode: Mode) -> Bool {
        contest.isActive && (contest.primaryMode == .digital || isActive(.DI, mode: mode))
    }
}
