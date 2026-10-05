import Foundation
import Testing
@testable import MCLCore

/// Port of the Java `OperatingRulesInDefinitionTest` (2 + 6×2 = 14 cases) and new
/// edge cases of `OperatingRules.resolve` that the Java test does not cover.
@Suite struct OperatingRulesInDefinitionsTests {

    static let singleOp = ["OPERATOR": "SINGLE-OP"]
    static let singleClassic = ["OPERATOR": "SINGLE-OP", "OVERLAY": "CLASSIC"]
    static let multiOne = ["OPERATOR": "MULTI-OP", "TRANSMITTER": "ONE"]

    static let wpx = ["cq-wpx-cw.yaml", "cq-wpx-ssb.yaml"]
    static let ww = ["cq-ww-cw.yaml", "cq-ww-ssb.yaml"]
    static let cq160 = ["cq-160-cw.yaml", "cq-160-ssb.yaml"]

    private func operating(_ file: String, _ category: [String: String]) throws -> ContestDefinition.Operating? {
        let definition = try ContestDefinitionLoaderTests.bundled(file)
        return OperatingRules.resolve(definition.operating, category)
    }

    @Test(arguments: wpx)
    func wpxSingleOpMustRestTwelveHoursInBreaksOfAtLeastAnHour(file: String) throws {
        // „36 of the 48 hours – off times must be a minimum of 60 minutes"
        let resolved = try operating(file, Self.singleOp)
        #expect(resolved?.offTime?.minimumMinutes == 60)
        #expect(resolved?.offTime?.requiredMinutes == 720)
        #expect(resolved?.bandChange == nil, "Single-Op has no band-change limit")
    }

    @Test(arguments: wpx)
    func wpxMultiSingleIsLimitedToTenBandChangesPerHour(file: String) throws {
        let resolved = try operating(file, Self.multiOne)
        #expect(resolved?.bandChange?.perHour == 10)
        #expect(resolved?.bandChange?.minimumMinutes == nil,
                "WPX has a limit on the number of changes, not on the time spent on a band")
    }

    @Test(arguments: ww)
    func cqWwSingleOpHasNoOperatingLimit(file: String) throws {
        let resolved = try operating(file, Self.singleOp)
        #expect(resolved?.offTime == nil)
        #expect(resolved?.bandChange == nil)
    }

    @Test(arguments: ww)
    func cqWwClassicOverlayRestsTwentyFourHours(file: String) throws {
        let resolved = try operating(file, Self.singleClassic)
        #expect(resolved?.offTime?.minimumMinutes == 60)
        #expect(resolved?.offTime?.requiredMinutes == 1440)
    }

    @Test(arguments: ww)
    func cqWwMultiSingleMustStayTenMinutesOnABand(file: String) throws {
        #expect(try operating(file, Self.multiOne)?.bandChange?.minimumMinutes == 10)
    }

    @Test(arguments: cq160)
    func cq160AppliesTheSameOffTimeToEveryCategory(file: String) throws {
        // „Off times must be a minimum of 30 minutes in length for all categories."
        for category in [Self.singleOp, Self.multiOne] {
            let resolved = try operating(file, category)
            #expect(resolved?.offTime?.minimumMinutes == 30)
            #expect(resolved?.offTime?.requiredMinutes == 1080)
        }
    }

    @Test func definitionsWithoutVerifiedRulesCarryNone() throws {
        // Where the rules are not verified, the block is rather missing — the timers then only
        // inform instead of showing an invented limit.
        for file in ["iaru-hf.yaml", "ok-om-dx-cw.yaml", "ww-digi.yaml",
                     "dx.yaml", "cq-ww-rtty.yaml", "cq-wpx-rtty.yaml"] {
            let definition = try ContestDefinitionLoaderTests.bundled(file)
            #expect(definition.operating == nil, "\(file) has rules that nobody verified")
        }
    }

    @Test func everyDefinitionWithRulesStillValidates() throws {
        for file in ["cq-ww-cw.yaml", "cq-ww-ssb.yaml", "cq-wpx-cw.yaml",
                     "cq-wpx-ssb.yaml", "cq-160-cw.yaml", "cq-160-ssb.yaml"] {
            let definition = try ContestDefinitionLoaderTests.bundled(file)
            #expect(ContestValidator.validate(definition).isValid, Comment(rawValue: file))
        }
    }

    // MARK: - new: edge cases of resolve

    private static func map(_ pairs: [(String, String?)]) -> YamlOrderedMap<String> {
        var result = YamlOrderedMap<String>()
        for (key, value) in pairs { result.set(key, value) }
        return result
    }

    private static func operating(rules: [ContestDefinition.OperatingRule?]?,
                                  flat: Int = 1) -> ContestDefinition.Operating {
        ContestDefinition.Operating(
            offTime: .init(minimumMinutes: flat, requiredMinutes: nil), bandChange: nil, rules: rules)
    }

    private static func rule(when: YamlOrderedMap<String>?, minutes: Int) -> ContestDefinition.OperatingRule {
        .init(when: when, offTime: .init(minimumMinutes: minutes, requiredMinutes: nil), bandChange: nil)
    }

    @Test func nilOperatingResolvesToNil() {
        #expect(OperatingRules.resolve(nil, ["OPERATOR": "X"]) == nil)
    }

    @Test func emptyWhenAppliesAlways() {
        let op = Self.operating(rules: [Self.rule(when: YamlOrderedMap<String>(), minutes: 7)])
        #expect(OperatingRules.resolve(op, nil)?.offTime?.minimumMinutes == 7)
        let nilWhen = Self.operating(rules: [Self.rule(when: nil, minutes: 8)])
        #expect(OperatingRules.resolve(nilWhen, [:])?.offTime?.minimumMinutes == 8)
    }

    @Test func emptyCategoryDisablesConditionalRules() {
        let op = Self.operating(rules: [Self.rule(when: Self.map([("OPERATOR", "SINGLE-OP")]), minutes: 7)])
        #expect(OperatingRules.resolve(op, nil)?.offTime?.minimumMinutes == 1)
        #expect(OperatingRules.resolve(op, [:])?.offTime?.minimumMinutes == 1)
    }

    @Test func firstMatchingRuleWinsAndResultDropsRules() {
        let op = Self.operating(rules: [
            Self.rule(when: Self.map([("OPERATOR", "MULTI-OP")]), minutes: 5),
            Self.rule(when: Self.map([("OPERATOR", "SINGLE-OP")]), minutes: 6),
            Self.rule(when: nil, minutes: 9),
        ])
        let resolved = OperatingRules.resolve(op, ["OPERATOR": "SINGLE-OP"])
        #expect(resolved?.offTime?.minimumMinutes == 6)
        #expect(resolved?.rules == nil)
        #expect(OperatingRules.resolve(op, ["OPERATOR": "CHECKLOG"])?.offTime?.minimumMinutes == 9)
    }

    @Test func allConditionsMustMatchAndMissingKeyFails() {
        let op = Self.operating(rules: [
            Self.rule(when: Self.map([("OPERATOR", "SINGLE-OP"), ("OVERLAY", "CLASSIC")]), minutes: 7)])
        #expect(OperatingRules.resolve(op, ["OPERATOR": "SINGLE-OP"])?.offTime?.minimumMinutes == 1)
        #expect(OperatingRules.resolve(op, Self.singleClassic)?.offTime?.minimumMinutes == 7)
    }

    @Test func comparisonTrimsAndIgnoresCaseButNotNbsp() {
        let op = Self.operating(rules: [Self.rule(when: Self.map([("OPERATOR", " multi-op ")]), minutes: 7)])
        #expect(OperatingRules.resolve(op, ["OPERATOR": "Multi-Op\t"])?.offTime?.minimumMinutes == 7)
        // NBSP (U+00A0) is not trimmed by Java `trim()`, so they do not match
        #expect(OperatingRules.resolve(op, ["OPERATOR": "\u{00A0}MULTI-OP"])?.offTime?.minimumMinutes == 1)
    }

    @Test func flatValuesApplyWhenNoRuleMatches() {
        let op = Self.operating(rules: nil, flat: 3)
        #expect(OperatingRules.resolve(op, Self.singleOp)?.offTime?.minimumMinutes == 3)
    }

    // Divergences from Java (a deliberate divergence from Java v1.1.1), measured by the `ProbeOp` probe.

    @Test func nilRuleElementIsSkipped() {
        let op = Self.operating(rules: [nil, Self.rule(when: nil, minutes: 9)])
        #expect(OperatingRules.resolve(op, ["OPERATOR": "X"])?.offTime?.minimumMinutes == 9,
                "Java: NullPointerException na `rule.when()` (rules: [~])")
    }

    @Test func nilWhenValueDoesNotMatch() {
        let op = Self.operating(rules: [Self.rule(when: Self.map([("OPERATOR", nil)]), minutes: 7)])
        #expect(OperatingRules.resolve(op, ["OPERATOR": "X"])?.offTime?.minimumMinutes == 1,
                "Java: NullPointerException na `getValue().trim()` (when: {OPERATOR: ~})")
        #expect(OperatingRules.resolve(op, [:])?.offTime?.minimumMinutes == 1, "Java: no crash, flat values")
    }
}
