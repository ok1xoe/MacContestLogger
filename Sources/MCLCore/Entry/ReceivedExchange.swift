/// The received exchange in the shape the entry panel stores it. Port of the private `flatExchange`
/// of `ui/AppState.kt:3366-3368`: the Kotlin-trimmed, non-blank values of the active received fields
/// in field order, joined with a space; `nil` when nothing is left. Without it the rescore and the
/// Cabrillo export would not know the exchange of QSOs imported from WSJT-X/N1MM.
public enum ReceivedExchange {

    /// `fields` = the active received fields for the callsign (`contest.exchangeFields(call)`);
    /// `received` = raw received values by field id (a `nil` value is skipped).
    public static func flat(fields: [ContestDefinition.ExchangeField], received: JavaLinkedMap<String>) -> String? {
        var parts: [String] = []
        for field in fields {
            guard let raw = received[field.id] else { continue }
            let value = KotlinText.trim(raw)
            if !KotlinText.isBlank(value) {
                parts.append(value)
            }
        }
        let joined = parts.joined(separator: " ")
        return KotlinText.isBlank(joined) ? nil : joined
    }
}
