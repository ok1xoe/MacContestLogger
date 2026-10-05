import Foundation

/// Typing CW from the keyboard (N1MM CW keyboard, Ctrl+K): from what the operator types it picks finished words
/// to transmit. In "word by word" mode a word is sent as soon as a space follows it; Enter sends the rest.
/// Text already sent is not sent again. Mirrors Java `keyer.CwKeyboardBuffer`.
///
/// Positions are in UTF-16 units as in Java (`😀` = 2); the word separator is only the space U+0020,
/// trimming is Java `trim()` (characters ≤ U+0020, NBSP stays).
public struct CwKeyboardBuffer: Sendable {

    /// How many characters (UTF-16 units) of the field have already been sent (for highlighting).
    public private(set) var sentUpTo = 0

    public init() {}

    /// New field content → text to transmit (empty = nothing yet).
    ///
    /// - Parameter wordByWord: send words as you go (otherwise only on `flush`)
    public mutating func onTextChanged(_ text: String, wordByWord: Bool) -> String {
        let units = Array(text.utf16)
        if units.count < sentUpTo {
            sentUpTo = min(sentUpTo, units.count) // deleting — we do not take back what was already sent
            return ""
        }
        if !wordByWord {
            return ""
        }
        let lastSpace = units.lastIndex(of: 0x20) ?? -1
        if lastSpace < sentUpTo {
            return ""
        }
        let chunk = JavaText.trim(JavaChar.string(Array(units[sentUpTo...lastSpace])))
        sentUpTo = lastSpace + 1
        return chunk
    }

    /// Enter: the rest of the text that has not been sent yet.
    public mutating func flush(_ text: String) -> String {
        let units = Array(text.utf16)
        let rest = sentUpTo < units.count ? JavaText.trim(JavaChar.string(Array(units[sentUpTo...]))) : ""
        sentUpTo = units.count
        return rest
    }

    public mutating func reset() {
        sentUpTo = 0
    }

    /// Splits the text into words: Java `text.trim().split("\\s+")` without empty items — `\s` is only
    /// ASCII (`[ \t\n\u{0B}\f\r]`), NBSP and U+2003 do not split words.
    public static func words(_ text: String) -> [String] {
        var out: [String] = []
        var word: [UInt16] = []
        for unit in JavaText.trim(text).utf16 {
            if JavaChar.isRegexSpace(unit) {
                if !word.isEmpty { out.append(JavaChar.string(word)) }
                word.removeAll()
            } else {
                word.append(unit)
            }
        }
        if !word.isEmpty { out.append(JavaChar.string(word)) }
        return out
    }
}
