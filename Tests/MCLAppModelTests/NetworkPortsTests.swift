import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// The network is inert by default and with `MCL_INERT_NETWORK` present (any value but `"0"`); an inert
/// app opens no cluster connection — not the parallel ones at start, not the main one on request — and the callbook
/// and the browser reach nothing.
@MainActor @Suite struct NetworkPortsTests {

    @Test func theDefaultEnvironmentIsInert() {
        let environment = AppModel.Environment(dataDir: URL(fileURLWithPath: "/nonexistent"), dxccDir: nil,
                                               rescoreClock: ManualClock(), geometryClock: ManualClock())
        #expect(environment.network.isInert)
    }

    @Test(arguments: ["1", "", "true", "yes", "no", "00"])
    func theVariableMakesProductionInert(_ value: String) {
        #expect(NetworkPorts.production(environment: [NetworkPorts.inertVariable: value]).isInert)
        #expect(AppModel.Environment.production(processEnvironment: [
            NetworkPorts.inertVariable: value, HardwarePorts.inertVariable: "1",
        ]).network.isInert)
    }

    /// The live reading is the shared rule (absent or exactly `"0"`), checked without building the live ports.
    @Test func onlyAbsentOrZeroIsLive() {
        #expect(!HardwarePorts.isInert([:], variable: NetworkPorts.inertVariable))
        #expect(!HardwarePorts.isInert([NetworkPorts.inertVariable: "0"], variable: NetworkPorts.inertVariable))
    }

    @Test func anInertAppConnectsNothing() async throws {
        let server = try FakeTelnetServer()
        let app = try await TestApp.make { config, _ in
            config.dxCluster.favorites = [server.favorite(name: "Parallel", login: "OK1XXX", parallel: true)]
            CallbookModelTests.credentials(&config)
        }
        let dx: DxClusterModel = app.model.dxCluster
        dx.toggle(server.favorite(name: "Main", login: "OK1XXX"))
        dx.login(server.favorite(name: "Main", login: "OK1XXX"))
        dx.send("SH/DX")
        await dx.settle()
        #expect(server.connectionCount == 0)
        #expect(!dx.connected)
        #expect(dx.statusText == "Odpojeno")
        #expect(dx.parallel.values.allSatisfy { !$0.connected && $0.status == "Odpojeno" })
        #expect(dx.log.snapshot().contains { $0.hasSuffix("· " + NetworkPorts.disabledMessage) })

        let callbook: CallbookModel = app.model.callbook
        callbook.lookup("OK1ABC", typedCall: { "OK1ABC" })
        await callbook.settle()
        #expect(callbook.callbookRecord == nil)
        #expect(callbook.cache.record("OK1ABC") == .empty)
        callbook.openQrz("OK1ABC")
        await callbook.settle()
    }
}
