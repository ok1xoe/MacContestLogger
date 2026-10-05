import Foundation
import Testing
@testable import MCLCore

/// The engine's shared data are `Sendable` (shared immutable data).
///
/// Java builds a new session in the background (`Dispatchers.Default`) and takes it over on the main thread;
/// it shares the DXCC resolver and the multiplier registry with the live session. In Swift 6 this works only
/// if these parts are `Sendable` — this file guards it by **compilation** (strict concurrency)
/// and by concurrent use of the same instances.
@Suite struct SharedDataSendableTests {

    /// Session parts built off the main actor (the future `ContestSession` composes them together).
    struct Built: Sendable {
        let definition: ContestDefinition
        let dxcc: any DxccLookup
        let registry: MultiplierSetRegistry
        let factory: QsoContextFactory
        let evaluator: MultiplierEvaluator
    }

    private static func multipliersDirectory() throws -> URL {
        let root = try #require(Bundle.module.url(forResource: "contest-data", withExtension: nil))
        return root.appendingPathComponent("multipliers")
    }

    /// Review focus 1: the factory, the evaluator (with the registry) and DXCC are created in `Task.detached`,
    /// one QSO is credited there, and the finished ones are handed to the main actor, which keeps working with them.
    @Test func sessionPartsBuiltInBackgroundAreAdoptedOnMainActor() async throws {
        let dxccData = try DxccTestFixture.data()
        let multipliers = try Self.multipliersDirectory()
        let definition = try ExchangeMeasuredTests.definition("@cq-ww-cw.yaml")

        let built = try await Task.detached {
            let dxcc = DxccSpecialCases(try DxccResolver.fromData(dxccData))
            let registry = try MultiplierSetRegistry(dxcc: dxcc).loadDir(multipliers)
            let factory = QsoContextFactory(definition: definition, dxcc: dxcc, exchange: ExchangeEngine(),
                                            myCall: "OK1XOE")
            factory.setBonusPredicate { $0 == "DL1AA" }
            var evaluator = MultiplierEvaluator(registry: registry)
            let context = try factory.build(call: "DL1AA", band: "20m", mode: "CW",
                                            receivedRaw: JavaLinkedMap([("rst", "599"), ("zone", "14")]))
            _ = try evaluator.commit(definition, context)
            return Built(definition: definition, dxcc: dxcc, registry: registry, factory: factory,
                         evaluator: evaluator)
        }.value

        try await MainActor.run {
            let again = try built.factory.build(call: "DL1AA", band: "20m", mode: "CW",
                                                receivedRaw: JavaLinkedMap([("rst", "599"), ("zone", "14")]))
            #expect(again.bonusStation, "a predicate set in the background still applies after the handover")
            let results = try built.evaluator.preview(built.definition, again)
            #expect(!results.isEmpty)
            #expect(results.allSatisfy { $0.state == .knownAlreadyWorked },
                    "a QSO credited in the background is in the tracker of the handed-over evaluator: \(results)")
            #expect(built.registry.contains("wpx_prefixes"))
        }
    }

    /// The same resolver (`DxccResolver`, `CtyDxccResolver`, the decorator) used from many tasks
    /// at once gives the same as sequentially — the memoisation cache is behind a lock. A
    /// **fresh** instance with a cold cache runs concurrently (tasks fight over the first write of each callsign);
    /// the expectation is given by another instance of the same kind, evaluated sequentially.
    @Test func sharedResolversAreSafeUnderConcurrentResolve() async throws {
        let data = try DxccTestFixture.data()
        let makers: [@Sendable () throws -> any DxccLookup] = [
            { try DxccResolver.fromData(data) },
            { CtyDxccResolver.parse(CtyDxccResolverTests.ctySource) },
            { DxccSpecialCases(try DxccResolver.fromData(data)) },
        ]
        // Built in steps with explicit types: a single `+` chain inside a closure the older
        // compiler in CI (Xcode 16) cannot type-check in time.
        let prefixes: [String] = ["OK", "DL", "W", "KG4", "OM", "TA", "JA", "G"]
        let calls: [String] = (0..<400).map { (i: Int) -> String in
            let prefix: String = prefixes[i % 8]
            let digits: String = String(i % 50)
            return prefix + digits + "AB"
        }

        for make in makers {
            let baseline = try make()
            let expected = calls.map { baseline.resolve($0)?.entityCode }
            let resolver = try make()
            let rounds = try await withThrowingTaskGroup(of: [Int?].self) { group in
                for _ in 0..<8 {
                    group.addTask { calls.map { resolver.resolve($0)?.entityCode } }
                }
                var out: [[Int?]] = []
                for try await round in group {
                    out.append(round)
                }
                return out
            }
            #expect(rounds.count == 8)
            #expect(rounds.allSatisfy { $0 == expected })
            #expect(calls.map { resolver.resolve($0)?.entityCode } == expected, "cache after concurrency")
        }
    }

    /// One factory and one registry shared by two "sessions" in different tasks (a live session
    /// and a background replay): each has its own tracker (a value), the results do not influence each other.
    @Test func sharedFactoryAndRegistryServeIndependentTrackers() async throws {
        let dxcc = try DxccResolver.fromData(DxccTestFixture.data())
        let registry = try MultiplierSetRegistry(dxcc: dxcc).loadDir(Self.multipliersDirectory())
        let definition = try ExchangeMeasuredTests.definition("@cq-ww-cw.yaml")
        let factory = QsoContextFactory(definition: definition, dxcc: dxcc, exchange: ExchangeEngine(),
                                        myCall: "OK1XOE")
        let calls = ["DL1AA", "W1AW", "OK2AA", "OM7M", "G4ABC", "F5XYZ"]

        let counts = try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<4 {
                group.addTask {
                    var evaluator = MultiplierEvaluator(registry: registry)
                    var newOnes = 0
                    for i in 0..<300 {
                        let context = try factory.build(call: calls[i % calls.count], band: "20m", mode: "CW",
                                                        receivedRaw: JavaLinkedMap([("rst", "599"),
                                                                                     ("zone", String(i % 40 + 1))]))
                        newOnes += try evaluator.commit(definition, context).filter(\.isNew).count
                    }
                    return newOnes
                }
            }
            var out: [Int] = []
            for try await count in group {
                out.append(count)
            }
            return out
        }
        #expect(counts.count == 4)
        #expect(Set(counts).count == 1, "independent trackers over a shared factory: \(counts)")
    }
}
