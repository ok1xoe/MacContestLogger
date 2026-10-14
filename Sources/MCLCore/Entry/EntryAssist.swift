import Foundation

/// Small N1MM Entry window helpers: the `?` selection of the call field, whether a message sends the serial
/// number, and the text of a CW message for the status line.
public enum EntryAssist {

    /// N1MM: a `?` in the callsign is selected when the cursor comes back to the field, and with two or more `?` the
    /// text from the first to the last one (`DL?K?A` → `?K?`). UTF-16 location and length; `nil` without a `?`.
    public static func questionMarkSelection(_ call: String) -> NSRange? {
        let units: [UInt16] = Array(call.utf16)
        guard let first = units.firstIndex(of: 0x3F), let last = units.lastIndex(of: 0x3F) else { return nil }
        return NSRange(location: first, length: last - first + 1)
    }

    /// Whether a function key message sends the serial number: `#` outside a `{…}` macro, `{NR}`, or `{EXCH}` with a
    /// sent exchange that has `#`.
    public static func sendsSerial(_ message: String, sentExchange: String) -> Bool {
        var inMacro = false
        var macro = ""
        for character in message {
            if inMacro {
                if character == "}" {
                    inMacro = false
                    let name: String = macro.uppercased()
                    if name == "NR" || (name == "EXCH" && sentExchange.contains("#")) {
                        return true
                    }
                } else {
                    macro.append(character)
                }
            } else if character == "{" {
                inMacro = true
                macro = ""
            } else if character == "#" {
                return true
            }
        }
        return false
    }

    /// The text of a CW message as sent (prosigns in angle brackets, speed changes left out).
    public static func sentText(_ message: CwMessage) -> String {
        var out = ""
        for part in message.parts {
            switch part {
            case .text(let text): out += text
            case .prosign(let prosign): out += "<" + prosign + ">"
            case .speed: break
            }
        }
        return out.trimmingCharacters(in: .whitespaces)
    }
}
