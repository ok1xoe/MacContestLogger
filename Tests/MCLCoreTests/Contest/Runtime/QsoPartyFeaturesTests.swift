import Foundation
import Testing
@testable import MCLCore

/// Port of the Java `QsoPartyFeaturesTest` (9): TOUR (sessions), rover / county line (my county)
/// and bonus stations (QSO party).
///
/// Two Java tests go through the real `ContestReplay.replay(session, qsos)`.
@Suite struct QsoPartyFeaturesTests {

    static let qsoParty = """
        schemaVersion: 1
        id: test-qp
        metadata: { name: "Test QSO Party" }
        bands: [80m, 40m, 20m]
        modes: [CW, SSB]
        exchange:
          sent:
            - { id: rst, type: RST,  source: AUTO_RST }
            - { id: qth, type: TEXT, source: ROVER_QTH }
          received:
            - { id: rst,  type: RST,  required: true }
            - { id: cnty, type: TEXT, required: true }
        scoring:
          qsoPoints: { mode: FIRST_MATCH, default: 1 }
          bonuses:
            - { id: bonus, when: { bonusStation: true }, value: { fixed: 100 }, scope: PER_BAND_MODE }
          total: "qsoPoints + bonusPoints"
        dupe: { scope: PER_BAND_MODE }
        cabrillo: { contestName: TEST-QP, sentOrder: [rst, qth], receivedOrder: [rst, cnty] }
        """

    /// `2026-11-28T12:05:00Z`.
    static let t0: Int64 = 1_795_867_500

    private func session() throws -> ContestSession {
        try SessionFixture.session(Self.qsoParty, myCall: "W1AW", myGrid: nil)
    }

    private static func exch(_ cnty: String) -> JavaLinkedMap<String> {
        SessionFixture.raw(("rst", "599"), ("cnty", cnty))
    }

    private static func log(_ s: ContestSession, _ call: String, _ at: Int64,
                            _ ownQth: String? = nil) throws -> ContestSession.LogResult {
        try s.log(call: call, band: "20m", mode: "CW", receivedRaw: exch("ESX"), atEpochSecond: at, ownQth: ownQth)
    }

    // MARK: - TOUR

    @Test func withoutTourSameCallIsDupeAllContest() throws {
        let s = try session()
        _ = try Self.log(s, "K1ABC", Self.t0)

        #expect(try Self.log(s, "K1ABC", Self.t0 + 3_600).dupe)
    }

    @Test func tourAllowsSameStationInEachSession() throws {
        let s = try session()
        s.setTour(Tour.parse("1200/30"))
        #expect(s.tour != nil)

        #expect(try !Self.log(s, "K1ABC", Self.t0).dupe)
        #expect(try Self.log(s, "K1ABC", Self.t0 + 600).dupe, "same session")
        #expect(try !Self.log(s, "K1ABC", Self.t0 + 1_800).dupe, "next session")
        #expect(try s.score().qsoPoints == 2)
    }

    @Test func replayRespectsQsoTimestampsWithTour() throws {
        let s = try session()
        s.setTour(Tour.parse("1200/30"))
        #expect(s.tour != nil)
        let a = Self.qso("K1ABC", Self.t0, "")
        let b = Self.qso("K1ABC", Self.t0 + 1_800, "")

        let out = ContestReplay.replay(s, [a, b])
        #expect(out.replayed == 2)
        #expect(out.skipped == 0)

        #expect(try s.score().qsoPoints == 2, "each session is counted")
    }

    // MARK: - rover / county line

    @Test func roverFromNewCountyCanWorkSameStationAgain() throws {
        let s = try session()

        #expect(try !Self.log(s, "K1ABC", Self.t0, "HAM").dupe)
        #expect(try Self.log(s, "K1ABC", Self.t0 + 60, "HAM").dupe)
        #expect(try !Self.log(s, "K1ABC", Self.t0 + 120, "FRA").dupe, "new county")
    }

    @Test func ownQthIsReadFromStoredSentExchange() throws {
        let s = try session()

        #expect(s.ownQthFromSent("599 DAD") == "DAD")
        #expect(s.ownQthFromSent("599 -") == nil)
        #expect(s.ownQthFromSent(nil) == nil)
    }

    @Test func replayOfCountyLineCopiesCountsEachCounty() throws {
        // County line: one QSO written once for each of my counties.
        let s = try session()
        let dad = Self.qso("K1ABC", Self.t0, "599 DAD")
        let jef = Self.qso("K1ABC", Self.t0, "599 JEF")

        let out = ContestReplay.replay(s, [dad, jef])
        #expect(out.replayed == 2)
        #expect(out.skipped == 0)

        #expect(try s.score().qsoPoints == 2)
    }

    // MARK: - bonus stations

    @Test func bonusStationAddsBonusOncePerBandMode() throws {
        let s = try session()
        s.setBonusStations(["K1BON"])

        _ = try Self.log(s, "K1BON", Self.t0)
        _ = try s.log(call: "K1BON/M", band: "40m", mode: "CW", receivedRaw: Self.exch("ESX"),
                      atEpochSecond: Self.t0 + 60, ownQth: nil)   // callsign variations apply
        _ = try Self.log(s, "K1BON", Self.t0 + 120)   // dupe → no bonus
        _ = try Self.log(s, "K1ABC", Self.t0 + 180)   // not a bonus station

        #expect(try s.score().bonusPoints == 200)
        #expect(try s.score().total == 3 + 200)
    }

    @Test func withoutListNoBonus() throws {
        let s = try session()
        _ = try Self.log(s, "K1BON", Self.t0)

        #expect(try s.score().bonusPoints == 0)
    }

    @Test func baseCallStripsPortableSuffixesKeepsForeignPrefix() {
        #expect(ContestSession.baseCall("w1aw/m") == "W1AW")
        #expect(ContestSession.baseCall("OK/DL1ABC/P") == "DL1ABC")
        #expect(ContestSession.baseCall("K1ABC/ESX") == "K1ABC")
    }

    // MARK: - helpers

    private static func qso(_ call: String, _ at: Int64, _ exchangeSent: String) -> Qso {
        var q = Qso()
        q.call = call
        q.timestampUtc = Date(timeIntervalSince1970: TimeInterval(at))
        q.freqHz = 14_025_000
        q.mode = .cw
        q.exchangeRcvd = "599 ESX"
        q.exchangeSent = exchangeSent
        return q
    }
}
