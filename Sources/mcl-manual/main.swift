import Foundation
import MCLManual

/// `mcl-manual [--docs <dir>] --out <file.pdf> [--version <v>]`: the PDF user guide from the Markdown pages in
/// `docs/` (order and parts from `docs/README.md`). Used by the release workflow; needs nothing but macOS.
@MainActor
func run() -> Int32 {
    var docs = "docs"
    var out: String?
    var version: String?
    var arguments = Array(CommandLine.arguments.dropFirst())
    while !arguments.isEmpty {
        let flag: String = arguments.removeFirst()
        switch flag {
        case "--docs" where !arguments.isEmpty: docs = arguments.removeFirst()
        case "--out" where !arguments.isEmpty: out = arguments.removeFirst()
        case "--version" where !arguments.isEmpty: version = arguments.removeFirst()
        case "-h", "--help":
            print("usage: mcl-manual [--docs <dir>] --out <file.pdf> [--version <v>]")
            return 0
        default:
            FileHandle.standardError.write(Data("mcl-manual: unknown argument \(flag)\n".utf8))
            return 2
        }
    }
    guard let out else {
        FileHandle.standardError.write(Data("mcl-manual: --out is required\n".utf8))
        return 2
    }
    do {
        let dir = URL(fileURLWithPath: docs, isDirectory: true)
        let book: ManualBook = try ManualBook.load(docs: dir)
        let renderer = ManualRenderer(book: book, docs: dir, options: .init(version: version))
        let summary = try renderer.write(to: URL(fileURLWithPath: out))
        print("mcl-manual: \(out): \(summary.pages) pages, \(summary.chapters) chapters, "
              + "\(summary.outlineEntries) outline entries, \(summary.links) links")
        return 0
    } catch {
        FileHandle.standardError.write(Data("mcl-manual: \(error)\n".utf8))
        return 1
    }
}

exit(MainActor.assumeIsolated { run() })
