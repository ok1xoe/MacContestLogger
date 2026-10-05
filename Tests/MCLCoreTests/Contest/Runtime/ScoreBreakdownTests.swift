import Foundation
import Testing
@testable import MCLCore

/// Port of the Java `ScoreBreakdownTest` (1 case) + breakdown edges.
@Suite struct ScoreBreakdownTests {

    /// Java `Instant.parse("2026-11-28T12:00:00Z").plusSeconds(60L * minute)`.
    static func qso(_ minute: Int, _ call: String, _ freqHz: Int, _ exch: String, id: Int64? = nil) -> Qso {
        var q = Qso()
        q.id = id
        q.timestampUtc = Date(timeIntervalSince1970: TimeInterval(1_795_867_200 + 60 * minute))
        q.call = call
        q.freqHz = freqHz
        q.mode = .ssb
        q.exchangeRcvd = exch
        return q
    }

    static func session() throws -> ContestSession {
        try SessionFixture.session("@cq-ww-ssb.yaml")
    }

    @Test func splitsByBandAndSumsToTotal() throws {
        let session = try Self.session()
        let qsos = [
            Self.qso(0, "DL1ABC", 14_200_000, "59 14"),
            Self.qso(1, "W1AW", 14_210_000, "59 5"),
            Self.qso(2, "DL1ABC", 14_220_000, "59 14"), // dupe
            Self.qso(3, "DL1ABC", 7_150_000, "59 14"),
            Self.qso(4, "VE3XX", 7_160_000, "59 4"),
        ]

        let b = try ScoreBreakdown.compute(session, qsos)
        let order = session.definition.bands

        #expect(b.bands(order) == ["40m", "20m"], "order by definition (160 → 10)")
        let m20 = b.band("20m")
        #expect(m20.qsos == 3)
        #expect(m20.dupes == 1)
        // 20m: zones 14, 5 + countries DL, W = 4 multipliers; 40m: zones 14, 4 + DL, VE = 4.
        #expect(m20.mults("zones") == 2)
        #expect(m20.mults("countries") == 2)
        #expect(b.band("40m").multTotal == 4)
        #expect(b.total.multTotal == 8)
        #expect(b.score.multTotal == b.total.multTotal)
        #expect(b.score.qsoPoints == b.band("20m").points + b.band("40m").points)
        #expect(b.total.qsos == b.mode("SSB").qsos)
        #expect(b.rows(order).count == 2, "band × mode rows")
        #expect(b.multIds == ["zones", "countries"])
    }

    /// Decision 3: an uncounted QSO (CW in an SSB contest) is counted in the cells as in Java,
    /// so `total.qsos` is greater than `score.qsoCount`.
    @Test func notCountedQsoIsInTheCellsLikeJava() throws {
        var cw = Self.qso(1, "W1AW", 14_200_000, "59 5")
        cw.mode = .cw
        let b = try ScoreBreakdown.compute(try Self.session(), [Self.qso(0, "DL1ABC", 14_200_000, "59 14"), cw])
        #expect(b.total.qsos == 2)
        #expect(b.score.qsoCount == 1)
        #expect(b.modes == ["SSB", "CW"])
        #expect(b.mode("CW").points == 0)
    }

    /// Unknown band / mode / cell → empty cell (not `nil`), like Java `new Cell()`.
    @Test func unknownCellIsEmpty() throws {
        let b = try ScoreBreakdown.compute(try Self.session(), [])
        #expect(b.band("20m") == ScoreBreakdown.Cell())
        #expect(b.cell("20m", "SSB").qsos == 0)
        #expect(b.mode("CW").multTotal == 0)
        #expect(b.rows(nil).isEmpty)
        #expect(b.multLabel("nope") == "nope")
    }

    /// `multipliers: [~, …]`: Java NPE in `compute` (`m.id()`); Swift skips the `nil` binding
    /// (a deliberate divergence from Java v1.1.1).
    @Test func nilBindingIsSkipped() throws {
        let s = try SessionFixture.session("{id: nb, modes: [CW], multipliers: [~, {id: c, set: dxcc_entities, "
            + "from: callsign, scope: PER_BAND}], scoring: {qsoPoints: {default: 1}, total: \"qsoPoints * multTotal\"}}")
        var q = Self.qso(0, "DL1ABC", 14_025_000, "599")
        q.mode = .cw
        let b = try ScoreBreakdown.compute(s, [q])
        #expect(b.multIds == ["c"])
        #expect(b.total.mults("c") == 1)
    }

    /// A replay error (number above 2³¹−1) is only counted into `skipped` as in Java; Swift also returns it.
    @Test func replayErrorIsReported() throws {
        let b = try ScoreBreakdown.compute(try Self.session(), [Self.qso(0, "DL1ABC", 14_200_000, "59 2147483648")])
        #expect(b.skipped == 1)
        #expect(b.firstError != nil)
        #expect(b.total.qsos == 0)
    }
}
