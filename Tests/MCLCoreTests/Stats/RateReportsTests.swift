import Foundation
import Testing
@testable import MCLCore

/// Port of the Java `stats/RateReportsTest` (2 tests).
@Suite struct RateReportsTests {

    private static let base: JavaInstant = JavaInstant.parseIsoInstant("2026-11-28T12:00:00Z")!

    private static func qso(_ minute: Int, _ hz: Int, _ rm: RunMode) -> Qso {
        var q = Qso()
        q.timestampUtc = base.plus(seconds: 60 * Int64(minute))!.date
        q.call = "X" + String(minute)
        q.freqHz = hz
        q.mode = .cw
        q.runMode = rm
        return q
    }

    private static func log() -> [Qso] {
        var l: [Qso] = []
        for m in 0..<10 {
            l.append(qso(m, 14_025_000 + m * 100, .run))
        }
        l.append(qso(15, 14_030_000, .searchAndPounce))
        l.append(qso(80, 7_010_000, .run))
        l.append(qso(82, 7_010_000, .run))
        return l
    }

    @Test func bestRate() throws {
        let r = try #require(RateReports.bestRate(Self.log(), 10))
        #expect(r.qsos == 10)
        #expect(try r.perHour() == 60)
        #expect(RateReports.bestRate(Self.log(), 60)?.qsos == 11)
        #expect(RateReports.bestRate([], 10) == nil)
    }

    @Test func offTimesAndRuns() {
        let off = RateReports.offTimes(Self.log(), 30)
        #expect(off.count == 1)
        #expect(off.first?.minutes() == 65)

        let runs = RateReports.runs(Self.log(), 2)
        #expect(runs.count == 2)
        #expect(runs.first?.band == "20m")
        #expect(runs.first?.qsos == 10)
        #expect(runs.last?.qsos == 2)
    }
}
