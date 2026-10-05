/// Call History Lookup in the entry window (N1MM; `EP:271-295`): after a pause in typing the call, empty exchange
/// fields are prefilled from the call history; what was prefilled is remembered and taken back when the call changes
/// (values the operator overwrote stay). Reverse lookup (`EP:1211-1232`): an empty call with a filled exchange lists
/// the calls the exchange matches.
///
/// The callbook part of the Kotlin prefill (`CallbookPrefill.prefill(callbookRec, cfields)`) is handled by the spot windows — the fill
/// is the call history alone.
public enum CallHistoryFill {

    /// The values to prefill: only in a contest and for a Kotlin-trimmed call of at least 3 UTF-16 units,
    /// `callHistory.prefill(call, fields)`; otherwise none.
    public static func fill(callHistory: CallHistory, call: String, fields: [ContestDefinition.ExchangeField],
                            contestActive: Bool) -> JavaLinkedMap<String> {
        guard contestActive, KotlinStrings.trim(call).utf16.count >= 3 else { return JavaLinkedMap() }
        return callHistory.prefill(call, fields)
    }

    /// Applies `fill` (Kotlin `LaunchedEffect(call, …)` body):
    /// 1. every previously filled value that the new fill does not repeat (UTF-16 equality) is forgotten and — when the
    ///    field still holds it — removed from the exchange;
    /// 2. every fill value goes into a blank (Kotlin `isNullOrBlank`) field and is remembered.
    ///
    /// Touch marks are not changed.
    public static func apply(form: EntryForm, fill: JavaLinkedMap<String>,
                             previouslyFilled: JavaLinkedMap<String>) -> (form: EntryForm, filled: JavaLinkedMap<String>) {
        var out = form
        var filled = previouslyFilled
        for (id, value) in previouslyFilled.entries {
            guard let value else { continue }
            if let again = fill[id], JavaText.equals(again, value) {
                continue
            }
            if let current = out.contestExchange[id], JavaText.equals(current, value) {
                out.contestExchange = out.contestExchange.removingKey(id)
            }
            filled = filled.removingKey(id)
        }
        for (id, value) in fill.entries {
            guard let value else { continue }
            let current: String? = out.contestExchange[id]
            if current.map(KotlinStrings.isBlank) ?? true {
                out.contestExchange.put(id, value)
                filled.put(id, value)
            }
        }
        return (out, filled)
    }

    /// Reverse lookup: only in a contest, with a blank call and a non-blank exchange value;
    /// `callHistory.reverse(exchange, fields, 8)`.
    public static func reverse(callHistory: CallHistory, form: EntryForm, fields: [ContestDefinition.ExchangeField],
                               contestActive: Bool) -> [String] {
        guard contestActive, KotlinStrings.isBlank(form.call),
              form.contestExchange.entries.contains(where: { $0.value.map { !KotlinStrings.isBlank($0) } ?? false })
        else { return [] }
        return callHistory.reverse(form.contestExchange, fields, limit: EntrySuggestions.limit)
    }
}

extension JavaLinkedMap {

    /// Java `remove(key)`: the map without `key`, the order of the rest kept.
    fileprivate func removingKey(_ key: String?) -> JavaLinkedMap {
        guard containsKey(key) else { return self }
        var out = JavaLinkedMap()
        for (k, v) in entries where !(JavaStringKey(k) == JavaStringKey(key)) {
            out.put(k, v)
        }
        return out
    }
}
