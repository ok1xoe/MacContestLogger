import Foundation
import Testing
@testable import MCLCore

/// `PrintLayout` against `io/LogPrinter.java` (`LP:46-75`) and `AppState.printLog` (`AS:4025-4035`) of v1.1.1;
/// rows `LINES`, `LPP` of the maintainer-only probe.
@Suite struct PrintLayoutTests {

    @Test(arguments: [
        (734.0, 71), (733.9, 70), (720.0, 69), (24.0, 0), (23.0, 0), (14.5, 0), (0.0, -2), (769.89, 74),
    ])
    func linesPerPageTruncatesLikeJava(_ height: Double, _ lines: Int) {
        #expect(PrintLayout.linesPerPage(imageableHeight: height) == lines)
    }

    @Test func javaIntSaturates() {
        #expect(PrintLayout.javaInt(.nan) == 0)
        #expect(PrintLayout.javaInt(.infinity) == Int(Int32.max))
        #expect(PrintLayout.javaInt(-.infinity) == Int(Int32.min))
        #expect(PrintLayout.javaInt(-2.9) == -2)
    }

    @Test func titleJoinsNameAndCall() {
        #expect(PrintLayout.title(definitionName: "CQ WW DX CW", call: "OK1XOE") == "CQ WW DX CW — OK1XOE")
        #expect(PrintLayout.title(definitionName: "Deník", call: "") == "Deník — ")
    }

    /// Height 74 → 5 lines per page: the 3 header lines repeat, 2 body lines per page; lines at y 10, 20, …,
    /// the footer `"<title> — strana i/n"` at `(int) h − 4`; `\r\n` and `\r` split like `String.lines()`.
    @Test func pagesRepeatTheHeaderAndNumberTheFooter() {
        let text = "T\r\nH\rR\n1\n2\n3\n"
        let pages = PrintLayout.pages(text: text, title: "Log — OK1XOE", imageableHeight: 74.9)
        #expect(pages.count == 2)
        #expect(pages[0].lines.map(\.text) == ["T", "H", "R", "1", "2"])
        #expect(pages[0].lines.map(\.y) == [10, 20, 30, 40, 50])
        #expect(pages[1].lines.map(\.text) == ["T", "H", "R", "3"])
        #expect(pages[0].footer == PrintLayout.Line(text: "Log — OK1XOE — strana 1/2", y: 70))
        #expect(pages[1].footer.text == "Log — OK1XOE — strana 2/2")
    }

    /// An empty listing is one page; a page too small for the header still prints one body line per page.
    @Test func degeneratePages() {
        #expect(PrintLayout.pages(text: "", title: "t", imageableHeight: 700).count == 1)
        let tiny = PrintLayout.pages(text: "a\nb\nc\nd\ne", title: "t", imageableHeight: 0)
        #expect(tiny.map { $0.lines.count } == [4, 4])
        #expect(tiny[0].footer.y == -4)
    }

    @Test func statusTexts() {
        #expect(IoTexts.printSent.czech == "Deník odeslán na tiskárnu")
        #expect(IoTexts.printCancelled.czech == "Tisk zrušen")
        #expect(IoTexts.printFailed(message: "no printer") == .verbatim("Tisk selhal: no printer"))
        #expect(IoTexts.printFailed(message: nil) == .verbatim("Tisk selhal: null"))
    }
}
