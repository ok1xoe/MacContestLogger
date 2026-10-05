import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// The transports an app asked its ports for (never a socket: the factory hands out a `LinkedTransport`).
final class MadeTransports: @unchecked Sendable {
    private let lock = NSLock()
    private var configs: [ClusterConfig] = []
    private var transports: [LinkedTransport] = []

    var all: [ClusterConfig] { lock.withLock { configs } }
    var count: Int { all.count }
    var made: [LinkedTransport] { lock.withLock { transports } }

    /// The first request gets `first`, later ones (a restart) a new transport on the same hub — the old one is closed.
    func next(_ config: ClusterConfig, first: LinkedTransport, hub: InMemorySyncTransport) -> LinkedTransport {
        lock.withLock {
            configs.append(config)
            let transport: LinkedTransport = transports.isEmpty ? first : LinkedTransport(hub: hub)
            transports.append(transport)
            return transport
        }
    }
}

/// One station of a test network: an app over a temporary data directory whose sync transport is a
/// `LinkedTransport` on a shared hub (in memory), with fake keying hardware and manual clocks for the cluster and the
/// keyer. The inert network ports stay in force for everything else, so no other service opens.
@MainActor
struct NetStation {
    let keying: KeyingApp
    let transport: LinkedTransport
    let clusterClock: ManualClock
    let made: MadeTransports

    /// The time the stations start at (shared by the stations of a network, moved by the test).
    static func start() -> TestNow {
        TestNow(Date(timeIntervalSince1970: 1_800_000_000))
    }

    var app: TestApp { keying.app }
    var model: AppModel { keying.app.model }
    var cluster: ClusterSyncModel { model.cluster }
    var network: NetworkModel { model.network }
    var status: String { model.status.message }

    /// - Parameters:
    ///   - enabled: `cluster.enabled`; the broker host is a name only (the factory never opens it)
    static func make(id: String, hub: InMemorySyncTransport, now: TestNow = NetStation.start(),
                     link: LinkedTransport? = nil, enabled: Bool = true,
                     configure: @escaping (inout AppConfig) -> Void = { _ in },
                     adjust: (inout AppModel.Environment) -> Void = { _ in }) async throws -> NetStation {
        let transport: LinkedTransport = link ?? LinkedTransport(hub: hub)
        let made = MadeTransports()
        let hardware = FakeHardware()
        let fakeKeying = FakeKeyingHardware()
        let keyerClock = ManualClock()
        let radioClock = ManualClock()
        let clusterClock = ManualClock()
        let app = try await TestApp.make(now: now, configure: { config, _ in
            winkeyerConfig(&config)
            config.cluster.enabled = enabled
            config.cluster.brokerHost = "broker.invalid"
            config.cluster.stationId = id
            configure(&config)
        }, adjust: { environment in
            environment.hardware = fakeKeying.ports(over: hardware.ports)
            environment.keyerClock = keyerClock
            environment.rotatorClock = ManualClock()
            environment.radioWindowClock = radioClock
            environment.clusterClock = clusterClock
            var ports: NetworkPorts = NetworkPorts.inert
            ports.makeSyncTransport = { config, _ in
                made.next(config, first: transport, hub: hub)
            }
            ports.isInert = false
            environment.network = ports
            adjust(&environment)
        })
        let keying = KeyingApp(app: app, hardware: hardware, keying: fakeKeying, clock: keyerClock,
                               radioClock: radioClock)
        return NetStation(keying: keying, transport: transport, clusterClock: clusterClock, made: made)
    }

    /// Starts CQ WW CW (the activation starts the cluster) and waits for the session to connect.
    func activate() async throws {
        try await app.startCqWwCw()
        await eventually("\(model.config.config.cluster.stationId) connected") { cluster.isRunning && cluster.connected }
    }

    /// Lets the lane, the hops and a re-read of the log finish.
    func settle() async {
        await cluster.settle()
        await keying.settle()
    }

    /// Types and logs one QSO through the entry window (CQ WW zone exchange).
    func log(_ call: String, zone: String = "14") async {
        await app.logContestQso(call: call, zone: zone)
        await settle()
    }
}
