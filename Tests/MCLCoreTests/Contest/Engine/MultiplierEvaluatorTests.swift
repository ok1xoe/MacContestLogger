import Foundation
import Testing
@testable import MCLCore

/// Port of the Java `MultiplierEvaluatorTest` (6 cases) and a table measured by the probe
/// a maintainer-only probe (JDK 21.0.2): multiplier states after
/// bindings over QSO sequences on real definitions (cq-ww-cw/rtty, cq-wpx-cw, cq-160-cw,
/// wae-cw with band weights, iaru-hf, ok-om-dx-cw) and score counts after each step, Java errors
/// that are copied (duplicate binding id, `from: ZONE`, scope `"null"`, inherited
/// `appliesWhen`), and `MultiplierTracker` directly.
///
/// **Port of the Java tests.** The Java test goes through `ContestSession`.
/// `ContestSession.preview(call, band, mode, raw)` is `factory.build(call, band, mode, raw,
/// null)` + `PointsCalculator.points` + `dupe.isDupe` + `evaluator.preview` over the same context
/// (`ContestSession.java:257-261`); it changes neither points nor the dupe tracker and the `multipliers()` of the result is
/// exactly `evaluator.preview`. `ContestSession.log(…)` (the third test), with a filled band and a mode
/// the contest has (CW in cq-ww-cw), calls `evaluator.commit` over the same context
/// (`ContestSession.java:271-293`); dupe, points and bonuses do not change the tracker. The session constructor
/// (`def, dxcc, registry, "OK1XOE"`) builds a factory with the same callsign without a locator and ITU zone.
/// `Map.of(…)` → `JavaLinkedMap`: `build` reads only the ids of the definition's fields and none of them is `null`,
/// so an immutable map and a `LinkedHashMap` give the same. Hence `build` + `preview`/`commit`
/// are equivalent and the results are the same (the same scenario is also in the table under the name `java-…`).
@Suite struct MultiplierEvaluatorTests {

    let registry: MultiplierSetRegistry
    let dxcc: DxccResolver

    init() throws {
        dxcc = try DxccResolver.fromData(DxccTestFixture.data())
        let root = try #require(Bundle.module.url(forResource: "contest-data", withExtension: nil))
        registry = try MultiplierSetRegistry(dxcc: dxcc).loadDir(root.appendingPathComponent("multipliers"))
    }

    /// A replacement for the Java `ContestSession` for multipliers: definition, context factory and evaluator.
    struct Session {
        let definition: ContestDefinition
        let factory: QsoContextFactory
        var evaluator: MultiplierEvaluator

        func preview(_ call: String?, _ band: String?, _ mode: String?,
                     _ raw: JavaLinkedMap<String>?) throws -> [MultiplierEvalResult] {
            try evaluator.preview(definition, factory.build(call: call, band: band, mode: mode, receivedRaw: raw))
        }

        mutating func log(_ call: String?, _ band: String?, _ mode: String?,
                          _ raw: JavaLinkedMap<String>?) throws -> [MultiplierEvalResult] {
            try evaluator.commit(definition, factory.build(call: call, band: band, mode: mode, receivedRaw: raw))
        }
    }

    func session(_ definition: String, myCall: String? = "OK1XOE") throws -> Session {
        let def = try ExchangeMeasuredTests.definition(definition)
        let factory = QsoContextFactory(definition: def, dxcc: dxcc, exchange: ExchangeEngine(), myCall: myCall)
        return Session(definition: def, factory: factory, evaluator: MultiplierEvaluator(registry: registry))
    }

    private static func raw(_ pairs: (String?, String?)...) -> JavaLinkedMap<String> {
        JavaLinkedMap(pairs)
    }

    /// Java `results.stream().filter(r -> r.bindingId().equals(id)).findFirst().orElseThrow().state()`.
    private static func state(_ results: [MultiplierEvalResult],
                              _ bindingId: String) throws -> MultiplierEvalResult.MultiplierState {
        try #require(results.first { JavaText.equals(bindingId, $0.bindingId) }).state
    }

    // MARK: - Java MultiplierEvaluatorTest

    /// Java `nasobicSeNehodnotiKdyzJehoPoleProTuStaniciNeplati` (the multiplier is not evaluated when its field does not apply to the station):
    /// `s.preview("OM7M", "20m", "RTTY", Map.of("zone", "15")).multipliers()` → the binding `states`
    /// is not in the result. CQ WW RTTY: only W/VE send the state; for a DX station the field is empty
    /// and the binding over it must not report "invalid".
    @Test func multiplierIsNotEvaluatedWhenItsFieldDoesNotApply() throws {
        let s = try session("@cq-ww-rtty.yaml")
        let dx = try s.preview("OM7M", "20m", "RTTY", Self.raw(("zone", "15")))
        #expect(dx.filter { JavaText.equals("states", $0.bindingId) }.isEmpty, "binding states is not evaluated at all for a DX station")
    }

    /// Java `nasobicStatuPlatiProWve`: `s.preview("W1AW", "20m", "RTTY", Map.of("zone", "5", "state", "CT"))`
    /// → `states` is `KNOWN_NEW_MULTIPLIER`.
    @Test func stateMultiplierAppliesToWve() throws {
        let s = try session("@cq-ww-rtty.yaml")
        let wve = try s.preview("W1AW", "20m", "RTTY", Self.raw(("zone", "5"), ("state", "CT")))
        #expect(try Self.state(wve, "states") == .knownNewMultiplier)
    }

    /// Java `knownNewThenAlreadyWorked`: `s.log("DL1ABC", "20m", "CW", Map.of("zone", "14"))` →
    /// `zones` and `countries` new; then `s.preview("DL2XYZ", "20m", "CW", Map.of("zone", "14"))` →
    /// `zones` already worked.
    @Test func knownNewThenAlreadyWorked() throws {
        var s = try session("@cq-ww-cw.yaml")
        let first = try s.log("DL1ABC", "20m", "CW", Self.raw(("zone", "14")))
        #expect(try Self.state(first, "zones") == .knownNewMultiplier)
        #expect(try Self.state(first, "countries") == .knownNewMultiplier)

        let again = try s.preview("DL2XYZ", "20m", "CW", Self.raw(("zone", "14")))
        #expect(try Self.state(again, "zones") == .knownAlreadyWorked)
    }

    /// Java `invalidFormatFromField`: `s.preview("DL1ABC", "20m", "CW", Map.of("zone", "abc"))` →
    /// `zones` is `INVALID_FORMAT`.
    @Test func invalidFormatFromField() throws {
        let s = try session("@cq-ww-cw.yaml")
        let r = try s.preview("DL1ABC", "20m", "CW", Self.raw(("zone", "abc")))
        #expect(try Self.state(r, "zones") == .invalidFormat)
    }

    /// Java `suspiciousFromUnknownCallsign`: `s.preview("QQ9QQ", "20m", "CW", Map.of("zone", "14"))` →
    /// `countries` is `SUSPICIOUS`.
    @Test func suspiciousFromUnknownCallsign() throws {
        let s = try session("@cq-ww-cw.yaml")
        let r = try s.preview("QQ9QQ", "20m", "CW", Self.raw(("zone", "14")))
        #expect(try Self.state(r, "countries") == .suspicious)
    }

    /// Java `unknownAcceptedForOpenValueInClosedSet`: `s.preview("W1AW", "160m", "CW", Map.of("state", "XX"))`
    /// in cq-160-cw → `areas` is `UNKNOWN_ACCEPTED` (W1AW = W/VE → active field `state`; "XX" passes
    /// the format, but is not in `na_areas`).
    @Test func unknownAcceptedForOpenValueInClosedSet() throws {
        let s = try session("@cq-160-cw.yaml")
        let r = try s.preview("W1AW", "160m", "CW", Self.raw(("state", "XX")))
        #expect(try Self.state(r, "areas") == .unknownAccepted)
    }

    // MARK: - table measured on Java

    static func describe(_ results: [MultiplierEvalResult]) -> String {
        let esc = ExchangeMeasuredTests.esc
        return results.map { r in
            [esc(r.bindingId), esc(r.setId), esc(r.key), esc(r.scopeKey), r.state.rawValue,
             "\(r.countsAsMultiplier)", "\(r.isNew)"].joined(separator: ",")
        }.joined(separator: ";")
    }

    static func score(_ definition: ContestDefinition, _ tracker: MultiplierTracker) -> String {
        do {
            let state = try ScoreEngine.compute(definition, qsoPoints: 0, bonusPoints: 0, qtcPoints: 0,
                                                qsoCount: 0, tracker: tracker)
            let groups = state.multByGroup.entries.map { ExchangeMeasuredTests.esc($0.key) + "=\($0.value ?? 0)" }
            return "mult=\(state.multTotal) groups=[" + groups.joined(separator: ",") + "] distinct=\(tracker.totalDistinct())"
        } catch {
            return "EXC " + ExchangeMeasuredTests.esc(error.message)
        }
    }

    private static func received(_ fields: [MultiplierMeasured.Field]?) -> JavaLinkedMap<String>? {
        fields.map { JavaLinkedMap($0.map { ($0.key, $0.value) }) }
    }

    private static func evaluate(_ body: () throws -> [MultiplierEvalResult]) -> String {
        do {
            return describe(try body())
        } catch let error as MultiplierError {
            return "EXC MultiplierException: " + ExchangeMeasuredTests.esc(error.message)
        } catch {
            return "EXC \(error)"
        }
    }

    private static func tracker(_ tracker: inout MultiplierTracker, _ op: String, _ binding: String?,
                                _ scope: String?, _ key: String?) throws -> String {
        switch op {
        case "A": return "\(tracker.add(binding, try #require(scope), key))"
        case "R": return "\(tracker.remove(binding, try #require(scope), key))"
        case "W": return "\(tracker.isWorked(binding, try #require(scope), key))"
        case "D": return "\(tracker.distinctForBinding(binding))"
        case "N": return "\(tracker.totalDistinct())"
        case "K": return tracker.keysForBinding(binding).map { ExchangeMeasuredTests.esc($0) }.joined(separator: ";")
        default: throw ProbeFormatError(op: op)
        }
    }

    struct ProbeFormatError: Error {
        let op: String
    }

    /// Replays the scenario and returns (result, score) after each step — the same text as the probe.
    func replay(_ scenario: MultiplierMeasured.Scenario) throws -> [Pair] {
        var s = try session(scenario.definition, myCall: scenario.myCall)
        var out: [Pair] = []
        for step in scenario.steps {
            switch step.input {
            case let .preview(call, band, mode, fields):
                let result = Self.evaluate { try s.preview(call, band, mode, Self.received(fields)) }
                out.append(Pair(result, Self.score(s.definition, s.evaluator.tracker)))
            case let .commit(call, band, mode, fields):
                let result = Self.evaluate { try s.log(call, band, mode, Self.received(fields)) }
                out.append(Pair(result, Self.score(s.definition, s.evaluator.tracker)))
            case let .tracker(op, binding, scope, key):
                out.append(Pair(try Self.tracker(&s.evaluator.tracker, op, binding, scope, key), "-"))
            }
        }
        return out
    }

    struct Pair: Equatable, CustomStringConvertible {
        let result: String
        let score: String
        init(_ result: String, _ score: String) {
            self.result = result
            self.score = score
        }
        var description: String { result + " | " + score }
    }

    /// Scenarios where Java crashes or where Swift knowingly differs:
    /// the pinned Swift result by steps.
    ///
    /// - `nil-binding`, `nil-binding-mixed`: `multipliers: [~, …]` — Java NPE in `bindingApplies`
    ///   (after crediting earlier bindings) and in `ScoreEngine`; Swift skips the `nil` binding.
    /// - `nil-received-field`: `exchange.received: [~, …]` — Java NPE already in `QsoContextFactory.build`
    ///   (and in `sourceFieldAppliesWhen`); Swift skips the element and inherits `appliesWhen` from the next field.
    /// - `weights-null-value`: `bandWeights: {80m: ~}` with a multiplier on 80m — Java NPE on unboxing
    ///   `Integer`; Swift takes weight 1 (like a band without a weight).
    /// - `weights-canonical-keys`: `bandWeights: {K: 2, "\u{212A}": 5}` — the model (`YamlOrderedMap`)
    ///   merges canonically equal keys into `K: 5`; Java keeps two keys. The tracker looks up by UTF-16, but
    ///   the difference arises already at load.
    static let lenient: [String: [Pair]] = [
        "nil-binding": [Pair("", "mult=0 groups=[] distinct=0")],
        "nil-binding-mixed": [
            Pair("a,cq_zones,14,*,KNOWN_NEW_MULTIPLIER,true,true;b,dxcc_entities,230,*,KNOWN_NEW_MULTIPLIER,true,true",
                 "mult=2 groups=[a=1,b=1] distinct=2"),
            Pair("a,cq_zones,14,*,KNOWN_ALREADY_WORKED,true,false;b,dxcc_entities,230,*,KNOWN_ALREADY_WORKED,true,false",
                 "mult=2 groups=[a=1,b=1] distinct=2"),
        ],
        "nil-received-field": [Pair("z,cq_zones,14,*,KNOWN_NEW_MULTIPLIER,true,true", "mult=1 groups=[z=1] distinct=1")],
        "weights-null-value": [
            Pair("w,cq_zones,14,20m,KNOWN_NEW_MULTIPLIER,true,true", "mult=1 groups=[w=1] distinct=1"),
            Pair("w,cq_zones,14,40m,KNOWN_NEW_MULTIPLIER,true,true", "mult=4 groups=[w=4] distinct=2"),
            Pair("w,cq_zones,14,80m,KNOWN_NEW_MULTIPLIER,true,true", "mult=5 groups=[w=5] distinct=3"),
        ],
        "weights-canonical-keys": [
            Pair("w,cq_zones,14,K,KNOWN_NEW_MULTIPLIER,true,true", "mult=5 groups=[w=5] distinct=1"),
            Pair("w,cq_zones,14,\\u212A,KNOWN_NEW_MULTIPLIER,true,true", "mult=6 groups=[w=6] distinct=2"),
        ],
    ]

    @Test(arguments: MultiplierMeasured.scenarios)
    func matchesJava(_ scenario: MultiplierMeasured.Scenario) throws {
        let swift = try replay(scenario)
        let java = scenario.steps.map { Pair($0.result, $0.score) }
        if let pinned = Self.lenient[scenario.name] {
            // Pinning must have a reason: Java really differs from Swift in this scenario.
            #expect(java != pinned, "the pinned scenario agrees with Java — it belongs in the table")
            #expect(swift == pinned)
        } else {
            #expect(swift == java)
        }
    }

    @Test func everyLenientScenarioIsMeasured() {
        let names = Set(MultiplierMeasured.scenarios.map(\.name))
        #expect(Set(Self.lenient.keys).isSubset(of: names))
    }

    // MARK: - properties outside the table

    /// An unknown set in the middle of `commit`: the error propagates, but the bindings before it are already
    /// in the tracker (Java `commit` has no transaction). The same is in the table (`unknown-set-partial-commit`).
    @Test func failingCommitKeepsEarlierBindings() throws {
        var s = try session("{exchange: {received: [{id: zone, type: CQ_ZONE}]}, multipliers: "
                            + "[{id: a, set: cq_zones, from: zone}, {id: b, set: nope, from: zone}]}")
        #expect(throws: MultiplierError.failure("multiplikátorová sada 'nope' není v registru")) {
            try s.log("DL1ABC", "20m", "CW", Self.raw(("zone", "14")))
        }
        #expect(s.evaluator.tracker.isWorked("a", "*", "14"))
    }

    /// `scopeKey` is Java `MultiplierEvaluator.scopeKey` — shared with the duplicate check.
    @Test func scopeKeyWritesNullAsText() {
        let context = QsoContext(call: "X", band: nil, mode: nil, received: nil, workedEntity: nil, ownEntity: nil,
                                 workedClass: nil)
        #expect(MultiplierEvaluator.scopeKey(nil, context) == "*")
        #expect(MultiplierEvaluator.scopeKey(.ONCE, context) == "*")
        #expect(MultiplierEvaluator.scopeKey(.PER_BAND, context) == "null")
        #expect(MultiplierEvaluator.scopeKey(.PER_MODE, context) == "null")
        #expect(MultiplierEvaluator.scopeKey(.PER_BAND_MODE, context) == "null|null")
    }

    /// `==` of the result is Java `record.equals`: texts by UTF-16, not canonically.
    @Test func resultEqualityIsUtf16() {
        func result(_ key: String?) -> MultiplierEvalResult {
            MultiplierEvalResult(bindingId: "b", setId: "s", key: key, scopeKey: "*", state: .knownNewMultiplier,
                                 countsAsMultiplier: true, isNew: true)
        }
        #expect(result("\u{C5}") == result("\u{C5}"))
        #expect(result("\u{C5}") != result("A\u{30A}"))
        #expect(result("K") != result("\u{212A}"))
        #expect(result(nil) != result("null"))
    }
}

// MARK: - Java MultiplierEvaluatorTest on the real ContestSession

/// The same Java tests as above, but through the real `ContestSession` — the way
/// Java writes them. The `Session` replacement above stays (it also covers the table, where only the evaluator is called);
/// these tests guard that the session gives the same.
extension MultiplierEvaluatorTests {

    private func realSession(_ definition: String) throws -> ContestSession {
        ContestSession(definition: try ExchangeMeasuredTests.definition(definition), dxcc: dxcc, registry: registry,
                       myCall: "OK1XOE")
    }

    private static func states(_ result: ContestSession.LogResult,
                               _ bindingId: String) throws -> MultiplierEvalResult.MultiplierState {
        try state(result.multipliers, bindingId)
    }

    @Test func sessionMultiplierIsNotEvaluatedWhenItsFieldDoesNotApply() throws {
        let s = try realSession("@cq-ww-rtty.yaml")
        let dx = try s.preview(call: "OM7M", band: "20m", mode: "RTTY", receivedRaw: Self.raw(("zone", "15")))
        #expect(dx.multipliers.filter { JavaText.equals("states", $0.bindingId) }.isEmpty)
    }

    @Test func sessionStateMultiplierAppliesToWve() throws {
        let s = try realSession("@cq-ww-rtty.yaml")
        let wve = try s.preview(call: "W1AW", band: "20m", mode: "RTTY", receivedRaw: Self.raw(("zone", "5"), ("state", "CT")))
        #expect(try Self.states(wve, "states") == .knownNewMultiplier)
    }

    @Test func sessionKnownNewThenAlreadyWorked() throws {
        let s = try realSession("@cq-ww-cw.yaml")
        let first = try s.log(call: "DL1ABC", band: "20m", mode: "CW", receivedRaw: Self.raw(("zone", "14")))
        #expect(try Self.states(first, "zones") == .knownNewMultiplier)
        #expect(try Self.states(first, "countries") == .knownNewMultiplier)

        let again = try s.preview(call: "DL2XYZ", band: "20m", mode: "CW", receivedRaw: Self.raw(("zone", "14")))
        #expect(try Self.states(again, "zones") == .knownAlreadyWorked)
    }

    @Test func sessionInvalidFormatFromField() throws {
        let s = try realSession("@cq-ww-cw.yaml")
        let r = try s.preview(call: "DL1ABC", band: "20m", mode: "CW", receivedRaw: Self.raw(("zone", "abc")))
        #expect(try Self.states(r, "zones") == .invalidFormat)
    }

    @Test func sessionSuspiciousFromUnknownCallsign() throws {
        let s = try realSession("@cq-ww-cw.yaml")
        let r = try s.preview(call: "QQ9QQ", band: "20m", mode: "CW", receivedRaw: Self.raw(("zone", "14")))
        #expect(try Self.states(r, "countries") == .suspicious)
    }

    @Test func sessionUnknownAcceptedForOpenValueInClosedSet() throws {
        let s = try realSession("@cq-160-cw.yaml")
        let r = try s.preview(call: "W1AW", band: "160m", mode: "CW", receivedRaw: Self.raw(("state", "XX")))
        #expect(try Self.states(r, "areas") == .unknownAccepted)
    }
}
