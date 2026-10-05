import Foundation

/// The page layout of a printed log — port of `io/LogPrinter.print` and `LogPrinter.print(Graphics, …)` (Java
/// v1.1.1, `LP:46-75`) for the app's `NSPrintOperation` view: the text listing (`LogExports.text`) split by
/// `String.lines()`, paginated with the 3-line column header repeated on every page, a monospaced 8 pt font, lines
/// 10 pt apart starting at y = 10 from the top of the imageable area, and the footer `"<title> — strana i/n"`
/// (literal, not translated) at `(int) imageableHeight − 4`.
///
/// Java computes the lines per page from the default page **before** the print dialog; the app computes
/// it from the paper chosen in the dialog (same formula).
public enum PrintLayout {

    /// The column header of `LogExports.text` (title, column names, rule) repeated on every page (`LP:51`).
    public static let headerLines = 3

    /// One line of text at `y` points from the top of the imageable area (its baseline, Java `drawString`).
    public struct Line: Equatable, Sendable {
        public let text: String
        public let y: Int
    }

    public struct Page: Equatable, Sendable {
        public let lines: [Line]
        public let footer: Line
    }

    /// `AS:4026-4027` — `"$name — ${config.station.call}"`, the print job's and the listing's title.
    public static func title(definitionName: String, call: String) -> String {
        definitionName + " — " + call
    }

    /// `(int) ((imageableHeight - 24) / 10)` — Java's `(int)` truncates toward zero (probe rows `LPP`: 734 → 71,
    /// 733.9 → 70, 0 → −2).
    public static func linesPerPage(imageableHeight: Double) -> Int {
        javaInt((imageableHeight - 24) / 10)
    }

    /// The pages of `text` for a page with `imageableHeight` points.
    public static func pages(text: String, title: String, imageableHeight: Double) -> [Page] {
        let lines: [String] = JavaLines.split(text)
        let paged: [[String]] = LogPrinter.paginate(lines, headerLines: headerLines,
                                                    linesPerPage: linesPerPage(imageableHeight: imageableHeight))
        let footerY: Int = javaInt(imageableHeight) - 4
        var out: [Page] = []
        out.reserveCapacity(paged.count)
        for (index, page) in paged.enumerated() {
            var placed: [Line] = []
            placed.reserveCapacity(page.count)
            for (row, line) in page.enumerated() {
                placed.append(Line(text: line, y: 10 + 10 * row))
            }
            let footer: String = title + " — strana " + String(index + 1) + "/" + String(paged.count)
            out.append(Page(lines: placed, footer: Line(text: footer, y: footerY)))
        }
        return out
    }

    /// Java `(int) d`: toward zero, NaN → 0, saturated at the `int` range.
    static func javaInt(_ value: Double) -> Int {
        if value.isNaN {
            return 0
        }
        if value >= Double(Int32.max) {
            return Int(Int32.max)
        }
        if value <= Double(Int32.min) {
            return Int(Int32.min)
        }
        return Int(value)
    }
}
