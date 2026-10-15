import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// The Bonjour search for an MQTT broker and the search for the cluster among the Tailscale peers (Settings →
/// Cluster): only on request, never under the inert network, and the found brokers are offered. The discoverers are
/// fakes; nothing is browsed, run or probed.
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

    // MARK: - Tailscale

    final class Asked: @unchecked Sendable {
        private let lock = NSLock()
        private var value: [[TailscaleProbePort]] = []
        var ports: [[TailscaleProbePort]] { lock.withLock { value } }
        func add(_ ports: [TailscaleProbePort]) { lock.withLock { value.append(ports) } }
    }

    static func tailscaleApp(_ asked: Asked, answer: TailscaleClusterSearch.Outcome) async throws -> TestApp {
        try await TestApp.make(adjust: { environment in
            var ports: NetworkPorts = NetworkPorts.inert
            ports.isInert = false
            ports.discoverTailscale = { probePorts, done in
                asked.add(probePorts)
                done(answer)
            }
            environment.network = ports
        })
    }

    @Test func theClusterFoundInTheTailnetIsOffered() async throws {
        let asked = Asked()
        let found = [DiscoveredBroker(name: "hub", host: "100.64.0.2", port: 1883, tls: false),
                     DiscoveredBroker(name: "hub", host: "hub.tail1234.ts.net", port: 8883, tls: true)]
        let app = try await Self.tailscaleApp(asked, answer: .found(found, probed: 3))
        #expect(asked.ports.isEmpty, "nothing runs before the click")
        app.model.cluster.discoverTailscaleCluster(port: "8883", tls: true)
        await eventually("found") { app.model.cluster.discoveredBrokers == found }
        #expect(!app.model.cluster.discovering)
        #expect(asked.ports == [[TailscaleProbePort(port: 1883, tls: false), TailscaleProbePort(port: 8883, tls: true)]])
        #expect(app.model.status.message == "Nalezené MQTT brokery v tailnetu: 2")
    }

    @Test func tailscaleProblemsAreExplained() async throws {
        let missing = try await Self.tailscaleApp(Asked(), answer: .notInstalled)
        missing.model.cluster.discoverTailscaleCluster(port: "", tls: false)
        await eventually("missing") { !missing.model.cluster.discovering }
        #expect(missing.model.status.message
                == "Tailscale není nainstalovaný (aplikace Tailscale ani příkaz tailscale nenalezeny)")
        let stopped = try await Self.tailscaleApp(Asked(), answer: .notRunning("Stopped"))
        stopped.model.cluster.discoverTailscaleCluster(port: "1883", tls: false)
        await eventually("stopped") { !stopped.model.cluster.discovering }
        #expect(stopped.model.status.message == "Tailscale není připojený (Stopped) — spusťte a přihlaste Tailscale")
        let none = try await Self.tailscaleApp(Asked(), answer: .found([], probed: 4))
        none.model.cluster.discoverTailscaleCluster(port: "1883", tls: false)
        await eventually("none") { !none.model.cluster.discovering }
        #expect(none.model.cluster.discoveredBrokers.isEmpty)
        #expect(none.model.status.message == "Žádná z 4 stanic tailnetu online neodpovídá jako MQTT broker")
    }

    @Test func theInertNetworkRunsNoTailscaleSearch() async throws {
        let asked = Asked()
        let app = try await TestApp.make(adjust: { environment in
            var ports: NetworkPorts = NetworkPorts.inert
            ports.discoverTailscale = { probePorts, done in
                asked.add(probePorts)
                done(.notInstalled)
            }
            environment.network = ports
        })
        app.model.cluster.discoverTailscaleCluster(port: "1883", tls: false)
        await runMainQueue()
        #expect(asked.ports.isEmpty)
        #expect(app.model.status.message == "Síť je vypnutá (MCL_INERT_NETWORK)")
        let inertAsked = Asked()
        NetworkPorts.inert.discoverTailscale([TailscaleProbePort(port: 1883, tls: false)]) { outcome in
            if outcome == .notInstalled {
                inertAsked.add([])
            }
        }
        #expect(inertAsked.ports == [[]])
    }
}
