import Testing
@testable import MCLCore

/// Port of the Java `goals/GoalSetTest` (12 tests).
@Suite struct GoalSetTests {

    static func instant(_ text: String) -> JavaInstant {
        JavaInstant.parseIsoInstant(text)!
    }

    /// ARRL SS starts on Saturday 21:00Z — a typical contest not starting at midnight.
    private static let start: JavaInstant = instant("2026-11-28T21:00:00Z")

    private static func after(_ seconds: Int64) -> JavaInstant {
        start.plus(seconds: seconds)!
    }

    @Test func keyJoinsContestDayAndHour() {
        // "222" = the second day of the contest, the hour starting at 22:00Z.
        #expect(GoalSet.key(2, 22) == 222)
        #expect(GoalSet.key(1, 0) == 100)
    }

    @Test func dayIsCountedByCalendarDatesNotByElapsedHours() throws {
        let goals = GoalSet.of([122: 60, 205: 30])

        // Saturday 22:00Z is still the first day of the contest, even though an hour has passed since the start.
        #expect(try goals.goalFor(Self.start, Self.instant("2026-11-28T22:30:00Z")) == 60)
        // Sunday 05:00Z is the second day, although only eight hours have passed since the start.
        #expect(try goals.goalFor(Self.start, Self.instant("2026-11-29T05:30:00Z")) == 30)
    }

    @Test func emptySetFallsBackToDefaultFifty() throws {
        #expect(try GoalSet.empty().goalFor(Self.start, Self.after(3600)) == 50)
    }

    @Test func hourWithoutRecordInANonEmptySetMeansNoPlannedOperating() throws {
        // Hours when no operation is planned are not written to the file — the goal is zero.
        let goals = GoalSet.of([122: 60])

        #expect(try goals.goalFor(Self.start, Self.instant("2026-11-29T05:30:00Z")) == 0)
    }

    @Test func beforeTheStartTheFirstContestHourIsUsed() throws {
        let goals = GoalSet.of([121: 80, 122: 60])

        // An hour before the start the plan of the first contest hour is shown (21:00Z).
        #expect(try goals.goalFor(Self.start, Self.after(-3600)) == 80)
    }

    @Test func goalsAreZeroBeyondNinetySixHoursFromTheStart() throws {
        let goals = GoalSet.of([521: 90])

        #expect(try goals.goalFor(Self.start, Self.after(96 * 3600)) == 0)
        #expect(try goals.goalFor(Self.start, Self.after(200 * 3600)) == 0)
    }

    @Test func horizonWinsOverTheDefaultForAnEmptySet() throws {
        // Without goals the default 50 is otherwise shown, but for a contest that ended
        // a week ago the plan has nothing to say — the horizon takes precedence.
        #expect(try GoalSet.empty().goalFor(Self.start, Self.after(200 * 3600)) == 0)
    }

    @Test func missingContestStartIsAnErrorAndFallsBackToDefault() throws {
        // Without a start date the contest hour cannot be determined; per N1MM 50 is used.
        #expect(try GoalSet.of([122: 60]).goalFor(nil, Self.start) == 50)
    }

    @Test func entriesAreExposedForExport() {
        let goals = GoalSet.of([122: 60, 205: 30])

        #expect(goals.entries == [122: 60, 205: 30])
        #expect(GoalSet.empty().isEmpty)
    }

    // --- listing of contest hours (the base for the goals editor) -----------------------

    @Test func listsContestHoursAcrossMidnight() throws {
        // Contest from 21:00Z: the first three hours of the first day, the fourth already the second day.
        #expect(try GoalSet.hoursOf(Self.start, 4) == [121, 122, 123, 200])
    }

    @Test func hourListStartsAtTheHourOfTheStartEvenWhenItIsNotSharp() throws {
        let ragged: JavaInstant = Self.instant("2026-11-28T21:37:00Z")

        #expect(try GoalSet.hoursOf(ragged, 2) == [121, 122])
    }

    @Test func hourListIsEmptyWithoutStartOrDuration() throws {
        #expect(try GoalSet.hoursOf(nil, 48).isEmpty)
        #expect(try GoalSet.hoursOf(Self.start, 0).isEmpty)
    }
}
