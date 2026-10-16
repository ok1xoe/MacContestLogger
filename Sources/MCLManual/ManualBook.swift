import Foundation

/// The guide as a book: `docs/README.md` gives the title, the introduction and the chapters in order (its `## …`
/// sections are the parts, the linked `*.md` pages the chapters); each chapter is the page's blocks.
///
/// The Czech book reads `docs/cs/README.md` and `docs/cs/*.md`; a page that is not translated yet comes from `docs/`
/// (a warning, or an error when the load is strict). Image paths are resolved when loading to a path relative to
/// `docs/`: the English book takes `img/en/<name>` when it exists and otherwise the default (Czech) screenshot, whose
/// caption then says so, with a note in the introduction.
public struct ManualBook: Sendable {

    public struct Chapter: Sendable, Equatable {
        /// The page's file name (`entry-window.md`), also its anchor.
        public var file: String
        /// The page's first heading (or the link text when it has none).
        public var title: String
        /// The README section it is listed under (`Getting started`).
        public var part: String
        public var blocks: [ManualBlock]
        /// The directory the page was read from, relative to `docs/` (`""` or `cs/`): its relative links start there.
        public var sourceDir: String = ""
    }

    public var title: String
    public var intro: [ManualBlock]
    public var chapters: [Chapter]
    public var language: ManualLanguage = .en
    /// The directory the README was read from, relative to `docs/`.
    public var readmeDir: String = ""
    /// The pages (file names) of a Czech book that came from the English `docs/` (not translated yet).
    public var untranslated: [String] = []
    /// The screenshots (paths relative to `docs/`) of an English book that have no English version yet.
    public var czechScreenshots: [String] = []
    /// What the load fell back on (untranslated pages), for the command line to print.
    public var warnings: [String] = []

    public enum LoadError: Error, Equatable, CustomStringConvertible {
        case missing(String)
        case noChapters
        /// A strict load of a translated book found a page (or the README) that is not translated.
        case untranslated(String)

        public var description: String {
            switch self {
            case .missing(let file): return "missing file: " + file
            case .noChapters: return "README.md lists no chapters"
            case .untranslated(let file): return "not translated: " + file
            }
        }
    }

    /// The parts in order with their chapters.
    public var parts: [(name: String, chapters: [Chapter])] {
        var out: [(name: String, chapters: [Chapter])] = []
        for chapter in chapters {
            if out.last?.name == chapter.part {
                out[out.count - 1].chapters.append(chapter)
            } else {
                out.append((chapter.part, [chapter]))
            }
        }
        return out
    }

    /// Reads `README.md` and every page it links in `dir` (`language` picks the pages and the screenshots; `strict`
    /// turns a missing translation into an error instead of a fallback to the English page).
    public static func load(docs dir: URL, language: ManualLanguage = .en, strict: Bool = false) throws -> ManualBook {
        var warnings: [String] = []
        var untranslated: [String] = []
        /// The translated file when it exists, else the English one (`nil` = no translation needed).
        func source(_ name: String) throws -> String {
            let translated: String = language.pagesDir + name
            if language.pagesDir.isEmpty || exists(dir, translated) {
                return language.pagesDir
            }
            if strict {
                throw LoadError.untranslated(translated)
            }
            warnings.append("\(translated) is not translated yet, the English page is used")
            return ""
        }
        let readmeDir: String = try source("README.md")
        let readme: String = try read(dir, readmeDir + "README.md")
        let blocks: [ManualBlock] = ManualMarkdown.blocks(readme)
        var title = "MacContestLogger"
        var intro: [ManualBlock] = []
        var part = ""
        var listed: [(file: String, label: String, part: String)] = []
        for block in blocks {
            switch block {
            case .heading(1, let text):
                title = text
            case .heading(_, let text):
                part = text
            case .list(let items) where !part.isEmpty:
                for item in items {
                    if let link = firstLink(item.text), link.target.hasSuffix(".md"), !link.target.contains("/") {
                        listed.append((link.target, link.label, part))
                    }
                }
            default:
                if part.isEmpty {
                    intro.append(block)
                }
            }
        }
        var chapters: [Chapter] = []
        var czechScreenshots: [String] = []
        for entry in listed where !chapters.contains(where: { $0.file == entry.file }) {
            let sourceDir: String = try source(entry.file)
            if sourceDir != language.pagesDir {
                untranslated.append(entry.file)
            }
            var pageBlocks: [ManualBlock] = ManualMarkdown.blocks(try read(dir, sourceDir + entry.file))
            var chapterTitle: String = entry.label
            if case .heading(1, let text)? = pageBlocks.first {
                chapterTitle = text
                pageBlocks.removeFirst()
            }
            for (index, block) in pageBlocks.enumerated() {
                guard case .image(let alt, let raw) = block else { continue }
                guard let found = imagePath(raw, from: sourceDir, in: dir) else { throw LoadError.missing(raw) }
                var path: String = found
                var caption: String = alt
                if language == .en, path.hasPrefix("img/"), !path.hasPrefix("img/en/") {
                    let english = "img/en/" + path.dropFirst("img/".count)
                    if exists(dir, english) {
                        path = english
                    } else {
                        if !czechScreenshots.contains(path) {
                            czechScreenshots.append(path)
                        }
                        caption = alt.isEmpty ? ManualLanguage.czechScreenshotCaption
                            : alt + " " + ManualLanguage.czechScreenshotCaption
                    }
                }
                pageBlocks[index] = .image(alt: caption, path: path)
            }
            chapters.append(Chapter(file: entry.file, title: chapterTitle, part: entry.part, blocks: pageBlocks,
                                    sourceDir: sourceDir))
        }
        guard !chapters.isEmpty else { throw LoadError.noChapters }
        if !czechScreenshots.isEmpty {
            intro.append(.paragraph(ManualLanguage.czechScreenshotsNote))
        }
        var book = ManualBook(title: title, intro: intro, chapters: chapters)
        book.language = language
        book.readmeDir = readmeDir
        book.untranslated = untranslated
        book.czechScreenshots = czechScreenshots
        book.warnings = warnings
        return book
    }

    /// An image reference of a page in `sourceDir` as a path relative to `docs/` that exists: relative to the page
    /// (`../img/a.png` from `cs/`), or else relative to `docs/` (`img/a.png` in a translated page); `nil` = none.
    static func imagePath(_ raw: String, from sourceDir: String, in dir: URL) -> String? {
        for candidate in [normalize(sourceDir + raw), normalize(raw)] {
            if let candidate, exists(dir, candidate) {
                return candidate
            }
        }
        return nil
    }

    /// `cs/../img/a.png` → `img/a.png`; `nil` for a path that leaves `docs/` or is absolute.
    static func normalize(_ path: String) -> String? {
        guard !path.isEmpty, !path.hasPrefix("/") else { return nil }
        var parts: [Substring] = []
        for piece in path.split(separator: "/", omittingEmptySubsequences: true) {
            switch piece {
            case ".": continue
            case "..":
                guard !parts.isEmpty else { return nil }
                parts.removeLast()
            default: parts.append(piece)
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: "/")
    }

    static func exists(_ dir: URL, _ name: String) -> Bool {
        FileManager.default.fileExists(atPath: dir.appendingPathComponent(name).path)
    }

    private static func read(_ dir: URL, _ name: String) throws -> String {
        let url: URL = dir.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url) else { throw LoadError.missing(name) }
        return String(decoding: data, as: UTF8.self)
    }

    /// `[label](target)` — the first link of an inline text.
    static func firstLink(_ text: String) -> (label: String, target: String)? {
        guard let open = text.range(of: "["), let middle = text.range(of: "](", range: open.upperBound..<text.endIndex),
              let close = text.range(of: ")", range: middle.upperBound..<text.endIndex) else { return nil }
        return (String(text[open.upperBound..<middle.lowerBound]), String(text[middle.upperBound..<close.lowerBound]))
    }

    /// GitHub's heading anchor: lower case, punctuation dropped, spaces to `-`.
    public static func slug(_ heading: String) -> String {
        var out = ""
        for character in heading.lowercased() {
            if character.isLetter || character.isNumber || character == "-" || character == "_" {
                out.append(character)
            } else if character == " " {
                out.append("-")
            }
        }
        return out
    }

    /// The anchor of a heading in a chapter (`dx-cluster.md#spot-comment`).
    public static func anchor(file: String, heading: String) -> String {
        file + "#" + slug(heading)
    }

    /// Where links to other files of the repository lead.
    public static let repositoryDocs = "https://github.com/ok1xoe/MacContestLogger/blob/main/docs/"

    /// A link target of the book (the same for the PDF and the HTML): `#<anchor>` for a chapter (`#map.md`) or a
    /// heading in it (`#map.md#layers`), otherwise an absolute URL; `nil` for a path that leaves `docs/`.
    public func resolveLink(_ raw: String, from file: String) -> String? {
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") || raw.hasPrefix("mailto:") {
            return raw
        }
        if raw.hasPrefix("#") {
            return "#" + file + raw
        }
        var path: String = raw
        var fragment: String?
        if let hash = raw.firstIndex(of: "#") {
            path = String(raw[..<hash])
            fragment = String(raw[raw.index(after: hash)...])
        }
        if chapters.contains(where: { $0.file == path }) {
            return "#" + path + (fragment.map { "#" + $0 } ?? "")
        }
        // Relative to the page's own directory (`../cluster-aclfile` from `cs/`).
        let dir: String = file == "README.md" ? readmeDir : (chapters.first { $0.file == file }?.sourceDir ?? "")
        guard !path.hasPrefix("/"), let inDocs = Self.normalize(dir + path) else { return nil }
        if chapters.contains(where: { $0.file == inDocs }) {
            return "#" + inDocs + (fragment.map { "#" + $0 } ?? "")
        }
        return Self.repositoryDocs + inDocs
    }
}
