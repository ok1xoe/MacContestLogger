import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// The Bonjour search for an MQTT broker (Settings → Cluster): only on request, never under the inert network, and
/// the found brokers are offered. The discoverer is a fake; nothing is browsed.
@MainActor @Suite struct BrokerDiscoveryTests {

    final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        var count: Int { lock.withLock { value } }
        func add() { lock.withLock { value += 1 } }
    }

    @Test func foundBrokersAreOffered() async throws {
        let calls = Calls()
        let found = [DiscoveredBroker(name: "hub", host: "192.168.1.10", port: 1883, tls: false)]
        let app = try await TestApp.make(adjust: { environment in
            var ports: NetworkPorts = NetworkPorts.inert
            ports.isInert = false
            ports.discoverBrokers = { _, done in
                calls.add()
                done(found)
            }
            environment.network = ports
        })
        #expect(calls.count == 0)
        app.model.cluster.discoverBrokers()
        await eventually("found") { app.model.cluster.discoveredBrokers == found }
        #expect(!app.model.cluster.discovering)
        #expect(calls.count == 1)
        #expect(app.model.status.message == "Nalezené MQTT brokery v místní síti: 1")
    }

    @Test func theInertNetworkSearchesNothing() async throws {
        let calls = Calls()
        let app = try await TestApp.make(adjust: { environment in
            var ports: NetworkPorts = NetworkPorts.inert
            ports.discoverBrokers = { _, done in
                calls.add()
                done([])
            }
            environment.network = ports
        })
        app.model.cluster.discoverBrokers()
        await runMainQueue()
        #expect(calls.count == 0)
        #expect(app.model.cluster.discoveredBrokers.isEmpty)
        #expect(app.model.status.message == "V místní síti není žádný MQTT broker ohlášený přes Bonjour")
        // The production switch never hands the live discoverer to an inert run.
        let production = NetworkPorts.production(environment: [NetworkPorts.inertVariable: "1"])
        #expect(production.isInert)
    }

    @Test func brokerTexts() {
        #expect(DiscoveredBroker.hostText("fe80::1%en0") == "fe80::1")
        #expect(DiscoveredBroker.hostText("hub.local.") == "hub.local")
        let a = DiscoveredBroker(name: "b", host: "10.0.0.2", port: 8883, tls: true)
        let b = DiscoveredBroker(name: "a", host: "10.0.0.1", port: 1883, tls: false)
        let again = DiscoveredBroker(name: "a", host: "fe80::1", port: 1883, tls: false)
        #expect(DiscoveredBroker.unique([a, b, again]) == [b, a])
        #expect(a.label == "b — 10.0.0.2:8883 (TLS)")
    }
}
