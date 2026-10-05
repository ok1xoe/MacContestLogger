import Foundation

/// The frequency field of the entry panel: text in kHz ↔ hertz. Port of the private Kotlin
/// `parseFreqHz` (`ui/EntryPanel.kt:1989-1992`) and of the `String.format(Locale.US, "%.2f", …)` calls
/// that fill the field (`EntryPanel.kt:181, 194, 372, 612, 801, 1039`).
///
/// Measured on JDK 21 + kotlin-stdlib 2.1.20 (maintainer-only probe): Kotlin `trim` (Unicode
/// whitespace incl. NBSP, but not U+0085 nor control characters), `,` → `.`, Kotlin `toDoubleOrNull`
/// (= Java `Double.parseDouble` grammar: exponent, `NaN`, `Infinity`, hexadecimal `0x1p3`, one `d`/`f`
/// suffix; `nan`, `inf`, `0x10`, `14,074.5` and non-ASCII digits are rejected), then `Math.round`
/// (halves toward +∞, `NaN` → 0, saturation at `Long.MIN/MAX`). Anything unparsable is 0.
public enum FrequencyText {

    /// Kotlin `parseFreqHz(text)`.
    public static func parseHz(_ text: String) -> Int64 {
        // Kotlin `replace(',', '.')` by UTF-16 units (a Swift `Character` replace would skip a comma
        // followed by a combining mark).
        let units: [UInt16] = KotlinText.trim(text).utf16.map { $0 == 0x2C ? 0x2E : $0 }
        let normalized = JavaChar.string(units)
        guard let kHz = KotlinNumber.toDoubleOrNull(normalized) else {
            return 0
        }
        return JavaMath.round(kHz * 1000.0)
    }

    /// `String.format(Locale.US, "%.2f", kHz)` — Java HALF_UP of the shortest decimal (`14074.005` →
    /// `14074.01`, `2.675` → `2.68`), `-0.0` → `-0.00`, `NaN`/`Infinity` literally.
    public static func formatKHz(_ kHz: Double) -> String {
        JavaFormat.fixed(kHz, precision: 2)
    }

    /// `String.format(Locale.US, "%.2f", hz / 1000.0)` (Kotlin `Long / Double`).
    public static func formatHz(_ hz: Int64) -> String {
        formatKHz(Double(hz) / 1000.0)
    }
}

/// Kotlin number parsing (JVM stdlib 2.1.20), measured in a maintainer-only probe.
enum KotlinNumber {

    /// `String.toDoubleOrNull()`: the JVM implementation screens the text with the `Double.valueOf`
    /// grammar and calls `java.lang.Double.parseDouble` — identical results to `JavaDouble.parseDouble`
    /// (leading/trailing characters ≤ U+0020 are allowed, NBSP is not).
    static func toDoubleOrNull(_ text: String) -> Double? {
        JavaDouble.parseDouble(text)
    }

    /// `String.toIntOrNull()` (radix 10): `+`/`-` sign, a bare sign is `nil`, Unicode decimal digits by
    /// UTF-16 units (`"١٢"` = 12), no spaces, overflow → `nil` — the same algorithm as `Integer.parseInt`.
    static func toIntOrNull(_ text: String) -> Int32? {
        JavaInteger.parseInt(text)
    }
}
