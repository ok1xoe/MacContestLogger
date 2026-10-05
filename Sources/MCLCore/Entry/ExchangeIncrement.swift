/// Ctrl+U: the number in the exchange +1 (N1MM "Increase the number in the exchange field"; Kotlin
/// `incrementExchangeNumber`, `EP:599-609`).
public enum ExchangeIncrement {

    /// In a contest the first `SERIAL` field, otherwise the last received field (no fields = no change); the value is
    /// Kotlin `trim().toIntOrNull() ?: 0` plus one as a Kotlin `Int` (`2147483647` wraps to `-2147483648`), the field
    /// is marked as touched. Outside a contest the generic exchange is incremented the same way.
    public static func apply(form: EntryForm, fields: [ContestDefinition.ExchangeField],
                             contestActive: Bool) -> EntryForm {
        var out = form
        if contestActive {
            guard let field = fields.first(where: { $0.type == .SERIAL }) ?? fields.last else {
                return form
            }
            out.contestExchange.put(field.id, incremented(form.contestExchange[field.id] ?? ""))
            out.touchedFields.insert(field.id)
        } else {
            out.exch = incremented(form.exch)
        }
        return out
    }

    /// `((text.trim().toIntOrNull() ?: 0) + 1).toString()`.
    static func incremented(_ text: String) -> String {
        let value: Int32 = JavaInteger.parseInt(KotlinStrings.trim(text)) ?? 0
        return String(value &+ 1)
    }
}
