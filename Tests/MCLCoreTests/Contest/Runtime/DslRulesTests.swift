import Foundation
import Testing
@testable import MCLCore

/// The Swift-only definition rules that cover N1MM UDC parameters: `timeBetween`, `qsoPoints.factors`
/// (PointsMultAtTime / ByBand / ByMode), `scoring.powerFactor` (PowerMult), multiplier `when` (CountMultOnlyFor,
/// DoNotCountMeAsMult), `dupe.none` / `reworkMinutes` / `byField` (DupeType 4, DupeQSOMinutesAgo, DupeSqlString) and
/// `period.sessions.resetMultipliers` (ResetMultsEverySession).
@Suite struct DslRulesTests {

    /// `2026-11-28T12:05:00Z`.
    static let t0: Int64 = 1_795_867_500

    private static func definition(scoring: String = "qsoPoints: { mode: FIRST_MATCH, default: 1 }\n  total: \"qsoPoints * multTotal\"",
                                   multipliers: String = "[ { id: c, set: dxcc_entities, from: callsign, scope: PER_BAND } ]",
                                   dupe: String = "{ scope: PER_BAND }", period: String = "") -> String {
        """
        schemaVersion: 1
        id: dsl-test
        metadata: { name: "DSL test" }
        \(period)
        bands: [80m, 40m, 20m]
        modes: [CW, SSB]
        exchange:
          sent:
            - { id: rst, type: RST, source: AUTO_RST }
          received:
            - { id: rst, type: RST, required: true }
            - { id: qth, type: TEXT }
        scoring:
          \(scoring)
        multipliers: \(multipliers)
        dupe: \(dupe)
        """
    }

    private static func log(_ s: ContestSession, _ call: String, _ at: Int64, band: String = "20m",
                            mode: String = "CW", qth: String = "") throws -> ContestSession.LogResult {
        try s.log(call: call, band: band, mode: mode, receivedRaw: SessionFixture.raw(("rst", "599"), ("qth", qth)),
                  atEpochSecond: at)
    }

    @Test func timeWindows() throws {
        func at(_ hhmm: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(1_795_824_000 + (hhmm / 100) * 3600 + (hhmm % 100) * 60)) }
        #expect(ConditionEvaluator.inWindow("0000-0559", at(559)))
        #expect(!ConditionEvaluator.inWindow("0000-0559", at(600)))
        #expect(ConditionEvaluator.inWindow("2200-0159", at(2330)))
        #expect(ConditionEvaluator.inWindow("2200-0159", at(100)))
        #expect(!ConditionEvaluator.inWindow("2200-0159", at(1200)))
        #expect(!ConditionEvaluator.inWindow("2500-0100", at(0)))
        #expect(ConditionEvaluator.parseWindow("12:00-13:00") == nil)
    }

    @Test func pointFactorsMultiply() throws {
        let s = try SessionFixture.session(Self.definition(scoring: """
            qsoPoints:
                mode: FIRST_MATCH
                default: 2
                factors:
                  - { when: { timeBetween: "1200-1259" }, factor: 2 }
                  - { when: { bandIn: [80m] }, factor: 3 }
                  - { when: { mode: SSB }, factor: 0.5 }
              total: "qsoPoints"
            """))
        #expect(try Self.log(s, "DL1ABC", Self.t0).points == 4)
        #expect(try Self.log(s, "DL2ABC", Self.t0 + 3_600).points == 2)
        #expect(try Self.log(s, "DL3ABC", Self.t0, band: "80m").points == 12)
        #expect(try Self.log(s, "DL4ABC", Self.t0 + 3_600, mode: "SSB").points == 1)
    }

    @Test func powerFactorMultipliesTheScore() throws {
        let s = try SessionFixture.session(Self.definition(scoring: """
            qsoPoints: { mode: FIRST_MATCH, default: 1 }
              total: "qsoPoints * multTotal"
              powerFactor: { HIGH: 1, LOW: 2, QRP: 4 }
            """))
        _ = try Self.log(s, "DL1ABC", Self.t0)
        _ = try Self.log(s, "W1AW", Self.t0 + 60)
        #expect(try s.score().total == 4, "no category = ×1")
        s.setPowerCategory("QRP")
        #expect(try s.score().total == 16)
        s.setPowerCategory("low")
        #expect(try s.score().total == 8)
        let n1mmKeys = ContestDefinition.Scoring(qsoPoints: nil, bonuses: nil, total: nil,
                                                 powerFactor: Self.map(["HP": 1, "LP": 3]))
        #expect(n1mmKeys.powerFactorFor("LOW") == 3)
        #expect(n1mmKeys.powerFactorFor("QRP") == 1)
    }

    private static func map(_ values: [String: Int]) -> YamlOrderedMap<Int> {
        var out = YamlOrderedMap<Int>()
        for (key, value) in values.sorted(by: { $0.key < $1.key }) {
            out.set(key, value)
        }
        return out
    }

    @Test func multiplierCondition() throws {
        let s = try SessionFixture.session(Self.definition(multipliers: """
            [ { id: c, set: dxcc_entities, from: callsign, scope: PER_BAND, when: { not: { ownDxcc: true } } } ]
            """))
        let own = try Self.log(s, "OK1ABC", Self.t0)
        #expect(own.multipliers.isEmpty, "my own country is no multiplier")
        let other = try Self.log(s, "DL1ABC", Self.t0 + 60)
        #expect(SessionFixture.newMultipliers(other) == 1)
    }

    @Test func noDupeCheck() throws {
        let s = try SessionFixture.session(Self.definition(dupe: "{ scope: PER_BAND, none: true }"))
        #expect(try !Self.log(s, "DL1ABC", Self.t0).dupe)
        #expect(try !Self.log(s, "DL1ABC", Self.t0 + 60).dupe)
        #expect(try s.score().qsoPoints == 2)
    }

    @Test func reworkAfterMinutes() throws {
        let s = try SessionFixture.session(Self.definition(dupe: "{ scope: PER_BAND, reworkMinutes: 30 }"))
        #expect(try !Self.log(s, "DL1ABC", Self.t0).dupe)
        #expect(try Self.log(s, "DL1ABC", Self.t0 + 29 * 60).dupe)
        #expect(try !Self.log(s, "DL1ABC", Self.t0 + 31 * 60).dupe, "30 minutes after the QSO that counted")
        #expect(try Self.log(s, "DL1ABC", Self.t0 + 40 * 60).dupe, "counted from the last QSO that counted")
        #expect(try !Self.log(s, "DL1ABC", Self.t0 + 40 * 60, band: "40m").dupe)
        var checker = ContestDupeChecker(scope: .PER_BAND, reworkMinutes: 30)
        let context = QsoContext(call: "W1AW", band: "20m", mode: "CW", received: nil, workedEntity: nil,
                                 ownEntity: nil, workedClass: nil)
        checker.add(context, atEpochSecond: Self.t0)
        #expect(checker.minutesUntilRework(context, atEpochSecond: Self.t0 + 600) == 20)
        #expect(checker.minutesUntilRework(context, atEpochSecond: Self.t0 + 1_800) == nil)
    }

    @Test func dupeByField() throws {
        let s = try SessionFixture.session(Self.definition(dupe: "{ scope: PER_BAND, byField: qth }"))
        #expect(try !Self.log(s, "W1AW", Self.t0, qth: "ESX").dupe)
        #expect(try Self.log(s, "W1AW", Self.t0 + 60, qth: "ESX").dupe)
        #expect(try !Self.log(s, "W1AW", Self.t0 + 120, qth: "MID").dupe, "a mobile in another county")
    }

    @Test func multipliersResetEverySession() throws {
        let yaml = Self.definition(period: "period: { durationHours: 2, sessions: { start: \"1200\", minutes: 30, resetMultipliers: true } }")
        let s = try SessionFixture.session(yaml)
        s.setTour(Tour.fromDefinition(try SessionFixture.definition(yaml)))
        #expect(SessionFixture.newMultipliers(try Self.log(s, "DL1ABC", Self.t0)) == 1)
        #expect(SessionFixture.newMultipliers(try Self.log(s, "DL2ABC", Self.t0 + 60)) == 0)
        #expect(SessionFixture.newMultipliers(try Self.log(s, "DL3ABC", Self.t0 + 1_800)) == 1, "next session")
        #expect(try s.score().multTotal == 2)
        let plain = try SessionFixture.session(Self.definition())
        plain.setTour(Tour.parse("1200/30"))
        _ = try Self.log(plain, "DL1ABC", Self.t0)
        #expect(SessionFixture.newMultipliers(try Self.log(plain, "DL3ABC", Self.t0 + 1_800)) == 0)
    }

    /// N1MM `Exchange, *` and `IsMisc, n` need no new key: an expression over the field and `fieldPresent`.
    @Test func pointsFromTheExchange() throws {
        let s = try SessionFixture.session(Self.definition(scoring: """
            qsoPoints:
                mode: FIRST_MATCH
                default: 1
                rules:
                  - { when: { expr: "matches(qth, '[0-9]+')" }, value: { expr: "qth" } }
                  - { when: { fieldPresent: qth }, value: { fixed: 3 } }
              total: "qsoPoints"
            """))
        #expect(try Self.log(s, "DL1ABC", Self.t0, qth: "7").points == 7)
        #expect(try Self.log(s, "DL2ABC", Self.t0, qth: "ESX").points == 3)
        #expect(try Self.log(s, "DL3ABC", Self.t0).points == 1)
    }

    @Test func newKeysAreRead() throws {
        let definition = try SessionFixture.definition(Self.definition(
            dupe: "{ scope: ONCE, none: false, reworkMinutes: 10, byField: qth }",
            period: "period: { durationHours: 2, sessions: { start: \"1200\", minutes: 30, resetMultipliers: true } }"))
        #expect(definition.dupe == ContestDefinition.Dupe(scope: .ONCE, dupeWorthZero: nil, none: false,
                                                          reworkMinutes: 10, byField: "qth"))
        #expect(definition.period?.sessions?.resetMultipliers == true)
    }

    @Test func lastCallParts() {
        #expect(LastCall.lastTwoLetters("OK1XOE") == "OE")
        #expect(LastCall.lastTwoLetters("dl1ab/p") == "AB")
        #expect(LastCall.suffix("OK1XOE") == "XOE")
        #expect(LastCall.suffix("DL0ABC/MM") == "ABC")
        #expect(LastCall.suffix(nil) == "")
        let definition = ContestDefinition(id: "x", exchange: ContestDefinition.Exchange(sent: [
            ContestDefinition.ExchangeField(id: "rst", type: .RST, required: false, source: .AUTO_RST,
                                          appliesWhen: nil, validation: nil),
            ContestDefinition.ExchangeField(id: "l2", type: .TEXT, required: false, source: .DERIVED,
                                          appliesWhen: nil, validation: nil, derive: "lastCall2L"),
            ContestDefinition.ExchangeField(id: "sf", type: .TEXT, required: false, source: .DERIVED,
                                          appliesWhen: nil, validation: nil, derive: "lastCallSuffix"),
        ], received: []))
        #expect(SentExchange.text(definition: definition, setup: nil, mode: .cw, serial: 1, roverQth: "",
                                  countyLine: [], lastCall: "W1AW") == "599 AW AW")
        #expect(SentExchange.flat(definition: definition, setup: nil, mode: .cw, serial: 1, rstSent: "",
                                  ownQth: nil, lastCall: nil) == "599 - -")
    }

    @Test func workableRestriction() throws {
        let yaml = Self.definition() + "\nworkable: { continentIs: EU }\n"
        let s = try SessionFixture.session(yaml)
        let dx = try Self.log(s, "W1AW", Self.t0)
        #expect(!dx.workable)
        #expect(dx.points == 0)
        #expect(dx.multipliers.isEmpty)
        let eu = try Self.log(s, "DL1ABC", Self.t0 + 60)
        #expect(eu.workable)
        #expect(eu.points == 1)
        #expect(try s.score().total == 1)
        #expect(try !s.preview(call: "W1AW", band: "40m", mode: "CW", receivedRaw: nil).workable)
    }

    @Test func expectedStartWeekday() throws {
        let definition = try SessionFixture.definition(Self.definition(
            period: "period: { durationHours: 24, startWeekday: SAT, startTime: \"1200\" }"))
        // 2026-11-25 is a Wednesday: the next Saturday is 2026-11-28.
        let wednesday = Date(timeIntervalSince1970: 1_795_824_000 - 3 * 86_400 + 3_600)
        let form = NewContestForm.prefill(definition: definition, saved: nil, stationCall: "OK1XOE", now: wednesday)
        #expect(form.startedAt == "2026-11-28 12:00")
        #expect(form.endedAt == "2026-11-29 12:00")
        var last = ContestSetup()
        last.startedAt = "2025-11-29 12:00"
        #expect(NewContestForm.prefill(definition: definition, saved: last, stationCall: "", now: wednesday)
            .startedAt == "2026-11-28 12:00", "last year's start is replaced")
        last.startedAt = "2026-11-28 12:00"
        last.endedAt = "2026-11-29 12:00"
        let during = Date(timeIntervalSince1970: 1_795_867_500 + 23 * 3_600)
        #expect(NewContestForm.prefill(definition: definition, saved: last, stationCall: "", now: during)
            .startedAt == "2026-11-28 12:00", "the running contest keeps its start")
        let saturday = Date(timeIntervalSince1970: 1_795_824_000 + 60)
        #expect(NewContestForm.expectedStart(definition, now: saturday) == Int64(1_795_867_200))
    }

    @Test func iotaReferenceGetsTheDash() {
        #expect(CabrilloExporter.iotaReference("EU123") == "EU-123")
        #expect(CabrilloExporter.iotaReference("EU-123") == "EU-123")
        #expect(CabrilloExporter.iotaReference("-") == "-")
    }

    @Test func numberingPerBandForMultiOp() {
        let both = ContestDefinition.Numbering(perBand: true)
        #expect(both.perBand(category: [:]))
        let multi = ContestDefinition.Numbering(perBand: true, multiOpOnly: true)
        #expect(!multi.perBand(category: ["OPERATOR": "SINGLE-OP", "TRANSMITTER": "ONE"]))
        #expect(multi.perBand(category: ["OPERATOR": "MULTI-OP", "TRANSMITTER": "UNLIMITED"]))
        var setup = ContestSetup()
        setup.firstSerial = 101
        let json = String(decoding: (try? JSONEncoder().encode(setup)) ?? Data(), as: UTF8.self)
        #expect(json.contains("\"firstSerial\":101"))
        #expect(!String(decoding: (try? JSONEncoder().encode(ContestSetup())) ?? Data(), as: UTF8.self)
            .contains("firstSerial"))
    }

    @Test func ownCountryAndEntityConditions() throws {
        let s = try SessionFixture.session(Self.definition(scoring: """
            qsoPoints:
                mode: FIRST_MATCH
                default: 1
                rules:
                  - { when: { ownDxccIn: [CZ] , entityIn: [291] }, value: { fixed: 5 } }
                  - { when: { ownEntityIn: [503] }, value: { fixed: 2 } }
              total: "qsoPoints"
            """))
        #expect(try Self.log(s, "W1AW", Self.t0).points == 5)
        #expect(try Self.log(s, "DL1ABC", Self.t0).points == 2)
        let other = try SessionFixture.session(Self.definition(scoring: """
            qsoPoints:
                mode: FIRST_MATCH
                default: 1
                rules:
                  - { when: { ownDxccIn: [US] }, value: { fixed: 9 } }
              total: "qsoPoints"
            """))
        #expect(try Self.log(other, "W1AW", Self.t0).points == 1)
    }
}
