/// N1MM „Send partial calls": when ESM resends a corrected call, only the part that changed goes out — the prefix
/// (up to and including the last digit of the call's prefix) when the suffix is unchanged, the suffix when the prefix
/// is unchanged; otherwise, or for a call with `/`, the whole call.
public enum PartialCall {

    /// The text to send for `call` after `sent` was sent; `nil` = nothing sent before or no change.
    public static func part(sent: String?, call: String) -> String? {
        let now: String = KotlinStrings.uppercase(KotlinStrings.trim(call))
        guard let sent, !now.isEmpty else { return nil }
        let before: String = KotlinStrings.uppercase(KotlinStrings.trim(sent))
        guard before != now else { return nil }
        guard !now.contains("/"), !before.contains("/"),
              let (nowPrefix, nowSuffix) = split(now), let (oldPrefix, oldSuffix) = split(before) else {
            return now
        }
        if nowPrefix == oldPrefix && !nowSuffix.isEmpty {
            return nowSuffix
        }
        if nowSuffix == oldSuffix {
            return nowPrefix
        }
        return now
    }

    /// `OK1XOE` → (`OK1`, `XOE`): the split after the last digit; `nil` = no digit.
    static func split(_ call: String) -> (String, String)? {
        guard let digit = call.lastIndex(where: { $0.isASCII && $0.isNumber }) else { return nil }
        let end: String.Index = call.index(after: digit)
        return (String(call[..<end]), String(call[end...]))
    }
}
