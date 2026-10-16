import AppKit
import Foundation

extension NSAttributedString.Key {
    /// The anchor a heading starts (`entry-window.md`, `entry-window.md#keys`), on its first character.
    static let manualAnchor = NSAttributedString.Key("mcl.manual.anchor")
    /// The heading level (1–6) over the whole heading paragraph.
    static let manualHeading = NSAttributedString.Key("mcl.manual.heading")
    /// A link: `#<anchor>` inside the book, otherwise an absolute URL.
    static let manualLink = NSAttributedString.Key("mcl.manual.link")
    /// What separates a chapter from the previous one (the form feed, or the rule of a joined chapter): its file.
    static let manualChapterLead = NSAttributedString.Key("mcl.manual.chapterLead")
}

/// Turns the book into one attributed text for the paginated layout: the title page, the contents (with the page
/// numbers of the previous layout pass) and the chapters, each starting on a new page (form feed) unless the previous
/// layout pass found the chapter before it ending high on its page (`joined`: the chapter goes on below it). Colours are
/// fixed sRGB values, never the appearance-dependent system colours.
@MainActor
struct ManualTypesetter {

    let book: ManualBook
    /// The `docs` directory (images are read from it).
    let docs: URL
    let version: String?
    /// The build date on the title page (`nil` = none).
    let buildDate: Date?
    /// Content width of a page, for images and the contents' right tab.
    let contentWidth: CGFloat
    let contentHeight: CGFloat
    /// Pages of the anchors from the previous pass (`nil` = not known yet, a placeholder is printed).
    let pages: [String: Int]
    /// Headings that ended up alone at the bottom of a page in the previous pass: they start a new page.
    let breaks: Set<String>
    /// Chapters (by file) that go on below the previous one instead of starting a new page.
    let joined: Set<String>

    // MARK: - styles

    static let ink = NSColor(srgbRed: 0.10, green: 0.10, blue: 0.12, alpha: 1)
    static let muted = NSColor(srgbRed: 0.40, green: 0.40, blue: 0.44, alpha: 1)
    static let linkColor = NSColor(srgbRed: 0.05, green: 0.33, blue: 0.70, alpha: 1)
    static let codeBackground = NSColor(srgbRed: 0.95, green: 0.95, blue: 0.96, alpha: 1)
    static let rule = NSColor(srgbRed: 0.75, green: 0.75, blue: 0.78, alpha: 1)
    static let tableHeader = NSColor(srgbRed: 0.91, green: 0.92, blue: 0.94, alpha: 1)

    static let bodySize: CGFloat = 10

    static func font(_ size: CGFloat, _ weight: NSFont.Weight = .regular, italic: Bool = false) -> NSFont {
        let base: NSFont = NSFont.systemFont(ofSize: size, weight: weight)
        guard italic else { return base }
        return NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask)
    }

    static func mono(_ size: CGFloat, bold: Bool = false) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: bold ? .bold : .regular)
    }

    static func headingFont(_ level: Int) -> NSFont {
        switch level {
        case 1: return font(20, .bold)
        case 2: return font(14.5, .bold)
        case 3: return font(12, .semibold)
        default: return font(10.5, .semibold)
        }
    }

    func paragraphStyle(spacingBefore: CGFloat = 0, after: CGFloat = 5, indent: CGFloat = 0,
                        firstIndent: CGFloat? = nil, alignment: NSTextAlignment = .natural) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = spacingBefore
        style.paragraphSpacing = after
        style.headIndent = indent
        style.firstLineHeadIndent = firstIndent ?? indent
        style.alignment = alignment
        style.lineHeightMultiple = 1.1
        return style
    }

    // MARK: - inline text

    /// Inline Markdown (emphasis, code, links) in the given font; `file` resolves relative links.
    func inline(_ text: String, font: NSFont, color: NSColor = ManualTypesetter.ink, file: String,
                style: NSParagraphStyle) -> NSMutableAttributedString {
        let out = NSMutableAttributedString()
        let base: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: style]
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        guard let parsed = try? AttributedString(markdown: text, options: options) else {
            out.append(NSAttributedString(string: text, attributes: base))
            return out
        }
        for run in parsed.runs {
            let piece = String(parsed[run.range].characters)
            var attributes = base
            let intent: InlinePresentationIntent = run.inlinePresentationIntent ?? []
            let size: CGFloat = font.pointSize
            if intent.contains(.code) {
                attributes[.font] = Self.mono(size * 0.92)
                attributes[.backgroundColor] = Self.codeBackground
            } else {
                let bold: Bool = intent.contains(.stronglyEmphasized)
                    || font.fontDescriptor.symbolicTraits.contains(.bold)
                let italic: Bool = intent.contains(.emphasized)
                var chosen: NSFont = Self.font(size, bold ? .semibold : .regular, italic: italic)
                if font.fontDescriptor.symbolicTraits.contains(.monoSpace) {
                    chosen = font
                }
                attributes[.font] = chosen
            }
            if intent.contains(.strikethrough) {
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            if let link = run.link, let target = resolve(link.absoluteString, from: file) {
                attributes[.manualLink] = target
                attributes[.foregroundColor] = Self.linkColor
            }
            out.append(NSAttributedString(string: piece, attributes: attributes))
        }
        return out
    }

    /// A link target of the book (`ManualBook.resolveLink`).
    func resolve(_ raw: String, from file: String) -> String? {
        book.resolveLink(raw, from: file)
    }

    // MARK: - the book

    func build() -> NSAttributedString {
        let text = NSMutableAttributedString()
        titlePage(into: text)
        text.append(pageBreak())
        contents(into: text)
        for chapter in book.chapters {
            let goesOn: Bool = joined.contains(chapter.file) && !breaks.contains(chapter.file)
                && chapter.file != book.chapters.first?.file
            let lead: Int = text.length
            if !goesOn {
                text.append(pageBreak())
            }
            if goesOn {
                rule(into: text)
            }
            text.addAttribute(.manualChapterLead, value: chapter.file, range: NSRange(location: lead, length: text.length - lead))
            heading(1, chapter.title, anchor: chapter.file, file: chapter.file, into: text)
            for block in chapter.blocks {
                append(block, file: chapter.file, into: text)
            }
        }
        return text
    }

    func pageBreak() -> NSAttributedString {
        NSAttributedString(string: "\u{000C}", attributes: [.font: Self.font(Self.bodySize)])
    }

    /// The title page: the name, the version and build date, the guide's introduction and the parts with their
    /// chapters at a glance (the contents with page numbers follow on the next page).
    func titlePage(into text: NSMutableAttributedString) {
        let center: NSMutableParagraphStyle = paragraphStyle(spacingBefore: 0, after: 6, alignment: .center)
        let top: NSMutableParagraphStyle = paragraphStyle(spacingBefore: contentHeight * 0.1, after: 8, alignment: .center)
        text.append(NSAttributedString(string: "MacContestLogger\n", attributes: [
            .font: Self.font(30, .bold), .foregroundColor: Self.ink, .paragraphStyle: top,
        ]))
        text.append(NSAttributedString(string: Self.subtitle(book) + "\n", attributes: [
            .font: Self.font(16), .foregroundColor: Self.muted, .paragraphStyle: center,
        ]))
        if let line = book.language.editionLine(version: version, buildDate: buildDate) {
            text.append(NSAttributedString(string: line + "\n", attributes: [
                .font: Self.font(10.5, .medium), .foregroundColor: Self.muted, .paragraphStyle: center,
            ]))
        }
        let gap: NSMutableParagraphStyle = paragraphStyle(spacingBefore: 26, after: 6)
        var first = true
        for block in book.intro {
            if case .paragraph(let body) = block {
                let line = inline(body, font: Self.font(Self.bodySize), file: "README.md", style: first ? gap : paragraphStyle())
                line.append(NSAttributedString(string: "\n"))
                text.append(line)
                first = false
            }
        }
        text.append(NSAttributedString(string: book.language.atAGlance + "\n", attributes: [
            .font: Self.font(11, .semibold), .foregroundColor: Self.ink,
            .paragraphStyle: paragraphStyle(spacingBefore: 16, after: 4),
        ]))
        for (part, chapters) in book.parts {
            let style: NSMutableParagraphStyle = paragraphStyle(after: 4)
            let line = NSMutableAttributedString(string: part + "  ", attributes: [
                .font: Self.font(8.5, .semibold), .foregroundColor: Self.ink, .paragraphStyle: style,
            ])
            for (index, chapter) in chapters.enumerated() {
                if index > 0 {
                    line.append(NSAttributedString(string: " · ", attributes: [
                        .font: Self.font(8.5), .foregroundColor: Self.rule, .paragraphStyle: style,
                    ]))
                }
                line.append(NSAttributedString(string: ManualRenderer.plain(chapter.title), attributes: [
                    .font: Self.font(8.5), .foregroundColor: Self.muted, .paragraphStyle: style,
                    .manualLink: "#" + chapter.file,
                ]))
            }
            line.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: style]))
            text.append(line)
        }
        let link: String = "https://github.com/ok1xoe/MacContestLogger"
        text.append(NSAttributedString(string: link + "\n", attributes: [
            .font: Self.font(Self.bodySize), .foregroundColor: Self.linkColor, .manualLink: link,
            .paragraphStyle: paragraphStyle(spacingBefore: 14, alignment: .center),
        ]))
    }

    /// `MacContestLogger user guide` → `User guide`.
    static func subtitle(_ title: String) -> String {
        var subtitle: String = title
        if subtitle.hasPrefix("MacContestLogger ") {
            subtitle = String(subtitle.dropFirst("MacContestLogger ".count))
            subtitle = subtitle.prefix(1).uppercased() + subtitle.dropFirst()
        }
        return subtitle
    }

    /// The title page's subtitle in the book's language (the English one from the README's heading).
    static func subtitle(_ book: ManualBook) -> String {
        book.language.fixedSubtitle ?? subtitle(book.title)
    }

    /// The contents: the parts and their chapters with right-aligned page numbers (linked to the chapter).
    func contents(into text: NSMutableAttributedString) {
        heading(1, book.language.contents, anchor: nil, file: "", into: text)
        var part = ""
        for chapter in book.chapters {
            if chapter.part != part {
                part = chapter.part
                text.append(NSAttributedString(string: part + "\n", attributes: [
                    .font: Self.font(11, .semibold), .foregroundColor: Self.ink,
                    .paragraphStyle: paragraphStyle(spacingBefore: 7, after: 2),
                ]))
            }
            // Compact enough for the whole book's contents to fit one page.
            let style: NSMutableParagraphStyle = paragraphStyle(after: 1, indent: 14)
            style.lineHeightMultiple = 1.0
            style.tabStops = [NSTextTab(textAlignment: .right, location: contentWidth)]
            let page: String = pages[chapter.file].map(String.init) ?? "000"
            text.append(NSAttributedString(string: ManualRenderer.plain(chapter.title) + "\t" + page + "\n", attributes: [
                .font: Self.font(Self.bodySize), .foregroundColor: Self.ink, .paragraphStyle: style,
                .manualLink: "#" + chapter.file,
            ]))
        }
    }

    /// The separator above a chapter that goes on below the previous one.
    func rule(into text: NSMutableAttributedString) {
        let style: NSMutableParagraphStyle = paragraphStyle(spacingBefore: 22, after: 10, alignment: .center)
        text.append(NSAttributedString(string: "\u{2014}  \u{2014}  \u{2014}\n", attributes: [
            .font: Self.font(Self.bodySize), .foregroundColor: Self.rule, .paragraphStyle: style,
        ]))
    }

    func heading(_ level: Int, _ title: String, anchor: String?, file: String, into text: NSMutableAttributedString) {
        if let anchor, breaks.contains(anchor), level > 1 {
            text.append(pageBreak())
        }
        let before: CGFloat = level == 1 ? 0 : (level == 2 ? 14 : 10)
        let style: NSMutableParagraphStyle = paragraphStyle(spacingBefore: before, after: level == 1 ? 12 : 5)
        let line: NSMutableAttributedString = inline(title, font: Self.headingFont(level), file: file, style: style)
        line.append(NSAttributedString(string: "\n", attributes: [.font: Self.headingFont(level), .paragraphStyle: style]))
        line.addAttribute(.manualHeading, value: level, range: NSRange(location: 0, length: line.length))
        if let anchor, line.length > 0 {
            line.addAttribute(.manualAnchor, value: anchor, range: NSRange(location: 0, length: 1))
        }
        text.append(line)
    }

    func append(_ block: ManualBlock, file: String, into text: NSMutableAttributedString) {
        switch block {
        case .heading(let level, let title):
            heading(min(level, 4), title, anchor: ManualBook.anchor(file: file, heading: title), file: file, into: text)
        case .paragraph(let body):
            let line = inline(body, font: Self.font(Self.bodySize), file: file, style: paragraphStyle())
            line.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: paragraphStyle()]))
            text.append(line)
        case .quote(let body):
            let style: NSMutableParagraphStyle = paragraphStyle(indent: 14)
            let line = inline(body, font: Self.font(Self.bodySize, italic: true), color: Self.muted, file: file, style: style)
            line.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: style]))
            text.append(line)
        case .list(let items):
            for (index, item) in items.enumerated() {
                let indent: CGFloat = 16 * CGFloat(item.level + 1)
                let style: NSMutableParagraphStyle = paragraphStyle(after: index == items.count - 1 ? 6 : 2,
                                                                    indent: indent, firstIndent: indent - 12)
                style.tabStops = [NSTextTab(textAlignment: .left, location: indent)]
                let line = NSMutableAttributedString(string: item.marker + "\t", attributes: [
                    .font: Self.font(Self.bodySize), .foregroundColor: Self.ink, .paragraphStyle: style,
                ])
                line.append(inline(item.text, font: Self.font(Self.bodySize), file: file, style: style))
                line.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: style]))
                text.append(line)
            }
        case .code(let body):
            // A box per line (a block that cannot split across pages would never be placed when it is longer than
            // a page), joined edge to edge: the side padding on every line, the top and bottom on the first and last.
            let lines: [String] = body.components(separatedBy: "\n")
            for (index, line) in lines.enumerated() {
                let box = NSTextBlock()
                box.backgroundColor = Self.codeBackground
                box.setValue(contentWidth - 14, type: .absoluteValueType, for: .width)
                box.setWidth(6, type: .absoluteValueType, for: .padding, edge: .minX)
                box.setWidth(6, type: .absoluteValueType, for: .padding, edge: .maxX)
                box.setWidth(index == 0 ? 5 : 0, type: .absoluteValueType, for: .padding, edge: .minY)
                box.setWidth(index == lines.count - 1 ? 5 : 0, type: .absoluteValueType, for: .padding, edge: .maxY)
                let style: NSMutableParagraphStyle = paragraphStyle(spacingBefore: index == 0 ? 2 : 0,
                                                                    after: index == lines.count - 1 ? 8 : 0)
                style.lineHeightMultiple = 1.0
                style.lineBreakMode = .byCharWrapping
                style.textBlocks = [box]
                text.append(NSAttributedString(string: line + "\n", attributes: [
                    .font: Self.mono(8.5), .foregroundColor: Self.ink, .paragraphStyle: style,
                ]))
            }
        case .table(let header, let rows):
            table(header: header, rows: rows, file: file, into: text)
        case .image(let alt, let path):
            image(alt: alt, path: path, into: text)
        case .rule:
            let style: NSMutableParagraphStyle = paragraphStyle(spacingBefore: 4, after: 8, alignment: .center)
            text.append(NSAttributedString(string: "\u{2014}  \u{2014}  \u{2014}\n", attributes: [
                .font: Self.font(Self.bodySize), .foregroundColor: Self.rule, .paragraphStyle: style,
            ]))
        }
    }

    /// A table as one paragraph per row, each row a drawn attachment (cells wrapped in their column width). The text
    /// system's own tables (`NSTextTable`) lay out in time that grows with the square of the table, which the guide's
    /// long reference tables make unusable; rows as attachments are laid out once and break between pages cleanly.
    func table(header: [String], rows: [[String]], file: String, into text: NSMutableAttributedString) {
        let columns: Int = max(header.count, rows.map(\.count).max() ?? 0)
        guard columns > 0 else { return }
        let shares: [CGFloat] = Self.columnShares(([header] + rows), columns: columns)
        // A hair narrower than the page: an attachment wider than the container is never placed.
        let widths: [CGFloat] = shares.map { floor((contentWidth - 2) * $0) / 100 }
        let style: NSMutableParagraphStyle = paragraphStyle(after: 0)
        style.lineHeightMultiple = 1.0
        let cellStyle: NSMutableParagraphStyle = paragraphStyle(after: 0)
        cellStyle.lineHeightMultiple = 1.05
        for (rowIndex, row) in ([header] + rows).enumerated() {
            let font: NSFont = Self.font(8.5, rowIndex == 0 ? .semibold : .regular)
            let cells: [NSAttributedString] = (0..<columns).map { column in
                inline(column < row.count ? row[column] : "", font: font, file: file, style: cellStyle)
            }
            let cell = ManualTableRowCell(cells: cells, widths: widths, header: rowIndex == 0)
            let attachment = NSTextAttachment()
            attachment.attachmentCell = cell
            let line = NSMutableAttributedString(attachment: attachment)
            line.append(NSAttributedString(string: "\n"))
            line.addAttributes([.font: Self.font(1), .paragraphStyle: style], range: NSRange(location: 0, length: line.length))
            text.append(line)
        }
        // Space after the table.
        text.append(NSAttributedString(string: "\n", attributes: [.font: Self.font(4), .paragraphStyle: paragraphStyle(after: 0)]))
    }

    /// Column widths in percent: by the average length of their cells (short key columns stay narrow).
    static func columnShares(_ rows: [[String]], columns: Int) -> [CGFloat] {
        var weights: [CGFloat] = Array(repeating: 1, count: columns)
        for column in 0..<columns {
            let lengths: [Int] = rows.map { column < $0.count ? $0[column].count : 0 }
            let average: CGFloat = CGFloat(lengths.reduce(0, +)) / CGFloat(max(lengths.count, 1))
            weights[column] = min(max(average, 8), 80)
        }
        let total: CGFloat = weights.reduce(0, +)
        return weights.map { $0 / total * 100 }
    }

    func image(alt: String, path: String, into text: NSMutableAttributedString) {
        let url: URL = docs.appendingPathComponent(path)
        guard let image = NSImage(contentsOf: url), let rep = image.representations.first else {
            // The loader checks the images first; a missing one is left out.
            return
        }
        let pixels = CGSize(width: max(rep.pixelsWide, 1), height: max(rep.pixelsHigh, 1))
        // Screenshots are taken at 2x: half their pixels in points, at most the page width and half its height.
        var width: CGFloat = min(contentWidth - 2, pixels.width / 2)
        var height: CGFloat = width * pixels.height / pixels.width
        let maxHeight: CGFloat = contentHeight * 0.5
        if height > maxHeight {
            height = maxHeight
            width = height * pixels.width / pixels.height
        }
        let scaled: NSImage = image.copy() as? NSImage ?? image
        scaled.size = CGSize(width: width, height: height)
        let attachment = NSTextAttachment()
        attachment.attachmentCell = NSTextAttachmentCell(imageCell: scaled)
        let style: NSMutableParagraphStyle = paragraphStyle(spacingBefore: 4, after: 2, alignment: .center)
        let picture = NSMutableAttributedString(attachment: attachment)
        picture.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: picture.length))
        picture.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: style]))
        text.append(picture)
        if !alt.isEmpty {
            text.append(NSAttributedString(string: alt + "\n", attributes: [
                .font: Self.font(8.5, italic: true), .foregroundColor: Self.muted,
                .paragraphStyle: paragraphStyle(after: 8, alignment: .center),
            ]))
        }
    }
}

/// One table row drawn as an attachment: the cells side by side in their widths, wrapped, with borders; the header row
/// shaded. The text is drawn as text (selectable and searchable in the PDF).
final class ManualTableRowCell: NSTextAttachmentCell {

    static let padding: CGFloat = 3

    let cells: [NSAttributedString]
    let widths: [CGFloat]
    let header: Bool
    let height: CGFloat

    init(cells: [NSAttributedString], widths: [CGFloat], header: Bool) {
        self.cells = cells
        self.widths = widths
        self.header = header
        var tallest: CGFloat = 0
        for (index, cell) in cells.enumerated() {
            let size = CGSize(width: max(widths[index] - 2 * Self.padding, 10), height: .greatestFiniteMagnitude)
            let bounds: CGRect = cell.boundingRect(with: size, options: [.usesLineFragmentOrigin, .usesFontLeading])
            tallest = max(tallest, ceil(bounds.height))
        }
        height = max(tallest, 10) + 2 * Self.padding
        super.init(textCell: "")
    }

    required init(coder: NSCoder) {
        fatalError("not used")
    }

    override func cellSize() -> NSSize {
        NSSize(width: widths.reduce(0, +), height: height)
    }

    override func cellBaselineOffset() -> NSPoint {
        .zero
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        var x: CGFloat = cellFrame.minX
        for (index, cell) in cells.enumerated() {
            let box = CGRect(x: x, y: cellFrame.minY, width: widths[index], height: height)
            if header {
                ManualTypesetter.tableHeader.setFill()
                box.fill()
            }
            ManualTypesetter.rule.setStroke()
            let border = NSBezierPath(rect: box.insetBy(dx: 0.25, dy: 0.25))
            border.lineWidth = 0.5
            border.stroke()
            cell.draw(with: box.insetBy(dx: Self.padding, dy: Self.padding),
                      options: [.usesLineFragmentOrigin, .usesFontLeading])
            x += widths[index]
        }
    }

    /// The linked runs of the cells: rects relative to the row's top left corner, with their targets.
    func links() -> [(rect: CGRect, target: String)] {
        var out: [(rect: CGRect, target: String)] = []
        var x: CGFloat = 0
        for (index, cell) in cells.enumerated() {
            defer { x += widths[index] }
            var linked = false
            cell.enumerateAttribute(.manualLink, in: NSRange(location: 0, length: cell.length)) { value, _, _ in
                linked = linked || value != nil
            }
            guard linked else { continue }
            let storage = NSTextStorage(attributedString: cell)
            let manager = NSLayoutManager()
            storage.addLayoutManager(manager)
            let container = NSTextContainer(size: CGSize(width: max(widths[index] - 2 * Self.padding, 10),
                                                         height: .greatestFiniteMagnitude))
            container.lineFragmentPadding = 0
            manager.addTextContainer(container)
            manager.ensureLayout(for: container)
            cell.enumerateAttribute(.manualLink, in: NSRange(location: 0, length: cell.length)) { value, range, _ in
                guard let target = value as? String else { return }
                let glyphs: NSRange = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                manager.enumerateEnclosingRects(forGlyphRange: glyphs,
                                                withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                                                in: container) { rect, _ in
                    out.append((rect.offsetBy(dx: x + Self.padding, dy: Self.padding), target))
                }
            }
        }
        return out
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?, characterIndex charIndex: Int,
                       layoutManager: NSLayoutManager) {
        draw(withFrame: cellFrame, in: controlView)
    }
}
