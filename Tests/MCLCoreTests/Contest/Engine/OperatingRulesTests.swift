import Testing
@testable import MCLCore

/// A 1:1 port of the Java `OperatingRulesTest` (8 cases). Overlap with
/// `OperatingRulesInDefinitionsTests` (edge tests at the bottom of the file): case 8
/// (`missingOperatingOrCategoryIsHandled`) is covered by `nil` operating and a `nil`/empty category
/// there, case 6 (flat base) and 2 (first matching) are covered by the `contest-data` definitions.
/// Case 2 `ruleMatchingTheCategoryWins` and 4 `firstMatchingRuleWins` are not covered separately there.
@Suite struct OperatingRulesTests {

    typealias Operating = ContestDefinition.Operating
    typealias OperatingRule = ContestDefinition.OperatingRule
    typealias OffTime = ContestDefinition.OffTime
    typealias BandChange = ContestDefinition.BandChange

    static let singleOp = ["OPERATOR": "SINGLE-OP", "TRANSMITTER": "ONE"]
    static let multiOne = ["OPERATOR": "MULTI-OP", "TRANSMITTER": "ONE"]
    static let multiTwo = ["OPERATOR": "MULTI-OP", "TRANSMITTER": "TWO"]

    private static func when(_ pairs: [(String, String?)]) -> YamlOrderedMap<String> {
        var map = YamlOrderedMap<String>()
        for (key, value) in pairs { map.set(key, value) }
        return map
    }

    @Test func withoutRulesTheFlatValuesApply() {
        let op = Operating(offTime: OffTime(minimumMinutes: 60, requiredMinutes: 720),
                           bandChange: BandChange(minimumMinutes: 10, perHour: 8), rules: nil)

        let resolved = OperatingRules.resolve(op, Self.singleOp)

        #expect(resolved?.offTime?.minimumMinutes == 60)
        #expect(resolved?.bandChange?.minimumMinutes == 10)
    }

    @Test func ruleMatchingTheCategoryWins() {
        // CQ WPX: the ten-minute rule applies only to Multi-Single, not to Single-Op.
        let op = Operating(offTime: nil, bandChange: nil, rules: [
            OperatingRule(when: Self.when([("OPERATOR", "SINGLE-OP")]),
                          offTime: OffTime(minimumMinutes: 60, requiredMinutes: 720), bandChange: nil),
            OperatingRule(when: Self.when([("OPERATOR", "MULTI-OP"), ("TRANSMITTER", "ONE")]),
                          offTime: nil, bandChange: BandChange(minimumMinutes: 10, perHour: nil)),
        ])

        #expect(OperatingRules.resolve(op, Self.singleOp)?.offTime?.minimumMinutes == 60)
        #expect(OperatingRules.resolve(op, Self.singleOp)?.bandChange == nil)

        #expect(OperatingRules.resolve(op, Self.multiOne)?.bandChange?.minimumMinutes == 10)
        #expect(OperatingRules.resolve(op, Self.multiOne)?.offTime == nil)
    }

    @Test func allConditionsOfARuleMustMatch() {
        let op = Operating(offTime: nil, bandChange: nil, rules: [
            OperatingRule(when: Self.when([("OPERATOR", "MULTI-OP"), ("TRANSMITTER", "ONE")]),
                          offTime: nil, bandChange: BandChange(minimumMinutes: 10, perHour: nil)),
        ])

        // Multi-Two has the same operator but a different number of transmitters — the rule does not apply.
        #expect(OperatingRules.resolve(op, Self.multiTwo)?.bandChange == nil)
    }

    @Test func firstMatchingRuleWins() {
        let op = Operating(offTime: nil, bandChange: nil, rules: [
            OperatingRule(when: Self.when([("OPERATOR", "MULTI-OP")]),
                          offTime: nil, bandChange: BandChange(minimumMinutes: 10, perHour: nil)),
            OperatingRule(when: Self.when([("OPERATOR", "MULTI-OP")]),
                          offTime: nil, bandChange: BandChange(minimumMinutes: 99, perHour: nil)),
        ])

        #expect(OperatingRules.resolve(op, Self.multiOne)?.bandChange?.minimumMinutes == 10)
    }

    @Test func ruleWithoutConditionsActsAsDefault() {
        let op = Operating(offTime: nil, bandChange: nil, rules: [
            OperatingRule(when: Self.when([("OPERATOR", "MULTI-OP")]),
                          offTime: nil, bandChange: BandChange(minimumMinutes: 10, perHour: nil)),
            OperatingRule(when: nil, offTime: OffTime(minimumMinutes: 30, requiredMinutes: nil),
                          bandChange: nil),
        ])

        #expect(OperatingRules.resolve(op, Self.singleOp)?.offTime?.minimumMinutes == 30)
    }

    @Test func flatValuesServeAsFallbackWhenNoRuleMatches() {
        let op = Operating(offTime: OffTime(minimumMinutes: 30, requiredMinutes: nil), bandChange: nil, rules: [
            OperatingRule(when: Self.when([("OPERATOR", "MULTI-OP")]),
                          offTime: nil, bandChange: BandChange(minimumMinutes: 10, perHour: nil)),
        ])

        #expect(OperatingRules.resolve(op, Self.singleOp)?.offTime?.minimumMinutes == 30)
    }

    @Test func categoryComparisonIgnoresCaseAndSpacing() {
        let op = Operating(offTime: nil, bandChange: nil, rules: [
            OperatingRule(when: Self.when([("OPERATOR", "single-op")]),
                          offTime: OffTime(minimumMinutes: 60, requiredMinutes: nil), bandChange: nil),
        ])

        #expect(OperatingRules.resolve(op, ["OPERATOR": " SINGLE-OP "])?.offTime?.minimumMinutes == 60)
    }

    @Test func missingOperatingOrCategoryIsHandled() {
        #expect(OperatingRules.resolve(nil, Self.singleOp) == nil)

        let op = Operating(offTime: OffTime(minimumMinutes: 30, requiredMinutes: nil), bandChange: nil, rules: [
            OperatingRule(when: Self.when([("OPERATOR", "MULTI-OP")]),
                          offTime: nil, bandChange: BandChange(minimumMinutes: 10, perHour: nil)),
        ])
        // Without a selected category conditional rules do not apply, but the flat base does.
        #expect(OperatingRules.resolve(op, nil)?.offTime?.minimumMinutes == 30)
        #expect(OperatingRules.resolve(op, nil)?.bandChange == nil)
    }
}
