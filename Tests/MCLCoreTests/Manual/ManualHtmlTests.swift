import AppKit
import Foundation
@testable import MCLManual
import PDFKit
import Testing

/// The self-contained HTML user guide (`mcl-manual --html`) and the PDF's page flow: the HTML is well-formed (it is
/// written so an XML parser reads it), every internal link has its target, every image is embedded, nothing is loaded
/// from outside, the contents list the chapters in order; a short chapter goes on below the previous one in the PDF.
@MainActor @Suite struct ManualHtmlTests {

    /// What an XML parse of the page found.
    final class Collector: NSObject, XMLParserDelegate {
        var root: [String: String] = [:]
        var ids: [String] = []
        var hrefs: [String] = []
        var sources: [String] = []
        var widths: [String] = []
        var elements: [String] = []
        /// The `href`s of the contents' chapter entries, in order.
        var tocLinks: [String] = []
        /// The ids and classes of the chapter sections, in order.
        var chapters: [(id: String, classes: String)] = []
        var style = ""
        private var inToc = false
        private var inStyle = false

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            elements.append(name)
            if name == "html" {
                root = attributes
            }
            if let id = attributes["id"] {
                ids.append(id)
            }
            if let href = attributes["href"] {
                hrefs.append(href)
                if inToc {
                    tocLinks.append(href)
                }
            }
            if let source = attributes["src"] {
                sources.append(source)
                widths.append(attributes["width"] ?? "")
            }
            let classes: String = attributes["class"] ?? ""
            inToc = name == "li" && classes == "toc-chapter"
            if name == "section", classes.hasPrefix("chapter ") {
                chapters.append((attributes["id"] ?? "", classes))
            }
            inStyle = name == "style"
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            if name == "style" {
                inStyle = false
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if inStyle {
                style += string
            }
        }
    }

    static func parse(_ html: String) throws -> Collector {
        let parser = XMLParser(data: Data(html.utf8))
        let collector = Collector()
        parser.delegate = collector
        let parsed: Bool = parser.parse()
        #expect(parsed, "not well-formed: \(String(describing: parser.parserError))")
        return collector
    }

    static let built = Date(timeIntervalSince1970: 1_791_000_000)

    @Test func htmlIsOneSelfContainedLinkedPage() throws {
        let dir: URL = try ManualPdfTests.makeDocs()
        defer { try? FileManager.default.removeItem(at: dir) }
        let book = try ManualBook.load(docs: dir)
        let options = ManualHTML.Options(version: "v9.9.9", buildDate: Self.built, pageStarts: ["first.md"])
        let (html, summary) = ManualHTML(book: book, docs: dir, options: options).render()
        #expect(html.hasPrefix("<!DOCTYPE html>\n<html lang=\"en\">"))
        let page = try Self.parse(html)
        #expect(page.root["lang"] == "en")
        // Ids are unique and every internal link has its target.
        #expect(Set(page.ids).count == page.ids.count)
        let inBook: [String] = page.hrefs.filter { $0.hasPrefix("#") }
        #expect(!inBook.isEmpty)
        for href in inBook {
            #expect(page.ids.contains(String(href.dropFirst())), "no target for \(href)")
        }
        // Links between chapters became anchors (a missing section falls back to its chapter); the web link stays.
        #expect(inBook.contains("#ch-second"))
        #expect(inBook.contains("#ch-second--details"))
        #expect(page.hrefs.contains("https://example.com/"))
        #expect(!page.hrefs.contains { $0.hasSuffix(".md") || $0.contains(".md#") })
        #expect(summary.internalLinks == inBook.count - book.chapters.count - 1)
        // Every image embedded; nothing loaded from outside the file.
        #expect(page.sources.count == 1)
        #expect(page.sources.allSatisfy { $0.hasPrefix("data:image/png;base64,") })
        for source in page.sources {
            let data = try #require(Data(base64Encoded: String(source.drop { $0 != "," }.dropFirst())))
            #expect(NSImage(data: data) != nil)
        }
        #expect(summary.images == 1)
        #expect(!page.elements.contains("script") && !page.elements.contains("link") && !page.elements.contains("iframe"))
        #expect(!page.style.contains("url(") && !page.style.contains("@import"))
        #expect(!html.contains("src=\"http") && !html.contains("file:"))
        // The contents: one entry per chapter, in book order, numbered, linking to the chapters' sections.
        #expect(page.tocLinks == ["#ch-first", "#ch-second"])
        #expect(page.chapters.map(\.id) == ["ch-first", "ch-second"])
        #expect(html.contains("<span class=\"num\">1</span> First chapter</h1>"))
        #expect(html.contains("<span class=\"num\">2</span> Second chapter</h1>"))
        // The print flow follows `pageStarts`: the second chapter goes on below the first one, in its named page.
        #expect(page.chapters.map(\.classes) == ["chapter g1 page-start", "chapter g1 goes-on"])
        #expect(page.style.contains("@page g1 { @top-right { content: \"1 First chapter  ·  2 Second chapter\""))
        #expect(!page.style.contains("@page g2"))
        #expect(page.style.contains("@media print"))
        #expect(page.style.contains("prefers-color-scheme: dark"))
        // Title page: the version and the build date; the table's cells and the code are there.
        #expect(html.contains("Version v9.9.9 · built 2026-10-03"))
        #expect(html.contains("<td>key 150</td>"))
        #expect(html.contains("line 160\n</code></pre>") || html.contains("line 160</code></pre>"))
        // Every chapter starts a printed page when the flow is not known.
        let (plain, _) = ManualHTML(book: book, docs: dir).render()
        #expect(try Self.parse(plain).chapters.map(\.classes) == ["chapter g1 page-start", "chapter g2 page-start"])
    }

    @Test func markdownBecomesTheMatchingElements() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mcl-manual-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try """
        # MacContestLogger user guide

        ## Part

        - [One](one.md)
        """.write(to: dir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try """
        # One & only

        Text with **bold**, *italic*, `a<b>&c` and [a section](#keys).

        ## Keys

        3. third
        4. fourth
           - nested <tag>
        - bullet

        > a quote

        ## Keys

        ---
        """.write(to: dir.appendingPathComponent("one.md"), atomically: true, encoding: .utf8)
        let book = try ManualBook.load(docs: dir)
        let (html, _) = ManualHTML(book: book, docs: dir).render()
        let page = try Self.parse(html)
        #expect(html.contains("<strong>bold</strong>"))
        #expect(html.contains("<em>italic</em>"))
        #expect(html.contains("<code>a&lt;b&gt;&amp;c</code>"))
        #expect(html.contains("<a href=\"#ch-one--keys\">a section</a>"))
        #expect(html.contains("<ol start=\"3\">"))
        #expect(html.contains("<li>fourth<ul>") || html.contains("<li>fourth<ul>\n"))
        #expect(html.contains("nested &lt;tag&gt;"))
        #expect(html.contains("<blockquote><p>a quote</p></blockquote>"))
        #expect(html.contains("<hr />"))
        #expect(html.contains("One &amp; only</h1>"))
        // A repeated heading gets its own id; links go to the first one.
        #expect(page.ids.contains("ch-one--keys") && page.ids.contains("ch-one--keys-2"))
        #expect(Set(page.ids).count == page.ids.count)
    }

    /// A wide, incompressible screenshot is scaled down and re-encoded; its display size stays half its pixels.
    @Test func largeImagesAreReduced() throws {
        let dir: URL = try ManualPdfTests.makeDocs()
        defer { try? FileManager.default.removeItem(at: dir) }
        let width = 1_200
        let height = 300
        let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                                bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
                                                colorSpaceName: .deviceRGB, bytesPerRow: width * 3, bitsPerPixel: 24))
        var seed: UInt32 = 12_345
        let pixels = try #require(rep.bitmapData)
        for index in 0..<(width * height * 3) {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            pixels[index] = UInt8(truncatingIfNeeded: seed >> 24)
        }
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try png.write(to: dir.appendingPathComponent("img/pic.png"))
        let book = try ManualBook.load(docs: dir)
        var options = ManualHTML.Options()
        options.maxImagePixels = 600
        options.maxImageBytes = 200_000
        let (html, summary) = ManualHTML(book: book, docs: dir, options: options).render()
        #expect(summary.reducedImages == 1)
        #expect(summary.imageBytes < png.count)
        let page = try Self.parse(html)
        let source: String = try #require(page.sources.first)
        let data = try #require(Data(base64Encoded: String(source.drop { $0 != "," }.dropFirst())))
        #expect(try #require(NSBitmapImageRep(data: data)).pixelsWide == 600)
        #expect(page.widths == ["600"])
        // Small images are embedded as they are.
        let (_, untouched) = ManualHTML(book: book, docs: dir).render()
        #expect(untouched.reducedImages == 0)
        #expect(untouched.imageBytes == png.count)
    }

    /// Short chapters fill the page of the previous one instead of each starting a new page; the title page shows the
    /// edition and the parts at a glance.
    @Test func shortChaptersGoOnBelowThePreviousOne() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mcl-manual-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try """
        # MacContestLogger user guide

        Intro.

        ## Basics

        - [Alpha](alpha.md)
        - [Beta](beta.md)

        ## More

        - [Gamma](gamma.md)
        - [Delta](delta.md)
        """.write(to: dir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        let filler: String = (1...26).map { "Paragraph \($0) of a long chapter that fills its pages." }
            .joined(separator: "\n\n")
        for (file, title, body) in [("alpha.md", "Alpha", "One short paragraph."),
                                    ("beta.md", "Beta", "Another short paragraph."),
                                    ("gamma.md", "Gamma", filler + "\n\n" + filler + "\n\n" + filler),
                                    ("delta.md", "Delta", "Short again.")] {
            try "# \(title)\n\n\(body)\n".write(to: dir.appendingPathComponent(file), atomically: true, encoding: .utf8)
        }
        let book = try ManualBook.load(docs: dir)
        let renderer = ManualRenderer(book: book, docs: dir, options: .init(version: "v1.2.3", buildDate: Self.built))
        let (data, summary) = try renderer.render()
        let alpha: Int = try #require(summary.chapterPages["alpha.md"])
        #expect(alpha == 3)
        #expect(summary.chapterPages["beta.md"] == alpha)
        #expect(summary.chapterPages["gamma.md"] == alpha)
        #expect(summary.pageStarts.first == "alpha.md")
        #expect(!summary.pageStarts.contains("beta.md"))
        #expect(renderer.pageStarts() == summary.pageStarts)
        // Every chapter that starts a page follows one that left less than a third of its last page empty.
        let document = try #require(PDFDocument(data: data))
        #expect(document.pageCount == summary.pages)
        for file in summary.pageStarts.dropFirst() {
            let page: Int = try #require(summary.chapterPages[file])
            let previous = try #require(document.page(at: page - 2))
            let text: String = previous.string ?? ""
            #expect(text.split(separator: "\n").count > 20, "\(file) follows a page with little text")
        }
        let title: String = document.page(at: 0)?.string ?? ""
        #expect(title.contains("Version v1.2.3 · built 2026-10-03"))
        #expect(title.contains("At a glance"))
        #expect(title.contains("Basics") && title.contains("Alpha") && title.contains("Delta"))
    }
}
