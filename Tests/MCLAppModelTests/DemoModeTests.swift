import Foundation
import os
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// The maintainers' screenshot demo is honoured only with both inert switches, and then opens nothing but loopback.
@Suite struct DemoModeTests {

    private static func directory(_ json: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("demo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: dir.appendingPathComponent("demo.json"))
        return dir
    }

    @Test func needsBothInertSwitches() throws {
        let dir: URL = try Self.directory(#"{"clusterPort": 7300}"#)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path: String = dir.path
        #expect(DemoMode.from(["MCL_DEMO_DIR": path]) == nil)
        #expect(DemoMode.from(["MCL_DEMO_DIR": path, "MCL_INERT_HARDWARE": "1"]) == nil)
        #expect(DemoMode.from(["MCL_DEMO_DIR": path, "MCL_INERT_NETWORK": "1"]) == nil)
        #expect(DemoMode.from(["MCL_DEMO_DIR": path, "MCL_INERT_HARDWARE": "0", "MCL_INERT_NETWORK": "1"]) == nil)
        #expect(DemoMode.from(["MCL_DEMO_DIR": path, "MCL_INERT_HARDWARE": "1", "MCL_INERT_NETWORK": "1"]) != nil)
        #expect(DemoMode.from(["MCL_INERT_HARDWARE": "1", "MCL_INERT_NETWORK": "1"]) == nil)
    }

    @Test func withoutPortsTheNetworkStaysInert() throws {
        let dir: URL = try Self.directory(#"{"rigs": [{"freqHz": 14025000, "mode": "CW"}]}"#)
        defer { try? FileManager.default.removeItem(at: dir) }
        let demo = try #require(DemoMode.from(["MCL_DEMO_DIR": dir.path, "MCL_INERT_HARDWARE": "1",
                                               "MCL_INERT_NETWORK": "1"]))
        #expect(demo.network().isInert)
        #expect(demo.hardware().isInert)
    }

    @Test func theDemoRigConnectsAndFollowsTheTuning() throws {
        let start = DemoMode.Script.Rig(freqHz: 14_025_000, mode: "CW", passband: nil)
        let seen = OSAllocatedUnfairLock<[CatSession.Snapshot]>(initialState: [])
        let hooks = CatHooks(index: 0, transverters: { [] }, modes: { HamlibModeMapping(dataMode: .ft8, rttyAfsk: true) }, log: CatTrafficLog(maxLines: 10),
                             translate: { $0 }, onChange: { snapshot in seen.withLock { $0.append(snapshot) } },
                             onUnexpectedError: { _ in })
        let cat = DemoCat(hooks: hooks, start: start)
        cat.connect(RigConfig())
        #expect(cat.snapshot.connected)
        #expect(cat.snapshot.state?.freqHz == 14_025_000)
        try cat.tune(7_012_300)
        #expect(cat.snapshot.state?.freqHz == 7_012_300)
        #expect(cat.snapshot.state?.mode == .cw)
        cat.disconnect(String?.none)
        #expect(!cat.snapshot.connected)
        #expect(seen.withLock { $0.count } == 3)
    }
}
