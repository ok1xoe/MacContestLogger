import Foundation
@testable import MCLCore
import Testing

/// The multi-op cluster search over Tailscale: the peers of `tailscale status --json` (a fake answer and a fake
/// command, never the real client) and the MQTT probe (a fake responder on 127.0.0.1 with an ephemeral port).
@Suite struct TailscaleDiscoveryTests {

    static let running = """
    {
      "Version": "1.76.1",
      "BackendState": "Running",
      "Self": {"HostName": "this-mac", "DNSName": "this-mac.tail1234.ts.net.", "TailscaleIPs": ["100.64.0.1"], "Online": true},
      "Peer": {
        "nodekey:b": {"HostName": "hub", "DNSName": "hub.tail1234.ts.net.",
                      "TailscaleIPs": ["fd7a:115c:a1e0::2", "100.64.0.2"], "Online": true, "OS": "linux"},
        "nodekey:a": {"HostName": "Op2-MacBook", "DNSName": "op2-macbook.tail1234.ts.net.",
                      "TailscaleIPs": ["100.64.0.3"], "Online": false, "OS": "macOS"},
        "nodekey:c": {"HostName": "", "DNSName": "phone.tail1234.ts.net.", "TailscaleIPs": ["100.64.0.4"], "Online": true}
      }
    }
    """

    @Test func statusIsParsed() {
        let result = TailscaleStatus.parse(Data(Self.running.utf8))
        #expect(result == .peers([
            TailscaleStatus.Peer(hostName: "hub", dnsName: "hub.tail1234.ts.net",
                                 addresses: ["fd7a:115c:a1e0::2", "100.64.0.2"], online: true),
            TailscaleStatus.Peer(hostName: "Op2-MacBook", dnsName: "op2-macbook.tail1234.ts.net",
                                 addresses: ["100.64.0.3"], online: false),
            TailscaleStatus.Peer(hostName: "", dnsName: "phone.tail1234.ts.net", addresses: ["100.64.0.4"], online: true),
        ]))
        if case .peers(let peers) = result {
            #expect(peers.map(\.name) == ["hub", "Op2-MacBook", "phone"])
            #expect(peers[0].address == "100.64.0.2")
        }
        #expect(TailscaleStatus.parse(Data(#"{"BackendState": "Stopped", "Peer": null}"#.utf8)) == .notRunning("Stopped"))
        #expect(TailscaleStatus.parse(Data(#"{"BackendState": "NeedsLogin"}"#.utf8)) == .notRunning("NeedsLogin"))
        #expect(TailscaleStatus.parse(Data("Tailscale is stopped.\n".utf8)) == .notRunning("Tailscale is stopped."))
        #expect(TailscaleStatus.parse(Data(#"{"BackendState": "Running"}"#.utf8)) == .peers([]))
    }

    /// The command line provider runs only `status --json` of the first command it finds — here a fake script that
    /// records its arguments; a missing command is "not installed".
    @Test func theCommandLineProviderRunsOnlyStatusJson() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mcl-ts-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let json: URL = dir.appendingPathComponent("status.json")
        try Data(Self.running.utf8).write(to: json)
        let script: URL = dir.appendingPathComponent("tailscale")
        let args: URL = dir.appendingPathComponent("args.txt")
        try """
        #!/bin/sh
        echo "$@" > '\(args.path)'
        cat '\(json.path)'
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let missing: String = dir.appendingPathComponent("nothing-here").path
        let cli = TailscaleCli(candidates: [missing, script.path], timeoutMs: 600_000)  // generous: slow CI runners
        // Blocking calls run on a thread of their own, never on the shared pool of the test run.
        let status: TailscaleStatus.Result = await onOwnThread { cli.status() }
        guard case .peers(let peers) = status else {
            Issue.record("expected peers")
            return
        }
        #expect(peers.count == 3)
        #expect(try String(contentsOf: args, encoding: .utf8) == "status --json\n")
        let none: TailscaleStatus.Result = await onOwnThread { TailscaleCli(candidates: [missing]).status() }
        #expect(none == .notInstalled)
        #expect(TailscaleCli.standardCandidates.first == "/Applications/Tailscale.app/Contents/MacOS/Tailscale")
    }

    /// A fake MQTT broker: answers CONNECT with CONNACK (reason `code`) and records every byte it receives.
    final class FakeBroker: @unchecked Sendable {
        private let lock = NSLock()
        private var received: [UInt8] = []
        private var listener: LoopbackListener!

        init(answer: [UInt8]? = [0x20, 0x03, 0x00, 0x00, 0x00]) throws {
            listener = try LoopbackListener(name: "fake-mqtt") { [self] connection in
                var first = true
                while let chunk = connection.receive() {
                    lock.withLock { received.append(contentsOf: chunk) }
                    if first, let answer {
                        connection.send(answer)
                    }
                    first = false
                }
            }
        }

        var port: Int { listener.port }
        var bytes: [UInt8] { lock.withLock { received } }
        func stop() { listener.stop() }
    }

    @Test func theProbeKnowsABrokerAndSendsNothingElse() async throws {
        let broker = try FakeBroker()
        defer { broker.stop() }
        let port: Int = broker.port
        let found: Bool = await onOwnThread { MqttBrokerProbe.probe(host: "127.0.0.1", port: port, tls: false, timeoutMs: 5_000) }
        #expect(found)
        let disconnect: [UInt8] = try MqttPacket.disconnect(MqttDisconnect()).encode()
        // The probe returns after writing DISCONNECT; the fake receives it on its own thread (no time limit asserted).
        for _ in 0..<2_000 where broker.bytes.count < 2 || broker.bytes.count < 2 + Int(broker.bytes[1]) + disconnect.count {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        let bytes: [UInt8] = broker.bytes
        #expect(bytes.first == 0x10, "CONNECT first")
        #expect(Array(bytes.suffix(disconnect.count)) == disconnect)
        // Only CONNECT and DISCONNECT: no PUBLISH (0x3x) or SUBSCRIBE (0x82) — the CONNECT packet's own length
        // says where it ends.
        #expect(bytes.count == 2 + Int(bytes[1]) + disconnect.count)
        // A broker that refuses the anonymous client still answers with a CONNACK: it is found.
        let strict = try FakeBroker(answer: [0x20, 0x03, 0x00, 0x87, 0x00])
        defer { strict.stop() }
        let strictPort: Int = strict.port
        #expect(await onOwnThread { MqttBrokerProbe.probe(host: "127.0.0.1", port: strictPort, tls: false, timeoutMs: 5_000) })
    }

    @Test func otherServicesAreNotBrokers() async throws {
        let web = try FakeBroker(answer: Array("HTTP/1.1 400 Bad Request\r\n\r\n".utf8))
        defer { web.stop() }
        let webPort: Int = web.port
        #expect(!(await onOwnThread { MqttBrokerProbe.probe(host: "127.0.0.1", port: webPort, tls: false, timeoutMs: 5_000) }))
        // Silent: the deadline closes the connection.
        let silent = try FakeBroker(answer: nil)
        defer { silent.stop() }
        let silentPort: Int = silent.port
        #expect(!(await onOwnThread { MqttBrokerProbe.probe(host: "127.0.0.1", port: silentPort, tls: false, timeoutMs: 200) }))
        let closed: Int = FreeLoopbackPort.take()
        #expect(!(await onOwnThread { MqttBrokerProbe.probe(host: "127.0.0.1", port: closed, tls: false, timeoutMs: 2_000) }))
    }

    struct FakeProvider: TailscaleStatusProvider {
        let result: TailscaleStatus.Result
        func status() -> TailscaleStatus.Result { result }
    }

    final class Probes: @unchecked Sendable {
        private let lock = NSLock()
        private var value: [String] = []
        var calls: [String] { lock.withLock { value.sorted() } }
        func add(_ call: String) { lock.withLock { value.append(call) } }
    }

    @Test func onlyOnlinePeersAreProbedOnTheMqttPorts() async {
        let probes = Probes()
        let peers: [TailscaleStatus.Peer] = [
            .init(hostName: "hub", dnsName: "hub.ts.net", addresses: ["100.64.0.2"], online: true),
            .init(hostName: "away", dnsName: "away.ts.net", addresses: ["100.64.0.3"], online: false),
            .init(hostName: "op2", dnsName: "", addresses: ["100.64.0.4"], online: true),
        ]
        let search = TailscaleClusterSearch(provider: FakeProvider(result: .peers(peers)), probe: { host, port, tls, _ in
            probes.add("\(host):\(port)\(tls ? "s" : "")")
            return host == "100.64.0.2" || (host == "hub.ts.net" && tls)
        })
        let ports: [TailscaleProbePort] = TailscaleProbePort.list(configuredPort: 8883, tls: true)
        #expect(ports == [TailscaleProbePort(port: 1883, tls: false), TailscaleProbePort(port: 8883, tls: true)])
        #expect(TailscaleProbePort.list(configuredPort: 1883, tls: false) == [TailscaleProbePort(port: 1883, tls: false)])
        #expect(TailscaleProbePort.list(configuredPort: nil, tls: false) == [TailscaleProbePort(port: 1883, tls: false)])
        let outcome: TailscaleClusterSearch.Outcome = await onOwnThread { search.run(ports: ports) }
        #expect(probes.calls == ["100.64.0.2:1883", "100.64.0.4:1883", "100.64.0.4:8883s", "hub.ts.net:8883s"])
        #expect(outcome == .found([
            DiscoveredBroker(name: "hub", host: "100.64.0.2", port: 1883, tls: false),
            DiscoveredBroker(name: "hub", host: "hub.ts.net", port: 8883, tls: true),
        ], probed: 2))
        let never: MqttBrokerProbe.Probe = { _, _, _, _ in
            Issue.record("nothing may be probed")
            return false
        }
        let missing = TailscaleClusterSearch(provider: FakeProvider(result: .notInstalled), probe: never)
        let notInstalled: TailscaleClusterSearch.Outcome = await onOwnThread { missing.run(ports: ports) }
        #expect(notInstalled == .notInstalled)
        let stopped = TailscaleClusterSearch(provider: FakeProvider(result: .notRunning("Stopped")), probe: never)
        let notRunning: TailscaleClusterSearch.Outcome = await onOwnThread { stopped.run(ports: ports) }
        #expect(notRunning == .notRunning("Stopped"))
        let many: [TailscaleStatus.Peer] = (0..<100).map {
            .init(hostName: "p\($0)", dnsName: "", addresses: ["100.64.1.\($0)"], online: true)
        }
        let counted = Probes()
        let bigSearch = TailscaleClusterSearch(provider: FakeProvider(result: .peers(many)), probe: { host, _, _, _ in
            counted.add(host)
            return false
        })
        let big: TailscaleClusterSearch.Outcome = await onOwnThread { bigSearch.run(ports: [TailscaleProbePort(port: 1883, tls: false)]) }
        #expect(big == .found([], probed: TailscaleClusterSearch.maxPeers))
        #expect(counted.calls.count == TailscaleClusterSearch.maxPeers)
    }

    /// End to end with the real probe: a peer at 127.0.0.1 and the fake broker's port.
    @Test func aBrokerOnAPeerIsFound() async throws {
        let broker = try FakeBroker()
        defer { broker.stop() }
        let peer = TailscaleStatus.Peer(hostName: "hub", dnsName: "hub.ts.net", addresses: ["127.0.0.1"], online: true)
        let search = TailscaleClusterSearch(provider: FakeProvider(result: .peers([peer])), timeoutMs: 5_000)
        let port: Int = broker.port
        let outcome = await onOwnThread { search.run(ports: [TailscaleProbePort(port: port, tls: false)]) }
        #expect(outcome == .found([DiscoveredBroker(name: "hub", host: "127.0.0.1", port: port, tls: false)], probed: 1))
    }
}
