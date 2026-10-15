import AppKit
import Foundation
import PDFKit

/// The PDF of the user guide: A4 pages laid out by the text system (one text container per page; a chapter starts a
/// page unless the previous one ends in the upper two thirds of its page, then it goes on below it), a running header with the chapter, page numbers in the footer, a contents page with page numbers, the PDF
/// outline (chapters and their sections) and working links (inside the book and to the web). Only AppKit and PDFKit —
/// nothing to install on the build machine.
@MainActor
public struct ManualRenderer {

    public struct Options: Sendable {
        /// Shown on the title page and in the document info (`v0.9.0`).
        public var version: String?
        /// The build date on the title page (`nil` = none).
        public var buildDate: Date?
        public var pageSize = CGSize(width: 595.28, height: 841.89)
        public var margin = CGSize(width: 54, height: 60)

        public init(version: String? = nil, buildDate: Date? = nil) {
            self.version = version
            self.buildDate = buildDate
        }
    }

    /// What was rendered.
    public struct Summary: Sendable, Equatable {
        public var pages: Int
        public var chapters: Int
        /// The page of each chapter (1-based, as printed).
        public var chapterPages: [String: Int]
        public var outlineEntries: Int
        public var links: Int
        /// The chapters (files, in book order) that start a new page; the others go on below the previous chapter.
        public var pageStarts: [String]
    }

    /// A chapter goes on below the previous one when that one leaves more than this share of its last page empty.
    static let joinBelow: CGFloat = 2.0 / 3.0

    let book: ManualBook
    let docs: URL
    let options: Options

    public init(book: ManualBook, docs: URL, options: Options = Options()) {
        self.book = book
        self.docs = docs
        self.options = options
    }

    var contentSize: CGSize {
        CGSize(width: options.pageSize.width - 2 * options.margin.width,
               height: options.pageSize.height - 2 * options.margin.height)
    }

    /// One laid-out pass.
    struct Layout {
        let storage: NSTextStorage
        let manager: NSLayoutManager
        let containers: [NSTextContainer]
        /// Anchor → page index (0-based) and the y of its line in the page's container.
        var anchors: [String: (page: Int, y: CGFloat)] = [:]
        /// Headings (by anchor) whose next paragraph starts on a later page.
        var stranded: Set<String> = []
        /// The chapters (by file) whose previous chapter ends high enough on its page for them to go on below it.
        var joinable: Set<String> = []
        /// The chapters that went on below the previous one in this pass.
        var joined: Set<String> = []
    }

    /// Lays the book out until the contents' page numbers and the page breaks before stranded headings settle.
    func settledLayout() -> Layout {
        var pages: [String: Int] = [:]
        var breaks: Set<String> = []
        var joined: Set<String> = []
        var layout: Layout = lay(pages: pages, breaks: breaks, joined: joined)
        // Every set only grows, so the passes settle; the cap is a safety net.
        for _ in 0..<10 {
            let found: [String: Int] = layout.anchors.mapValues { $0.page + 1 }
            let newBreaks: Set<String> = breaks.union(layout.stranded)
            let newJoined: Set<String> = joined.union(layout.joinable)
            if found == pages && newBreaks == breaks && newJoined == joined {
                break
            }
            pages = found
            breaks = newBreaks
            joined = newJoined
            layout = lay(pages: pages, breaks: breaks, joined: joined)
        }
        return layout
    }

    func lay(pages: [String: Int], breaks: Set<String>, joined: Set<String>) -> Layout {
        let typesetter = ManualTypesetter(book: book, docs: docs, version: options.version, buildDate: options.buildDate,
                                          contentWidth: contentSize.width, contentHeight: contentSize.height,
                                          pages: pages, breaks: breaks, joined: joined)
        let storage = NSTextStorage(attributedString: typesetter.build())
        let manager = NSLayoutManager()
        manager.allowsNonContiguousLayout = false
        storage.addLayoutManager(manager)
        var containers: [NSTextContainer] = []
        // One container per page until every glyph is placed (a form feed ends a container).
        while true {
            let container = NSTextContainer(size: contentSize)
            container.lineFragmentPadding = 0
            manager.addTextContainer(container)
            containers.append(container)
            let range: NSRange = manager.glyphRange(for: container)
            // An empty page means a glyph that fits no page (it would never be placed): stop rather than loop.
            if NSMaxRange(range) >= manager.numberOfGlyphs || range.length == 0 || containers.count > 2_000 {
                break
            }
        }
        var layout = Layout(storage: storage, manager: manager, containers: containers)
        let containerIndex: [ObjectIdentifier: Int] = Dictionary(uniqueKeysWithValues: containers.enumerated().map {
            (ObjectIdentifier($0.element), $0.offset)
        })
        func page(ofCharacter index: Int) -> (page: Int, y: CGFloat)? {
            guard index < storage.length else { return nil }
            let glyph: Int = manager.glyphIndexForCharacter(at: index)
            var effective = NSRange()
            guard let container = manager.textContainer(forGlyphAt: glyph, effectiveRange: &effective),
                  let number = containerIndex[ObjectIdentifier(container)] else { return nil }
            let rect: CGRect = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            return (number, rect.minY)
        }
        let whole = NSRange(location: 0, length: storage.length)
        storage.enumerateAttribute(.manualAnchor, in: whole) { value, range, _ in
            guard let anchor = value as? String, let place = page(ofCharacter: range.location) else { return }
            if layout.anchors[anchor] == nil {
                layout.anchors[anchor] = place
            }
        }
        // Where each chapter's predecessor ends: high on its page → the chapter may go on below it.
        let first: String? = book.chapters.first?.file
        storage.enumerateAttribute(.manualChapterLead, in: whole) { value, range, _ in
            guard let file = value as? String, file != first, range.location > 0 else { return }
            if storage.attributedSubstring(from: NSRange(location: range.location, length: 1)).string != "\u{000C}" {
                layout.joined.insert(file)
            }
            let end: Int = range.location - 1
            let glyph: Int = manager.glyphIndexForCharacter(at: end)
            guard manager.textContainer(forGlyphAt: glyph, effectiveRange: nil) != nil else { return }
            let line: CGRect = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            if line.maxY < contentSize.height * Self.joinBelow {
                layout.joinable.insert(file)
            }
        }
        // A heading alone at the bottom of a page (also a chapter title that went on below the previous chapter).
        storage.enumerateAttribute(.manualHeading, in: whole) { value, range, _ in
            guard let level = value as? Int, let start = page(ofCharacter: range.location),
                  let next = page(ofCharacter: NSMaxRange(range)), next.page > start.page,
                  let anchor = storage.attribute(.manualAnchor, at: range.location, effectiveRange: nil) as? String,
                  level > 1 || layout.joined.contains(anchor) else {
                return
            }
            layout.stranded.insert(anchor)
        }
        return layout
    }

    // MARK: - output

    /// Renders the PDF to `url`.
    @discardableResult
    public func write(to url: URL) throws -> Summary {
        let (data, summary) = try render()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        return summary
    }

    public enum RenderError: Error, CustomStringConvertible {
        case context
        case pdfKit

        public var description: String {
            switch self {
            case .context: return "cannot create the PDF context"
            case .pdfKit: return "PDFKit cannot read the rendered pages"
            }
        }
    }

    /// The PDF bytes and what they hold.
    public func render() throws -> (Data, Summary) {
        let layout: Layout = settledLayout()
        let raw: Data = try drawPages(layout)
        guard let document = PDFDocument(data: raw) else { throw RenderError.pdfKit }
        let links: Int = addLinks(layout, to: document)
        let outlineEntries: Int = addOutline(layout, to: document)
        var attributes: [AnyHashable: Any] = [
            PDFDocumentAttribute.titleAttribute: "MacContestLogger — " + ManualTypesetter.subtitle(book),
            PDFDocumentAttribute.creatorAttribute: "mcl-manual",
            PDFDocumentAttribute.subjectAttribute: book.language.documentSubject,
        ]
        if let version = options.version, !version.isEmpty {
            attributes[PDFDocumentAttribute.keywordsAttribute] = [version]
        }
        document.documentAttributes = attributes
        guard let data = document.dataRepresentation() else { throw RenderError.pdfKit }
        var chapterPages: [String: Int] = [:]
        for chapter in book.chapters {
            if let place = layout.anchors[chapter.file] {
                chapterPages[chapter.file] = place.page + 1
            }
        }
        let summary = Summary(pages: layout.containers.count, chapters: book.chapters.count, chapterPages: chapterPages,
                              outlineEntries: outlineEntries, links: links, pageStarts: pageStarts(layout))
        return (data, summary)
    }

    /// The chapters that start a new page in `layout` (book order).
    func pageStarts(_ layout: Layout) -> [String] {
        book.chapters.map(\.file).filter { !layout.joined.contains($0) }
    }

    /// The page flow alone (no PDF): the chapters that start a new page, for the HTML's print breaks.
    public func pageStarts() -> [String] {
        pageStarts(settledLayout())
    }

    /// The chapter title shown in the header of each page (the last chapter that starts on or before it).
    func runningTitles(_ layout: Layout) -> [String?] {
        var titles: [String?] = Array(repeating: nil, count: layout.containers.count)
        let starts: [(page: Int, title: String)] = book.chapters.compactMap { chapter in
            layout.anchors[chapter.file].map { ($0.page, Self.plain(chapter.title)) }
        }.sorted { $0.page < $1.page }
        for index in titles.indices {
            titles[index] = starts.last(where: { $0.page <= index })?.title
        }
        return titles
    }

    func drawPages(_ layout: Layout) throws -> Data {
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: options.pageSize)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { throw RenderError.context }
        let titles: [String?] = runningTitles(layout)
        let origin = CGPoint(x: options.margin.width, y: options.margin.height)
        let small: [NSAttributedString.Key: Any] = [
            .font: ManualTypesetter.font(7.5), .foregroundColor: ManualTypesetter.muted,
        ]
        for (index, container) in layout.containers.enumerated() {
            context.beginPDFPage(nil)
            context.saveGState()
            context.translateBy(x: 0, y: options.pageSize.height)
            context.scaleBy(x: 1, y: -1)
            let graphics = NSGraphicsContext(cgContext: context, flipped: true)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphics
            let glyphs: NSRange = layout.manager.glyphRange(for: container)
            layout.manager.drawBackground(forGlyphRange: glyphs, at: origin)
            layout.manager.drawGlyphs(forGlyphRange: glyphs, at: origin)
            if index > 0 {
                let footer = NSAttributedString(string: String(index + 1), attributes: small)
                let footerSize: CGSize = footer.size()
                footer.draw(at: CGPoint(x: (options.pageSize.width - footerSize.width) / 2,
                                        y: options.pageSize.height - options.margin.height / 2 - footerSize.height / 2))
                if let title = titles[index] {
                    let left = NSAttributedString(string: "MacContestLogger", attributes: small)
                    left.draw(at: CGPoint(x: options.margin.width, y: options.margin.height / 2 - 4))
                    let right = NSAttributedString(string: title, attributes: small)
                    right.draw(at: CGPoint(x: options.pageSize.width - options.margin.width - right.size().width,
                                           y: options.margin.height / 2 - 4))
                }
            }
            NSGraphicsContext.restoreGraphicsState()
            context.restoreGState()
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }

    /// A destination at the top of an anchor's line.
    func destination(_ anchor: String, _ layout: Layout, in document: PDFDocument) -> PDFDestination? {
        guard let place = layout.anchors[anchor], let page = document.page(at: place.page) else { return nil }
        let y: CGFloat = options.pageSize.height - options.margin.height - place.y + 4
        return PDFDestination(page: page, at: CGPoint(x: options.margin.width, y: min(options.pageSize.height, y)))
    }

    /// Link annotations over every linked run (internal: go to the anchor, else the URL), also inside table rows.
    func addLinks(_ layout: Layout, to document: PDFDocument) -> Int {
        var count = 0
        let storage: NSTextStorage = layout.storage
        let manager: NSLayoutManager = layout.manager
        let whole = NSRange(location: 0, length: storage.length)
        /// `rect` in the page's container coordinates.
        func annotate(_ rect: CGRect, page index: Int, target: String) {
            guard let page = document.page(at: index), let action = action(target, layout, in: document) else { return }
            let bounds = CGRect(x: options.margin.width + rect.minX,
                                y: options.pageSize.height - options.margin.height - rect.maxY,
                                width: rect.width, height: rect.height)
            let annotation = PDFAnnotation(bounds: bounds, forType: .link, withProperties: nil)
            let border = PDFBorder()
            border.lineWidth = 0
            annotation.border = border
            annotation.action = action
            page.addAnnotation(annotation)
            count += 1
        }
        storage.enumerateAttribute(.manualLink, in: whole) { value, range, _ in
            guard let target = value as? String else { return }
            let glyphs: NSRange = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            for (index, container) in layout.containers.enumerated() {
                let pageGlyphs: NSRange = NSIntersectionRange(glyphs, manager.glyphRange(for: container))
                guard pageGlyphs.length > 0 else { continue }
                manager.enumerateEnclosingRects(forGlyphRange: pageGlyphs,
                                                withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                                                in: container) { rect, _ in
                    annotate(rect, page: index, target: target)
                }
            }
        }
        let containerIndex: [ObjectIdentifier: Int] = Dictionary(uniqueKeysWithValues: layout.containers.enumerated().map {
            (ObjectIdentifier($0.element), $0.offset)
        })
        storage.enumerateAttribute(.attachment, in: whole) { value, range, _ in
            guard let row = (value as? NSTextAttachment)?.attachmentCell as? ManualTableRowCell else { return }
            let links = row.links()
            guard !links.isEmpty else { return }
            let glyph: Int = manager.glyphIndexForCharacter(at: range.location)
            guard let container = manager.textContainer(forGlyphAt: glyph, effectiveRange: nil),
                  let index = containerIndex[ObjectIdentifier(container)] else { return }
            let line: CGRect = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let location: CGPoint = manager.location(forGlyphAt: glyph)
            let size: NSSize = row.cellSize()
            // The attachment sits on the baseline: its top is the baseline minus its height.
            let origin = CGPoint(x: line.minX + location.x, y: line.minY + location.y - size.height)
            for link in links {
                annotate(link.rect.offsetBy(dx: origin.x, dy: origin.y), page: index, target: link.target)
            }
        }
        return count
    }

    /// Where a link goes: an anchor in the book (a missing section falls back to its chapter) or a URL.
    func action(_ target: String, _ layout: Layout, in document: PDFDocument) -> PDFAction? {
        guard target.hasPrefix("#") else {
            return URL(string: target).map { PDFActionURL(url: $0) }
        }
        var anchor = String(target.dropFirst())
        if layout.anchors[anchor] == nil, let hash = anchor.firstIndex(of: "#") {
            anchor = String(anchor[..<hash])
        }
        return destination(anchor, layout, in: document).map { PDFActionGoTo(destination: $0) }
    }

    /// The outline: parts → chapters → their `##` sections.
    func addOutline(_ layout: Layout, to document: PDFDocument) -> Int {
        let root = PDFOutline()
        var count = 0
        var partNode: PDFOutline?
        var partName: String?
        for chapter in book.chapters {
            if chapter.part != partName {
                partName = chapter.part
                let node = PDFOutline()
                node.label = chapter.part
                node.destination = destination(chapter.file, layout, in: document)
                root.insertChild(node, at: root.numberOfChildren)
                partNode = node
                count += 1
            }
            guard let parent = partNode else { continue }
            let chapterNode = PDFOutline()
            chapterNode.label = Self.plain(chapter.title)
            chapterNode.destination = destination(chapter.file, layout, in: document)
            parent.insertChild(chapterNode, at: parent.numberOfChildren)
            count += 1
            for block in chapter.blocks {
                guard case .heading(2, let title) = block else { continue }
                let anchor: String = ManualBook.anchor(file: chapter.file, heading: title)
                guard let target = destination(anchor, layout, in: document) else { continue }
                let section = PDFOutline()
                section.label = Self.plain(title)
                section.destination = target
                chapterNode.insertChild(section, at: chapterNode.numberOfChildren)
                count += 1
            }
        }
        document.outlineRoot = root
        return count
    }

    /// A heading without its inline Markdown (`` `X` `` → `X`), for the outline.
    static func plain(_ text: String) -> String {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        guard let parsed = try? AttributedString(markdown: text, options: options) else { return text }
        return String(parsed.characters)
    }
}
