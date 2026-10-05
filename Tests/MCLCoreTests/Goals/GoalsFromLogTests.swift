import Testing
@testable import MCLCore

/// Port of the Java `goals/GoalsFromLogTest` (6 tests).
@Suite struct GoalsFromLogTests {

    /// The contest starts at 21:00Z, so it does not start at midnight — the day is counted by date.
    private static let start: JavaInstant = GoalSetTests.instant("2026-11-28T21:00:00Z")

    static func qso(_ iso: String, _ band: Band?) -> Qso {
        var q = Qso()
        q.call = "DL1ABC"
        q.timestampUtc = GoalSetTests.instant(iso).date
        q.band = band
        return q
    }

    @Test func countsQsosPerContestDayAndHour() throws {
        let log: [Qso] = [
            Self.qso("2026-11-28T21:10:00Z", .m40),
            Self.qso("2026-11-28T21:50:00Z", .m40),
            Self.qso("2026-11-28T22:05:00Z", .m20),
            Self.qso("2026-11-29T05:30:00Z", .m20),
        ]

        let goals = try GoalsFromLog.derive(log, Self.start, nil)

        #expect(goals.entries == [
            GoalSet.key(1, 21): 2,
            GoalSet.key(1, 22): 1,
            GoalSet.key(2, 5): 1,
        ])
    }

    @Test func bandFilterCountsOnlyThatBand() throws {
        let log: [Qso] = [
            Self.qso("2026-11-28T21:10:00Z", .m40),
            Self.qso("2026-11-28T21:50:00Z", .m20),
            Self.qso("2026-11-28T22:05:00Z", .m20),
        ]

        let goals = try GoalsFromLog.derive(log, Self.start, .m20)

        #expect(goals.entries == [GoalSet.key(1, 21): 1, GoalSet.key(1, 22): 1])
    }

    @Test func hoursBeforeTheContestStartAreIgnored() throws {
        // A log may also carry QSOs outside the contest; they do not belong in the plan.
        let log: [Qso] = [
            Self.qso("2026-11-28T18:00:00Z", .m40),
            Self.qso("2026-11-28T21:10:00Z", .m40),
        ]

        #expect(try GoalsFromLog.derive(log, Self.start, nil).entries == [GoalSet.key(1, 21): 1])
    }

    @Test func deletedAndIncompleteQsosAreSkipped() throws {
        var tomb = Self.qso("2026-11-28T21:10:00Z", .m40)
        tomb.deleted = true
        var noTime = Qso()
        noTime.band = .m40
        let log: [Qso] = [tomb, noTime, Self.qso("2026-11-28T21:20:00Z", .m40)]

        #expect(try GoalsFromLog.derive(log, Self.start, nil).entries == [GoalSet.key(1, 21): 1])
    }

    @Test func qsoWithoutBandCountsIntoTheTotalButNotIntoABandFilter() throws {
        let noBand = Self.qso("2026-11-28T21:10:00Z", nil)
        let log: [Qso] = [noBand]

        #expect(try GoalsFromLog.derive(log, Self.start, nil).entries == [GoalSet.key(1, 21): 1])
        #expect(try GoalsFromLog.derive(log, Self.start, .m20).isEmpty)
    }

    @Test func emptyLogOrMissingStartGivesEmptySet() throws {
        #expect(try GoalsFromLog.derive([], Self.start, nil).isEmpty)
        #expect(try GoalsFromLog.derive([Self.qso("2026-11-28T21:10:00Z", .m40)], nil, nil).isEmpty)
    }
}
