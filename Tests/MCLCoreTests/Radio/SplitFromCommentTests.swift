import Testing
@testable import MCLCore

/// Port of the Java `SplitFromCommentTest` (3 tests, same names). The measured edges
/// (overflow, Unicode, `\b`) are in `RadioMeasuredTests.splitFromCommentMatchesJava`.
@Suite struct SplitFromCommentTests {

    private static let spot: Int = 14_023_000

    private func p(_ comment: String?) -> Int? {
        SplitFromComment.parse(comment, spotFreqHz: Self.spot, defaultUpHz: 1000)
    }

    @Test func upAndDown() {
        #expect(p("UP 5") == 14_028_000)
        #expect(p("cq up2") == 14_025_000)
        #expect(p("UP 2-4 tnx") == 14_025_000)
        #expect(p("up 1.5") == 14_024_500)
        #expect(p("UP") == 14_024_000, "default shift")
        #expect(p("DOWN 3") == 14_020_000)
        #expect(p("dn 2") == 14_021_000)
        #expect(p("DOWN") == nil)
    }

    @Test func qsx() {
        #expect(p("QSX 14025.5") == 14_025_500)
        #expect(p("qsx 025") == 14_025_000)
        #expect(p("QSX25") == 14_025_000)
        #expect(p("QSX 7025") == nil, "different band")
    }

    @Test func noSplit() {
        #expect(p("TNX QSO 599") == nil)
        #expect(p("SUPER SIGNAL") == nil, "UP inside a word does not count")
        #expect(p(nil) == nil)
        #expect(p("UP 500") == nil, "shift over 100 kHz")
    }
}
