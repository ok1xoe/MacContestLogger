import Foundation
import Testing
@testable import MCLCore

/// `PointsCalculator` — there are no Java tests (`ContestSession` covers it only indirectly), hence a
/// table measured by the maintainer-only probe (JDK 21.0.2):
/// `FIRST_MATCH`/`SUM`, missing parts, priority `fixed` > `expr` > `perKm`, `perKm`
/// (`CEIL`/`FLOOR`/`ROUND`/anything else, `min`, `max`, `factor` from `ww-digi`, `(long)` saturation
/// and the low 32 bits `(int)`), `int` sum wraparound,
/// the bonus value and the points of all 22 definitions from `contest-data` over 10 contexts.
@Suite struct PointsCalculatorTests {

    // MARK: - probe contexts and definitions

    private static func entity(_ code: Int, _ country: String, _ continent: String) -> DxccEntity {
        DxccEntity(entityCode: code, name: "N\(code)", countryCode: country, continents: [continent],
                   cq: [], itu: [], lat: .nan, lon: .nan)
    }

    private static func received(_ pairs: [(String, String)]) -> JavaLinkedMap<ExchangeValue> {
        var map = JavaLinkedMap<ExchangeValue>()
        for (key, value) in pairs {
            map.put(key, .valid(value, value))
        }
        return map
    }

    private static func ctx(_ call: String?, _ band: String?, _ mode: String?,
                            _ received: JavaLinkedMap<ExchangeValue>?, _ worked: DxccEntity?,
                            _ own: DxccEntity?, _ workedClass: String?, _ ownGrid: String?,
                            _ ownItuZone: String?) -> QsoContext {
        QsoContext(call: call, band: band, mode: mode, received: received, workedEntity: worked,
                   ownEntity: own, workedClass: workedClass, ownGrid: ownGrid, ownItuZone: ownItuZone)
    }

    /// Probe contexts under the same descriptions (`ProbeScore.main`).
    static let contexts: [String: QsoContext] = {
        let ok = entity(503, "CZ", "EU")
        let dl = entity(230, "DE", "EU")
        let k = entity(291, "US", "NA")
        let ve = entity(1, "CA", "NA")
        let ja = entity(339, "JP", "AS")
        let ru = entity(54, "RU", "EU")
        var out: [String: QsoContext] = [:]
        out["okok-40m"] = ctx("OK2AA", "40m", "CW", received([("loc", "JO70"), ("grid", "JO70"), ("exch", "28")]),
                              ok, ok, "okom", "JN89", "28")
        out["dlok-20m"] = ctx("DL1AA", "20m", "SSB", received([("loc", "JO31"), ("grid", "JO31"), ("exch", "28")]),
                              dl, ok, "dx", "JN89", "28")
        out["kok-80m"] = ctx("K1AA", "80m", "CW", received([("loc", "FN31"), ("grid", "FN31"), ("exch", "8")]),
                             k, ok, "wve", "JN89", "28")
        out["kve-40m"] = ctx("K2AA", "40m", "CW", received([("exch", "DARC"), ("state", "MA")]),
                             k, ve, "wve", "FN20", "8")
        out["jaok-10m"] = ctx("JA1AA", "10m", "SSB", received([("loc", "PM95"), ("grid", "PM95"), ("exch", "45")]),
                              ja, ok, "dx", "jn89aa", "28")
        out["ruok-15m"] = ctx("UA3AA", "15m", "CW", received([("loc", "KO85"), ("grid", "KO85"), ("exch", "29")]),
                              ru, ok, "ru", "JN89", "28")
        out["empty"] = ctx(nil, nil, nil, nil, nil, nil, nil, nil, nil)
        var nullKey = received([("loc", "XX99"), ("exch", "7")])
        nullKey.put(nil, .valid("JO70", "JO70"))
        nullKey.put("grid", nil)
        out["nullkey"] = ctx("OK1AA", "20m", "CW", nullKey, ok, ok, nil, "JN89", nil)
        out["no-own-grid"] = ctx("OK1AB", "20m", "CW", received([("loc", "JO70"), ("grid", "JO70")]),
                                 ok, ok, nil, nil, nil)
        out["same-grid"] = ctx("OK1AC", "2m", "CW", received([("loc", "JN89"), ("grid", "JN89")]),
                               ok, ok, nil, "JN89", nil)
        return out
    }()

    static func contestsDirectory() throws -> URL {
        let root = try #require(Bundle.module.url(forResource: "contest-data", withExtension: nil))
        return root.appendingPathComponent("contests")
    }

    /// A case definition: `@<file>` from the fixtures `contest-data/contests`, otherwise YAML from the table.
    static func definition(_ name: String) throws -> ContestDefinition {
        if name.hasPrefix("@") {
            let file = try contestsDirectory().appendingPathComponent(String(name.dropFirst()))
            return try ContestDefinitionLoader.loadFile(file)
        }
        let yaml = try #require(ScoreMeasured.yaml.first { $0.0 == name }?.1, "missing YAML for case \(name)")
        return try ContestDefinitionLoader.load(Data(yaml.utf8))
    }

    private static func outcome(_ body: () throws(ExpressionError) -> Int32) -> ScoreMeasured.Outcome {
        do {
            return .value(try body())
        } catch {
            return .error(error.kind, error.message)
        }
    }

    // MARK: - measured table (ScoreMeasured)

    /// Cases where Java fails with an NPE (a `null` element of `qsoPoints.rules`): Swift skips the element
    /// ("`nil` points rule"). The value does not depend on the context.
    static let lenientPoints: [String: Int32] = [
        "rules-nil-only": 9,             // the only rule is nil → nothing matches → default
        "rules-nil-only-sum": 9,         // SUM without a valid rule → default
        "rules-nil-first": 4,            // nil skipped, the next rule matches
        "rules-nil-after-match-sum": 4,  // SUM reaches nil only after summing
        "rules-nil-before-none": 9,      // nil skipped, RTTY does not match → default
        "rules-nil-after-miss": 9,       // outside SSB it reaches nil (Java NPE) → default
    ]

    @Test(arguments: ScoreMeasured.points)
    func pointsMatchJava(_ row: ScoreMeasured.Row) throws {
        let definition = try Self.definition(row.name)
        let context = try #require(Self.contexts[row.context])
        let swift = Self.outcome { () throws(ExpressionError) -> Int32 in
            try PointsCalculator.points(definition, context)
        }
        if row.java == .npe {
            let lenient = try #require(Self.lenientPoints[row.name], "NPE row without a pinned value")
            #expect(swift == .value(lenient))
        } else {
            #expect(swift == row.java)
        }
    }

    @Test(arguments: ScoreMeasured.bonusValues)
    func bonusValueMatchesJava(_ row: ScoreMeasured.Row) throws {
        let definition = try Self.definition(row.name)
        let bonus = try #require(definition.scoring?.bonuses?.first ?? nil)
        let context = try #require(Self.contexts[row.context])
        let swift = Self.outcome { () throws(ExpressionError) -> Int32 in
            try PointsCalculator.value(bonus.value, context)
        }
        #expect(swift == row.java)
    }

    /// Every definition from contest-data has measured points over all contexts and every row
    /// of the table has a context (guards that neither the set of definitions nor of contexts drifted from the probe).
    @Test func everyContestDefinitionAndContextIsMeasured() throws {
        let files = try FileManager.default.contentsOfDirectory(atPath: Self.contestsDirectory().path)
            .filter { $0.hasSuffix(".yaml") }
        #expect(files.count == 22)
        for file in files {
            let measured = Set(ScoreMeasured.points.filter { $0.name == "@" + file }.map(\.context))
            #expect(measured == Set(Self.contexts.keys), "\(file)")
        }
        for row in ScoreMeasured.points + ScoreMeasured.bonusValues {
            #expect(Self.contexts[row.context] != nil, "\(row)")
        }
    }

    // MARK: - nil elements (pinned outside the table)

    private static func sumDefinition(_ values: [Int]) -> ContestDefinition {
        var definition = ContestDefinition(id: "t")
        let rules: [ContestDefinition.PointRule?] = values.map {
            ContestDefinition.PointRule(when: nil, value: .init(fixed: $0, expr: nil, perKm: nil))
        }
        definition.scoring = .init(qsoPoints: .init(mode: .SUM, defaultValue: 0, rules: rules),
                                   bonuses: nil, total: nil)
        return definition
    }

    /// The `SUM` total over 2³¹ wraps like a Java `int` (2e9 + 2e9 → −294967296), it does not crash.
    @Test func sumPastInt32WrapsLikeJavaInt() throws {
        let context = try #require(Self.contexts["empty"])
        #expect(try PointsCalculator.points(Self.sumDefinition([2_000_000_000, 2_000_000_000]), context)
                == -294_967_296)
        #expect(try PointsCalculator.points(Self.sumDefinition([Int(Int32.max), 1]), context) == Int32.min)
        #expect(try PointsCalculator.points(Self.sumDefinition([Int(Int32.min), -1]), context) == Int32.max)
    }

    /// A `null` element of `qsoPoints.rules`: Java NPE, Swift skips it (a deliberate divergence from Java v1.1.1).
    @Test func nilRuleIsSkipped() throws {
        let context = try #require(Self.contexts["okok-40m"])
        var definition = Self.sumDefinition([3])
        definition.scoring?.qsoPoints?.rules = [nil, .init(when: nil, value: .init(fixed: 3, expr: nil, perKm: nil)), nil]
        #expect(try PointsCalculator.points(definition, context) == 3)
        definition.scoring?.qsoPoints?.mode = .FIRST_MATCH
        #expect(try PointsCalculator.points(definition, context) == 3)
        definition.scoring?.qsoPoints?.rules = [nil]
        definition.scoring?.qsoPoints?.defaultValue = 9
        #expect(try PointsCalculator.points(definition, context) == 9)
    }
}
