import Foundation
import Testing
@testable import MCLCore

/// Port of the Java `MoveMultipliersTest` (2 cases) + edges.
@Suite struct MoveMultipliersTests {

    static func qso(_ call: String, _ hz: Int, _ exch: String) -> Qso {
        ScoreBreakdownTests.qso(0, call, hz, exch)
    }

    @Test func suggestsBandsWhereStationIsNewMultiplier() throws {
        let session = try SessionFixture.session("@cq-ww-ssb.yaml")
        let w1 = Self.qso("W1AW", 14_200_000, "59 5")
        try session.replayLogged(call: "W1AW", band: "20m", mode: "SSB", exchangeRcvdFlat: "59 5", serialRcvd: nil)
        // On 40 m both zone 5 and country W (another station) are already there → a move brings nothing.
        try session.replayLogged(call: "K1ABC", band: "40m", mode: "SSB", exchangeRcvdFlat: "59 5", serialRcvd: nil)

        let c = try MoveMultipliers.candidates(session, w1, bands: ["80m", "40m", "20m", "15m"])

        #expect(c.map(\.band) == ["80m", "15m"])
        #expect(c[0].newMults == ["zones", "countries"])
    }

    @Test func dupeBandIsSkipped() throws {
        let session = try SessionFixture.session("@cq-ww-ssb.yaml")
        let w1 = Self.qso("W1AW", 14_200_000, "59 5")
        try session.replayLogged(call: "W1AW", band: "20m", mode: "SSB", exchangeRcvdFlat: "59 5", serialRcvd: nil)
        try session.replayLogged(call: "W1AW", band: "15m", mode: "SSB", exchangeRcvdFlat: "59 5", serialRcvd: nil)

        let c = try MoveMultipliers.candidates(session, w1, bands: ["20m", "15m", "10m"])

        #expect(c.map(\.band) == ["10m"])
        #expect(c[0].points > 0)
    }

    /// A QSO without a band → nothing (Java `getBand() == null`).
    @Test func qsoWithoutBandHasNoCandidates() throws {
        let session = try SessionFixture.session("@cq-ww-ssb.yaml")
        let q = Self.qso("W1AW", 0, "59 5")
        #expect(try MoveMultipliers.candidates(session, q, bands: ["80m", "15m"]).isEmpty)
    }

    /// A `nil` list or a `nil` band element: Java NPE; Swift skips them (a deliberate divergence from Java v1.1.1).
    @Test func nilBandsAreSkipped() throws {
        let session = try SessionFixture.session("@cq-ww-ssb.yaml")
        let q = Self.qso("W1AW", 14_200_000, "59 5")
        #expect(try MoveMultipliers.candidates(session, q, bands: nil).isEmpty)
        #expect(try MoveMultipliers.candidates(session, q, bands: ["80m", nil, "15m"]).map(\.band) == ["80m", "15m"])
    }

    /// A number above 2³¹−1 in the exchange: an error like Java's `NumberFormatException`, not a crash.
    @Test func overflowingExchangeThrows() throws {
        let session = try SessionFixture.session("@cq-ww-ssb.yaml")
        let q = Self.qso("W1AW", 14_200_000, "59 2147483648")
        #expect(throws: ContestSessionError.self) {
            try MoveMultipliers.candidates(session, q, bands: ["80m"])
        }
    }
}
