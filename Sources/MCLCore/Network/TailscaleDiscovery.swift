import Foundation

/// The tailnet as the local Tailscale client reports it (`tailscale status --json`): whether it runs, and its peers.
/// Only what the cluster search needs is read; everything else in the answer is ignored.
public enum TailscaleStatus {

    /// One peer of the tailnet.
    public struct Peer: Equatable, Sendable {
        /// The machine name (`hub`).
        public var hostName: String
        /// The MagicDNS name without the final dot (`hub.tail1234.ts.net`); empty when the client gives none.
        public var dnsName: String
        /// The tailnet addresses (`100.x.y.z` first, then IPv6).
        public var addresses: [String]
        public var online: Bool

        public init(hostName: String, dnsName: String, addresses: [String], online: Bool) {
            self.hostName = hostName
            self.dnsName = dnsName
            self.addresses = addresses
            self.online = online
        }

        /// The name shown in the list: the machine name, else the first label of the MagicDNS name, else the address.
        public var name: String {
            if !hostName.isEmpty {
                return hostName
            }
            if let label = dnsName.split(separator: ".").first {
                return String(label)
            }
            return addresses.first ?? "?"
        }

        /// The address to probe and offer for a plain connection: the IPv4 one (works without MagicDNS).
        public var address: String? {
            addresses.first { !$0.contains(":") } ?? addresses.first
        }
    }

    /// What the client said.
    public enum Result: Equatable, Sendable {
        /// Neither the Tailscale app nor the `tailscale` command was found.
        case notInstalled
        /// The client answered but is not connected (its state, e.g. `Stopped`, `NeedsLogin`, or its message).
        case notRunning(String)
        /// Connected: the peers (this Mac itself is not among them).
        case peers([Peer])
    }

    /// The answer of `status --json`; anything that is not that JSON is the client's message (not running).
    public static func parse(_ data: Data) -> Result {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let text: String = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return .notRunning(text.isEmpty ? "?" : String(text.prefix(200)))
        }
        let state: String = object["BackendState"] as? String ?? "?"
        guard state == "Running" else { return .notRunning(state) }
        let table: [String: Any] = object["Peer"] as? [String: Any] ?? [:]
        var peers: [Peer] = []
        for key in table.keys.sorted() {
            guard let entry = table[key] as? [String: Any] else { continue }
            var dns: String = entry["DNSName"] as? String ?? ""
            if dns.hasSuffix(".") {
                dns.removeLast()
            }
            peers.append(Peer(hostName: entry["HostName"] as? String ?? "", dnsName: dns,
                              addresses: entry["TailscaleIPs"] as? [String] ?? [],
                              online: entry["Online"] as? Bool ?? false))
        }
        return .peers(peers.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
    }
}

/// Where the tailnet's peers come from; the production provider runs the Tailscale command line, tests a fake.
public protocol TailscaleStatusProvider: Sendable {
    /// Blocks (at most a few seconds) — call from a thread of your own.
    func status() -> TailscaleStatus.Result
}

/// The Tailscale client's own command line: the app's binary
/// (`/Applications/Tailscale.app/Contents/MacOS/Tailscale`, both the App Store and the standalone app) or the
/// `tailscale` command (Homebrew, `/usr/local/bin`). Only `status --json` is ever run — it reads the client's state and
/// changes nothing.
public struct TailscaleCli: TailscaleStatusProvider {

    public static let standardCandidates: [String] = [
        "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
        "/opt/homebrew/bin/tailscale",
        "/usr/local/bin/tailscale",
    ]

    let candidates: [String]
    let timeoutMs: Int

    public init(candidates: [String] = TailscaleCli.standardCandidates, timeoutMs: Int = 5_000) {
        self.candidates = candidates
        self.timeoutMs = timeoutMs
    }

    /// The first candidate that exists and can be run.
    var executable: String? {
        candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    public func status() -> TailscaleStatus.Result {
        guard let executable else { return .notInstalled }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["status", "--json"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        process.standardInput = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do {
            try process.run()
        } catch {
            return .notInstalled
        }
        // Read on its own thread so a large answer never fills the pipe while we wait.
        let collected = Collected()
        let reader = Thread {
            collected.set(output.fileHandleForReading.readDataToEndOfFile())
        }
        reader.start()
        if finished.wait(timeout: .now() + .milliseconds(timeoutMs)) == .timedOut {
            process.terminate()
            return .notRunning("timeout")
        }
        guard collected.wait(timeoutMs: timeoutMs) else { return .notRunning("timeout") }
        return TailscaleStatus.parse(collected.data)
    }

    private final class Collected: @unchecked Sendable {
        private let lock = NSLock()
        private let done = DispatchSemaphore(value: 0)
        private var value = Data()

        func set(_ data: Data) {
            lock.withLock { value = data }
            done.signal()
        }

        func wait(timeoutMs: Int) -> Bool {
            done.wait(timeout: .now() + .milliseconds(timeoutMs)) == .success
        }

        var data: Data { lock.withLock { value } }
    }
}

/// Whether an MQTT broker listens at an address: an MQTT CONNECT (a throwaway client id, no user name, no will) and
/// the first byte of the answer — a CONNACK (`0x20`), whatever its reason code (a broker that wants a password still
/// answers). Then DISCONNECT and close; nothing is subscribed or published.
public enum MqttBrokerProbe {

    public typealias Probe = @Sendable (_ host: String, _ port: Int, _ tls: Bool, _ timeoutMs: Int) -> Bool

    public static let live: Probe = { host, port, tls, timeoutMs in
        probe(host: host, port: port, tls: tls, timeoutMs: timeoutMs)
    }

    public static func probe(host: String, port: Int, tls: Bool, timeoutMs: Int,
                             factory: MqttTransportFactory = MqttTransports.standard) -> Bool {
        guard let transport = try? factory(MqttEndpoint(host: host, port: port, tls: tls), timeoutMs) else { return false }
        // `read` has no timeout of its own: closing the transport at the deadline ends it.
        let watchdog = DispatchWorkItem { transport.close() }
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(timeoutMs), execute: watchdog)
        defer {
            watchdog.cancel()
            transport.close()
        }
        let clientId: String = "mcl-probe-" + String(UInt32.random(in: 0...UInt32.max), radix: 16)
        guard let connect = try? MqttPacket.connect(MqttConnect(clientId: clientId, cleanStart: true,
                                                                keepAliveSeconds: 10)).encode(),
              (try? transport.write(connect)) != nil,
              let answer = (try? transport.read()) ?? nil, let first = answer.first else {
            return false
        }
        guard first == 0x20 else { return false }
        if let disconnect = try? MqttPacket.disconnect(MqttDisconnect(reasonCode: 0)).encode() {
            try? transport.write(disconnect)
        }
        return true
    }
}

/// A port the cluster search tries on every peer.
public struct TailscaleProbePort: Equatable, Sendable, Hashable {
    public var port: Int
    public var tls: Bool

    public init(port: Int, tls: Bool) {
        self.port = port
        self.tls = tls
    }

    /// The standard MQTT port and the one in the settings (with their TLS switch) when it is another.
    public static func list(configuredPort: Int?, tls: Bool) -> [TailscaleProbePort] {
        var out: [TailscaleProbePort] = [TailscaleProbePort(port: 1883, tls: false)]
        if let configuredPort, (1...65_535).contains(configuredPort) {
            let configured = TailscaleProbePort(port: configuredPort, tls: tls)
            if !out.contains(configured) {
                out.append(configured)
            }
        }
        return out
    }
}

/// The multi-op cluster (its MQTT broker) in the tailnet: the online peers of `tailscale status --json`, each
/// probed on the MQTT ports. Nothing outside the tailnet's peer list is ever contacted. Only on the operator's click.
public struct TailscaleClusterSearch: Sendable {

    /// What the search ended with.
    public enum Outcome: Equatable, Sendable {
        case notInstalled
        case notRunning(String)
        /// The brokers found and how many online peers were probed.
        case found([DiscoveredBroker], probed: Int)
    }

    /// At most this many peers are probed (a large tailnet is not swept).
    public static let maxPeers = 64

    let provider: any TailscaleStatusProvider
    let probe: MqttBrokerProbe.Probe
    let timeoutMs: Int

    public init(provider: any TailscaleStatusProvider, probe: @escaping MqttBrokerProbe.Probe = MqttBrokerProbe.live,
                timeoutMs: Int = 2_000) {
        self.provider = provider
        self.probe = probe
        self.timeoutMs = timeoutMs
    }

    /// Blocks until every probe answered or timed out — call from a thread of your own.
    public func run(ports: [TailscaleProbePort]) -> Outcome {
        let peers: [TailscaleStatus.Peer]
        switch provider.status() {
        case .notInstalled: return .notInstalled
        case .notRunning(let state): return .notRunning(state)
        case .peers(let all): peers = Array(all.filter(\.online).prefix(Self.maxPeers))
        }
        var targets: [(peer: TailscaleStatus.Peer, port: TailscaleProbePort, host: String)] = []
        for peer in peers {
            for port in ports {
                // TLS needs the name the certificate is for (MagicDNS); a plain connection uses the address.
                let host: String? = port.tls ? (peer.dnsName.isEmpty ? peer.address : peer.dnsName) : peer.address
                if let host {
                    targets.append((peer, port, host))
                }
            }
        }
        let results = Results(count: targets.count)
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "mcl.tailscale-probe", attributes: .concurrent)
        let probe: MqttBrokerProbe.Probe = self.probe
        let timeoutMs: Int = self.timeoutMs
        for (index, target) in targets.enumerated() {
            let host: String = target.host
            let port: TailscaleProbePort = target.port
            queue.async(group: group) {
                results.set(index, probe(host, port.port, port.tls, timeoutMs))
            }
        }
        group.wait()
        var found: [DiscoveredBroker] = []
        for (index, target) in targets.enumerated() where results.value(index) {
            found.append(DiscoveredBroker(name: target.peer.name, host: target.host, port: target.port.port,
                                          tls: target.port.tls))
        }
        return .found(found, probed: peers.count)
    }

    private final class Results: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [Bool]

        init(count: Int) {
            values = Array(repeating: false, count: count)
        }

        func set(_ index: Int, _ value: Bool) {
            lock.withLock { values[index] = value }
        }

        func value(_ index: Int) -> Bool {
            lock.withLock { values[index] }
        }
    }
}
