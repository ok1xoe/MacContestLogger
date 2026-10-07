import Foundation
import Testing
@testable import MCLCore

/// „Přepočítat posledních N hodin": the window and the guarantee that a QSO in it scores exactly as in a full rescore.
@Suite struct RescoreWindowTests {

    @Test func hoursAreWholeNumbersInRange() {
        #expect(RescoreWindow.parseHours("24") == 24)
        #expect(RescoreWindow.parseHours("  6 ") == 6)
        #expect(RescoreWindow.parseHours("1") == 1)
        #expect(RescoreWindow.parseHours("8760") == 8760)
        for bad in ["", "0", "-3", "8761", "2.5", "2,5", "abc", "12h", "١٢", "+5"] {
            #expect(RescoreWindow.parseHours(bad) == nil, "\(bad)")
        }
    }

    @Test func cutoffAndMembership() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let since = RescoreWindow.cutoff(hours: 2, now: now)
        #expect(since == Date(timeIntervalSince1970: 1_000_000 - 7_200))
        var inside = Qso()
        inside.timestampUtc = since
        var outside = Qso()
        outside.timestampUtc = since.addingTimeInterval(-1)
        let untimed = Qso()
        #expect(RescoreWindow.contains(inside, since: since))
        #expect(!RescoreWindow.contains(outside, since: since))
        #expect(RescoreWindow.contains(untimed, since: since))
        var deleted = inside
        deleted.deleted = true
        #expect(RescoreWindow.count([inside, outside, deleted], since: since) == 1)
    }

    private static let t0: Int64 = 1_795_867_200

    private static func qso(_ hour: Double, _ call: String, _ freqHz: Int, _ exch: String) -> Qso {
        var q = Qso()
        q.timestampUtc = Date(timeIntervalSince1970: TimeInterval(t0) + hour * 3600)
        q.call = call
        q.freqHz = freqHz
        q.mode = .ssb
        q.exchangeRcvd = exch
        return q
    }

    /// Earlier QSOs make later ones dupes and take the multipliers the later ones would have had.
    private static func log() -> [Qso] {
        [qso(0, "DL1ABC", 14_200_000, "59 14"),
         qso(1, "W1AW", 14_210_000, "59 5"),
         qso(2, "VE3XX", 7_150_000, "59 4"),
         // in the window below
         qso(30, "DL1ABC", 14_205_000, "59 14"),   // dupe of the first QSO
         qso(31, "W1AW", 7_050_000, "59 5"),       // zone 5 already a multiplier on 20 m, new on 40 m
         qso(32, "JA1XYZ", 14_200_000, "59 25"),   // a new zone
         qso(33, "JA1XYZ", 14_210_000, "59 25")]   // a dupe within the window
    }

    @Test func windowResultsEqualTheFullRescore() throws {
        let qsos = Self.log()
        let since = Date(timeIntervalSince1970: TimeInterval(Self.t0) + 29 * 3600)

        var full: [String: ContestSession.LogResult] = [:]
        let fullOutcome = ContestReplay.replay(try SessionFixture.session("@cq-ww-ssb.yaml", myCall: "OK1XOE"), qsos) {
            full[$0.uuid + "|" + String($0.timestampUtc!.timeIntervalSince1970)] = $1
        }
        let tail = ContestReplay.replayWindow(try SessionFixture.session("@cq-ww-ssb.yaml", myCall: "OK1XOE"), qsos,
                                              since: since)

        #expect(tail.window.count == 4)
        #expect(tail.skippedInWindow == 0)
        #expect(tail.outcome.replayed == fullOutcome.replayed)
        #expect(try tail.outcome.session.score().total == fullOutcome.session.score().total)
        for entry in tail.window {
            let key = entry.qso.uuid + "|" + String(entry.qso.timestampUtc!.timeIntervalSince1970)
            let reference = try #require(full[key])
            #expect(entry.result.points == reference.points)
            #expect(entry.result.dupe == reference.dupe)
            #expect(entry.result.counted == reference.counted)
            #expect(entry.result.multipliers.count == reference.multipliers.count)
        }
        // The context matters: replaying only the window gives other results (the first QSO is not a dupe there).
        let alone = ContestReplay.replay(try SessionFixture.session("@cq-ww-ssb.yaml", myCall: "OK1XOE"),
                                         qsos.filter { RescoreWindow.contains($0, since: since) })
        #expect(try alone.session.score().total != fullOutcome.session.score().total)
        let dupes = tail.window.map(\.result.dupe)
        #expect(dupes == [true, false, false, true])
    }
}
