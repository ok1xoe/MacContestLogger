import Foundation

/// N1MM „CW/PH AutoSend Threshold" (Config menu, Ctrl+Shift+M): in Run, the call starts going out while it is
/// still being typed, once the given number of characters follows its last digit; the characters typed after that
/// follow one by one. 0 turns it off (the default). Pure.
public enum AutoSend {

    /// The characters after the call's last digit; `nil` when the call has no digit yet.
    public static func charactersAfterLastDigit(_ call: String) -> Int? {
        guard let last = call.lastIndex(where: { $0.isASCII && $0.isNumber }) else { return nil }
        return call.distance(from: call.index(after: last), to: call.endIndex)
    }

    /// What to send now for the typed `call` (upper case, trimmed), given what AutoSend already sent for this QSO
    /// (`sent`, `nil` = nothing yet): the whole call when the threshold is reached, then only the characters added
    /// at its end. `nil` = nothing (off, not reached, or the call was edited other than by typing on — the ESM
    /// Enter then resends the corrected call).
    public static func next(call: String, sent: String?, threshold: Int) -> String? {
        guard threshold > 0, !call.isEmpty else { return nil }
        if let sent {
            guard call.count > sent.count, call.hasPrefix(sent) else { return nil }
            return String(call.dropFirst(sent.count))
        }
        guard let after = charactersAfterLastDigit(call), after >= threshold else { return nil }
        return call
    }
}
