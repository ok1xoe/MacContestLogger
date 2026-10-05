import AppKit
import MCLAppModel
import MCLCore

/// The printed log (Kotlin `LogPrinter.print`, `LP:46-75`): the pages of `PrintLayout` drawn one below the other,
/// each `rectForPage` one imageable area of the chosen paper. Monospaced 8 pt, black, the line's `y` is its
/// baseline from the top of the page (Java `drawString`), the footer `"<title> — strana i/n"` at its `y`.
@MainActor
final class LogPrintView: NSView {

    private let pages: [PrintLayout.Page]
    private let pageSize: NSSize
    private let font: NSFont

    /// - Parameters:
    ///   - pages: `PrintLayout.pages` for `pageSize.height`.
    ///   - pageSize: the imageable size of the chosen paper.
    init(pages: [PrintLayout.Page], pageSize: NSSize) {
        self.pages = pages
        self.pageSize = pageSize
        // Java `new Font(Font.MONOSPACED, Font.PLAIN, 8)`.
        font = NSFont.userFixedPitchFont(ofSize: 8) ?? NSFont.monospacedSystemFont(ofSize: 8, weight: .regular)
        let height: CGFloat = pageSize.height * CGFloat(max(pages.count, 1))
        super.init(frame: NSRect(x: 0, y: 0, width: pageSize.width, height: height))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var isFlipped: Bool {
        true
    }

    override func knowsPageRange(_ range: NSRangePointer) -> Bool {
        range.pointee = NSRange(location: 1, length: pages.count)
        return true
    }

    /// Page `number` (1-based) is the `number`-th imageable area from the top.
    override func rectForPage(_ number: Int) -> NSRect {
        NSRect(x: 0, y: pageSize.height * CGFloat(number - 1), width: pageSize.width, height: pageSize.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        for (index, page) in pages.enumerated() {
            let top: CGFloat = pageSize.height * CGFloat(index)
            let rect = NSRect(x: 0, y: top, width: pageSize.width, height: pageSize.height)
            guard rect.intersects(dirtyRect) else { continue }
            for line in page.lines {
                draw(line, top: top, attributes: attributes)
            }
            draw(page.footer, top: top, attributes: attributes)
        }
    }

    /// `y` is the baseline; `NSString.draw(at:)` in a flipped view takes the top of the line.
    private func draw(_ line: PrintLayout.Line, top: CGFloat, attributes: [NSAttributedString.Key: Any]) {
        let point = NSPoint(x: 0, y: top + CGFloat(line.y) - font.ascender)
        (line.text as NSString).draw(at: point, withAttributes: attributes)
    }
}

/// Kotlin `printLog()` from the dialog on (`AS:4028-4033`, `LogPrinter.print`): the system print panel
/// (application-modal like Java's `printDialog()`), then the job spooled with the paper chosen in the panel
/// (the lines per page follow that paper's imageable height). The outcome goes to `printFinished`: printed,
/// cancelled in the panel, or failed (`NSPrintOperation` reports no reason → Java's `null` message).
@MainActor
enum LogPrinting {

    static func run(_ job: ImportExportModel.PrintJob, app: AppModel) {
        guard let info = NSPrintInfo.shared.copy() as? NSPrintInfo else {
            app.exports.printFinished(.failed(nil))
            return
        }
        let panel = NSPrintPanel()
        // No scaling: the pagination follows the unscaled imageable height (Java's layout is fixed too).
        panel.options = [.showsCopies, .showsPageRange, .showsPaperSize, .showsOrientation]
        guard panel.runModal(with: info) == NSApplication.ModalResponse.OK.rawValue else {
            app.exports.printFinished(.cancelled)
            return
        }
        // Java draws from the imageable origin: the margins are the paper's unprintable edges.
        let paper: NSSize = info.paperSize
        let imageable: NSRect = info.imageablePageBounds
        info.leftMargin = imageable.minX
        info.rightMargin = paper.width - imageable.maxX
        info.bottomMargin = imageable.minY
        info.topMargin = paper.height - imageable.maxY
        info.scalingFactor = 1
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        let pages: [PrintLayout.Page] = PrintLayout.pages(text: job.text, title: job.title,
                                                          imageableHeight: Double(imageable.height))
        let view = LogPrintView(pages: pages, pageSize: imageable.size)
        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.jobTitle = job.title
        operation.showsPrintPanel = false
        operation.showsProgressPanel = true
        app.exports.printFinished(operation.run() ? .sent : .failed(nil))
    }
}
