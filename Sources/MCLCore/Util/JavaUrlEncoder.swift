/// Java `URLEncoder.encode(s, StandardCharsets.UTF_8)` (form encoding, JDK 21).
///
/// Swift's `addingPercentEncoding` is different (a different set of unreserved characters, space as `%20`), hence a custom
/// function. Rules (measured, `misc-probe.txt` line `URLENC`):
/// - `[A-Za-z0-9]` and `.`, `-`, `*`, `_` stay unchanged;
/// - space → `+`;
/// - everything else → UTF-8 bytes as `%XX` with **uppercase** hexadecimal digits
///   (`~` → `%7E`, `č` → `%C4%8D`, `😀` → `%F0%9F%98%80`).
///
/// Java encodes runs of characters at once via `String.getBytes(UTF_8)`; a lone half of a surrogate pair
/// it would write as `?` (`%3F`). Swift's `String` is always valid Unicode, so encoding by scalars
/// gives the same bytes and a lone half cannot arrive here.
public enum JavaUrlEncoder {

    private static let hexDigits: [Character] = Array("0123456789ABCDEF")

    public static func encode(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.utf8.count)
        for scalar in text.unicodeScalars {
            if isUnreserved(scalar) {
                out.unicodeScalars.append(scalar)
            } else if scalar == " " {
                out.append("+")
            } else {
                for byte in String(scalar).utf8 {
                    out.append("%")
                    out.append(hexDigits[Int(byte >> 4)])
                    out.append(hexDigits[Int(byte & 0x0F)])
                }
            }
        }
        return out
    }

    /// Java's `dontNeedEncoding` set without the space.
    private static func isUnreserved(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x30...0x39, 0x41...0x5A, 0x61...0x7A:
            return true
        case 0x2D, 0x2E, 0x2A, 0x5F: // - . * _
            return true
        default:
            return false
        }
    }
}
