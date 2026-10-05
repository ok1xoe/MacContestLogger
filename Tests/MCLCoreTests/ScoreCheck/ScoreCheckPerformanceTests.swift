import Foundation
import Testing
@testable import MCLCore

/// Performance measurement before running the gate over the full corpus. Does not run in the normal suite —
/// it is enabled by the environment variable `MCL_BENCH=1` (repetition count `MCL_BENCH_ITER`, default
/// 1000). Times are only printed; nothing is verified here except that the results agree
/// with the first pass.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["MCL_BENCH"] != nil))
struct ScoreCheckPerformanceTests {

    static var iterations: Int {
        ProcessInfo.processInfo.environment["MCL_BENCH_ITER"].flatMap { Int($0) } ?? 1000
    }

    /// All edge logs of `Fixtures/scorecheck-edge/` × `MCL_BENCH_ITER` in both DXCC modes.
    @Test func edgeLogsRepeated() throws {
        let edgeDir = try #require(Bundle.module.url(forResource: "scorecheck-edge", withExtension: nil))
        let files = try FileManager.default.contentsOfDirectory(atPath: edgeDir.path).sorted()
        let logs = try files.map { ($0, try Data(contentsOf: edgeDir.appendingPathComponent($0))) }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("scorecheck-bench-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let jsonDir = root.appendingPathComponent("json")
        let ctyDir = root.appendingPathComponent("cty")
        try FileManager.default.createDirectory(at: jsonDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: ctyDir, withIntermediateDirectories: true)
        try DxccTestFixture.data().write(to: jsonDir.appendingPathComponent("dxcc.json"))
        try ScoreCheckMeasuredTests.ctyMini().write(to: ctyDir.appendingPathComponent("cty.dat"))
        let contestData = try SessionFixture.contestData()
        let defs = try ContestCatalog.fromDir(contestData.appendingPathComponent("contests"))
        for (tag, dir) in [("json", jsonDir), ("cty", ctyDir)] {
            let loaded = try #require(ScoreCheck.loadDxcc(directory: dir))
            let registry = try MultiplierSetRegistry(dxcc: loaded.lookup)
                .loadDir(contestData.appendingPathComponent("multipliers"))
            let first = logs.map { ScoreCheckMeasuredTests.row(ScoreCheck.check(
                fileName: $0.0, data: $0.1, definitions: defs, dxcc: loaded.lookup, registry: registry)) }
            let n = Self.iterations
            var mismatches = 0
            let elapsed = ContinuousClock().measure {
                for _ in 0..<n {
                    for (index, log) in logs.enumerated() {
                        let outcome = ScoreCheck.check(fileName: log.0, data: log.1, definitions: defs,
                                                       dxcc: loaded.lookup, registry: registry)
                        if ScoreCheckMeasuredTests.row(outcome) != first[index] { mismatches += 1 }
                    }
                }
            }
            print("ScoreCheck edge logs \(tag) \(logs.count) × \(n): \(elapsed)")
            #expect(mismatches == 0)
        }
    }

    /// Throughput of `DxccResolver` (`dxcc.json` mode) for a concurrent run over the corpus:
    /// 20,000 different callsigns serially and in 8 threads over **one** shared resolver.
    /// Data: `MCL_DXCC_JSON`, otherwise `~/dxcc-json/dxcc.json`, otherwise the test fixture.
    @Test func dxccResolverParallel() throws {
        let path = ProcessInfo.processInfo.environment["MCL_DXCC_JSON"]
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("dxcc-json/dxcc.json").path
        let data = try (FileManager.default.fileExists(atPath: path)
                        ? Data(contentsOf: URL(fileURLWithPath: path)) : DxccTestFixture.data())
        let calls = Self.calls(20_000)

        let serialResolver = try DxccResolver.fromData(data)
        var serial: [DxccEntity?] = []
        let serialTime = ContinuousClock().measure {
            serial = calls.map { serialResolver.resolve($0) }
        }

        let shared = try DxccResolver.fromData(data)
        let threads = 8
        let results = ResultBox(count: calls.count)
        let parallelTime = ContinuousClock().measure {
            DispatchQueue.concurrentPerform(iterations: threads) { t in
                var i = t
                while i < calls.count {
                    results.set(i, shared.resolve(calls[i]))
                    i += threads
                }
            }
        }
        print("DxccResolver \(calls.count) callsigns: serial \(serialTime), \(threads) threads \(parallelTime)")
        let parallel = results.values()
        #expect(zip(serial, parallel).allSatisfy { $0?.entityCode == $1?.entityCode })
    }

    /// Deterministic callsigns (own LCG): a prefix of two letters/digits, a digit, 1–3 letters.
    static func calls(_ n: Int) -> [String] {
        var seed: UInt64 = 7
        func next(_ bound: Int) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((seed >> 33) % UInt64(bound))
        }
        let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        let alnum = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        var out = Set<String>()
        var ordered: [String] = []
        while ordered.count < n {
            var call = String(letters[next(26)])
            if next(2) == 0 { call.append(alnum[next(36)]) }
            call += String(next(10))
            for _ in 0...next(3) { call.append(letters[next(26)]) }
            if out.insert(call).inserted { ordered.append(call) }
        }
        return ordered
    }

    final class ResultBox: @unchecked Sendable {
        private var storage: [DxccEntity?]
        private let lock = NSLock()
        init(count: Int) { storage = Array(repeating: nil, count: count) }
        func set(_ index: Int, _ value: DxccEntity?) {
            lock.lock()
            storage[index] = value
            lock.unlock()
        }
        func values() -> [DxccEntity?] {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
    }
}
