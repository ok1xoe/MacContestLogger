import Foundation
import Testing
@testable import MCLCore

/// Port of the Java `stats/ContestStatsTest` (33 tests).
@Suite struct ContestStatsTests {

    static func at(_ text: String) -> JavaInstant {
        JavaInstant.parseIsoInstant(text)!
    }

    private static let t: JavaInstant = at("2026-08-18T12:00:00Z")

    private static func minus(_ seconds: Int64) -> JavaInstant {
        t.plus(seconds: -seconds)!
    }

    static func qso(_ time: JavaInstant?, _ band: Band?) -> Qso {
        var q = Qso()
        q.call = "OK1XOE"
        q.timestampUtc = time?.date
        q.band = band
        return q
    }

    private static func minutes(_ m: Int64) -> Duration {
        Duration.seconds(m * 60)
    }

    // --- rate from the last N contacts ---------------------------------------

    @Test func rateOverLastQsosUsesTheirOwnTimeSpan() {
        var log: [Qso] = []
        for i in 0...10 {
            log.append(Self.qso(Self.minus(300 - Int64(i) * 30), .m20))
        }
        #expect(ContestStats.of(log).rateForLastQsos(10) == 120)
    }

    @Test func rateOverLastQsosLooksOnlyAtTheNewestOnes() {
        let stats = ContestStats.of([
            Self.qso(Self.minus(7200), .m20),
            Self.qso(Self.minus(3600), .m20),
            Self.qso(Self.minus(120), .m20),
            Self.qso(Self.minus(60), .m20),
            Self.qso(Self.t, .m20),
        ])
        #expect(stats.rateForLastQsos(3) == 60)
    }

    @Test func rateOverLastQsosNeedsAtLeastTwoQsos() {
        #expect(ContestStats.of([Self.qso(Self.t, .m20)]).rateForLastQsos(10) == 0)
        #expect(ContestStats.of([]).rateForLastQsos(10) == 0)
    }

    @Test func rateOverLastQsosSurvivesIdenticalTimestamps() {
        let stats = ContestStats.of([Self.qso(Self.t, .m20), Self.qso(Self.t, .m20)])
        #expect(stats.rateForLastQsos(10) == 0)
    }

    // --- rate over a time window ----------------------------------------------

    @Test func windowRateIsExtrapolatedToWholeHour() throws {
        let stats = ContestStats.of([
            Self.qso(Self.minus(60), .m20),
            Self.qso(Self.minus(120), .m20),
            Self.qso(Self.minus(180), .m20),
        ])
        #expect(try stats.ratePerHour(Self.t, Self.minutes(10)) == 18)
    }

    @Test func windowRateIgnoresQsosOutsideTheWindow() throws {
        let stats = ContestStats.of([Self.qso(Self.minus(60), .m20), Self.qso(Self.minus(1800), .m20)])
        #expect(try stats.ratePerHour(Self.t, Self.minutes(10)) == 6)
        #expect(try stats.ratePerHour(Self.t, Self.minutes(60)) == 2)
    }

    @Test func qsoExactlyAtWindowStartHasAlreadyDroppedOut() throws {
        let stats = ContestStats.of([Self.qso(Self.minus(600), .m20), Self.qso(Self.t, .m20)])
        #expect(try stats.ratePerHour(Self.t, Self.minutes(10)) == 6)
    }

    @Test func rateOfEmptyLogIsZero() throws {
        #expect(try ContestStats.of([]).ratePerHour(Self.t, Self.minutes(10)) == 0)
    }

    // --- rate of the current hour ------------------------------------------

    @Test func clockHourRateExtrapolatesFromElapsedPartOfTheHour() {
        let hourStart: JavaInstant = Self.at("2026-08-18T12:00:00Z")
        var log: [Qso] = []
        for i in 0..<5 {
            log.append(Self.qso(hourStart.plus(seconds: 60 * Int64(i)), .m20))
        }
        log.append(Self.qso(Self.at("2026-08-18T11:30:00Z"), .m20))
        #expect(ContestStats.of(log).rateThisClockHour(hourStart.plus(seconds: 900)!) == 20)
    }

    @Test func clockHourRateIsZeroAtTheVeryStartOfTheHour() {
        let hourStart: JavaInstant = Self.at("2026-08-18T12:00:00Z")
        let stats = ContestStats.of([Self.qso(hourStart, .m20)])
        #expect(stats.rateThisClockHour(hourStart) == 0)
    }

    // --- rate progress in fixed intervals --------------------------------

    @Test func trendBucketsAreAlignedToTheClock() throws {
        let now: JavaInstant = Self.at("2026-08-18T10:47:00Z")
        let stats = ContestStats.of([
            Self.qso(Self.at("2026-08-18T10:05:00Z"), .m20),
            Self.qso(Self.at("2026-08-18T10:20:00Z"), .m20),
            Self.qso(Self.at("2026-08-18T10:35:00Z"), .m20),
            Self.qso(Self.at("2026-08-18T10:41:00Z"), .m20),
        ])
        #expect(try stats.trendRates(now, Self.minutes(20), 3) == [3, 6, 8])
    }

    @Test func qsoExactlyOnBucketBoundaryBelongsToTheNewerBucket() throws {
        let now: JavaInstant = Self.at("2026-08-18T10:50:00Z")
        let stats = ContestStats.of([Self.qso(Self.at("2026-08-18T10:40:00Z"), .m20)])
        #expect(try stats.trendRates(now, Self.minutes(20), 2) == [0, 6])
    }

    @Test func unfinishedBucketIsExtrapolatedToWholeHour() throws {
        let now: JavaInstant = Self.at("2026-08-18T10:05:00Z")
        let stats = ContestStats.of([
            Self.qso(Self.at("2026-08-18T10:01:00Z"), .m20),
            Self.qso(Self.at("2026-08-18T10:03:00Z"), .m20),
        ])
        #expect(try stats.trendRates(now, Self.minutes(20), 1) == [24])
    }

    @Test func unfinishedBucketIsZeroExactlyAtItsStart() throws {
        let now: JavaInstant = Self.at("2026-08-18T10:40:00Z")
        let stats = ContestStats.of([Self.qso(now, .m20)])
        #expect(try stats.trendRates(now, Self.minutes(20), 1) == [0])
    }

    @Test func trendRatesOfEmptyLogAreAllZero() throws {
        #expect(try ContestStats.of([]).trendRates(Self.t, Self.minutes(20), 5) == [0, 0, 0, 0, 0])
    }

    // --- timers -----------------------------------------------------------

    @Test func lastQsoTimeIsTheNewestOne() {
        let stats = ContestStats.of([Self.qso(Self.minus(600), .m20), Self.qso(Self.minus(60), .m40)])
        #expect(stats.lastQsoAt() == Self.minus(60))
    }

    @Test func lastQsoTimeIsEmptyForEmptyLog() {
        #expect(ContestStats.of([]).lastQsoAt() == nil)
    }

    @Test func lastQsoBandIsTheBandOfTheNewestQso() {
        let stats = ContestStats.of([Self.qso(Self.minus(600), .m40), Self.qso(Self.minus(60), .m20)])
        #expect(stats.lastQsoBand() == .m20)
        #expect(ContestStats.of([]).lastQsoBand() == nil)
    }

    @Test func lastQsoOnAnotherBandMarksWhenTheBandChanged() {
        let stats = ContestStats.of([
            Self.qso(Self.minus(900), .m40),
            Self.qso(Self.minus(600), .m20),
            Self.qso(Self.minus(60), .m20),
        ])
        #expect(stats.lastQsoOnOtherBandAt(.m20) == Self.minus(900))
    }

    @Test func lastQsoOnAnotherBandIsEmptyWhenOnlyOneBandWasWorked() {
        let stats = ContestStats.of([Self.qso(Self.t, .m20)])
        #expect(stats.lastQsoOnOtherBandAt(.m20) == nil)
    }

    // --- timer base (MCL-21) -----------------------------------------

    @Test func offTimeStartsAtTheMinuteAfterTheLastQso() {
        let stats = ContestStats.of([Self.qso(Self.at("2026-08-18T12:34:20Z"), .m20)])
        #expect(stats.offTimeStart() == Self.at("2026-08-18T12:35:00Z"))
    }

    @Test func offTimeStartIsEmptyBeforeTheFirstQso() {
        #expect(ContestStats.of([]).offTimeStart() == nil)
    }

    @Test func cumulativeOffTimeSumsOnlyQualifyingBreaks() {
        let start: JavaInstant = Self.at("2026-08-18T00:00:00Z")
        let stats = ContestStats.of([
            Self.qso(Self.at("2026-08-18T00:10:00Z"), .m20),
            Self.qso(Self.at("2026-08-18T01:00:00Z"), .m20),
            Self.qso(Self.at("2026-08-18T01:20:00Z"), .m20),
        ])
        #expect(stats.cumulativeOffMinutes(start, Self.at("2026-08-18T01:25:00Z"), 30) == 50)
    }

    @Test func cumulativeOffTimeCountsRunningBreakOnlyOnceItQualifies() {
        let start: JavaInstant = Self.at("2026-08-18T00:00:00Z")
        let stats = ContestStats.of([Self.qso(start, .m20)])
        #expect(stats.cumulativeOffMinutes(start, start.plus(seconds: 1200)!, 30) == 0)
        #expect(stats.cumulativeOffMinutes(start, start.plus(seconds: 2400)!, 30) == 40)
    }

    @Test func bandChangeTimerStartsAtFirstQsoAfterTheBandChanged() {
        let stats = ContestStats.of([
            Self.qso(Self.at("2026-08-18T10:00:00Z"), .m40),
            Self.qso(Self.at("2026-08-18T10:20:00Z"), .m20),
            Self.qso(Self.at("2026-08-18T10:40:00Z"), .m20),
        ])
        #expect(stats.currentBandRunStart(.m20) == Self.at("2026-08-18T10:20:00Z"))
    }

    @Test func bandChangeTimerDoesNotStartBeforeTheFirstBandChange() {
        let stats = ContestStats.of([
            Self.qso(Self.at("2026-08-18T10:00:00Z"), .m20),
            Self.qso(Self.at("2026-08-18T10:20:00Z"), .m20),
        ])
        #expect(stats.currentBandRunStart(.m20) == nil)
    }

    @Test func bandChangeTimerIsEmptyRightAfterQsyToAnUntouchedBand() {
        let stats = ContestStats.of([
            Self.qso(Self.at("2026-08-18T10:00:00Z"), .m40),
            Self.qso(Self.at("2026-08-18T10:20:00Z"), .m20),
        ])
        #expect(stats.currentBandRunStart(.m15) == nil)
        #expect(stats.currentBandRunStart(.m40) == nil)
    }

    @Test func bandChangeTimerIsEmptyForAnEmptyLog() {
        #expect(ContestStats.of([]).currentBandRunStart(.m20) == nil)
    }

    @Test func bandChangesAreCountedWithinTheCurrentClockHour() {
        let stats = ContestStats.of([
            Self.qso(Self.at("2026-08-18T09:50:00Z"), .m20),
            Self.qso(Self.at("2026-08-18T10:05:00Z"), .m40),
            Self.qso(Self.at("2026-08-18T10:15:00Z"), .m40),
            Self.qso(Self.at("2026-08-18T10:25:00Z"), .m20),
        ])
        #expect(stats.bandChangesInClockHour(Self.at("2026-08-18T10:30:00Z")) == 2)
    }

    @Test func bandChangeFromThePreviousHourIsNotCounted() {
        let stats = ContestStats.of([
            Self.qso(Self.at("2026-08-18T09:50:00Z"), .m20),
            Self.qso(Self.at("2026-08-18T09:55:00Z"), .m40),
            Self.qso(Self.at("2026-08-18T10:05:00Z"), .m40),
        ])
        #expect(stats.bandChangesInClockHour(Self.at("2026-08-18T10:30:00Z")) == 0)
    }

    // --- edge cases ---------------------------------------------------

    @Test func deletedQsosAreIgnored() {
        var tomb = Self.qso(Self.t, .m20)
        tomb.deleted = true
        let stats = ContestStats.of([tomb, Self.qso(Self.minus(60), .m20)])
        #expect(stats.lastQsoAt() == Self.minus(60))
    }

    @Test func qsosWithoutBandOrTimeAreIgnored() {
        let stats = ContestStats.of([Self.qso(Self.t, nil), Self.qso(nil, .m20), Self.qso(Self.minus(60), .m15)])
        #expect(stats.lastQsoBand() == .m15)
    }

    @Test func unsortedLogIsOrderedByTime() {
        let stats = ContestStats.of([Self.qso(Self.t, .m20), Self.qso(Self.minus(600), .m40)])
        #expect(stats.lastQsoAt() == Self.t)
        #expect(stats.lastQsoBand() == .m20)
    }
}
