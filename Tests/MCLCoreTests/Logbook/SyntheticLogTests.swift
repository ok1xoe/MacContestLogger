import Foundation
import Testing
@testable import MCLCore

/// The synthetic CQ WW CW log of the 20k measurement: deterministic, the band distribution, the dupe
/// share and the mixed prefixes it promises.
@Suite struct SyntheticLogTests {

    private static let start = Date(timeIntervalSince1970: 1_795_824_000)

    private static func log(_ count: Int, seed: UInt64 = 7) -> [Qso] {
        SyntheticLog.generate(count: count, seed: seed, contestId: "synthetic", start: start)
    }

    private static func dupeCount(_ qsos: [Qso]) -> Int {
        var seen: Set<String> = []
        var dupes = 0
        for qso in qsos {
            let key: String = qso.call + "|" + (qso.band?.adif ?? "")
            if !seen.insert(key).inserted {
                dupes += 1
            }
        }
        return dupes
    }

    @Test func sameSeedGivesTheSameLog() {
        let first: [Qso] = Self.log(500)
        let second: [Qso] = Self.log(500)
        #expect(first == second)
        let other: [Qso] = Self.log(500, seed: 8)
        #expect(first.map(\.call) != other.map(\.call))
    }

    @Test func countSerialsAndContest() {
        let qsos: [Qso] = Self.log(2_000)
        #expect(qsos.count == 2_000)
        #expect(qsos.map { $0.serialSent ?? 0 } == Array(1...2_000))
        #expect(qsos.allSatisfy { $0.contestId == "synthetic" && $0.mode == .cw && $0.id == nil })
        #expect(Set(qsos.map(\.uuid)).count == 2_000)
        #expect(SyntheticLog.generate(count: 0, seed: 1, contestId: "x", start: Self.start).isEmpty)
    }

    @Test func timesAreOrderedWithinTheContestWeekend() throws {
        let qsos: [Qso] = Self.log(20_000)
        let times: [Date] = qsos.compactMap(\.timestampUtc)
        #expect(times.count == 20_000)
        #expect(times == times.sorted())
        let last: Date = try #require(times.last)
        #expect(last.timeIntervalSince(Self.start) < 48 * 3_600)
    }

    @Test func bandsFollowTheDistribution() {
        let qsos: [Qso] = Self.log(20_000)
        var perBand: [Band: Int] = [:]
        for qso in qsos {
            if let band = qso.band {
                perBand[band, default: 0] += 1
            }
        }
        #expect(Set(perBand.keys) == [.m160, .m80, .m40, .m20, .m15, .m10])
        #expect(perBand.values.reduce(0, +) == 20_000)
        // 40 m and 20 m carry the weekend (28 % and 30 % of the fresh QSOs), 160 m is the smallest (5 %).
        let share: (Band) -> Double = { Double(perBand[$0] ?? 0) / 20_000 }
        #expect(share(.m20) > 0.25 && share(.m20) < 0.35)
        #expect(share(.m40) > 0.23 && share(.m40) < 0.33)
        #expect(share(.m160) > 0.03 && share(.m160) < 0.07)
    }

    @Test func aboutTwoPercentAreDupes() {
        let dupes: Int = Self.dupeCount(Self.log(20_000))
        #expect(dupes >= 300 && dupes <= 600, "dupes: \(dupes)")
    }

    @Test func prefixesAreMixedAndExchangesCarryTheZone() {
        let qsos: [Qso] = Self.log(20_000)
        let firstTwo: Set<String> = Set(qsos.map { String($0.call.prefix(2)) })
        #expect(firstTwo.count >= 40)
        for qso in qsos.prefix(1_000) {
            let parts: [Substring] = qso.exchangeRcvd.split(separator: " ")
            #expect(parts.count == 2 && parts[0] == "599")
            let zone: Int = Int(parts.last ?? "") ?? 0
            #expect(zone >= 1 && zone <= 40)
            #expect(qso.exchangeSent == "599 15")
        }
    }

    /// The log replays into a CQ WW CW session: nothing is skipped.
    @Test func replaysIntoCqWwCw() throws {
        let qsos: [Qso] = Self.log(3_000)
        let session = try SessionFixture.session("@cq-ww-cw.yaml")
        let outcome = ContestReplay.replay(session, qsos)
        #expect(outcome.replayed + outcome.skipped == 3_000)
        #expect(outcome.skipped == 0)
    }
}
