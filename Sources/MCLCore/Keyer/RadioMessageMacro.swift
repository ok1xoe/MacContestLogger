import Foundation

/// `{FKEY(r1%r2)}`: one F-key message with a different part per radio (SO2R / SO2V). The part before `%` is used on
/// radio 1 (VFO A), the part after it on radio 2 (VFO B); with one radio the first part is used. A part that is just
/// a key name (`F3`, `3`, `F12`) stands for that F-key's message (`{F3}`), anything else is message text with its own
/// macros: `{FKEY(F1%F9)}`, `{FKEY(CQ {MYCALL} UP%CQ {MYCALL} TEST)}`.
///
/// The choice is made before anything else in the message is resolved, so the chosen part may hold `{LOGTHENPOP}`,
/// `{CTRLFx}` or any other macro. A macro without its closing `)}` is left as written (and reported as unknown).
public enum RadioMessageMacro {

    private static let opener: [UInt16] = Array("{FKEY(".utf16)
    private static let closer: [UInt16] = Array(")}".utf16)

    /// The text with every `{FKEY(a%b)}` replaced by the part of `radio` (1 or 2; anything else = 1).
    public static func select(_ text: String, radio: Int) -> String {
        let units: [UInt16] = Array(text.utf16)
        guard let first = find(opener, in: units, from: 0, ignoringCase: true) else { return text }
        var out: [UInt16] = Array(units[0..<first])
        var index: Int = first
        while index < units.count {
            guard let start = find(opener, in: units, from: index, ignoringCase: true) else {
                out.append(contentsOf: units[index...])
                break
            }
            out.append(contentsOf: units[index..<start])
            let bodyStart: Int = start + opener.count
            guard let end = find(closer, in: units, from: bodyStart, ignoringCase: false) else {
                out.append(contentsOf: units[start...])
                break
            }
            let body: String = JavaChar.string(Array(units[bodyStart..<end]))
            out.append(contentsOf: part(of: body, radio: radio).utf16)
            index = end + closer.count
        }
        return JavaChar.string(out)
    }

    /// The part of `body` (`a%b`) for `radio`; a missing second part is empty.
    static func part(of body: String, radio: Int) -> String {
        let pieces: [Substring] = body.split(separator: "%", maxSplits: 1, omittingEmptySubsequences: false)
        let chosen: String = radio == 2 ? (pieces.count > 1 ? String(pieces[1]) : "") : String(pieces[0])
        let trimmed: String = chosen.trimmingCharacters(in: .whitespaces)
        if let key = keyNumber(trimmed) {
            return "{F\(key)}"
        }
        return trimmed
    }

    /// `F3` / `f12` / `3` → the key number 1…12, otherwise `nil`.
    private static func keyNumber(_ text: String) -> Int? {
        var digits: Substring = Substring(text)
        if let head = digits.first, head == "F" || head == "f" {
            digits = digits.dropFirst()
        }
        guard !digits.isEmpty, digits.count <= 2, digits.allSatisfy({ $0.isASCII && $0.isNumber }),
              let number = Int(digits), (1...12).contains(number), !digits.hasPrefix("0") else { return nil }
        return number
    }

    private static func find(_ needle: [UInt16], in units: [UInt16], from: Int, ignoringCase: Bool) -> Int? {
        guard needle.count <= units.count else { return nil }
        var i: Int = from
        while i + needle.count <= units.count {
            var match = true
            for (k, n) in needle.enumerated() {
                let u: UInt16 = units[i + k]
                let a: UInt16 = ignoringCase && (0x61...0x7A).contains(u) ? u - 0x20 : u
                if a != n {
                    match = false
                    break
                }
            }
            if match { return i }
            i += 1
        }
        return nil
    }
}
