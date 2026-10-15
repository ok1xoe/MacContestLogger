import Foundation
import MCLManual

/// `mcl-manual [--docs <dir>] [--out <file.pdf>] [--html <file.html>] [--version <v>]`: the user guide from the
/// Markdown pages in `docs/` (order and parts from `docs/README.md`) as a PDF and/or one self-contained HTML file
/// (images embedded; prints to PDF from a browser). Used by CI and the release workflow; needs nothing but macOS.
@MainActor
func run() -> Int32 {
    var docs = "docs"
    var out: String?
    var html: String?
    var version: String?
    let usage = "usage: mcl-manual [--docs <dir>] [--out <file.pdf>] [--html <file.html>] [--version <v>]"
    var arguments = Array(CommandLine.arguments.dropFirst())
    while !arguments.isEmpty {
        let flag: String = arguments.removeFirst()
        switch flag {
        case "--docs" where !arguments.isEmpty: docs = arguments.removeFirst()
        case "--out" where !arguments.isEmpty: out = arguments.removeFirst()
        case "--html" where !arguments.isEmpty: html = arguments.removeFirst()
        case "--version" where !arguments.isEmpty: version = arguments.removeFirst()
        case "-h", "--help":
            print(usage)
            return 0
        default:
            FileHandle.standardError.write(Data("mcl-manual: unknown argument \(flag)\n".utf8))
            return 2
        }
    }
    guard out != nil || html != nil else {
        FileHandle.standardError.write(Data("mcl-manual: --out and/or --html is required\n\(usage)\n".utf8))
        return 2
    }
    do {
        let dir = URL(fileURLWithPath: docs, isDirectory: true)
        let book: ManualBook = try ManualBook.load(docs: dir)
        let built = Date()
        let renderer = ManualRenderer(book: book, docs: dir, options: .init(version: version, buildDate: built))
        var pageStarts: [String]?
        if let out {
            let summary = try renderer.write(to: URL(fileURLWithPath: out))
            pageStarts = summary.pageStarts
            print("mcl-manual: \(out): \(summary.pages) pages, \(summary.chapters) chapters "
                  + "(\(summary.pageStarts.count) start a page), \(summary.outlineEntries) outline entries, "
                  + "\(summary.links) links")
        }
        if let html {
            // The HTML breaks its printed pages where the PDF does.
            let starts: [String] = pageStarts ?? renderer.pageStarts()
            let writer = ManualHTML(book: book, docs: dir,
                                    options: .init(version: version, buildDate: built, pageStarts: Set(starts)))
            let summary = try writer.write(to: URL(fileURLWithPath: html))
            print("mcl-manual: \(html): \(summary.bytes / 1_024) KB, \(summary.chapters) chapters, "
                  + "\(summary.images) images (\(summary.imageBytes / 1_024) KB, \(summary.reducedImages) reduced), "
                  + "\(summary.internalLinks) internal links")
        }
        return 0
    } catch {
        FileHandle.standardError.write(Data("mcl-manual: \(error)\n".utf8))
        return 1
    }
}

exit(MainActor.assumeIsolated { run() })
