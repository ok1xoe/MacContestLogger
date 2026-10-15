import AppKit
import Foundation
@testable import MCLManual
import PDFKit
import Testing

/// The PDF user guide (`mcl-manual`): the Markdown subset of `docs/`, the book order from `README.md`, and a rendered
/// PDF with contents, outline, page numbers and working links. Runs on the main actor (AppKit text layout).
@MainActor @Suite struct ManualPdfTests {

    @Test func markdownBlocks() {
        let source = """
        # Title

        Some *text*
        on two lines.

        1. **First** item
           continued here
           - nested bullet
             - deeper
        2. Second
           ```bash
           brew install x
             indented
           ```
        - after code

        | Key | Action |
        |-----|--------|
        | `a\\|b` | does it |
        | short |

        > quoted
        > more

        ![Shot](img/a.png)

        ---
        """
        let blocks = ManualMarkdown.blocks(source)
        #expect(blocks == [
            .heading(level: 1, text: "Title"),
            .paragraph("Some *text* on two lines."),
            .list([
                ManualListItem(marker: "1.", level: 0, text: "**First** item continued here"),
                ManualListItem(marker: "•", level: 1, text: "nested bullet"),
                ManualListItem(marker: "•", level: 2, text: "deeper"),
                ManualListItem(marker: "2.", level: 0, text: "Second"),
            ]),
            .code("brew install x\n  indented"),
            .list([ManualListItem(marker: "•", level: 0, text: "after code")]),
            .table(header: ["Key", "Action"], rows: [["`a|b`", "does it"], ["short"]]),
            .quote("quoted more"),
            .image(alt: "Shot", path: "img/a.png"),
            .rule,
        ])
        #expect(ManualBook.slug("Spot comment: spotting S&P QSOs") == "spot-comment-spotting-sp-qsos")
    }

    /// A small `docs` directory: README with two parts, two chapters (a long table and a long code block that must
    /// break across pages), an image and cross links.
    static func makeDocs() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mcl-manual-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("img"), withIntermediateDirectories: true)
        try """
        # MacContestLogger user guide

        Intro paragraph.

        ## Part one

        - [First](first.md)

        ## Part two

        - [Second](second.md)
        - [Not a page](sample.conf)
        """.write(to: dir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        let rows: String = (1...150).map { "| key \($0) | action \($0) with [a link](second.md#details) |" }
            .joined(separator: "\n")
        try """
        # First chapter

        See [the second chapter](second.md) and [the web](https://example.com/).

        ## Keys

        | Key | Action |
        |-----|--------|
        \(rows)

        ![A picture](img/pic.png)
        """.write(to: dir.appendingPathComponent("first.md"), atomically: true, encoding: .utf8)
        let code: String = (1...160).map { "line \($0)" }.joined(separator: "\n")
        try """
        # Second chapter

        ## Details

        ```
        \(code)
        ```
        """.write(to: dir.appendingPathComponent("second.md"), atomically: true, encoding: .utf8)
        let image = NSImage(size: CGSize(width: 40, height: 20), flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            return true
        }
        let png = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        try png.write(to: dir.appendingPathComponent("img/pic.png"))
        return dir
    }

    @Test func bookFollowsTheReadme() throws {
        let dir: URL = try Self.makeDocs()
        defer { try? FileManager.default.removeItem(at: dir) }
        let book = try ManualBook.load(docs: dir)
        #expect(book.title == "MacContestLogger user guide")
        #expect(book.chapters.map(\.file) == ["first.md", "second.md"])
        #expect(book.chapters.map(\.title) == ["First chapter", "Second chapter"])
        #expect(book.chapters.map(\.part) == ["Part one", "Part two"])
        #expect(book.intro == [.paragraph("Intro paragraph.")])
    }

    @Test func missingPagesAndImagesAreErrors() throws {
        let dir: URL = try Self.makeDocs()
        defer { try? FileManager.default.removeItem(at: dir) }
        let picture: URL = dir.appendingPathComponent("img/pic.png")
        let png = try Data(contentsOf: picture)
        try FileManager.default.removeItem(at: picture)
        #expect(throws: ManualBook.LoadError.missing("img/pic.png")) { try ManualBook.load(docs: dir) }
        try png.write(to: picture)
        try FileManager.default.removeItem(at: dir.appendingPathComponent("second.md"))
        #expect(throws: ManualBook.LoadError.missing("second.md")) { try ManualBook.load(docs: dir) }
    }

    @Test func rendersAPaginatedPdfWithContentsOutlineAndLinks() throws {
        let dir: URL = try Self.makeDocs()
        defer { try? FileManager.default.removeItem(at: dir) }
        let book = try ManualBook.load(docs: dir)
        let (data, summary) = try ManualRenderer(book: book, docs: dir, options: .init(version: "v9.9.9")).render()
        #expect(data.prefix(5).elementsEqual("%PDF-".utf8))
        let document = try #require(PDFDocument(data: data))
        #expect(document.pageCount == summary.pages)
        // Title page, contents, the long table and the long code block each need more than one page.
        let first: Int = try #require(summary.chapterPages["first.md"])
        let second: Int = try #require(summary.chapterPages["second.md"])
        #expect(first == 3)
        #expect(second > first + 1)
        #expect(summary.pages > second + 1)
        // Contents: each chapter's line shows its page and links to it.
        let contents = try #require(document.page(at: 1))
        let text: String = contents.string ?? ""
        #expect(text.contains("First chapter\t\(first)") || text.contains("First chapter \(first)")
                || text.contains("First chapter\(first)"))
        let goTos: [Int] = contents.annotations.compactMap { annotation in
            (annotation.action as? PDFActionGoTo).flatMap { $0.destination.page }.map { document.index(for: $0) + 1 }
        }
        #expect(goTos == [first, second])
        // Page numbers in the footer, the version on the title page.
        #expect(document.page(at: 0)?.string?.contains("v9.9.9") == true)
        #expect(document.page(at: summary.pages - 1)?.string?.contains(String(summary.pages)) == true)
        // Outline: parts → chapters → sections.
        let root = try #require(document.outlineRoot)
        #expect(root.numberOfChildren == 2)
        #expect(root.child(at: 0)?.label == "Part one")
        #expect(root.child(at: 0)?.child(at: 0)?.label == "First chapter")
        #expect(root.child(at: 0)?.child(at: 0)?.child(at: 0)?.label == "Keys")
        #expect(root.child(at: 1)?.child(at: 0)?.child(at: 0)?.label == "Details")
        // Links in the text and in the table cells: internal ones go to the chapter, the web one to its URL.
        let firstPage = try #require(document.page(at: first - 1))
        let urls: [String] = firstPage.annotations.compactMap { ($0.action as? PDFActionURL)?.url?.absoluteString }
        #expect(urls == ["https://example.com/"])
        let tableLinks: [Int] = firstPage.annotations.compactMap { annotation in
            guard let page = (annotation.action as? PDFActionGoTo)?.destination.page else { return nil }
            return firstPage.selection(for: annotation.bounds.insetBy(dx: 1, dy: 1))?.string == "a link"
                ? document.index(for: page) + 1 : nil
        }
        #expect(!tableLinks.isEmpty)
        #expect(tableLinks.allSatisfy { $0 == second })
        #expect(summary.links >= 150 + 2 + 2)
    }
}
