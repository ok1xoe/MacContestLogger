import Foundation

/// One block of a user-guide page. The guide (`docs/*.md`) uses a small, regular subset of Markdown: ATX headings,
/// paragraphs, bullet and numbered lists (nested by indentation, continuation lines indented), fenced code (also
/// inside a list item), pipe tables, block quotes, images on a line of their own and horizontal rules. Inline
/// syntax (emphasis, code, links) stays in the text and is parsed later, when the block is laid out.
public enum ManualBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case code(String)
    case list([ManualListItem])
    case quote(String)
    case table(header: [String], rows: [[String]])
    case image(alt: String, path: String)
    case rule
}

/// One item of a list: its marker (`•`, `1.`), its nesting level (0 = top) and its inline text.
public struct ManualListItem: Equatable, Sendable {
    public var marker: String
    public var level: Int
    public var text: String

    public init(marker: String, level: Int, text: String) {
        self.marker = marker
        self.level = level
        self.text = text
    }
}

/// The block parser of the guide's Markdown subset.
public enum ManualMarkdown {

    /// The blocks of a page.
    public static func blocks(_ source: String) -> [ManualBlock] {
        var parser = Parser(lines: source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n"))
        return parser.run()
    }

    /// Leading spaces (a tab counts as four).
    static func indent(_ line: String) -> Int {
        var count = 0
        for character in line {
            if character == " " {
                count += 1
            } else if character == "\t" {
                count += 4
            } else {
                break
            }
        }
        return count
    }

    /// `- text`, `* text`, `+ text`, `1. text`, `1) text` → (marker, text); `nil` when the line is not a list item.
    static func listItem(_ line: String) -> (marker: String, text: String)? {
        let trimmed: Substring = line.drop { $0 == " " || $0 == "\t" }
        guard let first = trimmed.first else { return nil }
        if "-*+".contains(first) {
            let rest = trimmed.dropFirst()
            guard rest.first == " " else { return nil }
            return ("•", rest.trimmingCharacters(in: .whitespaces))
        }
        let digits = trimmed.prefix { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty, digits.count <= 3 else { return nil }
        let rest = trimmed.dropFirst(digits.count)
        guard let dot = rest.first, dot == "." || dot == ")", rest.dropFirst().first == " " else { return nil }
        return (String(digits) + ".", rest.dropFirst(2).trimmingCharacters(in: .whitespaces))
    }

    /// The cells of a table row; `\|` is a literal bar.
    static func cells(_ line: String) -> [String] {
        var body: String = line.trimmingCharacters(in: .whitespaces)
        if body.hasPrefix("|") {
            body.removeFirst()
        }
        if body.hasSuffix("|") && !body.hasSuffix("\\|") {
            body.removeLast()
        }
        var out: [String] = []
        var current = ""
        var escaped = false
        for character in body {
            if escaped {
                current.append(character == "|" ? "|" : "\\" + String(character))
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "|" {
                out.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(character)
            }
        }
        if escaped {
            current.append("\\")
        }
        out.append(current.trimmingCharacters(in: .whitespaces))
        return out
    }

    /// `|---|:--:|` — the line under a table's header.
    static func isTableSeparator(_ line: String) -> Bool {
        let trimmed: String = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("-") else { return false }
        return trimmed.allSatisfy { "|-: ".contains($0) }
    }

    /// `![alt](path)` alone on a line.
    static func image(_ line: String) -> (alt: String, path: String)? {
        let trimmed: String = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("!["), trimmed.hasSuffix(")"),
              let close = trimmed.range(of: "]("), close.lowerBound > trimmed.index(trimmed.startIndex, offsetBy: 1) else {
            return nil
        }
        let alt = String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: 2)..<close.lowerBound])
        let path = String(trimmed[close.upperBound..<trimmed.index(before: trimmed.endIndex)])
        guard !path.contains(" ") else { return nil }
        return (alt, path)
    }

    static func heading(_ line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix { $0 == "#" }
        guard (1...6).contains(hashes.count), line.dropFirst(hashes.count).first == " " else { return nil }
        var text: String = line.dropFirst(hashes.count).trimmingCharacters(in: .whitespaces)
        while text.hasSuffix("#") {
            text.removeLast()
        }
        return (hashes.count, text.trimmingCharacters(in: .whitespaces))
    }

    static func isRule(_ line: String) -> Bool {
        let compact: String = line.replacingOccurrences(of: " ", with: "")
        return compact.count >= 3 && (compact.allSatisfy { $0 == "-" } || compact.allSatisfy { $0 == "*" }
                                      || compact.allSatisfy { $0 == "_" })
    }

    private struct Parser {
        let lines: [String]
        var index = 0
        var out: [ManualBlock] = []
        var paragraph: [String] = []
        var items: [ManualListItem] = []
        /// The indentation of the current list's top level.
        var listBase = 0
        /// The indentations of the open list levels.
        var indents: [Int] = []

        init(lines: [String]) {
            self.lines = lines
        }

        mutating func run() -> [ManualBlock] {
            while index < lines.count {
                step(lines[index])
            }
            flushParagraph()
            flushList()
            return out
        }

        mutating func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            out.append(.paragraph(paragraph.joined(separator: " ")))
            paragraph = []
        }

        mutating func flushList() {
            guard !items.isEmpty else { return }
            out.append(.list(items))
            items = []
        }

        mutating func step(_ line: String) {
            let trimmed: String = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flushParagraph()
                index += 1
                // A list goes on over a blank line when the next text line is an item or indented under one.
                if !items.isEmpty, let next = nextTextLine(),
                   ManualMarkdown.listItem(next) != nil || ManualMarkdown.indent(next) > listBase {
                    return
                }
                flushList()
                return
            }
            if trimmed.hasPrefix("```") {
                flushParagraph()
                let fenceIndent: Int = ManualMarkdown.indent(line)
                var body: [String] = []
                index += 1
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    var codeLine: Substring = Substring(lines[index])
                    var dropped = 0
                    while dropped < fenceIndent, codeLine.first == " " {
                        codeLine = codeLine.dropFirst()
                        dropped += 1
                    }
                    body.append(String(codeLine))
                    index += 1
                }
                index += 1
                // A code block inside a list item stays in the list: the list is split around it.
                flushList()
                out.append(.code(body.joined(separator: "\n")))
                return
            }
            if let heading = ManualMarkdown.heading(trimmed), ManualMarkdown.indent(line) < 4 {
                flushParagraph()
                flushList()
                out.append(.heading(level: heading.level, text: heading.text))
                index += 1
                return
            }
            if let item = ManualMarkdown.listItem(line), !ManualMarkdown.isRule(trimmed) {
                flushParagraph()
                let indent: Int = ManualMarkdown.indent(line)
                if items.isEmpty {
                    listBase = indent
                    indents = []
                }
                while let last = indents.last, last > indent {
                    indents.removeLast()
                }
                if indents.last != indent {
                    indents.append(indent)
                }
                let level: Int = min(4, indents.count - 1)
                items.append(ManualListItem(marker: item.marker, level: level, text: item.text))
                index += 1
                return
            }
            if !items.isEmpty, ManualMarkdown.indent(line) > listBase, !trimmed.hasPrefix("|") {
                // A continuation line of the last item.
                items[items.count - 1].text += " " + trimmed
                index += 1
                return
            }
            if !items.isEmpty, paragraph.isEmpty, index > 0,
               !lines[index - 1].trimmingCharacters(in: .whitespaces).isEmpty, !trimmed.hasPrefix("|"),
               !trimmed.hasPrefix(">") {
                // A lazy continuation (not indented, straight after the item).
                items[items.count - 1].text += " " + trimmed
                index += 1
                return
            }
            flushList()
            if ManualMarkdown.isRule(trimmed) {
                flushParagraph()
                out.append(.rule)
                index += 1
                return
            }
            if trimmed.hasPrefix(">") {
                flushParagraph()
                var quote: [String] = []
                while index < lines.count {
                    let current: String = lines[index].trimmingCharacters(in: .whitespaces)
                    guard current.hasPrefix(">") else { break }
                    quote.append(current.dropFirst().trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                out.append(.quote(quote.joined(separator: " ")))
                return
            }
            if trimmed.hasPrefix("|"), index + 1 < lines.count, ManualMarkdown.isTableSeparator(lines[index + 1]) {
                flushParagraph()
                let header: [String] = ManualMarkdown.cells(trimmed)
                var rows: [[String]] = []
                index += 2
                while index < lines.count {
                    let current: String = lines[index].trimmingCharacters(in: .whitespaces)
                    guard current.hasPrefix("|") else { break }
                    rows.append(ManualMarkdown.cells(current))
                    index += 1
                }
                out.append(.table(header: header, rows: rows))
                return
            }
            if let image = ManualMarkdown.image(trimmed) {
                flushParagraph()
                out.append(.image(alt: image.alt, path: image.path))
                index += 1
                return
            }
            paragraph.append(trimmed)
            index += 1
        }

        func nextTextLine() -> String? {
            var probe: Int = index
            while probe < lines.count {
                if !lines[probe].trimmingCharacters(in: .whitespaces).isEmpty {
                    return lines[probe]
                }
                probe += 1
            }
            return nil
        }
    }
}
