import Foundation
import Testing
@testable import MCLCore

/// Shared fixtures of the `ContestSession` tests: DXCC from `dxcc-test.json` (CZ/US/CA/DE + deleted
/// `XX`), the set registry from `contest-data/multipliers` and definitions from `contest-data/contests` —
/// byte-identical files as in the Java tests (`src/test/resources`, `contest-data/`).
enum SessionFixture {

    static func dxcc() throws -> DxccResolver {
        try DxccResolver.fromData(DxccTestFixture.data())
    }

    static func contestData() throws -> URL {
        try #require(Bundle.module.url(forResource: "contest-data", withExtension: nil))
    }

    static func registry(_ dxcc: any DxccLookup) throws -> MultiplierSetRegistry {
        try MultiplierSetRegistry(dxcc: dxcc).loadDir(contestData().appendingPathComponent("multipliers"))
    }

    /// `@file.yaml` from `contest-data/contests`, otherwise YAML text.
    static func definition(_ yaml: String) throws -> ContestDefinition {
        try ExchangeMeasuredTests.definition(yaml)
    }

    /// Java `new ContestSession(def, dxcc, registry, myCall, myGrid, myItuZone)` over the fixtures.
    static func session(_ yaml: String, myCall: String? = "OK1XOE", myGrid: String? = nil,
                        myItuZone: String? = nil) throws -> ContestSession {
        let dxcc = try dxcc()
        return ContestSession(definition: try definition(yaml), dxcc: dxcc, registry: try registry(dxcc),
                              myCall: myCall, myGrid: myGrid, myItuZone: myItuZone)
    }

    /// Java `Map.of(k, v, …)` (insertion order; `build` reads only the definition's field ids).
    static func raw(_ pairs: (String?, String?)...) -> JavaLinkedMap<String> {
        JavaLinkedMap(pairs)
    }

    /// Java `results.stream().filter(m -> m.countsAsMultiplier() && m.isNew()).count()`.
    static func newMultipliers(_ result: ContestSession.LogResult) -> Int {
        result.multipliers.filter { $0.countsAsMultiplier && $0.isNew }.count
    }
}
