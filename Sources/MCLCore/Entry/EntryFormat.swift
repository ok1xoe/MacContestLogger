/// Number formatting and parsing of the entry window's operating texts (`AS:1777-1789, 2213`), for the app.
public enum EntryFormat {

    /// `String.format(Locale.US, "%.1f", value)` (Java HALF_UP of the shortest decimal).
    public static func oneDecimal(_ value: Double) -> String {
        JavaFormat.fixed(value, precision: 1)
    }

    /// The Ctrl+R prompt's number: Kotlin `text.trim().replace(',', '.').toDoubleOrNull()`.
    public static func repeatSeconds(_ text: String) -> Double? {
        let units: [UInt16] = KotlinText.trim(text).utf16.map { $0 == 0x2C ? 0x2E : $0 }
        return KotlinNumber.toDoubleOrNull(JavaChar.string(units))
    }
}
