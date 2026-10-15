import Foundation
import Testing
@testable import MCLCore

/// The first-weekend-of-May QSO parties: 7QP, Indiana and Delaware on their own (in-state / out-of-state by the ARRL
/// section) and N1MM's combined log of all four with New England (IN7QPNE), where the received county decides the party,
/// its points and its multiplier, and each party is scored on its own (`scoring.parts`).
@Suite struct CombinedQsoPartiesTests {

    private static let at = Date(timeIntervalSince1970: 1_795_867_500)

    private static func session(_ id: String, myCall: String, section: String?) throws -> ContestSession {
        let dxcc = try SessionFixture.dxcc()
        let root: URL = PublishedContestDataTests.root
        let registry = try MultiplierSetRegistry(dxcc: dxcc).loadDir(root.appendingPathComponent("multipliers"))
        let definition = try ContestDefinitionLoader.loadFile(root.appendingPathComponent("contests/\(id).yaml"))
        return ContestSession(definition: definition, dxcc: dxcc, registry: registry, myCall: myCall,
                              mySection: section)
    }

    /// Logs one entry like the entry window: a county line (`ORDES/JEF`) becomes one QSO per county.
    @discardableResult
    private static func log(_ session: ContestSession, _ call: String, _ qth: String, band: String = "20m",
                            mode: String = "CW") throws -> [ContestSession.LogResult] {
        try ExchangeSplit.parts(qth).map { county in
            try session.log(call: call, band: band, mode: mode,
                            receivedRaw: SessionFixture.raw(("rst", mode == "CW" ? "599" : "59"), ("qth", county)),
                            at: at)
        }
    }

    @Test func countySetsMatchTheSponsorLists() throws {
        let dxcc = try SessionFixture.dxcc()
        let registry = try MultiplierSetRegistry(dxcc: dxcc)
            .loadDir(PublishedContestDataTests.root.appendingPathComponent("multipliers"))
        let seven = try registry.get("sevenqp_counties").values.compactMap(\.key)
        #expect(seven.count == 259)
        let byState = Dictionary(grouping: seven, by: { String($0.prefix(2)) }).mapValues(\.count)
        #expect(byState == ["AZ": 15, "ID": 44, "MT": 56, "NV": 17, "OR": 36, "UT": 29, "WA": 39, "WY": 23])
        #expect(try registry.get("inqp_counties").values.count == 92)
        #expect(try registry.get("deqp_counties").values.compactMap(\.key) == ["NDE", "KDE", "SDE"])
        let qth = try registry.get("qp_weekend_qth")
        #expect(qth.values.count == 63, "50 states and 13 provinces; the counties are spellings of their state")
        for (county, state) in [("ORDES", "OR"), ("INMRN", "IN"), ("MAMID", "MA"), ("NDE", "DE"), ("DC", "MD")] {
            #expect(qth.normalize(county).key == state, "\(county)")
        }
    }

    @Test func combinedLogScoresEachPartyByItsOwnRules() throws {
        let s = try Self.session("combined-qso-parties-may", myCall: "W2XYZ", section: "ENY")
        try Self.log(s, "K7ABC", "ORDES")
        try Self.log(s, "K7ABC", "ORDES", mode: "SSB")
        try Self.log(s, "W9ABC", "INMRN")
        try Self.log(s, "W9ABC", "INMRN", band: "40m", mode: "SSB")
        try Self.log(s, "W1ABC", "MAMID")
        try Self.log(s, "W1ABC", "MAMID", band: "40m", mode: "SSB")
        try Self.log(s, "W3ABC", "NDE", mode: "SSB")
        try Self.log(s, "W3ABC", "NDE", band: "40m")
        let florida = try Self.log(s, "W4XYZ", "FL")
        #expect(florida.allSatisfy { !$0.workable }, "only stations of the four parties count")

        let score = try s.score()
        #expect(score.parts.map(\.label) == ["7QP", "Indiana", "New England", "Delaware"])
        #expect(score.parts.map(\.qsoPoints) == [5, 4, 3, 30])
        #expect(score.parts.map(\.multTotal) == [1, 2, 1, 2], "IN once per mode, DE once per band")
        #expect(score.parts.map(\.total) == [5, 8, 3, 60])
        #expect(score.total == 76)

        s.setPowerCategory("QRP")
        #expect(try s.score().total == 5 + 8 + 3 + 180, "the Delaware power factor applies to Delaware only")
    }

    @Test func countyLineShorthandLogsOneQsoPerCounty() throws {
        let s = try Self.session("combined-qso-parties-may", myCall: "W2XYZ", section: "ENY")
        let sameState = try Self.log(s, "N7XU", "ORDES/JEF")
        #expect(sameState.map { $0.context.fieldRaw("qth") } == ["ORDES", "ORJEF"])
        let twoStates = try Self.log(s, "K7ABC", "IDFRA/UTCAC")
        #expect(twoStates.map { $0.context.fieldRaw("qth") } == ["IDFRA", "UTCAC"])
        let indiana = try Self.log(s, "W9ABC", "INMRN/HAM")
        #expect(indiana.map { $0.context.fieldRaw("qth") } == ["INMRN", "INHAM"])
        let score = try s.score()
        #expect(score.parts[0].qsoCount == 4 && score.parts[0].multTotal == 4)
        #expect(score.parts[1].multTotal == 2)
    }

    @Test func sevenQpOutOfStateCountsCountiesAndInStateCountsStates() throws {
        let outside = try Self.session("7th-area-qso-party", myCall: "W2XYZ", section: "ENY")
        try Self.log(outside, "K7ABC", "ORDES")
        try Self.log(outside, "K7ABC", "ORDES", mode: "SSB")
        try Self.log(outside, "K7XYZ", "WAKNG", mode: "RTTY")
        #expect(try !Self.log(outside, "W9ABC", "INMRN")[0].workable)
        #expect(try outside.score().qsoPoints == 3 + 2 + 4)
        #expect(try outside.score().total == 9 * 2)

        let inside = try Self.session("7th-area-qso-party", myCall: "K7ABC", section: "OR")
        try Self.log(inside, "W1AW", "CT")
        try Self.log(inside, "K7XYZ", "ORJEF")
        try Self.log(inside, "W9ABC", "INMRN")
        try Self.log(inside, "W1ABC", "MAMID")
        try Self.log(inside, "DL1ABC", "DX")
        try Self.log(inside, "OK1ABC", "DX")
        let score = try inside.score()
        #expect(score.multByGroup["states"] == 4, "CT, OR, IN and MA: party counties count as their state")
        #expect(score.multByGroup["countries"] == 2)
        #expect(score.total == 6 * 3 * (4 + 2))
        // At most 10 DXCC countries count.
        let capped = try ScoreEngine.compute(inside.definition, qsoPoints: 100, bonusPoints: 0, qtcPoints: 0,
                                             qsoCount: 40, tracker: Counts(["states": 5, "countries": 12]))
        #expect(capped.total == 100 * (5 + 10))
    }

    /// Fixed multiplier counts per binding.
    private struct Counts: MultiplierCounts {
        let byBinding: [String: Int32]
        init(_ byBinding: [String: Int32]) { self.byBinding = byBinding }
        func distinctForBinding(_ bindingId: String?) -> Int32 { byBinding[bindingId ?? ""] ?? 0 }
        func weightedForBinding(_ bindingId: String?, _ bandWeights: YamlOrderedMap<Int>) -> Int32 {
            distinctForBinding(bindingId)
        }
        func totalDistinct() -> Int32 { byBinding.values.reduce(0, +) }
    }

    @Test func indianaCountsCountiesPerModeAndOtherStatesInside() throws {
        let inside = try Self.session("indiana-qso-party", myCall: "W9ABC", section: "IN")
        try Self.log(inside, "W1AW", "CT")
        try Self.log(inside, "W9XYZ", "INMRN")
        try Self.log(inside, "W9XYZ", "INMRN", mode: "SSB")
        try Self.log(inside, "DL1ABC", "DX")
        let score = try inside.score()
        #expect(score.qsoPoints == 8)
        #expect(score.multTotal == 3, "CT and Marion county on CW and on phone; no DX multipliers")

        let outside = try Self.session("indiana-qso-party", myCall: "W2XYZ", section: "ENY")
        #expect(try !Self.log(outside, "K7ABC", "ORDES")[0].workable)
        try Self.log(outside, "W9XYZ", "INMRN")
        #expect(try outside.score().total == 2)
    }

    @Test func delawarePointsBandMultipliersAndPower() throws {
        let outside = try Self.session("delaware-qso-party", myCall: "W2XYZ", section: "ENY")
        outside.setPowerCategory("QRP")
        try Self.log(outside, "W3ABC", "NDE", mode: "SSB")
        try Self.log(outside, "W3ABC", "NDE", band: "40m")
        try Self.log(outside, "W3XYZ", "KDE", band: "40m")
        let out = try outside.score()
        #expect(out.qsoPoints == 50)
        #expect(out.multTotal == 3)
        #expect(out.total == 50 * 3 * 3)

        let inside = try Self.session("delaware-qso-party", myCall: "W3ABC", section: "DE")
        try Self.log(inside, "W1AW", "CT", mode: "SSB")
        try Self.log(inside, "W3XYZ", "KDE")
        try Self.log(inside, "DL1ABC", "DX")
        let score = try inside.score()
        #expect(score.qsoPoints == 5)
        #expect(score.multTotal == 2, "CT and Germany; another Delaware station scores points only")
    }

    @Test func scoreCheckRecomputesAHandMadeCombinedCabrilloLog() throws {
        let dxcc = try SessionFixture.dxcc()
        let root: URL = PublishedContestDataTests.root
        let registry = try MultiplierSetRegistry(dxcc: dxcc).loadDir(root.appendingPathComponent("multipliers"))
        let definitions = try ContestCatalog.fromDir(root.appendingPathComponent("contests"))
        let log = """
            START-OF-LOG: 3.0
            CONTEST: IN7QPNE
            CALLSIGN: W2XYZ
            CATEGORY-POWER: QRP
            CLAIMED-SCORE: 196
            QSO: 14025 CW 2026-05-02 1400 W2XYZ 599 NY K7ABC 599 ORDES
            QSO: 14250 PH 2026-05-02 1410 W2XYZ 59 NY K7ABC 59 ORDES
            QSO: 14030 CW 2026-05-02 1600 W2XYZ 599 NY W9ABC 599 INMRN
            QSO: 7190 PH 2026-05-02 1610 W2XYZ 59 NY W9ABC 59 INMRN
            QSO: 14035 CW 2026-05-02 2100 W2XYZ 599 NY W1ABC 599 MAMID
            QSO: 7200 PH 2026-05-02 2110 W2XYZ 59 NY W1ABC 59 MAMID
            QSO: 14260 PH 2026-05-02 1800 W2XYZ 59 NY W3ABC 59 NDE
            QSO: 7040 CW 2026-05-02 1810 W2XYZ 599 NY W3ABC 599 NDE
            QSO: 14040 CW 2026-05-02 1820 W2XYZ 599 NY W4XYZ 599 FL
            END-OF-LOG:
            """
        let result = try ScoreCheck.evaluate(fileName: "w2xyz.log", content: log, definitions: definitions,
                                             dxcc: dxcc, registry: registry)
        #expect(result.error == nil)
        #expect(result.computed == 196)
        #expect(result.pass)
    }
}
