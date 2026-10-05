import Foundation
import Testing
@testable import MCLCore

/// `ContestStats.appending`: for time-ordered appends the snapshot equals `ContestStats.of` over the longer log, both
/// as a value and in every public query over a grid of times; an earlier time returns `nil`.
@Suite struct ContestStatsAppendingTests {

    static let start = Date(timeIntervalSince1970: 1_795_867_200)
    static let bands: [Band] = [.m80, .m40, .m20, .m15]

    static func qso(_ rng: inout DupeIndexTests.SplitMix, at date: Date?) -> Qso {
        var q = Qso()
        q.call = "OK1ABC"
        q.timestampUtc = date
        q.band = rng.below(12) == 0 ? nil : bands[rng.below(bands.count)]
        q.deleted = rng.below(25) == 0
        return q
    }

    /// Every public query of the snapshot at `now` (the rule pass and the Info window read these).
    static func queries(_ s: ContestStats, _ now: JavaInstant) throws -> [String] {
        var out: [String] = [
            String(s.rateForLastQsos(10)), String(s.rateForLastQsos(100)),
            String(try s.ratePerHour(now, .seconds(600))), String(s.rateThisClockHour(now)),
            try s.trendRates(now, .seconds(900), 6).map(String.init).joined(separator: ","),
            String(describing: s.lastQsoAt()), String(describing: s.firstQsoAt()),
            String(describing: s.lastQsoBand()), String(describing: s.offTimeStart()),
            String(s.cumulativeOffMinutes(JavaInstant(date: start), now, 30)),
            String(s.bandChangesInClockHour(now)),
        ]
        for band in bands {
            out.append(String(describing: s.lastQsoOnOtherBandAt(band)))
            out.append(String(describing: s.currentBandRunStart(band)))
        }
        return out
    }

    @Test(arguments: [UInt64(1), 2, 3])
    func appendingEqualsRecomputation(seed: UInt64) throws {
        var rng = DupeIndexTests.SplitMix(state: seed)
        var log: [Qso] = []
        var stats = ContestStats.of([])
        var clock: Double = 0
        for step in 0..<400 {
            // Non-decreasing times with equal seconds, equal instants and sub-second steps; some QSOs without a time.
            let advance: [Double] = [0, 0, 0.25, 0.5, 1, 7, 60, 600, 3_600]
            clock += advance[rng.below(advance.count)]
            let date: Date? = rng.below(30) == 0 ? nil : Self.start.addingTimeInterval(clock)
            let q = Self.qso(&rng, at: date)
            let appended = try #require(stats.appending(q))
            log.append(q)
            let recomputed = ContestStats.of(log)
            #expect(appended == recomputed)
            if step % 20 == 0 {
                for offset in [-1.0, 0, 0.5, 59, 1_800, 4_000] {
                    let now = JavaInstant(date: Self.start.addingTimeInterval(clock + offset))
                    #expect(try Self.queries(appended, now) == Self.queries(recomputed, now))
                }
            }
            stats = appended
        }
    }

    @Test func anEarlierQsoNeedsARecomputation() {
        var a = Qso()
        a.call = "OK1ABC"
        a.band = .m20
        a.timestampUtc = Self.start.addingTimeInterval(10.5)
        let stats = ContestStats.of([a])
        var earlier = a
        earlier.timestampUtc = Self.start.addingTimeInterval(10.25) // the same second, an earlier instant
        #expect(stats.appending(earlier) == nil)
        var equal = a
        equal.band = .m40
        let appended = stats.appending(equal)
        #expect(appended == ContestStats.of([a, equal]))
        #expect(appended?.lastQsoBand() == .m40, "an equal instant stays after the earlier QSO")
    }

    @Test func ignoredQsosLeaveTheSnapshotUnchanged() {
        var a = Qso()
        a.band = .m20
        a.timestampUtc = Self.start.addingTimeInterval(100)
        let stats = ContestStats.of([a])
        var deletedEarlier = a
        deletedEarlier.deleted = true
        deletedEarlier.timestampUtc = Self.start
        var noBand = a
        noBand.band = nil
        noBand.timestampUtc = Self.start
        var noTime = a
        noTime.timestampUtc = nil
        for q in [deletedEarlier, noBand, noTime] {
            #expect(stats.appending(q) == stats)
        }
    }
}
