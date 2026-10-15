import Foundation
import Testing
@testable import MCLCore

/// `scoring.parts` (Swift-only key): several contests scored from one log (N1MM's combined same-weekend QSO parties).
/// Each part sums the points of the QSOs matching its `when`, counts its own multiplier bindings and has its own formula
/// and power factor; the score is the sum of the parts, while `total` stays the fallback of older versions.
@Suite struct ScorePartsTests {

    /// `2026-11-28T12:05:00Z`.
    static let t0: Int64 = 1_795_867_500

    static let yaml = """
        schemaVersion: 1
        id: parts-test
        metadata: { name: "Parts test" }
        bands: [80m, 40m, 20m]
        modes: [CW, SSB]
        exchange:
          sent:
            - { id: rst, type: RST, source: AUTO_RST }
          received:
            - { id: rst, type: RST, required: true }
            - { id: qth, type: TEXT, required: true }
        workable:
          anyOf:
            - { fieldMatches: { field: qth, regex: "A[A-Z]{2}" } }
            - { fieldMatches: { field: qth, regex: "B[A-Z]{2}" } }
        scoring:
          qsoPoints:
            mode: FIRST_MATCH
            default: 1
            rules:
              - { when: { fieldMatches: { field: qth, regex: "B[A-Z]{2}" } }, value: { fixed: 10 } }
          total: "qsoPoints * multTotal"
          parts:
            - { id: a, label: "Party A", when: { fieldMatches: { field: qth, regex: "A[A-Z]{2}" } }, multipliers: [ma] }
            - { id: b, when: { fieldMatches: { field: qth, regex: "B[A-Z]{2}" } }, multipliers: [mb],
                total: "qsoPoints * multTotal + 5", powerFactor: { QRP: 3, LOW: 2, HIGH: 1 } }
        multipliers:
          - { id: ma, set: dxcc_entities, from: callsign, scope: PER_BAND,
              when: { fieldMatches: { field: qth, regex: "A[A-Z]{2}" } } }
          - { id: mb, set: dxcc_entities, from: callsign, scope: ONCE,
              when: { fieldMatches: { field: qth, regex: "B[A-Z]{2}" } } }
        dupe: { scope: PER_BAND, byField: qth }
        """

    @discardableResult
    private static func log(_ s: ContestSession, _ call: String, _ qth: String, band: String = "20m",
                            minute: Int64 = 0) throws -> ContestSession.LogResult {
        try s.log(call: call, band: band, mode: "CW", receivedRaw: SessionFixture.raw(("rst", "599"), ("qth", qth)),
                  atEpochSecond: t0 + 60 * minute)
    }

    private static func logSample(_ s: ContestSession) throws {
        try log(s, "DL1ABC", "AAA")
        try log(s, "W1AW", "AAB", minute: 1)
        try log(s, "DL1ABC", "AAA", band: "40m", minute: 2)
        try log(s, "DL2XYZ", "BBB", minute: 3)
        try log(s, "W1AW", "BCC", minute: 4)
        let outside = try log(s, "W2XYZ", "ZZZ", minute: 5)
        #expect(!outside.workable)
    }

    @Test func theScoreIsTheSumOfThePartScores() throws {
        let s = try SessionFixture.session(Self.yaml)
        try Self.logSample(s)
        let score = try s.score()
        #expect(score.qsoPoints == 23)
        #expect(score.multTotal == 5)
        #expect(score.parts.map(\.label) == ["Party A", "b"], "the label, else the id")
        let a = try #require(score.parts.first)
        let b = try #require(score.parts.last)
        #expect(a.qsoCount == 3 && a.qsoPoints == 3 && a.multTotal == 3 && a.total == 9)
        #expect(b.qsoCount == 2 && b.qsoPoints == 20 && b.multTotal == 2 && b.total == 45, "its own formula")
        #expect(score.total == 54)

        s.setPowerCategory("QRP")
        let qrp = try s.score()
        #expect(qrp.parts.map(\.total) == [9, 135], "the power factor of a part multiplies that part only")
        #expect(qrp.total == 144)
    }

    @Test func aDupeCountsInItsPartWithoutPoints() throws {
        let s = try SessionFixture.session(Self.yaml)
        try Self.log(s, "DL1ABC", "AAA")
        let dupe = try Self.log(s, "DL1ABC", "AAA", minute: 1)
        #expect(dupe.dupe && dupe.points == 0)
        let a = try #require(try s.score().parts.first)
        #expect(a.qsoCount == 2 && a.qsoPoints == 1 && a.total == 1)
    }

    @Test func withoutPartsTheTotalFormulaScoresAsBefore() throws {
        // What a version without `scoring.parts` computes from the same definition: `total` alone.
        var definition = try SessionFixture.definition(Self.yaml)
        definition.scoring?.parts = nil
        let dxcc = try SessionFixture.dxcc()
        let s = ContestSession(definition: definition, dxcc: dxcc, registry: try SessionFixture.registry(dxcc),
                               myCall: "OK1XOE")
        try Self.logSample(s)
        let score = try s.score()
        #expect(score.parts.isEmpty)
        #expect(score.total == 23 * 5)
    }

    @Test func theValidatorChecksThePartReferences() throws {
        var definition = try SessionFixture.definition(Self.yaml)
        #expect(!ContestValidator.validate(definition).hasErrors)
        definition.scoring?.parts = [
            .init(id: "a", when: nil, multipliers: ["ma", "nope"]),
            .init(id: "a", when: nil, multipliers: []),
            .init(id: nil, when: nil, multipliers: []),
        ]
        let messages = ContestValidator.validate(definition).errors
        #expect(messages == [
            "část skóre 'a' odkazuje na neexistující multiplier 'nope'",
            "duplicitní id části skóre 'a'",
            "scoring.parts obsahuje část bez id",
        ])
    }

    @Test func theScoreWindowFooterListsTheParts() throws {
        let s = try SessionFixture.session(Self.yaml)
        var qsos: [Qso] = []
        for (minute, call, qth) in [(0, "DL1ABC", "AAA"), (1, "DL2XYZ", "BBB")] {
            var q = Qso()
            q.timestampUtc = Date(timeIntervalSince1970: TimeInterval(Self.t0 + Int64(60 * minute)))
            q.call = call
            q.freqHz = 14_020_000
            q.mode = .cw
            q.exchangeRcvd = "599 " + qth
            qsos.append(q)
        }
        let breakdown = try ScoreBreakdown.compute(s, qsos)
        let table = StatsViews.scoreTable(breakdown: breakdown, bandOrder: ["20m"], byMode: false)
        #expect(table.footer == "Party A: body 1 × násobiče 1 = 1  ·  b: body 10 × násobiče 1 = 15  =  skóre 16")
    }
}
