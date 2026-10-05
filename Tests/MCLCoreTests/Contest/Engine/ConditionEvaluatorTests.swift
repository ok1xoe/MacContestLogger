import Foundation
import Testing
@testable import MCLCore

/// `ConditionEvaluator` — the ported Java `ConditionEvaluatorTest` (5 cases) and a table
/// measured by the maintainer-only probe (JDK 21.0.2):
/// each of the 17 components of `Condition`, combinators including empty ones and `[~]`, exception order.
@Suite struct ConditionEvaluatorTests {
    typealias Condition = ContestDefinition.Condition
    typealias FieldEquals = ContestDefinition.FieldEquals

    // MARK: - Java ConditionEvaluatorTest

    private static func ctx(_ ownItuZone: String, _ exchCanonical: String) -> QsoContext {
        let received = JavaLinkedMap<ExchangeValue>([("exch", .valid(exchCanonical, exchCanonical))])
        return QsoContext(call: "TEST", band: "20m", mode: "CW", received: received,
                          workedEntity: nil, ownEntity: nil, workedClass: "", ownGrid: nil,
                          ownItuZone: ownItuZone)
    }

    private static func expr(_ e: String) -> Condition {
        Condition(expr: e)
    }

    @Test func exprSameItuZoneMatches() throws {
        #expect(try ConditionEvaluator.eval(Self.expr("exch == ownItuZone"), Self.ctx("28", "28")))
    }

    @Test func exprSameItuZoneFalseWhenDifferent() throws {
        #expect(try !ConditionEvaluator.eval(Self.expr("exch == ownItuZone"), Self.ctx("28", "14")))
    }

    @Test func exprMatchesHqLetters() throws {
        #expect(try ConditionEvaluator.eval(Self.expr("matches(exch, '[A-Za-z]')"), Self.ctx("28", "ARRL")))
    }

    @Test func exprMatchesFalseForPureNumber() throws {
        #expect(try !ConditionEvaluator.eval(Self.expr("matches(exch, '[A-Za-z]')"), Self.ctx("28", "14")))
    }

    @Test func nullConditionIsTrue() throws {
        #expect(try ConditionEvaluator.eval(nil, Self.ctx("28", "28")))
    }

    // MARK: - measured table (ConditionMeasured)

    private static func entity(_ code: Int, _ country: String?, _ continents: [String?]) -> DxccEntity {
        DxccEntity(entityCode: code, name: "N\(code)", countryCode: country, continents: continents,
                   cq: [], itu: [], lat: .nan, lon: .nan)
    }

    /// Probe contexts: A full, B empty, C an entity without `countryCode` and canonically equal
    /// continents, D the probe context of `StationClassifier` (`Map.of()` in Java).
    static let contexts: [String: QsoContext] = {
        var received = JavaLinkedMap<ExchangeValue>()
        received.put("exch", .valid("14", "14"))
        received.put("nm", .valid("x", "X"))
        received.put("bad", .invalid("q", "chyba"))
        received.put(nil, .valid("n", "NK"))
        received.put("nv", nil)
        received.put("vn", .valid("r", nil))
        let a = QsoContext(call: "OK1ABC", band: "20m", mode: "CW", received: received,
                           workedEntity: entity(1, "OK", ["EU"]), ownEntity: entity(1, "OK", ["EU"]),
                           workedClass: "DX", ownGrid: "JO70", ownItuZone: "28", ownQth: nil,
                           bonusStation: true)
        let b = QsoContext(call: nil, band: nil, mode: nil, received: nil, workedEntity: nil,
                           ownEntity: entity(2, "K", ["NA"]), workedClass: nil)
        let c = QsoContext(call: "X", band: "40m", mode: "SSB", received: JavaLinkedMap(),
                           workedEntity: entity(3, nil, ["eu"]), ownEntity: entity(4, "A\u{30A}", ["\u{C5}"]),
                           workedClass: "")
        let d = QsoContext(call: nil, band: nil, mode: nil, received: JavaLinkedMap(),
                           workedEntity: entity(1, "OK", ["EU"]), ownEntity: entity(2, "K", ["NA"]),
                           workedClass: nil)
        return ["A": a, "B": b, "C": c, "D": d]
    }()

    /// Probe conditions under the same descriptions (`ProbeCondition.main`). `nil` = `nullCond`.
    static let conditions: [String: Condition?] = {
        let notEmpty = Condition(not: Condition())
        let foo = Condition(expr: "foo(1)")
        var c: [String: Condition?] = [:]
        c["nullCond"] = .some(nil)
        c["empty"] = Condition()
        c["allOf[]"] = Condition(allOf: [])
        c["allOf[~]"] = Condition(allOf: [nil])
        c["allOf[{},not{}]"] = Condition(allOf: [Condition(), notEmpty])
        c["allOf[mode CW,bandIn 20m]"] = Condition(allOf: [Condition(mode: "CW"), Condition(bandIn: ["20m"])])
        c["anyOf[]"] = Condition(anyOf: [])
        c["anyOf[~]"] = Condition(anyOf: [nil])
        c["anyOf[not{},~]"] = Condition(anyOf: [notEmpty, nil])
        c["anyOf[not{}]"] = Condition(anyOf: [notEmpty])
        c["anyOf[not{},mode cw]"] = Condition(anyOf: [notEmpty, Condition(mode: "cw")])
        c["not{}"] = notEmpty
        c["not{not{}}"] = Condition(not: notEmpty)
        c["not{mode SSB}"] = Condition(not: Condition(mode: "SSB"))
        c["ownDxcc true"] = Condition(ownDxcc: true)
        c["ownDxcc false"] = Condition(ownDxcc: false)
        c["sameDxcc true"] = Condition(sameDxcc: true)
        c["sameDxcc false"] = Condition(sameDxcc: false)
        c["sameContinent true"] = Condition(sameContinent: true)
        c["sameContinent false"] = Condition(sameContinent: false)
        c["otherContinent true"] = Condition(otherContinent: true)
        c["otherContinent false"] = Condition(otherContinent: false)
        c["continentIs EU"] = Condition(continentIs: "EU")
        c["continentIs eu"] = Condition(continentIs: "eu")
        c["ownContinentIs EU"] = Condition(ownContinentIs: "EU")
        c["ownContinentIs NA"] = Condition(ownContinentIs: "NA")
        c["ownContinentIs U+00C5"] = Condition(ownContinentIs: "\u{C5}")
        c["ownContinentIs A+U+030A"] = Condition(ownContinentIs: "A\u{30A}")
        c["workedClass DX"] = Condition(workedClass: "DX")
        c["workedClass dx"] = Condition(workedClass: "dx")
        c["workedClass ''"] = Condition(workedClass: "")
        c["dxccIn[OK]"] = Condition(dxccIn: ["OK"])
        c["dxccIn[ok]"] = Condition(dxccIn: ["ok"])
        c["dxccIn[]"] = Condition(dxccIn: [])
        c["dxccIn[~]"] = Condition(dxccIn: [nil])
        c["dxccIn[~,OK]"] = Condition(dxccIn: [nil, "OK"])
        c["bandIn[20m]"] = Condition(bandIn: ["20m"])
        c["bandIn[20M]"] = Condition(bandIn: ["20M"])
        c["bandIn[]"] = Condition(bandIn: [])
        c["bandIn[~]"] = Condition(bandIn: [nil])
        c["mode CW"] = Condition(mode: "CW")
        c["mode cw"] = Condition(mode: "cw")
        c["mode ''"] = Condition(mode: "")
        c["mode SSB"] = Condition(mode: "SSB")
        c["fieldEquals exch 14"] = Condition(fieldEquals: FieldEquals(field: "exch", value: "14"))
        c["fieldEquals exch '14 '"] = Condition(fieldEquals: FieldEquals(field: "exch", value: "14 "))
        c["fieldEquals nm x"] = Condition(fieldEquals: FieldEquals(field: "nm", value: "x"))
        c["fieldEquals ~ nk"] = Condition(fieldEquals: FieldEquals(field: nil, value: "nk"))
        c["fieldEquals exch ~"] = Condition(fieldEquals: FieldEquals(field: "exch", value: nil))
        c["fieldEquals missing x"] = Condition(fieldEquals: FieldEquals(field: "missing", value: "x"))
        c["fieldEquals bad q"] = Condition(fieldEquals: FieldEquals(field: "bad", value: "q"))
        c["fieldEquals vn r"] = Condition(fieldEquals: FieldEquals(field: "vn", value: "r"))
        c["fieldEquals nv ''"] = Condition(fieldEquals: FieldEquals(field: "nv", value: ""))
        c["fieldPresent exch"] = Condition(fieldPresent: "exch")
        c["fieldPresent bad"] = Condition(fieldPresent: "bad")
        c["fieldPresent nv"] = Condition(fieldPresent: "nv")
        c["fieldPresent vn"] = Condition(fieldPresent: "vn")
        c["fieldPresent missing"] = Condition(fieldPresent: "missing")
        c["bonusStation true"] = Condition(bonusStation: true)
        c["bonusStation false"] = Condition(bonusStation: false)
        c["expr 1"] = Condition(expr: "1")
        c["expr 0"] = Condition(expr: "0")
        c["expr ''"] = Condition(expr: "")
        c["expr blank"] = Condition(expr: "  ")
        c["expr 0/0"] = Condition(expr: "0/0")
        c["expr 'NaN' * 1"] = Condition(expr: "'NaN' * 1")   // NaN != 0 → pravda
        c["expr exch == 14"] = Condition(expr: "exch == 14")
        c["expr call == ''"] = Condition(expr: "call == ''")
        c["expr ownDxcc"] = Condition(expr: "ownDxcc")
        c["expr foo(1)"] = foo
        c["expr matches bad regex"] = Condition(expr: "matches(call, '(')")
        c["AND mode CW bandIn 40m"] = Condition(bandIn: ["40m"], mode: "CW")
        c["AND mode CW bandIn 20m"] = Condition(bandIn: ["20m"], mode: "CW")
        c["not{expr foo} + mode SSB"] = Condition(not: foo, mode: "SSB")
        c["mode SSB + expr foo"] = Condition(mode: "SSB", expr: "foo(1)")
        c["anyOf[{},expr foo]"] = Condition(anyOf: [Condition(), foo])
        c["allOf[not{},expr foo]"] = Condition(allOf: [notEmpty, foo])
        c["allOf[expr foo,not{}]"] = Condition(allOf: [foo, notEmpty])
        c["anyOf[not{}] + expr foo"] = Condition(anyOf: [notEmpty], expr: "foo(1)")
        return c
    }()

    /// Where Java fails with an NPE, Swift is lenient: `fieldEquals.field: ~` over the probe
    /// context (`Map.of().get(null)`) → the field is missing → no match.
    static let lenient: [String: Bool] = ["fieldEquals ~ nk @D": false]

    @Test(arguments: ConditionMeasured.conditions)
    func matchesJava(_ row: ConditionMeasured.Row) throws {
        let condition = try #require(Self.conditions[row.name], "missing condition \(row.name)")
        let context = try #require(Self.contexts[row.context])
        let result = Result { () throws(ExpressionError) in try ConditionEvaluator.eval(condition, context) }
        switch row.java {
        case .bool(let expected):
            #expect(try result.get() == expected)
        case .error(let kind, let message):
            #expect(throws: ExpressionError(kind: kind, message: message)) { try result.get() }
        case .npe:
            let expected = Self.lenient[row.description]
            #expect(expected != nil, "NPE without a lenient value")
            #expect(try result.get() == expected)
        case .id:
            Issue.record("condition does not return an id")
        }
    }

    @Test func everyConditionIsMeasured() {
        let measured = Set(ConditionMeasured.conditions.map(\.name))
        #expect(measured == Set(Self.conditions.keys))
        #expect(ConditionMeasured.conditions.count == Self.conditions.count * Self.contexts.count)
    }

    // MARK: - recursion depth on a 512 KB thread

    static func onSmallStack(_ condition: Condition, _ context: QsoContext) async -> Result<Bool, ExpressionError> {
        await withCheckedContinuation { continuation in
            let thread = Thread {
                continuation.resume(returning: Result { () throws(ExpressionError) in
                    try ConditionEvaluator.eval(condition, context)
                })
            }
            thread.stackSize = 512 * 1024
            thread.start()
        }
    }

    /// The worst expression at the `Expression` limit: 11× `max(` and at the bottom `matches` with a regex
    /// nested in 16 groups (consumption ~340 KB in a debug build).
    static let worstExpression: String = {
        let outer = Expression.maxNestingDepth - 1
        let regex = String(repeating: "(", count: 16) + "a" + String(repeating: ")", count: 16)
        return String(repeating: "max(", count: outer) + "matches(call, '" + regex + "')"
            + String(repeating: ")", count: outer)
    }()

    /// The wrapper of one level: `not`, `allOf` (at the end of the list) or `anyOf` (after an unmet
    /// condition). The number of `not` determines the result (even → the expression), the others do not change it.
    static func wrap(_ inner: Condition, level: Int) -> Condition {
        switch level % 3 {
        case 0: Condition(not: inner)
        case 1: Condition(allOf: [Condition(), inner])
        default: Condition(anyOf: [Condition(bandIn: ["2m"]), inner])
        }
    }

    static func nested(depth: Int, kind: String) -> Condition {
        var condition = Condition(expr: worstExpression)
        for level in 0..<depth {
            switch kind {
            case "not": condition = Condition(not: condition)
            case "allOf": condition = Condition(allOf: [Condition(), condition])
            case "anyOf": condition = Condition(anyOf: [Condition(bandIn: ["2m"]), condition])
            default: condition = wrap(condition, level: level)
            }
        }
        return condition
    }

    /// The YAML reader lets through at most 16 levels of maps and sequences (`YamlParser.maxNestingDepth`);
    /// a condition (`Condition`) starts at the shallowest at level 4 (`stationClasses[].when`;
    /// `scoring.bonuses[].when` is at level 5, `scoring.qsoPoints.rules[].when` at 6 —
    /// `appliesWhen` is not a `Condition`, it carries only `workedClass`), so from a definition
    /// at most 13 levels of `not` arrive.
    /// The test takes with a margin 16 levels of each wrapper and at the bottom an expression at the limit — the whole
    /// composition (conditions → expression → regex) must fit in 512 KB even in a debug build.
    @Test func yamlMaximumNestingWithWorstExpressionFitsSmallStack() async throws {
        let context = try #require(Self.contexts["A"])
        // call = OK1ABC does not contain "a" → matches 0 → max(…) 0 → the expression is not met.
        for kind in ["not", "allOf", "anyOf", "mix"] {
            let condition = Self.nested(depth: 16, kind: kind)
            let value = try await Self.onSmallStack(condition, context).get()
            // 16 × not: an even number of negations → the expression result (false); the mix has 6 × not.
            #expect(value == false, "\(kind)")
        }
        let lower = QsoContext(call: "a", band: "20m", mode: "CW", received: nil, workedEntity: nil,
                               ownEntity: nil, workedClass: nil)
        for kind in ["not", "allOf", "anyOf", "mix"] {
            let value = try await Self.onSmallStack(Self.nested(depth: 16, kind: kind), lower).get()
            #expect(value == true, "\(kind)")
        }
    }
}
