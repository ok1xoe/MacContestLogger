import Testing
@testable import MCLCore

/// Port of the Java `goals/GoalFileParserTest` (11 tests).
@Suite struct GoalFileParserTests {

    // --- format 1: export from View → Statistics -------------------------------

    private static let statistics: [String] = [
        "Day        Hr  1.8   3.5     7   14   21   28   Tot  Accum ",
        "2010-11-27 00    0    70   146    5    0    0   221    221   ",
        "2010-11-27 01    0   116   119    0    0    0   235    456   ",
        "2010-11-28 02   71    27   128    0    0    0   226    682   ",
        "Total       0  306   867  2088 2156 1763  542  7722   7722",
    ]

    @Test func statisticsExportUsesTotalColumnForAllBands() {
        let r = GoalFileParser.parse(Self.statistics, nil)

        #expect(r.goals.entries[GoalSet.key(1, 0)] == 221)
        #expect(r.goals.entries[GoalSet.key(1, 1)] == 235)
        // The second date in the file = the second day of the contest.
        #expect(r.goals.entries[GoalSet.key(2, 2)] == 226)
    }

    @Test func statisticsExportCanBeLimitedToOneBand() {
        let r = GoalFileParser.parse(Self.statistics, "3.5")

        #expect(r.goals.entries[GoalSet.key(1, 0)] == 70)
        #expect(r.goals.entries[GoalSet.key(1, 1)] == 116)
    }

    @Test func statisticsExportOffersItsBandColumns() {
        #expect(GoalFileParser.parse(Self.statistics, nil).bands == ["1.8", "3.5", "7", "14", "21", "28"])
    }

    @Test func totalRowIsNotMistakenForAnHour() {
        let r = GoalFileParser.parse(Self.statistics, nil)

        #expect(r.goals.entries.count == 3)
        #expect(r.ignoredLines.isEmpty, "a totals row is not an error: \(r.ignoredLines)")
    }

    // --- formats 2 and 3: hour/goal pairs -----------------------------------

    @Test func plainPairsBelowHundredAreHoursOfTheFirstDay() {
        let r = GoalFileParser.parse(["0  100", "1\t111", "  2   222 "], nil)

        #expect(r.goals.entries == [100: 100, 101: 111, 102: 222])
    }

    @Test func csvPairsAreAccepted() {
        let r = GoalFileParser.parse(["0, 100", "1, 111", "2,222"], nil)

        #expect(r.goals.entries == [100: 100, 101: 111, 102: 222])
    }

    @Test func keysAtOrAboveHundredAreTakenAsDayAndHour() {
        let r = GoalFileParser.parse(["100 350", "101 337", "222 90"], nil)

        #expect(r.goals.entries == [100: 350, 101: 337, 222: 90])
    }

    // --- format 4: export from the Edit Goals dialog ------------------------------

    @Test func editGoalsExportHeaderIsSkipped() {
        let r = GoalFileParser.parse(["Type=GOAL  SubType=", "     100     350", "     101     337"], nil)

        #expect(r.goals.entries == [100: 350, 101: 337])
        #expect(r.ignoredLines.isEmpty)
    }

    // --- common rules -------------------------------------------------------

    @Test func blankLinesAndCommentsAreIgnoredWithoutComplaint() {
        let r = GoalFileParser.parse(["# plán na sobotu", "", "   ", "0 100"], nil)

        #expect(r.goals.entries == [100: 100])
        #expect(r.ignoredLines.isEmpty)
    }

    @Test func unrecognisedLineIsReportedNotSilentlyDropped() {
        let r = GoalFileParser.parse(["0 100", "tohle není cíl", "1 111"], nil)

        #expect(r.goals.entries == [100: 100, 101: 111])
        #expect(r.ignoredLines == ["tohle není cíl"])
    }

    @Test func emptyFileGivesEmptySetRatherThanFailing() {
        let r = GoalFileParser.parse([], nil)

        #expect(r.goals.isEmpty)
        #expect(r.ignoredLines.isEmpty)
    }
}
