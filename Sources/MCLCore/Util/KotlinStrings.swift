/// Kotlin text functions for the app layer (`MCLAppModel`), which cannot reach the core's internal helpers.
///
/// The app models port Kotlin `AppState` code that tests strings with `isBlank()`/`ifBlank {}` and `trim()`, and the
/// entry fields uppercase with `uppercase()`. Kotlin's
/// whitespace differs from Swift's and from Java's (U+00A0 is blank, U+0001 is kept by `trim`), so these forward to
/// the measured `KotlinText` functions instead of `trimmingCharacters(in:)`.
public enum KotlinStrings {

    /// Kotlin `CharSequence.isBlank()`.
    public static func isBlank(_ text: String) -> Bool {
        KotlinText.isBlank(text)
    }

    /// Kotlin `String.trim()`.
    public static func trim(_ text: String) -> String {
        KotlinText.trim(text)
    }

    /// Kotlin `String.uppercase()` (= Java `toUpperCase(Locale.ROOT)`, the full mapping: `ß` → `SS`). The result
    /// can be longer than the input; the mapping is per code point, so the uppercase of a prefix is a prefix of the
    /// uppercase (the entry fields keep the caret with it).
    public static func uppercase(_ text: String) -> String {
        JavaText.toUpperCase(text)
    }

    /// Kotlin `String.equals(other, ignoreCase = true)` (= Java `equalsIgnoreCase`: per UTF-16 unit, upper then
    /// lower case).
    public static func equalsIgnoreCase(_ left: String, _ right: String) -> Bool {
        JavaChar.equalsIgnoreCase(left, right)
    }

    /// Kotlin `ifBlank { null }`.
    public static func nilIfBlank(_ text: String?) -> String? {
        guard let text, !KotlinText.isBlank(text) else { return nil }
        return text
    }
}
