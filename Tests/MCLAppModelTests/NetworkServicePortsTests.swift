import Darwin
import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// A UDP receiver on `127.0.0.1` with a port the system picks — it only reports whether a datagram arrived. A loopback
/// send is delivered inside the kernel before `sendto` returns, so a non-blocking read right after the call is exact.
final class FakeUdpReceiver: @unchecked Sendable {
    let port: Int
    private let fd: Int32

    init() throws {
        let socketFd: Int32 = Darwin.socket(AF_INET, SOCK_DGRAM, 0)
        guard socketFd >= 0 else { throw POSIXError(.EIO) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound: Int32 = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketFd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else {
            close(socketFd)
            throw POSIXError(.EADDRINUSE)
        }
        var actual = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &actual) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(socketFd, $0, &length) }
        }
        fd = socketFd
        port = Int(UInt16(bigEndian: actual.sin_port))
        guardTestPort(port)
    }

    deinit {
        close(fd)
    }

    /// `true` when a datagram is waiting (consumes it).
    func receivedDatagram() -> Bool {
        var buffer = [UInt8](repeating: 0, count: 2048)
        return recv(fd, &buffer, buffer.count, MSG_DONTWAIT) >= 0
    }
}

/// The ports of `NetworkPorts`: the MQTT transport, the UDP services, the NTP probe and the plugins are inert by
/// default and under `MCL_INERT_NETWORK` (plugins under `MCL_INERT_HARDWARE` too); an inert app opens nothing.
@MainActor @Suite struct NetworkServicePortsTests {

    /// Counts the calls of the factories of a stand-in for `NetworkPorts.live` (nothing is opened).
    final class LiveCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var counts: [String: Int] = [:]

        func hit(_ name: String) { lock.withLock { counts[name, default: 0] += 1 } }
        func count(_ name: String) -> Int { lock.withLock { counts[name, default: 0] } }
    }

    struct CountingHttp: HttpGetter {
        let counter: LiveCounter
        func get(_ url: String) throws(HttpGetFailure) -> HttpGetResponse {
            counter.hit("http")
            throw HttpGetFailure("counting stand-in")
        }
    }

    static func countingLive(_ counter: LiveCounter) -> NetworkPorts {
        let udp = UdpPorts(
            makeWsjtxListener: { _, _, _ in counter.hit("udp"); return nil },
            makeN1mmListener: { _, _, _ in counter.hit("udp"); return nil },
            makeAdifListener: { _, _, _ in counter.hit("udp"); return nil },
            makeBroadcaster: { counter.hit("udp"); return InertBroadcaster() })
        return NetworkPorts(
            makeSession: { hooks in InertClusterSession(log: hooks.log) }, http: CountingHttp(counter: counter),
            urlOpener: .inert,
            makeSyncTransport: { _, _ in counter.hit("mqtt"); return InertSyncTransport() },
            udp: udp,
            online: OnlinePorts(uploadClubLog: { _, _, _, _, _ in counter.hit("online"); return .OK },
                                postScore: { _, _ in counter.hit("online"); return 200 }),
            clock: { _ in counter.hit("ntp"); return 0 },
            plugins: PluginsPorts { _, _ in counter.hit("plugins"); return nil }, isInert: false)
    }

    /// Invokes every service factory of the ports once.
    static func exercise(_ ports: NetworkPorts) async {
        _ = try? ports.makeSyncTransport(ClusterConfig(), URL(fileURLWithPath: "/nonexistent"))
        _ = try? ports.udp.makeWsjtxListener("127.0.0.1", 0, WsjtxListener.Handler(onLoggedAdif: { _ in }))
        _ = try? ports.udp.makeN1mmListener("127.0.0.1", 0, { _ in })
        _ = try? ports.udp.makeAdifListener("127.0.0.1", 0, { _ in })
        _ = try? ports.udp.makeBroadcaster()
        _ = try? ports.http.get("http://127.0.0.1/")
        _ = try? ports.online.uploadClubLog("user", "secret", "OK1XXX", "key", "<eor>")
        _ = try? ports.online.postScore("https://scoreboard.example.test/", "<xml/>")
        _ = try? await ports.clock("127.0.0.1")
        _ = ports.plugins.makeRunner("/nonexistent", 1)
    }

    /// Per switch combination: under `MCL_INERT_NETWORK` no live factory runs; under `MCL_INERT_HARDWARE` only the
    /// plugins stay off; otherwise every service reaches its live factory.
    @Test(arguments: [nil, "0", "1", ""] as [String?], [nil, "0", "1", ""] as [String?])
    func productionReadsBothSwitches(network: String?, hardware: String?) async {
        var environment: [String: String] = [:]
        if let network { environment[NetworkPorts.inertVariable] = network }
        if let hardware { environment[HardwarePorts.inertVariable] = hardware }
        let networkInert: Bool = network != nil && network != "0"
        let hardwareInert: Bool = hardware != nil && hardware != "0"
        let counter = LiveCounter()
        let ports: NetworkPorts = NetworkPorts.production(environment: environment, live: Self.countingLive(counter))
        await Self.exercise(ports)
        let services: [String] = ["mqtt", "udp", "http", "online", "ntp", "plugins"]
        for service in services {
            let expected: Int
            if networkInert || (service == "plugins" && hardwareInert) {
                expected = 0
            } else {
                expected = service == "udp" ? 4 : (service == "online" ? 2 : 1)
            }
            let label = "\(service), network=\(network ?? "unset"), hardware=\(hardware ?? "unset")"
            #expect(counter.count(service) == expected, Comment(rawValue: label))
        }
    }

    @Test func inertPortsOpenNothing() async throws {
        let ports: NetworkPorts = .inert
        let handler = WsjtxListener.Handler(onLoggedAdif: { _ in })
        #expect(try ports.udp.makeWsjtxListener("127.0.0.1", 0, handler) == nil)
        #expect(try ports.udp.makeN1mmListener("127.0.0.1", 0, { _ in }) == nil)
        #expect(try ports.udp.makeAdifListener("127.0.0.1", 0, { _ in }) == nil)
        #expect(ports.plugins.makeRunner("/nonexistent", 10_000) == nil)
        #expect(throws: SyncTransportError.self) {
            _ = try ports.online.uploadClubLog("user", "secret", "OK1XXX", "key", "<eor>")
        }
        #expect(throws: SyncTransportError.self) {
            _ = try ports.online.postScore("https://scoreboard.example.test/", "<xml/>")
        }
        await #expect(throws: SyncTransportError.self) { _ = try await ports.clock("127.0.0.1") }
    }

    @Test func theDefaultEnvironmentBindsAndSendsNothing() throws {
        let environment = AppModel.Environment(dataDir: URL(fileURLWithPath: "/nonexistent"), dxccDir: nil,
                                               rescoreClock: ManualClock(), geometryClock: ManualClock())
        let receiver = try FakeUdpReceiver()
        let udp: UdpPorts = environment.network.udp
        #expect(try udp.makeWsjtxListener("127.0.0.1", 0, WsjtxListener.Handler(onLoggedAdif: { _ in })) == nil)
        let broadcaster: any Broadcaster = try udp.makeBroadcaster()
        broadcaster.send("<xml/>", [Target(host: "127.0.0.1", port: Int32(receiver.port))])
        broadcaster.send([1, 2, 3], [Target(host: "127.0.0.1", port: Int32(receiver.port))])
        #expect(!receiver.receivedDatagram())
        broadcaster.close()
    }

    @Test func theDefaultEnvironmentCreatesNoConnection() throws {
        let environment = AppModel.Environment(dataDir: URL(fileURLWithPath: "/nonexistent"), dxccDir: nil,
                                               rescoreClock: ManualClock(), geometryClock: ManualClock())
        let broker = try FakeTelnetServer()
        var config = ClusterConfig()
        config.enabled = true
        config.brokerHost = FakeTelnetServer.host
        config.port = broker.port
        config.stationId = "OP1"
        let transport: any SyncTransport = try environment.network.makeSyncTransport(
            config, URL(fileURLWithPath: "/nonexistent"))
        #expect(!transport.isConnected)
        #expect(throws: SyncTransportError.self) { try transport.connect() }
        #expect(!transport.isConnected)
        transport.close()
        #expect(broker.connectionCount == 0)
        broker.stop()
    }
}
