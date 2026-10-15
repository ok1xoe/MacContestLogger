import Foundation

/// The guide as a book: `docs/README.md` gives the title, the introduction and the chapters in order (its `## …`
/// sections are the parts, the linked `*.md` pages the chapters); each chapter is the page's blocks.
public struct ManualBook: Sendable {

    public struct Chapter: Sendable, Equatable {
        /// The page's file name (`entry-window.md`), also its anchor.
        public var file: String
        /// The page's first heading (or the link text when it has none).
        public var title: String
        /// The README section it is listed under (`Getting started`).
        public var part: String
        public var blocks: [ManualBlock]
    }

    public var title: String
    public var intro: [ManualBlock]
    public var chapters: [Chapter]

    public enum LoadError: Error, Equatable, CustomStringConvertible {
        case missing(String)
        case noChapters

        public var description: String {
            switch self {
            case .missing(let file): return "missing file: " + file
            case .noChapters: return "README.md lists no chapters"
            }
        }
    }

    /// Reads `README.md` and every page it links in `dir`.
    public static func load(docs dir: URL) throws -> ManualBook {
        let readme: String = try read(dir, "README.md")
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
        for entry in listed where !chapters.contains(where: { $0.file == entry.file }) {
            var pageBlocks: [ManualBlock] = ManualMarkdown.blocks(try read(dir, entry.file))
            var chapterTitle: String = entry.label
            if case .heading(1, let text)? = pageBlocks.first {
                chapterTitle = text
                pageBlocks.removeFirst()
            }
            for case .image(_, let path) in pageBlocks
            where !FileManager.default.fileExists(atPath: dir.appendingPathComponent(path).path) {
                throw LoadError.missing(path)
            }
            chapters.append(Chapter(file: entry.file, title: chapterTitle, part: entry.part, blocks: pageBlocks))
        }
        guard !chapters.isEmpty else { throw LoadError.noChapters }
        return ManualBook(title: title, intro: intro, chapters: chapters)
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
}
