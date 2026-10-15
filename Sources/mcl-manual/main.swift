import Foundation
import MCLManual

/// `mcl-manual [--docs <dir>] [--lang en|cs] [--strict-lang] [--out <file.pdf>] [--html <file.html>]
/// [--out-dir <dir>] [--version <v>]`: the user guide from the Markdown pages in `docs/` (order and parts from
/// `docs/README.md`; the Czech guide from `docs/cs/`) as a PDF and/or one self-contained HTML file (images embedded;
/// prints to PDF from a browser). `--out-dir` writes both as `MacContestLogger-manual-<lang>.pdf/.html` (the English
/// guide also under the original names `MacContestLogger-manual.pdf/.html`). A Czech page that is not translated yet is
/// taken from English with a warning; `--strict-lang` makes that an error. Used by CI and the release workflow; needs
/// nothing but macOS.
@MainActor
func run() -> Int32 {
    var docs = "docs"
    var out: String?
    var html: String?
    var version: String?
    var outDir: String?
    var language: ManualLanguage = .en
    var strict = false
    let usage = "usage: mcl-manual [--docs <dir>] [--lang en|cs] [--strict-lang] [--out <file.pdf>] [--html <file.html>] "
        + "[--out-dir <dir>] [--version <v>]"
    var arguments = Array(CommandLine.arguments.dropFirst())
    while !arguments.isEmpty {
        let flag: String = arguments.removeFirst()
        switch flag {
        case "--docs" where !arguments.isEmpty: docs = arguments.removeFirst()
        case "--out" where !arguments.isEmpty: out = arguments.removeFirst()
        case "--html" where !arguments.isEmpty: html = arguments.removeFirst()
        case "--version" where !arguments.isEmpty: version = arguments.removeFirst()
        case "--out-dir" where !arguments.isEmpty: outDir = arguments.removeFirst()
        case "--strict-lang": strict = true
        case "--lang" where !arguments.isEmpty:
            let code: String = arguments.removeFirst()
            guard let chosen = ManualLanguage(rawValue: code) else {
                FileHandle.standardError.write(Data("mcl-manual: unknown language \(code) (en, cs)\n".utf8))
                return 2
            }
            language = chosen
        case "-h", "--help":
            print(usage)
            return 0
        default:
            FileHandle.standardError.write(Data("mcl-manual: unknown argument \(flag)\n".utf8))
            return 2
        }
    }
    if let outDir {
        out = out ?? (outDir as NSString).appendingPathComponent(language.fileName("pdf"))
        html = html ?? (outDir as NSString).appendingPathComponent(language.fileName("html"))
    }
    guard out != nil || html != nil else {
        FileHandle.standardError.write(Data("mcl-manual: --out, --html or --out-dir is required\n\(usage)\n".utf8))
        return 2
    }
    do {
        let dir = URL(fileURLWithPath: docs, isDirectory: true)
        let book: ManualBook = try ManualBook.load(docs: dir, language: language, strict: strict)
        for warning in book.warnings {
            FileHandle.standardError.write(Data("mcl-manual: warning: \(warning)\n".utf8))
        }
        if !book.czechScreenshots.isEmpty {
            print("mcl-manual: \(book.czechScreenshots.count) screenshots have no English version yet (Czech ones used)")
        }
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
        // The English guide also under the names of the first releases (the app's older versions download those).
        if let outDir {
            for ext in ["pdf", "html"] {
                guard let legacy = language.legacyFileName(ext) else { continue }
                let from = URL(fileURLWithPath: (outDir as NSString).appendingPathComponent(language.fileName(ext)))
                let to = URL(fileURLWithPath: (outDir as NSString).appendingPathComponent(legacy))
                guard FileManager.default.fileExists(atPath: from.path) else { continue }
                try? FileManager.default.removeItem(at: to)
                try FileManager.default.copyItem(at: from, to: to)
                print("mcl-manual: \(to.path): copy of \(from.lastPathComponent)")
            }
        }
        return 0
    } catch {
        FileHandle.standardError.write(Data("mcl-manual: \(error)\n".utf8))
        return 1
    }
}

exit(MainActor.assumeIsolated { run() })
