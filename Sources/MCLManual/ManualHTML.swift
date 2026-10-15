import AppKit
import Foundation

/// The user guide as one self-contained HTML file, to read in a browser or to adjust and print to PDF (Safari's
/// „Export as PDF", Chrome's print): the same book as the PDF (`ManualBook`, the same Markdown blocks and link
/// resolution) with a title page, a linked table of contents, numbered chapters, every image embedded as a data URI
/// (large ones scaled down), no external resources, light and dark screen styles and a white A4 print style.
///
/// The output is also well-formed XML (void elements closed, only numeric character references), so it can be checked
/// with an XML parser. Printing: a chapter starts a new page where the PDF starts one (`Options.pageStarts`, from the
/// PDF's page flow), otherwise it goes on below the previous chapter; browsers with CSS page margin boxes and named
/// pages (Chrome) also print a running header with the chapter and page numbers.
@MainActor
public struct ManualHTML {

    public struct Options: Sendable {
        /// Shown on the title page (`v0.9.0`).
        public var version: String?
        /// The build date on the title page (`nil` = none).
        public var buildDate: Date?
        /// The chapters (files) that start a new printed page; `nil` = every chapter.
        public var pageStarts: Set<String>?
        /// An image wider than this (pixels) is scaled down to it.
        public var maxImagePixels: Int = 1_800
        /// A PNG or JPEG larger than this (bytes) is re-encoded (scaled down when also wide).
        public var maxImageBytes: Int = 1_200_000

        public init(version: String? = nil, buildDate: Date? = nil, pageStarts: Set<String>? = nil) {
            self.version = version
            self.buildDate = buildDate
            self.pageStarts = pageStarts
        }
    }

    /// What was written.
    public struct Summary: Sendable, Equatable {
        public var bytes: Int
        public var chapters: Int
        public var images: Int
        /// The images' bytes as embedded (before base64).
        public var imageBytes: Int
        /// The images that were scaled down or re-encoded.
        public var reducedImages: Int
        /// Links inside the book (`href="#…"`).
        public var internalLinks: Int
    }

    let book: ManualBook
    let docs: URL
    let options: Options

    public init(book: ManualBook, docs: URL, options: Options = Options()) {
        self.book = book
        self.docs = docs
        self.options = options
    }

    // MARK: - output

    @discardableResult
    public func write(to url: URL) throws -> Summary {
        let (html, summary) = render()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(html.utf8).write(to: url, options: .atomic)
        return summary
    }

    /// The HTML text and what it holds.
    public func render() -> (String, Summary) {
        var state = State(ids: Self.headingIds(book))
        var body = ""
        body += titlePage(&state)
        body += contents()
        var group = 0
        var groups: [(name: String, titles: [String])] = []
        for (index, chapter) in book.chapters.enumerated() {
            let starts: Bool = index == 0 || options.pageStarts?.contains(chapter.file) ?? true
            if starts || groups.isEmpty {
                group += 1
                groups.append(("g\(group)", []))
            }
            groups[groups.count - 1].titles.append("\(index + 1) " + ManualRenderer.plain(chapter.title))
            body += chapterHtml(chapter, number: index + 1, pageStart: starts, group: "g\(group)", state: &state)
        }
        var html = "<!DOCTYPE html>\n<html lang=\"" + book.language.htmlLang + "\">\n<head>\n<meta charset=\"utf-8\" />\n"
        html += "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />\n"
        html += "<meta name=\"color-scheme\" content=\"light dark\" />\n"
        html += "<meta name=\"generator\" content=\"mcl-manual\" />\n"
        html += "<title>" + Self.escape("MacContestLogger — " + ManualTypesetter.subtitle(book)
                                       + (options.version.map { $0.isEmpty ? "" : " " + $0 } ?? "")) + "</title>\n"
        html += "<style>\n" + Self.stylesheet + groupStyles(groups) + "</style>\n</head>\n<body>\n"
        html += body
        let contentsLabel: String = Self.escape(book.language.contents)
        html += "<a class=\"to-contents\" href=\"#contents\" aria-label=\"" + contentsLabel + "\">&#8593; " + contentsLabel
            + "</a>\n"
        html += "</body>\n</html>\n"
        let summary = Summary(bytes: html.utf8.count, chapters: book.chapters.count, images: state.images,
                              imageBytes: state.imageBytes, reducedImages: state.reducedImages,
                              internalLinks: state.internalLinks)
        return (html, summary)
    }

    /// Counters while rendering.
    struct State {
        /// Book anchor (`map.md`, `map.md#layers`) → HTML id; only the first heading of a name has one.
        let ids: [String: String]
        /// HTML ids already written (a repeated heading gets a numbered one).
        var used: Set<String> = []
        var images = 0
        var imageBytes = 0
        var reducedImages = 0
        var internalLinks = 0
    }

    // MARK: - ids and links

    /// The HTML id of a book anchor: `map.md` → `ch-map`, `map.md#layers` → `ch-map--layers`.
    static func id(_ anchor: String) -> String {
        var file: String = anchor
        var fragment: String?
        if let hash = anchor.firstIndex(of: "#") {
            file = String(anchor[..<hash])
            fragment = String(anchor[anchor.index(after: hash)...])
        }
        if file.hasSuffix(".md") {
            file.removeLast(3)
        }
        let safe = String(file.map { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") ? $0 : "-" })
        guard let fragment, !fragment.isEmpty else { return "ch-" + safe }
        return "ch-" + safe + "--" + ManualBook.slug(fragment)
    }

    /// Every chapter and heading anchor of the book with its id (the first heading of a repeated name wins, as on
    /// GitHub and in the PDF).
    static func headingIds(_ book: ManualBook) -> [String: String] {
        var ids: [String: String] = [:]
        for chapter in book.chapters {
            ids[chapter.file] = id(chapter.file)
            for case .heading(_, let title) in chapter.blocks {
                let anchor: String = ManualBook.anchor(file: chapter.file, heading: title)
                if ids[anchor] == nil {
                    ids[anchor] = id(anchor)
                }
            }
        }
        return ids
    }

    /// The `href` of a Markdown link: an id in this file (a missing section falls back to its chapter) or a URL.
    func href(_ raw: String, from file: String, state: inout State) -> String? {
        guard let target = book.resolveLink(raw, from: file) else { return nil }
        guard target.hasPrefix("#") else { return target }
        var anchor = String(target.dropFirst())
        if state.ids[anchor] == nil, let hash = anchor.firstIndex(of: "#") {
            anchor = String(anchor[..<hash])
        }
        guard let id = state.ids[anchor] else { return nil }
        state.internalLinks += 1
        return "#" + id
    }

    /// A unique id for a heading (a repeated name gets `-2`, `-3`, …; links go to the first).
    func headingId(_ anchor: String, state: inout State) -> String {
        var id: String = state.ids[anchor] ?? Self.id(anchor)
        if state.used.contains(id) {
            var counter = 2
            while state.used.contains(id + "-" + String(counter)) {
                counter += 1
            }
            id += "-" + String(counter)
        }
        state.used.insert(id)
        return id
    }

    // MARK: - text

    /// Text for an element or an attribute: `&`, `<`, `>`, `"` and `'` as character references.
    static func escape(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.utf8.count)
        for character in text {
            switch character {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&#39;"
            default: out.append(character)
            }
        }
        return out
    }

    /// Inline Markdown (emphasis, code, links) as HTML, parsed the same way as for the PDF.
    func inline(_ text: String, file: String, state: inout State) -> String {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        guard let parsed = try? AttributedString(markdown: text, options: options) else { return Self.escape(text) }
        var out = ""
        var open: String?
        for run in parsed.runs {
            var piece: String = Self.escape(String(parsed[run.range].characters))
            let intent: InlinePresentationIntent = run.inlinePresentationIntent ?? []
            if intent.contains(.code) {
                piece = "<code>" + piece + "</code>"
            }
            if intent.contains(.emphasized) {
                piece = "<em>" + piece + "</em>"
            }
            if intent.contains(.stronglyEmphasized) {
                piece = "<strong>" + piece + "</strong>"
            }
            if intent.contains(.strikethrough) {
                piece = "<del>" + piece + "</del>"
            }
            let link: String? = run.link.flatMap { href($0.absoluteString, from: file, state: &state) }
            if link != open {
                if open != nil {
                    out += "</a>"
                }
                if let link {
                    out += "<a href=\"" + Self.escape(link) + "\"" + (link.hasPrefix("#") ? "" : " class=\"external\"") + ">"
                }
                open = link
            }
            out += piece
        }
        if open != nil {
            out += "</a>"
        }
        return out
    }

    // MARK: - the book

    func titlePage(_ state: inout State) -> String {
        var out = "<header class=\"title-page\" id=\"title\">\n"
        out += "<p class=\"product\">MacContestLogger</p>\n"
        out += "<p class=\"subtitle\">" + Self.escape(ManualTypesetter.subtitle(book)) + "</p>\n"
        if let line = book.language.editionLine(version: options.version, buildDate: options.buildDate) {
            out += "<p class=\"edition\">" + Self.escape(line) + "</p>\n"
        }
        out += "<div class=\"intro\">\n"
        for block in book.intro {
            out += self.block(block, file: "README.md", state: &state)
        }
        out += "</div>\n"
        out += "<p class=\"repository\"><a class=\"external\" href=\"https://github.com/ok1xoe/MacContestLogger\">"
            + "https://github.com/ok1xoe/MacContestLogger</a></p>\n"
        out += "</header>\n"
        return out
    }

    /// The table of contents: the parts with their numbered chapters, each linked.
    func contents() -> String {
        let label: String = Self.escape(book.language.contents)
        var out = "<nav class=\"toc\" id=\"contents\" aria-label=\"" + label + "\">\n<h1 class=\"toc-title\">" + label
            + "</h1>\n"
        var number = 0
        for (part, chapters) in book.parts {
            out += "<section class=\"toc-part\">\n<h2>" + Self.escape(part) + "</h2>\n<ol>\n"
            for chapter in chapters {
                number += 1
                out += "<li class=\"toc-chapter\"><a href=\"#" + Self.id(chapter.file) + "\"><span class=\"num\">"
                    + String(number) + "</span> " + Self.escape(ManualRenderer.plain(chapter.title)) + "</a></li>\n"
            }
            out += "</ol>\n</section>\n"
        }
        out += "</nav>\n"
        return out
    }

    func chapterHtml(_ chapter: ManualBook.Chapter, number: Int, pageStart: Bool, group: String,
                     state: inout State) -> String {
        let id: String = headingId(chapter.file, state: &state)
        var out = "<section class=\"chapter " + group + (pageStart ? " page-start" : " goes-on") + "\" id=\"" + id
            + "\" aria-labelledby=\"" + id + "-title\">\n"
        out += "<p class=\"part\">" + Self.escape(chapter.part) + "</p>\n"
        out += "<h1 id=\"" + id + "-title\"><span class=\"num\">" + String(number) + "</span> "
            + inline(chapter.title, file: chapter.file, state: &state) + "</h1>\n"
        for block in chapter.blocks {
            out += self.block(block, file: chapter.file, state: &state)
        }
        out += "</section>\n"
        return out
    }

    func block(_ block: ManualBlock, file: String, state: inout State) -> String {
        switch block {
        case .heading(let level, let title):
            let tag = "h" + String(min(max(level, 2), 6))
            let id: String = headingId(ManualBook.anchor(file: file, heading: title), state: &state)
            return "<" + tag + " id=\"" + id + "\">" + inline(title, file: file, state: &state) + "</" + tag + ">\n"
        case .paragraph(let text):
            return "<p>" + inline(text, file: file, state: &state) + "</p>\n"
        case .quote(let text):
            return "<blockquote><p>" + inline(text, file: file, state: &state) + "</p></blockquote>\n"
        case .code(let body):
            let lines: Int = body.components(separatedBy: "\n").count
            return "<pre" + (lines <= 30 ? " class=\"keep\"" : "") + "><code>" + Self.escape(body) + "</code></pre>\n"
        case .list(let items):
            return list(items, file: file, state: &state)
        case .table(let header, let rows):
            return table(header: header, rows: rows, file: file, state: &state)
        case .image(let alt, let path):
            return image(alt: alt, path: path, state: &state)
        case .rule:
            return "<hr />\n"
        }
    }

    /// Nested lists from the items' levels; a numbered list keeps its first number.
    func list(_ items: [ManualListItem], file: String, state: inout State) -> String {
        var out = ""
        var open: [String] = []
        for item in items {
            let ordered: Bool = item.marker != "•"
            let tag: String = ordered ? "ol" : "ul"
            while open.count > item.level + 1 {
                out += "</li></" + open.removeLast() + ">\n"
            }
            if open.count == item.level + 1 {
                if open.last == tag {
                    out += "</li>\n"
                } else {
                    out += "</li></" + open.removeLast() + ">\n"
                }
            }
            while open.count < item.level + 1 {
                var start = ""
                if ordered, let number = Int(item.marker.dropLast()), number != 1 {
                    start = " start=\"" + String(number) + "\""
                }
                out += "<" + tag + start + ">\n"
                open.append(tag)
            }
            out += "<li>" + inline(item.text, file: file, state: &state)
        }
        while let tag = open.popLast() {
            out += "</li></" + tag + ">\n"
        }
        return out
    }

    func table(header: [String], rows: [[String]], file: String, state: inout State) -> String {
        let columns: Int = max(header.count, rows.map(\.count).max() ?? 0)
        guard columns > 0 else { return "" }
        var out = "<div class=\"table-wrap\"><table" + (rows.count <= 12 ? " class=\"keep\"" : "") + ">\n<thead><tr>"
        for column in 0..<columns {
            out += "<th>" + inline(column < header.count ? header[column] : "", file: file, state: &state) + "</th>"
        }
        out += "</tr></thead>\n<tbody>\n"
        for row in rows {
            out += "<tr>"
            for column in 0..<columns {
                out += "<td>" + inline(column < row.count ? row[column] : "", file: file, state: &state) + "</td>"
            }
            out += "</tr>\n"
        }
        out += "</tbody>\n</table></div>\n"
        return out
    }

    func image(alt: String, path: String, state: inout State) -> String {
        guard let embedded = embed(docs.appendingPathComponent(path)) else { return "" }
        state.images += 1
        state.imageBytes += embedded.data.count
        if embedded.reduced {
            state.reducedImages += 1
        }
        var size = ""
        if let display = embedded.displayWidth, let height = embedded.displayHeight {
            size = " width=\"" + String(display) + "\" height=\"" + String(height) + "\""
        }
        var out = "<figure><img src=\"data:" + embedded.type + ";base64," + embedded.data.base64EncodedString() + "\""
            + size + " alt=\"" + Self.escape(alt) + "\" />"
        if !alt.isEmpty {
            out += "<figcaption>" + Self.escape(alt) + "</figcaption>"
        }
        out += "</figure>\n"
        return out
    }

    /// An image file's bytes for a data URI: PNG and JPEG wider than `maxImagePixels` or larger than `maxImageBytes`
    /// are scaled down and re-encoded (the smaller of PNG and JPEG); others as they are. The display size is half the
    /// original pixels (the screenshots are taken at 2x), as in the PDF.
    func embed(_ url: URL) -> (data: Data, type: String, reduced: Bool, displayWidth: Int?, displayHeight: Int?)? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let type: String
        switch url.pathExtension.lowercased() {
        case "png": type = "image/png"
        case "jpg", "jpeg": type = "image/jpeg"
        case "gif": type = "image/gif"
        case "svg": return (data, "image/svg+xml", false, nil, nil)
        case "webp": type = "image/webp"
        default: type = "application/octet-stream"
        }
        guard let rep = NSBitmapImageRep(data: data), rep.pixelsWide > 0, rep.pixelsHigh > 0 else {
            return (data, type, false, nil, nil)
        }
        let width: Int = rep.pixelsWide
        let height: Int = rep.pixelsHigh
        let displayWidth: Int = max(1, width / 2)
        let displayHeight: Int = max(1, height * displayWidth / width)
        let reencodable: Bool = type == "image/png" || type == "image/jpeg"
        guard reencodable, width > options.maxImagePixels || data.count > options.maxImageBytes else {
            return (data, type, false, displayWidth, displayHeight)
        }
        let scale: Double = min(1, Double(options.maxImagePixels) / Double(width))
        let newWidth = max(1, Int((Double(width) * scale).rounded()))
        let newHeight = max(1, Int((Double(height) * scale).rounded()))
        guard let scaled = Self.redraw(rep, width: newWidth, height: newHeight) else {
            return (data, type, false, displayWidth, displayHeight)
        }
        // Only a smaller result replaces the file (a screenshot's palette PNG can beat a re-encoded one).
        var best: (Data, String) = (data, type)
        if let png = scaled.representation(using: .png, properties: [:]), png.count < best.0.count {
            best = (png, "image/png")
        }
        if best.0.count > options.maxImageBytes,
           let jpeg = scaled.representation(using: .jpeg, properties: [.compressionFactor: 0.85]), jpeg.count < best.0.count {
            best = (jpeg, "image/jpeg")
        }
        return (best.0, best.1, best.0 != data, displayWidth, displayHeight)
    }

    /// The image drawn into an sRGB bitmap of the given size.
    static func redraw(_ rep: NSBitmapImageRep, width: Int, height: Int) -> NSBitmapImageRep? {
        guard let target = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: target) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        rep.draw(in: CGRect(x: 0, y: 0, width: width, height: height), from: .zero, operation: .copy, fraction: 1,
                 respectFlipped: false, hints: nil)
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return target
    }

    // MARK: - styles

    /// A CSS string literal; `&` and `<` as CSS escapes, so the style element stays well-formed XML too.
    static func cssString(_ text: String) -> String {
        var out = "\""
        for character in text {
            switch character {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "&": out += "\\26 "
            case "<": out += "\\3c "
            case "\n": out += " "
            default: out.append(character)
            }
        }
        return out + "\""
    }

    /// One named page per run of chapters printed together (a chapter that starts a page and those that go on below
    /// it): its running header names them. Browsers without named pages ignore it and still break before
    /// `.page-start`.
    func groupStyles(_ groups: [(name: String, titles: [String])]) -> String {
        var out = "@page contents { @top-right { content: " + Self.cssString(book.language.contents)
            + "; font: 7.5pt -apple-system, \"Helvetica Neue\", Arial, sans-serif; color: #66666f; } }\n"
        for group in groups {
            var title: String = group.titles.first ?? ""
            if group.titles.count == 2 {
                title += "  ·  " + group.titles[1]
            } else if group.titles.count > 2, let last = group.titles.last {
                title += "  …  " + last
            }
            out += "@media print { ." + group.name + " { page: " + group.name + "; } }\n"
            out += "@page " + group.name + " { @top-right { content: " + Self.cssString(title)
                + "; font: 7.5pt -apple-system, \"Helvetica Neue\", Arial, sans-serif; color: #66666f; } }\n"
        }
        return out
    }

    static let stylesheet: String = """
    :root {
      --bg: #ffffff; --fg: #1a1a1f; --muted: #5f5f68; --rule: #d4d4da; --link: #0d54b3;
      --code-bg: #f2f2f4; --th-bg: #e8eaee; --accent: #0d54b3;
      --font: -apple-system, BlinkMacSystemFont, "Helvetica Neue", Helvetica, Arial, sans-serif;
      --mono: ui-monospace, "SF Mono", Menlo, Consolas, monospace;
    }
    @media screen and (prefers-color-scheme: dark) {
      :root {
        --bg: #1c1c1f; --fg: #e6e6ea; --muted: #a2a2ab; --rule: #3c3c43; --link: #7cb2ff;
        --code-bg: #2a2a2f; --th-bg: #2f3138; --accent: #7cb2ff;
      }
    }
    * { box-sizing: border-box; }
    html { -webkit-text-size-adjust: 100%; }
    body {
      margin: 0 auto; padding: 24px 16px 64px; max-width: 54rem; background: var(--bg); color: var(--fg);
      font: 16px/1.55 var(--font);
    }
    a { color: var(--link); text-decoration: none; }
    a:hover { text-decoration: underline; }
    h1, h2, h3, h4, h5, h6 { line-height: 1.25; margin: 1.6em 0 0.5em; }
    h1 { font-size: 1.9em; margin-top: 0.2em; }
    h2 { font-size: 1.4em; padding-bottom: 0.2em; border-bottom: 1px solid var(--rule); }
    h3 { font-size: 1.15em; }
    h4, h5, h6 { font-size: 1em; }
    p { margin: 0.5em 0 0.8em; }
    ul, ol { padding-left: 1.6em; margin: 0.4em 0 0.9em; }
    li { margin: 0.15em 0; }
    li > ul, li > ol { margin: 0.2em 0; }
    code { font-family: var(--mono); font-size: 0.88em; background: var(--code-bg); padding: 0.1em 0.3em; border-radius: 3px; }
    pre { background: var(--code-bg); padding: 0.7em 0.9em; border-radius: 5px; overflow-x: auto; line-height: 1.35; }
    pre code { background: none; padding: 0; font-size: 0.85em; }
    blockquote { margin: 0.8em 0; padding: 0.1em 1em; border-left: 3px solid var(--rule); color: var(--muted); }
    hr { border: none; border-top: 1px solid var(--rule); margin: 1.5em 0; }
    .table-wrap { overflow-x: auto; margin: 0.6em 0 1em; }
    table { border-collapse: collapse; width: 100%; font-size: 0.9em; }
    th, td { border: 1px solid var(--rule); padding: 0.3em 0.5em; text-align: left; vertical-align: top; }
    th { background: var(--th-bg); font-weight: 600; }
    figure { margin: 1em 0; text-align: center; }
    figure img { max-width: 100%; height: auto; border: 1px solid var(--rule); border-radius: 4px; }
    figcaption { font-size: 0.85em; font-style: italic; color: var(--muted); margin-top: 0.3em; }
    .num { color: var(--accent); font-weight: 600; margin-right: 0.35em; }
    .title-page { padding: 3em 0 2em; border-bottom: 1px solid var(--rule); }
    .title-page .product { font-size: 2.6em; font-weight: 700; margin: 0; text-align: center; }
    .title-page .subtitle { font-size: 1.35em; color: var(--muted); margin: 0.1em 0 0.3em; text-align: center; }
    .title-page .edition { color: var(--muted); text-align: center; margin: 0 0 2em; }
    .title-page .repository { text-align: center; margin-top: 1.5em; }
    .toc { padding: 1.5em 0; border-bottom: 1px solid var(--rule); }
    .toc-title { margin-bottom: 0.3em; }
    .toc h2 { font-size: 1.05em; border: none; margin: 1em 0 0.3em; }
    .toc ol { list-style: none; padding-left: 0.8em; margin: 0; columns: 2 18rem; column-gap: 2rem; }
    .toc li { break-inside: avoid; margin: 0.1em 0; }
    .chapter { padding-top: 2.5em; }
    .chapter + .chapter { border-top: 1px solid var(--rule); margin-top: 2.5em; }
    .chapter .part { text-transform: uppercase; letter-spacing: 0.06em; font-size: 0.75em; color: var(--muted); margin: 0; }
    .to-contents {
      position: fixed; right: 16px; bottom: 16px; padding: 0.35em 0.8em; border-radius: 999px; font-size: 0.85em;
      background: var(--code-bg); border: 1px solid var(--rule);
    }
    @page {
      size: A4; margin: 20mm 18mm 18mm;
      @top-left { content: "MacContestLogger"; font: 7.5pt -apple-system, "Helvetica Neue", Arial, sans-serif; color: #66666f; }
      @bottom-center { content: counter(page); font: 7.5pt -apple-system, "Helvetica Neue", Arial, sans-serif; color: #66666f; }
    }
    @page title-page { @top-left { content: none; } @top-right { content: none; } @bottom-center { content: none; } }
    @media print {
      :root {
        --bg: #ffffff; --fg: #1a1a1f; --muted: #5f5f68; --rule: #c0c0c8; --link: #0d54b3;
        --code-bg: #f2f2f4; --th-bg: #e8eaee; --accent: #0d54b3;
      }
      html, body { background: #ffffff; color: #1a1a1f; }
      body { max-width: none; padding: 0; font-size: 10pt; line-height: 1.4; }
      * { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
      .to-contents { display: none; }
      .title-page { page: title-page; border: none; padding: 30mm 0 0; }
      .toc { page: contents; break-before: page; border: none; padding: 0; }
      .toc ol { columns: 1; }
      .chapter { padding-top: 0; }
      .chapter.page-start { break-before: page; }
      .chapter.goes-on { margin-top: 8mm; padding-top: 6mm; border-top: 1px solid var(--rule); }
      .chapter + .chapter.page-start { border-top: none; margin-top: 0; }
      h1, h2, h3, h4, h5, h6, .chapter .part { break-after: avoid; page-break-after: avoid; break-inside: avoid; }
      p, li { orphans: 2; widows: 2; }
      figure, img, tr, pre.keep, table.keep, blockquote { break-inside: avoid; page-break-inside: avoid; }
      figure img { max-height: 120mm; max-width: 100%; height: auto; object-fit: contain; }
      thead { display: table-header-group; }
      .table-wrap { overflow: visible; }
      pre { white-space: pre-wrap; overflow-wrap: anywhere; overflow: visible; }
    }

    """
}
