import CryptoKit
import Foundation

/// Writing values like the Java maintainer-only probe (`esc`), so they can
/// be compared directly with the rows of `out-en_US.tsv`: `\n \r \t \\` escaped, characters outside U+0020…U+007E as
/// `\uXXXX` by UTF-16 units, `nil` = `<null>`.
enum ProbeText {

    static func esc(_ text: String?) -> String {
        guard let text else { return "<null>" }
        var out = ""
        for unit in text.utf16 {
            switch unit {
            case 0x0A: out += "\\n"
            case 0x0D: out += "\\r"
            case 0x09: out += "\\t"
            case 0x5C: out += "\\\\"
            case 0x20...0x7E: out.unicodeScalars.append(Unicode.Scalar(unit)!)
            default:
                let hex: String = String(unit, radix: 16).uppercased()
                out += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
            }
        }
        return out
    }

    /// A probe TSV row: `id`, then tab-separated columns (already escaped).
    static func row(_ id: String, _ columns: [String]) -> String {
        ([id] + columns).joined(separator: "\t")
    }

    /// SHA-256 (hex) of rows, each terminated by `\n` — like `grep … out-en_US.tsv | shasum -a 256`.
    static func digest(_ rows: [String]) -> String {
        let joined: String = rows.map { $0 + "\n" }.joined()
        return SHA256.hash(data: Data(joined.utf8)).map { byte in
            let text = String(byte, radix: 16)
            return byte < 16 ? "0" + text : text
        }.joined()
    }
}
