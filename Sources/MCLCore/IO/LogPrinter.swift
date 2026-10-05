/// Log printing (N1MM / DXLog Print log): a text listing (`LogExports.text`) split into
/// pages. Port of the pure part of `io/LogPrinter.java` (Java v1.1.1) — only `paginate`;
/// `print` (AWT dialog, font `MONOSPACED 8`, footer
/// `<title> — strana i/n`) is the app layer's (`NSPrintOperation`).
public enum LogPrinter {

    /// Splits lines into pages; the column header (the first `headerLines`) repeats on every page.
    /// An empty body = one page (header only, for `[]` empty); `linesPerPage ≤ headerLines`
    /// → one body line per page.
    ///
    /// - Precondition: `headerLines >= 0` (Java throws `IndexOutOfBoundsException` on negative
    ///   from `subList`; the caller passes a constant).
    public static func paginate(_ lines: [String], headerLines: Int, linesPerPage: Int) -> [[String]] {
        precondition(headerLines >= 0, "LogPrinter.paginate: záporné headerLines")
        let split = min(headerLines, lines.count)
        let header = Array(lines[0..<split])
        let body = Array(lines[split...])
        let perPage = max(1, linesPerPage - header.count)
        var out: [[String]] = []
        var i = 0
        while i < body.count || out.isEmpty {
            var page = header
            page.append(contentsOf: body[min(i, body.count)..<min(i + perPage, body.count)])
            out.append(page)
            if body.isEmpty {
                break
            }
            i += perPage
        }
        return out
    }
}
