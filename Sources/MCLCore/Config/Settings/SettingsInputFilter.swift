import Foundation

/// What the Settings fields do with typed text (the `onValueChange` lambdas of `ui/configurer/*.kt` of v1.1.1):
/// Kotlin `String.filter` and `take` work on UTF-16 units (`Char`), `Char.isDigit()` is Java's
/// `Character.isDigit(char)` (category `Nd`, a surrogate half is never a digit), `uppercase()` is
/// `toUpperCase(Locale.ROOT)`.
public enum SettingsInputFilter: Equatable, Sendable {
    /// Kept as typed.
    case none
    /// `it.filter(Char::isDigit)`, then `take(limit)` when a limit is given.
    case digits(limit: Int?)
    /// `it.filter { c -> c.isDigit() || c in extra }` (`'-'` of the transverter offset, `'.'`/`','` of the CQ pause).
    case digitsAnd(extra: String)
    /// `it.uppercase()` (call, operator, locator, blacklist entry).
    case uppercase
    /// `it.trim()` (the cluster station id).
    case trim

    public func apply(_ text: String) -> String {
        switch self {
        case .none:
            return text
        case .digits(let limit):
            return Self.keep(text, extra: [], limit: limit)
        case .digitsAnd(let extra):
            return Self.keep(text, extra: Set(extra.utf16), limit: nil)
        case .uppercase:
            return JavaText.toUpperCase(text)
        case .trim:
            return KotlinText.trim(text)
        }
    }

    /// Kotlin `filter { … }.take(limit)` over UTF-16 units.
    private static func keep(_ text: String, extra: Set<UInt16>, limit: Int?) -> String {
        var units: [UInt16] = []
        for unit in text.utf16 where JavaChar.isDigit(unit) || extra.contains(unit) {
            if let limit, units.count >= limit {
                break
            }
            units.append(unit)
        }
        return String(decoding: units, as: UTF16.self)
    }

    /// „Přidat" of a blacklist editor (`DxClusterTab.kt:190-193`): `newItem.trim().uppercase()` is added when it is
    /// not empty and no entry equals it ignoring case (Java `equalsIgnoreCase`); `nil` = the list stays as it is.
    /// The input field is cleared in both cases.
    public static func addingBlacklistEntry(_ text: String, to items: [String]) -> [String]? {
        let value: String = JavaText.toUpperCase(KotlinText.trim(text))
        guard !value.isEmpty else { return nil }
        guard !items.contains(where: { JavaChar.equalsIgnoreCase($0, value) }) else { return nil }
        return items + [value]
    }
}
