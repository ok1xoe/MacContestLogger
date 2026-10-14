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

    /// `((text.trim().toIntOrNull() ?: 0) + 1).toString()`; a Sweepstakes serial with its precedence (`23B`, also as a
    /// word of a whole exchange such as `23B 72 CT`) keeps the precedence and the other words (N1MM Ctrl+U).
    static func incremented(_ text: String) -> String {
        if let precedence = incrementedWithPrecedence(text) {
            return precedence
        }
        let value: Int32 = JavaInteger.parseInt(KotlinStrings.trim(text)) ?? 0
        return String(value &+ 1)
    }

    /// The first space-separated word made of digits and one or two letters, its number plus one; `nil` when no word
    /// is like that.
    static func incrementedWithPrecedence(_ text: String) -> String? {
        var words: [Substring] = text.split(separator: " ", omittingEmptySubsequences: false)
        for (index, word) in words.enumerated() {
            let digits: Substring = word.prefix { $0.isASCII && $0.isNumber }
            let letters: Substring = word.dropFirst(digits.count)
            guard !digits.isEmpty, (1...2).contains(letters.count),
                  letters.allSatisfy({ $0.isASCII && $0.isLetter }), let value = Int32(digits) else { continue }
            words[index] = Substring(String(value &+ 1) + letters)
            return words.joined(separator: " ")
        }
        return nil
    }
}
