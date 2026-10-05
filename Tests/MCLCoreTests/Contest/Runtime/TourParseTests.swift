import Testing
@testable import MCLCore

/// `Tour.parse` (Java `contest/runtime/Tour.java:41-59`). There is no Java test for `parse`;
/// the expected values are measured by the probe `ProbeVal.java`
/// (maintainer-only probe) on JDK 21.
@Suite struct TourParseTests {

    struct Case: Sendable, CustomTestStringConvertible {
        let text: String
        /// `(startMinute, durationMinutes)`; `nil` = Java `Optional.empty()`.
        let expected: (Int, Int)?
        var testDescription: String { text.debugDescription }
    }

    static let cases: [Case] = [
        Case(text: "0000/5", expected: (0, 5)),
        Case(text: "2359/4", expected: nil),              // duration below the minimum
        Case(text: "2400/60", expected: nil),             // hour 24
        Case(text: "1200/0130", expected: (720, 90)),     // four-digit duration = hhmm
        Case(text: " 1200/60 ", expected: (720, 60)),     // trim()
        Case(text: "\u{0661}\u{0662}\u{0660}\u{0660}/60", expected: nil), // `\d` is ASCII only
        Case(text: "100/30", expected: (60, 30)),         // single-digit hour
        Case(text: "12:00/30", expected: nil),
        Case(text: "1260/30", expected: nil),             // minute 60
        Case(text: "1200/", expected: nil),
        Case(text: "/30", expected: nil),
        Case(text: "\t1200/60\n", expected: (720, 60)),
        Case(text: "\u{2000}1200/60", expected: nil),     // trim() takes only characters ≤ U+0020
        Case(text: "1200/00005", expected: nil),          // five digits of duration
        Case(text: "1200/0004", expected: nil),           // hhmm = 4 minutes
        Case(text: "1200/0005", expected: (720, 5)),
        Case(text: "1200/9999", expected: (720, 6039)),   // 99 h 99 min, Java does not check
        Case(text: "0000/1440", expected: (0, 880)),      // four digits = 14:40, not 1440 min
        Case(text: "1200/005", expected: (720, 5)),
        Case(text: "01200/30", expected: nil),
        Case(text: "9/30", expected: nil),
        Case(text: "12345/30", expected: nil),
        Case(text: "1200/30/", expected: nil),
        Case(text: "1200/\u{0665}", expected: nil),
        Case(text: "2359/0060", expected: (1439, 60)),
        Case(text: "0060/30", expected: nil),
        Case(text: "1200 /30", expected: nil),
        Case(text: "", expected: nil),
    ]

    @Test(arguments: cases)
    func parsesLikeJava(_ testCase: Case) {
        let tour = Tour.parse(testCase.text)
        #expect(tour?.startMinute == testCase.expected?.0)
        #expect(tour?.durationMinutes == testCase.expected?.1)
    }

    @Test func nilIsEmpty() {
        #expect(Tour.parse(nil) == nil)
    }

    @Test func minimumDurationIsFive() {
        #expect(Tour.minDuration == 5)
    }
}
