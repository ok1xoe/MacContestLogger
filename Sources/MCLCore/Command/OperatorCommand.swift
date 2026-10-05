/// The text command `OPON` typed into the call field — logging in another operator, as N1MM knows it.
/// A bare `OPON` means "ask", the form `OPON <callsign>` sets the operator directly. Mirrors the Java
/// record `command.OperatorCommand`.
public struct OperatorCommand: Equatable, Sendable {

    /// Operator callsign, or an empty string when a dialog should fill it in.
    public let `operator`: String

    public init(operator: String) {
        self.operator = `operator`
    }

    /// `OPON` from N1MM, `LOGIN` is a DXLog alias.
    private static let keywords: Set<JavaStringKey> = [JavaStringKey("OPON"), JavaStringKey("LOGIN")]

    /// Java `\s+` (ASCII: space, `\t`, `\n`, U+000B, `\f`, `\r`).
    static let whitespace: JavaRegex = {
        do {
            return try JavaRegex("\\s+")
        } catch {
            preconditionFailure("vzor \\s+ je pevný a platný: \(error)")
        }
    }()

    /// Recognises the command in the content of the call field. Returns `nil` when it is not a command — including callsigns that
    /// merely start with `OPON` (e.g. OPONX), so that they can be logged normally.
    ///
    /// Java: `input.trim().toUpperCase().split("\\s+")` — `trim` only characters ≤ U+0020 (NBSP stays
    /// and glues the word), upper case `toUpperCase()` with the **default locale** — here without a locale, identical to it
    /// outside tr/az/lt (`ß` → `SS`), operator = the second token, the rest are dropped.
    public static func parse(_ input: String?) -> OperatorCommand? {
        guard let input else { return nil }
        let upper: String = JavaText.toUpperCase(JavaText.trim(input))
        let parts: [String] = JavaText.split(upper, regex: whitespace, limit: 0)
        guard let first = parts.first, keywords.contains(JavaStringKey(first)) else { return nil }
        return OperatorCommand(operator: parts.count > 1 ? parts[1] : "")
    }
}
