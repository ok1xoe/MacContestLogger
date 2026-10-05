/// UDP broadcast target (`host:port`). Port of Java `broadcast/Target` (record).
public struct Target: Equatable, Hashable, Sendable {
    public let host: String
    public let port: Int32

    public init(host: String, port: Int32) {
        self.host = host
        self.port = port
    }

    /// `Target.parseAll`: `"host:port host:port"` (separated by whitespace or commas);
    /// bad entries are skipped.
    ///
    /// As in Java: `null` and `isBlank()` (Java `Character.isWhitespace`) → empty list; otherwise
    /// `trim()` (≤ U+0020) and splitting by the regex `[\s,]+` (ASCII whitespace). The host is everything before the
    /// **last** `:` (non-empty), the port `Integer.parseInt` (including Unicode digits and `+`) in 1…65535.
    public static func parseAll(_ text: String?) -> [Target] {
        guard let text, !JavaText.isBlank(text) else { return [] }
        var out: [Target] = []
        var token: [UInt16] = []
        for unit in JavaText.trim(text).utf16 {
            if isSeparator(unit) {
                append(token, to: &out)
                token.removeAll(keepingCapacity: true)
            } else {
                token.append(unit)
            }
        }
        append(token, to: &out)
        return out
    }

    /// Empty tokens (a leading separator) Java `split` emits only at the start and they end at
    /// `lastIndexOf(':') == -1` — skipped the same way.
    private static func append(_ token: [UInt16], to out: inout [Target]) {
        guard let colon = token.lastIndex(of: 0x3A), colon > 0, colon < token.count - 1 else { return }
        let portText = JavaChar.string(Array(token[(colon + 1)...]))
        guard let port = JavaInteger.parseInt(portText), port > 0, port <= 65_535 else { return }
        out.append(Target(host: JavaChar.string(Array(token[..<colon])), port: port))
    }

    /// `[\s,]` in a Java regex without `UNICODE_CHARACTER_CLASS`: `[ \t\n\x0B\f\r]` and a comma.
    private static func isSeparator(_ unit: UInt16) -> Bool {
        unit == 0x2C || JavaChar.isRegexSpace(unit)
    }
}
