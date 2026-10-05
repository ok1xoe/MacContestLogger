/// Parsing of an FT8/FT4 message text from a decode: who transmits, to whom and whether it is a CQ — port of `wsjtx/Ft8Message.java`
/// (v1.1.1). Shapes: `CQ [DX|NA|TEST…] K1ABC FN42`, `OK1XOE K1ABC -12`, `K1ABC OK1XOE R-05`,
/// `<K1ABC> OK1XOE RR73`.
///
/// As in Java: `toUpperCase(ROOT)` (port convention `uppercased()`), `trim()`, removal of `<` `>` only after
/// the trim, `split("\\s+")`; a CQ modifier is skipped only when there are at least three words and the second is not
/// a callsign; grid `[A-R]{2}[0-9]{2}` except `RR73`.
public struct Ft8Message: Equatable, Sendable {
    public let caller: String
    public let target: String
    public let cq: Bool
    public let grid: String

    public init(caller: String, target: String, cq: Bool, grid: String) {
        self.caller = caller
        self.target = target
        self.cq = cq
        self.grid = grid
    }

    private static let gridPattern: JavaRegex = compile("[A-R]{2}[0-9]{2}")
    private static let callPattern: JavaRegex = compile(
        "[A-Z0-9/]*[0-9][A-Z0-9/]*[A-Z][A-Z0-9/]*|[A-Z0-9/]*[A-Z][A-Z0-9/]*[0-9][A-Z0-9/]*")
    private static let whitespace: JavaRegex = compile("\\s+")
    private static let empty = Ft8Message(caller: "", target: "", cq: false, grid: "")
    private static let cqUnderscore: [UInt16] = Array("CQ_".utf16)

    public static func parse(_ message: String?) -> Ft8Message {
        guard let message else { return empty }
        var text: String = JavaText.trim(message.uppercased())
        text = JavaText.replace(JavaText.replace(text, "<", ""), ">", "")
        let w: [String] = whitespace.split(text, limit: 0)
        guard let first = w.first, !first.isEmpty else { return empty }
        if first == "CQ" || Array(first.utf16).starts(with: cqUnderscore) {
            var i = 1
            // CQ modifier (DX, NA, TEST, POTA, 3 digits…) — without a digit+letter
            if w.count > 2 && !isCall(w[i]) {
                i += 1
            }
            let caller: String = i < w.count ? w[i] : ""
            let grid: String = i + 1 < w.count && isGrid(w[i + 1]) ? w[i + 1] : ""
            return Ft8Message(caller: isCall(caller) ? caller : "", target: "", cq: true, grid: grid)
        }
        if w.count >= 2 {
            let grid: String = w.count >= 3 && isGrid(w[2]) ? w[2] : ""
            return Ft8Message(caller: isCall(w[1]) ? w[1] : "", target: isCall(w[0]) ? w[0] : "", cq: false,
                              grid: grid)
        }
        return empty
    }

    static func isCall(_ s: String?) -> Bool {
        guard let s else { return false }
        return s.utf16.count >= 3 && callPattern.matches(s) && !gridPattern.matches(s)
    }

    /// `GRID.matcher(w).matches() && !w.equals("RR73")`.
    private static func isGrid(_ word: String) -> Bool {
        gridPattern.matches(word) && word != "RR73"
    }

    private static func compile(_ pattern: String) -> JavaRegex {
        do {
            return try JavaRegex(pattern)
        } catch {
            preconditionFailure("pevný vzor Ft8Message musí jít zkompilovat: \(error)")
        }
    }
}
