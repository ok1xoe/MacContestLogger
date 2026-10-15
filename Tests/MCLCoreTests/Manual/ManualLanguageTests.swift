import AppKit
import Foundation
@testable import MCLManual
import PDFKit
import Testing

/// The bilingual user guide: the Czech book from `docs/cs/` (an untranslated page falls back to English with a warning,
/// a strict load refuses it), the English book with English screenshots from `docs/img/en/` where they exist (the
/// others are marked as Czech), and the localised fixed texts of the title page and contents.
@MainActor @Suite struct ManualLanguageTests {

    static func png(_ color: NSColor) throws -> Data {
        let image = NSImage(size: CGSize(width: 40, height: 20), flipped: false) { rect in
            color.setFill()
            rect.fill()
            return true
        }
        let tiff: Data = try #require(image.tiffRepresentation)
        let rep: NSBitmapImageRep = try #require(NSBitmapImageRep(data: tiff))
        return try #require(rep.representation(using: .png, properties: [:]))
    }

    /// `ManualPdfTests.makeDocs()` plus `cs/README.md` and a Czech `first.md` (`second.md` is not translated).
    static func makeBilingualDocs() throws -> URL {
        let dir: URL = try ManualPdfTests.makeDocs()
        let cs: URL = dir.appendingPathComponent("cs")
        try FileManager.default.createDirectory(at: cs, withIntermediateDirectories: true)
        try """
        # Uživatelská příručka MacContestLogger

        Úvodní odstavec.

        ## První část

        - [První](first.md)

        ## Druhá část

        - [Druhá](second.md)
        """.write(to: cs.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try """
        # První kapitola

        Viz [druhou kapitolu](second.md), [ukázku](../sample.conf) a [zdroj](../../Sources/x.swift).

        ![Obrázek](../img/pic.png)

        ![Obrázek bez cesty ke kořeni](img/pic.png)
        """.write(to: cs.appendingPathComponent("first.md"), atomically: true, encoding: .utf8)
        return dir
    }

    static let built = Date(timeIntervalSince1970: 1_792_108_800) // 2026-10-16 UTC

    @Test func theCzechBookReadsTheTranslatedPagesAndFallsBackToEnglish() throws {
        let dir: URL = try Self.makeBilingualDocs()
        defer { try? FileManager.default.removeItem(at: dir) }
        let book = try ManualBook.load(docs: dir, language: .cs)
        #expect(book.language == .cs)
        #expect(book.title == "Uživatelská příručka MacContestLogger")
        #expect(book.intro == [.paragraph("Úvodní odstavec.")], "no screenshot note in the Czech book")
        #expect(book.chapters.map(\.title) == ["První kapitola", "Second chapter"])
        #expect(book.chapters.map(\.part) == ["První část", "Druhá část"])
        #expect(book.chapters.map(\.sourceDir) == ["cs/", ""])
        #expect(book.untranslated == ["second.md"])
        #expect(book.warnings == ["cs/second.md is not translated yet, the English page is used"])
        #expect(book.czechScreenshots.isEmpty)
        // Both ways of writing the image path find the default (Czech) screenshot.
        let images: [String] = book.chapters[0].blocks.compactMap {
            if case .image(_, let path) = $0 { return path }
            return nil
        }
        #expect(images == ["img/pic.png", "img/pic.png"])
        // Links: a page of the book, a file of the repository relative to the page, nothing outside docs/.
        #expect(book.resolveLink("second.md", from: "first.md") == "#second.md")
        #expect(book.resolveLink("../sample.conf", from: "first.md") == ManualBook.repositoryDocs + "sample.conf")
        #expect(book.resolveLink("../../Sources/x.swift", from: "first.md") == nil)
        #expect(book.resolveLink("../second.md#details", from: "first.md") == "#second.md#details")
        // Strict: the untranslated page is an error; without cs/README.md even the README is.
        #expect(throws: ManualBook.LoadError.untranslated("cs/second.md")) {
            try ManualBook.load(docs: dir, language: .cs, strict: true)
        }
        try FileManager.default.removeItem(at: dir.appendingPathComponent("cs/README.md"))
        #expect(throws: ManualBook.LoadError.untranslated("cs/README.md")) {
            try ManualBook.load(docs: dir, language: .cs, strict: true)
        }
        let fallback = try ManualBook.load(docs: dir, language: .cs)
        #expect(fallback.chapters.map(\.title) == ["První kapitola", "Second chapter"])
        #expect(fallback.warnings.first == "cs/README.md is not translated yet, the English page is used")
    }

    @Test func theEnglishBookPrefersEnglishScreenshotsAndMarksTheCzechOnes() throws {
        let dir: URL = try Self.makeBilingualDocs()
        defer { try? FileManager.default.removeItem(at: dir) }
        let czech = try ManualBook.load(docs: dir)
        #expect(czech.czechScreenshots == ["img/pic.png"])
        #expect(czech.intro == [.paragraph("Intro paragraph."), .paragraph(ManualLanguage.czechScreenshotsNote)])
        #expect(czech.chapters[0].blocks.contains(.image(alt: "A picture (Czech interface)", path: "img/pic.png")))
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("img/en"), withIntermediateDirectories: true)
        try Self.png(.blue).write(to: dir.appendingPathComponent("img/en/pic.png"))
        let english = try ManualBook.load(docs: dir)
        #expect(english.czechScreenshots.isEmpty)
        #expect(english.intro == [.paragraph("Intro paragraph.")])
        #expect(english.chapters[0].blocks.contains(.image(alt: "A picture", path: "img/en/pic.png")))
        // The Czech book keeps the Czech screenshot.
        let cs = try ManualBook.load(docs: dir, language: .cs)
        #expect(cs.chapters[0].blocks.contains(.image(alt: "Obrázek", path: "img/pic.png")))
        // The HTML embeds the English picture.
        let (html, _) = ManualHTML(book: english, docs: dir).render()
        let blue: String = try Self.png(.blue).base64EncodedString()
        #expect(html.contains(blue))
    }

    @Test func theFixedTextsFollowTheLanguage() throws {
        let dir: URL = try Self.makeBilingualDocs()
        defer { try? FileManager.default.removeItem(at: dir) }
        let book = try ManualBook.load(docs: dir, language: .cs)
        let (html, _) = ManualHTML(book: book, docs: dir, options: .init(version: "v1.2.3", buildDate: Self.built)).render()
        #expect(html.hasPrefix("<!DOCTYPE html>\n<html lang=\"cs\">"))
        #expect(html.contains("<title>MacContestLogger — Uživatelská příručka v1.2.3</title>"))
        #expect(html.contains("<p class=\"subtitle\">Uživatelská příručka</p>"))
        #expect(html.contains("Verze v1.2.3 · sestaveno 16. 10. 2026"))
        #expect(html.contains("<h1 class=\"toc-title\">Obsah</h1>"))
        #expect(!html.contains(">Contents<"))
        let renderer = ManualRenderer(book: book, docs: dir, options: .init(version: "v1.2.3", buildDate: Self.built))
        let (data, _) = try renderer.render()
        let document = try #require(PDFDocument(data: data))
        let title: String = document.page(at: 0)?.string ?? ""
        #expect(title.contains("Uživatelská příručka"))
        #expect(title.contains("16. 10. 2026"))
        #expect(title.contains("Přehled"))
        #expect(document.page(at: 1)?.string?.contains("Obsah") == true)
        #expect(document.documentAttributes?[PDFDocumentAttribute.subjectAttribute] as? String
                == "Uživatelská příručka MacContestLogger")
        #expect(ManualLanguage.en.editionLine(version: "v1", buildDate: Self.built) == "Version v1 · built 2026-10-16")
        #expect(ManualLanguage.cs.fileName("pdf") == "MacContestLogger-manual-cs.pdf")
        #expect(ManualLanguage.en.legacyFileName("html") == "MacContestLogger-manual.html")
        #expect(ManualLanguage.cs.legacyFileName("pdf") == nil)
    }

    /// The repository's own `docs/`.
    nonisolated static let repositoryDocs: URL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("docs")

    /// Once the Czech translation is in (`docs/cs/README.md`), every page it lists must be translated and every
    /// English page must have its Czech counterpart: a strict load of both languages.
    @Test(.enabled(if: FileManager.default.fileExists(
        atPath: ManualLanguageTests.repositoryDocs.appendingPathComponent("cs/README.md").path)))
    func theCzechGuideIsComplete() throws {
        let english = try ManualBook.load(docs: Self.repositoryDocs)
        let czech = try ManualBook.load(docs: Self.repositoryDocs, language: .cs, strict: true)
        #expect(czech.untranslated.isEmpty)
        #expect(czech.chapters.map(\.file) == english.chapters.map(\.file),
                "docs/cs/README.md lists the same pages in the same order as docs/README.md")
    }
}
