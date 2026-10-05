import Darwin
import Foundation
import Testing
@testable import MCLCore

/// Scripts and their execution for the gate `NetConversationParityTests`: a mirror of
/// a maintainer-only probe over the Swift clients. The scripts are read from
/// `Fixtures/net-gate/conversation.txt` (format in the file header) — the same file is read by the generator, the scenario rows
/// are an input of the item (fingerprint), so changing it without regenerating reports "REGENERATE REFERENCE".
///
/// One dedicated thread drives the scenario (`onOwnThread`): the stand-in side (POSIX sockets on 127.0.0.1, `FakeHttpServer`)
/// and the client calls. The shared Swift pool only waits. Every wait is event-based (a condition, `poll`, a blocking
/// receive) and every one of them is a success path — the Java reference expects no `<timeout>` anywhere. Their only bound
/// is the hang guard `hangGuardMs`, above the length of a whole strict-pool run of the suite and below the suite's
/// `ioSafetyNet`: it never decides a result under load, it only turns a hang into `<timeout>` (a MISMATCH) instead of a
/// test that never ends (a time limit cannot stop a thread blocked in a wait). The earlier 20 s limit was a wall-clock
/// bound on the success path: under the load of a full parallel run one wait outlived it and the gate failed once.
/// The timeouts of the Swift HTTP clients are generous (120 s): results do not depend on their length and under load of
/// the whole suite the completion of `URLSession` can lag.
enum NetConversationScripts {

    typealias Entry = JavaYamlParityTests.ReferenceFile

    /// Hang guard of every wait (4 min): a whole strict-pool run of the suite takes ~2–3 min, `ioSafetyNet` is 5 min.
    static let hangGuardMs: Int32 = 240_000
    static let httpTimeout: TimeInterval = 120

    struct Scenario: Sendable {
        let name: String
        let options: [String: String]
        let body: [[String]]
        let raw: [String]
    }

    struct Section: Sendable {
        let name: String
        var scenarios: [Scenario] = []
    }

    // MARK: - Scripts

    static func gateDirectory() throws -> URL {
        try #require(Bundle.module.url(forResource: "net-gate", withExtension: nil),
                     "the bundle has no net-gate directory — the .copy rule in Package.swift")
    }

    static func scriptLines() throws -> [String] {
        let url = try gateDirectory().appendingPathComponent("conversation.txt")
        var lines = String(decoding: try Data(contentsOf: url), as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.last == "" { lines.removeLast() }
        return lines
    }

    static func parse(_ file: [String]) throws -> [Section] {
        var sections: [Section] = []
        var scenario: (name: String, options: [String: String], body: [[String]], raw: [String])?
        for line in file where !line.isEmpty && !line.hasPrefix("#") {
            let f: [String] = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            switch f[0] {
            case "section":
                sections.append(Section(name: f[1]))
            case "scenario":
                var options: [String: String] = [:]
                for option in f.dropFirst(2) {
                    let kv = option.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
                    options[kv[0]] = kv[1]
                }
                scenario = (f[1], options, [], [line])
            case "end":
                let s = try #require(scenario, "end bez scenario")
                sections[sections.count - 1].scenarios.append(Scenario(name: s.name, options: s.options, body: s.body, raw: s.raw))
                scenario = nil
            default:
                scenario?.body.append(f)
                scenario?.raw.append(line)
            }
        }
        return sections
    }

    /// Fields after escapes; `<empty>` = empty.
    static func field(_ text: String) -> String {
        text == "<empty>" ? "" : RigConversationScripts.unesc(text)
    }

    /// Text after `field` as ISO-8859-1 bytes.
    static func latin1Bytes(_ decoded: String) -> [UInt8] {
        decoded.utf16.map { UInt8(truncatingIfNeeded: $0) }
    }

    static func unhex(_ hex: String) -> [UInt8] {
        let chars: [Character] = Array(hex)
        return stride(from: 0, to: chars.count - 1, by: 2).map { UInt8(String(chars[$0...($0 + 1)]), radix: 16) ?? 0 }
    }

    static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func bigEndian<T: FixedWidthInteger>(_ value: T) -> [UInt8] {
        withUnsafeBytes(of: value.bigEndian) { Array($0) }
    }

    /// Datagram from tokens (`NetConversationGen.assemble`).
    static func assemble(_ spec: String) -> [UInt8] {
        var out: [UInt8] = []
        for token in spec.split(separator: " ").map(String.init) {
            let colon = token.firstIndex(of: ":")
            let kind = colon.map { String(token[..<$0]) } ?? token
            let value = colon.map { String(token[token.index(after: $0)...]) } ?? ""
            switch kind {
            case "i32":
                let raw: Int64 = value.hasPrefix("0x") ? Int64(UInt64(value.dropFirst(2), radix: 16) ?? 0) : (Int64(value) ?? 0)
                out += bigEndian(Int32(truncatingIfNeeded: raw))
            case "i64": out += bigEndian(Int64(value) ?? 0)
            case "u8": out.append(UInt8(truncatingIfNeeded: Int(value) ?? 0))
            case "f64": out += bigEndian((Double(value) ?? 0).bitPattern)
            case "qs":
                let b: [UInt8] = Array(RigConversationScripts.unesc(value).utf8)
                out += bigEndian(Int32(b.count)) + b
            case "qnull": out += bigEndian(Int32(-1))
            case "qsh":
                let b: [UInt8] = unhex(value)
                out += bigEndian(Int32(b.count)) + b
            case "hex": out += unhex(value)
            case "txt": out += Array(RigConversationScripts.unesc(value).utf8)
            default: Issue.record("unknown token \(token)")
            }
        }
        return out
    }

    // MARK: - Output

    final class Out: @unchecked Sendable {
        private(set) var lines: [String] = []
        let prefix: String

        init(prefix: String) {
            self.prefix = prefix
        }

        func put(_ path: String, _ value: String) {
            lines.append(JavaIoParityFixture.line(prefix + path, "out", [JavaIoParityFixture.tx(value)]))
        }

        func step(_ index: Int, _ value: String) {
            put("/" + pad(index), value)
        }

        func list(_ kind: String, _ values: [String]) {
            for (index, value) in values.enumerated() {
                put("/" + kind + "/" + pad(index), value)
            }
        }
    }

    static func pad(_ n: Int) -> String {
        JavaIoParityFixture.pad(n, 3)
    }

    static func ports(_ text: String, _ names: [Int: String]) -> String {
        var s = text
        for (port, name) in names.sorted(by: { $0.key < $1.key }) {
            s = s.replacingOccurrences(of: ":" + String(port), with: ":" + name)
        }
        return s
    }

    /// Java `EXC Class: message`; the cause (`<- getCause().toString()`) only for the application's wrapper exceptions.
    static func exc(_ error: any Error) -> String {
        switch error {
        case let e as DxClusterException:
            return "EXC DxClusterException: " + e.message + (e.cause.map { " <- " + causeText($0) } ?? "")
        case let e as SyncTransportError:
            return "EXC SyncTransportException: " + e.message + (e.cause.map { " <- " + $0 } ?? "")
        case let e as JavaHttpError:
            return "EXC " + RigConversationScripts.simpleName(e.javaClass) + ": " + (e.message ?? "null")
        default:
            let (name, message) = RigConversationScripts.javaName(error)
            return "EXC " + name + ": " + (message ?? "null")
        }
    }

    /// Java `Throwable.toString()` of the cause.
    static func causeText(_ error: any Error) -> String {
        switch error {
        case let e as JavaSocketError: return e.description
        case let e as JavaIllegalArgumentError: return "java.lang.IllegalArgumentException: " + e.message
        default: return String(describing: error)
        }
    }

    /// Client events (client threads add, the script waits on its own thread).
    final class Events: @unchecked Sendable {
        private let condition = NSCondition()
        private var items: [String] = []

        func add(_ item: String) {
            condition.lock()
            items.append(item)
            condition.broadcast()
            condition.unlock()
        }

        /// Blocking: up to `n` events (or the hang guard); returns `min(count, n)` (the rest is shown by the dump at the end).
        func await(_ n: Int) -> Int {
            let deadline = Date(timeIntervalSinceNow: Double(hangGuardMs) / 1_000)
            condition.lock()
            defer { condition.unlock() }
            while items.count < n {
                if !condition.wait(until: deadline) { break }
            }
            return min(items.count, n)
        }

        var snapshot: [String] {
            condition.lock()
            defer { condition.unlock() }
            return items
        }
    }

    /// A test UDP socket whose receive guard (`SO_RCVTIMEO`, `ioWait` by default) is the hang guard: every datagram
    /// the scripts receive is a success path.
    static func guarded(_ socket: UdpTestSocket) -> UdpTestSocket {
        var tv = timeval(tv_sec: Int(hangGuardMs / 1_000), tv_usec: 0)
        _ = setsockopt(socket.fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        return socket
    }

    /// Counts the closes of the MQTT client's byte transports (the standard ones, wrapped), so `waitoffline` waits for
    /// the event instead of polling `isConnected`.
    final class TransportCloses: @unchecked Sendable {
        private let condition = NSCondition()
        private var count = 0

        func closed() {
            condition.lock()
            count += 1
            condition.broadcast()
            condition.unlock()
        }

        func factory(_ inner: @escaping MqttTransportFactory) -> MqttTransportFactory {
            { [self] endpoint, timeoutMs in
                ObservedTransport(inner: try inner(endpoint, timeoutMs), closes: self)
            }
        }

        /// Blocking: until `connected()` is false, re-checked after every transport close; `false` only after the
        /// hang guard.
        /// `connected()` is never called under the lock (the client may report a close while holding its own).
        func awaitOffline(_ connected: () -> Bool) -> Bool {
            let deadline = Date(timeIntervalSinceNow: Double(hangGuardMs) / 1_000)
            while true {
                condition.lock()
                let seen: Int = count
                condition.unlock()
                if !connected() {
                    return true
                }
                condition.lock()
                var expired = false
                while count == seen && !expired {
                    expired = !condition.wait(until: deadline)
                }
                condition.unlock()
                if expired {
                    return !connected()
                }
            }
        }
    }

    /// The standard transport, reporting its close.
    final class ObservedTransport: MqttByteTransport, @unchecked Sendable {
        let inner: MqttByteTransport
        let closes: TransportCloses

        init(inner: MqttByteTransport, closes: TransportCloses) {
            self.inner = inner
            self.closes = closes
        }

        func read() throws -> [UInt8]? { try inner.read() }
        func write(_ bytes: [UInt8]) throws { try inner.write(bytes) }

        func close() {
            inner.close()
            closes.closed()
        }
    }

    // MARK: - Items

    /// Runs a section; scenarios concurrently, each on its own thread.
    static func run(_ section: Section) async throws -> Entry {
        let outputs: [[String]] = try await withThrowingTaskGroup(of: (Int, [String]).self) { group in
            for (index, scenario) in section.scenarios.enumerated() {
                group.addTask {
                    let out: Out = try await onOwnThread("net-gate-" + scenario.name) {
                        let out = Out(prefix: "/" + scenario.name)
                        try runScenario(section.name, scenario, out)
                        return out
                    }
                    return (index, out.lines)
                }
            }
            var results = [[String]](repeating: [], count: section.scenarios.count)
            for try await (index, rows) in group {
                results[index] = rows
            }
            return results
        }
        var lines: [String] = []
        for (scenario, rows) in zip(section.scenarios, outputs) {
            lines.append(JavaIoParityFixture.line("/" + scenario.name, "in", scenario.raw.map { JavaIoParityFixture.tx($0) }))
            lines.append(contentsOf: rows)
        }
        let sum = JavaIoParityFixture.checksum(definition: nil, registry: "", lines: lines)
        return Entry(relative: section.name, sha256: sum, lines: lines)
    }

    static func runScenario(_ section: String, _ scenario: Scenario, _ out: Out) throws {
        switch section {
        case "telnet": try telnet(scenario, out)
        case "udp-rx", "udp-mcast": try udpRx(scenario, out)
        case "udp-tx": try udpTx(scenario, out)
        case "http": try http(scenario, out)
        case "mqtt": try mqtt(scenario, out)
        default: Issue.record("unknown section \(section)")
        }
    }

    // MARK: - telnet (DxClusterClient)

    static func telnet(_ sc: Scenario, _ out: Out) throws {
        let listener = try GateTcpListener()
        let port = listener.port
        if sc.options["port"] == "free" { listener.close() }
        defer { listener.close() }
        let host: String = sc.options["host"] ?? "127.0.0.1"
        let names: [Int: String] = [port: "<port>"]
        let ev = Events()
        var client: DxClusterClient?
        var peer: GateTcp?
        for (at, f) in sc.body.enumerated() {
            switch f[0] {
            case "connect":
                do {
                    client = try DxClusterClient(host: host, port: port, timeoutMs: 5_000,
                                                 onLine: { ev.add("LINE " + $0) },
                                                 onError: { ev.add("ERR " + String(exc($0).dropFirst(4))) })
                    out.step(at, "OK")
                } catch {
                    out.step(at, ports(exc(error), names))
                }
            case "accept": peer = listener.accept()
            case "srv": peer?.write(latin1Bytes(field(f[1])))
            case "srvrep":
                let one: [UInt8] = latin1Bytes(field(f[1]))
                for _ in 0..<(Int(f[2]) ?? 0) { peer?.write(one) }
            case "recv": out.step(at, peer?.readLine() ?? "<no peer>")
            case "await": out.step(at, String(ev.await(Int(f[1]) ?? 0)))
            case "send":
                do {
                    try client?.send(field(f[1]))
                    out.step(at, "OK")
                } catch {
                    out.step(at, exc(error))
                }
            case "connected": out.step(at, String(client?.isConnected ?? false))
            case "eof": peer?.shutdownWrite()
            case "rst": peer?.reset()
            case "srvclose": peer?.close()
            case "close": client?.close()
            default: Issue.record("telnet: \(f[0])")
            }
        }
        client?.close()
        peer?.close()
        out.list("ev", ev.snapshot.map { ports($0, names) })
    }

    // MARK: - UDP receive

    final class LastFrom: @unchecked Sendable {
        private let lock = NSLock()
        private var value: UdpEndpoint?

        func set(_ endpoint: UdpEndpoint) {
            lock.withLock { value = endpoint }
        }

        var current: UdpEndpoint? {
            lock.withLock { value }
        }
    }

    static func opts(_ r: UdpReceiver) -> String {
        let reuseAddr: Bool = (r.intOption(SOL_SOCKET, SO_REUSEADDR) ?? 0) != 0
        let reusePort: Bool = (r.intOption(SOL_SOCKET, SO_REUSEPORT) ?? 0) != 0
        let broadcast: Bool = (r.intOption(SOL_SOCKET, SO_BROADCAST) ?? 0) != 0
        return "reuseaddr=\(reuseAddr) reuseport=\(reusePort) broadcast=\(broadcast)"
    }

    static func parsed(_ xml: String) -> String {
        guard let p = N1mmContactParser.parse(xml) else { return "PARSED ~" }
        let q = p.qso
        let ts: String = q.timestampUtc.map { String(Int64(($0.timeIntervalSince1970 * 1_000).rounded())) } ?? "~"
        let fields: String = p.fields.entries.map { ($0.key ?? "null") + "=" + ($0.value ?? "null") }.joined(separator: ";")
        let parts: [String] = [
            "PARSED ts=" + ts, "call=" + q.call, "mode=" + (q.mode?.rawValue ?? "~"), "freq=" + String(q.freqHz),
            "snt=" + q.rstSent, "rcv=" + q.rstRcvd, "sntnr=" + (q.serialSent.map { String($0) } ?? "null"),
            "rcvnr=" + (q.serialRcvd.map { String($0) } ?? "null"), "app=" + (p.app ?? "null"),
            "station=" + (p.stationName ?? "null"), "fields=" + fields,
        ]
        return parts.joined(separator: " ")
    }

    static func decodeText(_ d: WsjtxMessages.Decode, _ from: UdpEndpoint) -> String {
        let parts: [String] = [
            d.id ?? "null", String(d.isNew), String(d.timeMs), String(d.snr), String(d.deltaTime.bitPattern, radix: 16),
            String(d.deltaFrequency), d.mode ?? "null", d.message ?? "null", String(d.lowConfidence), String(d.offAir),
        ]
        return "DECODE " + parts.joined(separator: "|") + " from=" + from.description
    }

    static func statusText(_ s: WsjtxMessages.Status) -> String {
        let parts: [String] = [
            s.id ?? "null", String(s.dialFrequencyHz), s.mode ?? "null", s.dxCall ?? "null", s.report ?? "null",
            s.txMode ?? "null", String(s.txEnabled), String(s.transmitting),
        ]
        return "STATUS " + parts.joined(separator: "|")
    }

    static func udpRx(_ sc: Scenario, _ out: Out) throws {
        let drv = guarded(UdpTestSocket())
        var names: [Int: String] = [drv.port: "<drv>"]
        let ev = Events()
        let lastFrom = LastFrom()
        var receivers: [UdpReceiver] = []
        var closers: [() -> Void] = []
        var wsjtx: WsjtxListener?
        var ports: [Int] = []
        var holders: [UdpTestSocket] = []
        for (at, f) in sc.body.enumerated() {
            switch f[0] {
            case "listen":
                var port = 0
                if f[3] == "taken" {
                    let hold = UdpTestSocket()
                    holders.append(hold)
                    port = hold.port
                    names[port] = "<taken>"
                } else if f[3] == "same" {
                    port = ports[0]
                }
                let tag = "L" + String(receivers.count) + " "
                do {
                    switch f[1] {
                    case "wsjtx":
                        let handler = WsjtxListener.Handler(
                            onLoggedAdif: { ev.add(tag + "LOGGED " + ($0 ?? "null")) },
                            onDecode: { d, from in
                                lastFrom.set(from)
                                ev.add(tag + decodeText(d, from))
                            },
                            onStatus: { ev.add(tag + statusText($0)) },
                            onClear: { ev.add(tag + "CLEAR " + ($0.id ?? "null")) })
                        let w = try WsjtxListener(bindHost: f[2], bindPort: port, handler: handler)
                        w.start()
                        ports.append(w.boundPort)
                        receivers.append(w.receiver)
                        closers.append { w.close() }
                        if wsjtx == nil { wsjtx = w }
                    case "adif":
                        let a = try AdifUdpListener(bindHost: f[2], bindPort: port) { ev.add(tag + "ADIF " + $0) }
                        a.start()
                        ports.append(a.boundPort)
                        receivers.append(a.receiver)
                        closers.append { a.close() }
                    default:
                        // Multicast only on `lo0` (no IGMP into the runner's network); unicast ignores the index.
                        let n = try N1mmListener(bindHost: f[2], bindPort: port,
                                                 multicastInterface: UdpIoMeasuredTests.loopbackIndex) { xml in
                            ev.add(tag + "N1MM " + xml)
                            ev.add(tag + parsed(xml))
                        }
                        n.start()
                        ports.append(n.boundPort)
                        receivers.append(n.receiver)
                        closers.append { n.close() }
                    }
                    if receivers.count == 1 { names[ports[0]] = "<l0>" }
                    out.step(at, "OK")
                } catch {
                    out.step(at, NetConversationScripts.ports(exc(error), names))
                }
            case "opts": out.step(at, opts(receivers[Int(f[1]) ?? 0]))
            case "dgram": drv.send(assemble(f[1]), toPort: ports[0])
            case "await": out.step(at, String(ev.await(Int(f[1]) ?? 0)))
            case "reply":
                guard let w = wsjtx, let from = lastFrom.current else {
                    out.step(at, "<no decode>")
                    continue
                }
                try w.send(assemble(f[1]), to: from)
                if let got = drv.receive() {
                    out.step(at, hex(got.bytes) + " sameport=" + String(got.port == ports[0]))
                } else {
                    out.step(at, "<timeout>")
                }
            default: Issue.record("udp-rx: \(f[0])")
            }
        }
        for close in closers { close() }
        holders.removeAll()
        out.list("ev", ev.snapshot.map { NetConversationScripts.ports($0, names) })
    }

    // MARK: - UDP send

    final class Logs: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String] = []

        func add(_ item: String) {
            lock.withLock { items.append(item) }
        }

        var snapshot: [String] {
            lock.withLock { items }
        }
    }

    static func udpTx(_ sc: Scenario, _ out: Out) throws {
        let logs = Logs()
        let rx: [String: UdpTestSocket] = [
            "R0": guarded(UdpTestSocket()), "R1": guarded(UdpTestSocket()), "R6": guarded(UdpTestSocket(ipv6: true)),
        ]
        var names: [Int: String] = [:]
        for (name, socket) in rx {
            names[socket.port] = "<" + name + ">"
        }
        var sources: [Int: String] = [:]
        let b = try UdpBroadcaster(failureSink: { logs.add("WARNING " + $0) })
        for (at, f) in sc.body.enumerated() {
            switch f[0] {
            case "opts": out.step(at, "broadcast=" + String(b.broadcastEnabled))
            case "send": b.send(field(f[1]), f.dropFirst(2).map { target($0, rx) })
            case "get":
                guard let got = rx[f[1]]?.receive() else {
                    out.step(at, "<timeout>")
                    continue
                }
                let src: String = sources[got.port] ?? "S" + String(sources.count)
                sources[got.port] = src
                out.step(at, String(decoding: got.bytes, as: UTF8.self) + " src=" + src)
            case "close": b.close()
            default: Issue.record("udp-tx: \(f[0])")
            }
        }
        b.close()
        out.list("log", logs.snapshot.map { ports($0, names) })
    }

    static func target(_ spec: String, _ rx: [String: UdpTestSocket]) -> Target {
        if let socket = rx[spec] {
            return Target(host: spec == "R6" ? "[::1]" : "127.0.0.1", port: Int32(socket.port))
        }
        let colon = spec.lastIndex(of: ":") ?? spec.endIndex
        let portText = String(spec[spec.index(after: colon)...])
        let port: Int = rx[portText]?.port ?? Int(portText) ?? 0
        return Target(host: String(spec[..<colon]), port: Int32(port))
    }

    // MARK: - HTTP

    /// Callbook onto the stand-in: scheme, host and port of the address rewritten to `base`.
    struct RewritingGetter: HttpGetter {
        let inner: URLSessionHttpGetter
        let base: String

        func get(_ url: String) throws(HttpGetFailure) -> HttpGetResponse {
            var rest = url
            if let scheme = url.range(of: "://"), let slash = url[scheme.upperBound...].firstIndex(of: "/") {
                rest = String(url[slash...])
            }
            return try inner.get(base + rest)
        }
    }

    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0

        func next() -> Int {
            lock.withLock {
                defer { value += 1 }
                return value
            }
        }
    }

    /// Normalised request (`NetConversationGen.HttpFake`): line without version, Content-Type only with a body, the body.
    static func request(_ bytes: [UInt8]) -> String {
        let end: Int = FakeHttpServer.headerEnd(bytes) ?? bytes.count
        let head = RigConversationScripts.latin1(Array(bytes[..<end]))
        let headLines: [String] = head.components(separatedBy: "\r\n")
        var contentType = "~"
        for line in headLines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            if line[..<colon].trimmingCharacters(in: .whitespaces).lowercased() == "content-type" {
                contentType = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
        }
        var first: String = headLines.first ?? ""
        if first.hasSuffix(" HTTP/1.1") { first.removeLast(9) }
        let body: [UInt8] = Array(bytes[end...])
        return first + " ct=" + (body.isEmpty ? "-" : contentType) + " body=" + RigConversationScripts.latin1(body)
    }

    static func http(_ sc: Scenario, _ out: Out) throws {
        let responses: [[String]] = sc.body.filter { $0[0] == "resp" }
        var server: FakeHttpServer?
        let port: Int
        if sc.options["port"] == "free" {
            port = FreeLoopbackPort.take()
        } else {
            let s = try FakeHttpServer()
            port = s.port
            server = s
        }
        defer { server?.stop() }
        let base = "http://127.0.0.1:" + String(port)
        if let server {
            let counter = Counter()
            let script: [[String]] = responses.isEmpty ? [["resp", "200", "text/plain", "<empty>"]] : responses
            server.respond(withHead: { _, _ in
                let r = script[min(counter.next(), script.count - 1)]
                if r[1] == "close" {
                    return FakeHttpServer.Response(closeWithoutReply: true)
                }
                let location: [String] = r.count > 4 ? ["Location: " + r[4].replacingOccurrences(of: "<base>", with: base)] : []
                return FakeHttpServer.Response(status: Int(r[1]) ?? 200, contentType: r[2], body: field(r[3]),
                                               headers: location)
            })
        }
        let names: [Int: String] = [port: "<port>"]
        let log = HamQthLog()
        let getter = RewritingGetter(inner: URLSessionHttpGetter(connectTimeout: httpTimeout, requestTimeout: httpTimeout),
                                     base: base)
        var callbook: (any CallbookClient)?
        for (at, f) in sc.body.enumerated() {
            switch f[0] {
            case "resp": continue
            case "client":
                let user = field(f[2])
                let pass = field(f[3])
                if f[1] == "hamqth" {
                    callbook = HamQthClient(username: user, password: pass, log: log, http: getter)
                } else {
                    callbook = QrzClient(username: user, password: pass, log: log, http: getter)
                }
            case "lookup":
                let r = try callbook?.lookup(field(f[1])) ?? HamQthRecord.empty
                out.step(at, "R grid=\(r.grid)|name=\(r.name)|cq=\(r.cqZone)|itu=\(r.ituZone)")
            case "clublog":
                let c = ClubLogClient(http: JavaHttpClient(connectTimeout: httpTimeout, redirect: .never),
                                      url: base + "/realtime.php", requestTimeout: httpTimeout)
                let outcome = try c.upload(email: field(f[1]), password: field(f[2]), callsign: field(f[3]),
                                           apiKey: field(f[4]), adifRecord: field(f[5]))
                out.step(at, outcome.rawValue)
            case "score":
                let poster = ScorePoster(http: JavaHttpClient(connectTimeout: httpTimeout, redirect: .normal),
                                         requestTimeout: httpTimeout)
                do {
                    out.step(at, String(try poster.post(base + field(f[1]), xml: field(f[2]))))
                } catch {
                    out.step(at, ports(exc(error), names))
                }
            default: Issue.record("http: \(f[0])")
            }
        }
        let requests: [String] = server?.requests.map(request) ?? []
        out.list("req", requests.map { ports($0, names) })
        out.list("log", log.snapshot().map { ports(String($0.dropFirst(10)), names) })
    }

    // MARK: - MQTT

    static let packetTypes: [String] = ["0", "CONNECT", "CONNACK", "PUBLISH", "PUBACK", "PUBREC", "PUBREL", "PUBCOMP",
                                        "SUBSCRIBE", "SUBACK", "UNSUBSCRIBE", "UNSUBACK", "PINGREQ", "PINGRESP",
                                        "DISCONNECT", "AUTH"]

    /// Hand-driven broker side (`NetConversationGen.Broker`).
    final class Broker {
        let listener: GateTcpListener
        var conn: GateTcp?
        /// Last packet id of SUBSCRIBE and PUBLISH QoS 1 from the client (for SUBACK and PUBACK).
        var subscribeId = 0
        var publishId = 0
        var nextId = 1

        init() throws {
            listener = try GateTcpListener()
        }

        /// Next client packet (hex) or `<timeout>`/`<eof>`.
        func read() -> String {
            guard let conn else { return "<eof>" }
            guard case .bytes(let head) = conn.readExact(1) else { return conn.lastFailure }
            var packet: [UInt8] = head
            var multiplier = 1
            var length = 0
            while true {
                guard case .bytes(let b) = conn.readExact(1) else { return conn.lastFailure }
                packet += b
                length += Int(b[0] & 127) * multiplier
                multiplier *= 128
                if b[0] & 128 == 0 { break }
            }
            guard case .bytes(let body) = conn.readExact(length) else { return conn.lastFailure }
            packet += body
            let type = Int(head[0] >> 4)
            if type == 8 { subscribeId = Int(body[0]) << 8 | Int(body[1]) }
            if type == 3 && (head[0] >> 1) & 3 > 0 {
                let topicLength = Int(body[0]) << 8 | Int(body[1])
                publishId = Int(body[2 + topicLength]) << 8 | Int(body[3 + topicLength])
            }
            return hex(packet)
        }

        func send(_ bytes: [UInt8]) {
            conn?.write(bytes)
        }

        func publish(qos: Int, retain: Bool, topic: String, payload: [UInt8]) {
            let t: [UInt8] = Array(topic.utf8)
            var body: [UInt8] = [UInt8(t.count >> 8), UInt8(t.count & 0xFF)] + t
            if qos > 0 {
                body += [UInt8(nextId >> 8), UInt8(nextId & 0xFF)]
                nextId += 1
            }
            body.append(0)
            body += payload
            var packet: [UInt8] = [UInt8(0x30 | qos << 1 | (retain ? 1 : 0))]
            var length = body.count
            repeat {
                let digit = length % 128
                length /= 128
                packet.append(UInt8(length > 0 ? digit | 0x80 : digit))
            } while length > 0
            send(packet + body)
        }
    }

    /// State listeners wait until the script lets them go (`gate`/`release`).
    final class Gate: @unchecked Sendable {
        private let condition = NSCondition()
        private var closed = false

        func close() {
            condition.lock()
            closed = true
            condition.unlock()
        }

        func open() {
            condition.lock()
            closed = false
            condition.broadcast()
            condition.unlock()
        }

        func pass() {
            let deadline = Date(timeIntervalSinceNow: Double(hangGuardMs) / 1_000)
            condition.lock()
            defer { condition.unlock() }
            while closed {
                if !condition.wait(until: deadline) { return }
            }
        }
    }

    /// Result of a background call (`bg` / `join`).
    final class Pending: @unchecked Sendable {
        private let condition = NSCondition()
        private var result: String?

        func complete(_ value: String) {
            condition.lock()
            result = value
            condition.broadcast()
            condition.unlock()
        }

        func join() -> String {
            let deadline = Date(timeIntervalSinceNow: Double(hangGuardMs) / 1_000)
            condition.lock()
            defer { condition.unlock() }
            while result == nil {
                if !condition.wait(until: deadline) { break }
            }
            return result ?? "<timeout>"
        }
    }

    struct WireDecodeError: Error {}

    static func wire<T: WireMessage>(_ json: String?, _ type: T.Type) throws -> T {
        guard let value = try WireJson.fromBytes(Array(field(json ?? "null").utf8), as: type) else {
            throw WireDecodeError()
        }
        return value
    }

    static func op(_ t: MqttSyncTransport, _ name: String, _ json: String?) throws {
        switch name {
        case "connect": try t.connect()
        case "close": t.close()
        case "insert": try t.publishInsert(wire(json, QsoCommand.self))
        case "update": try t.publishUpdate(wire(json, QsoCommand.self))
        case "delete": try t.publishDelete(wire(json, DeleteCommand.self))
        case "status": try t.publishStatus(wire(json, StationStatusWire.self))
        case "spot": try t.publishSpot(wire(json, SpotWire.self))
        case "msg": try t.publishMessage(wire(json, NetMessageWire.self))
        case "serial": try t.requestSerial(wire(json, SerialRequest.self))
        default: Issue.record("mqtt op \(name)")
        }
    }

    static func subscribe(_ t: MqttSyncTransport, _ ev: Events, _ gate: Gate) throws {
        try t.subscribeState { s in
            guard let s else { return }
            ev.add("state \(s.uuid ?? "null") v\(s.version) deleted=\(s.deleted) station=\(s.stationId ?? "null")")
            gate.pass()
        }
        t.subscribeSpots { s in
            guard let s else { return }
            ev.add("spot \(s.dxCall ?? "null") \(s.freqHz) from=\(s.stationId ?? "null")")
        }
        try t.subscribeStatus { s in
            guard let s else { return }
            ev.add("status \(s.stationId ?? "null") online=\(s.online) tx=\(s.transmitting)")
        }
        t.subscribeMessages { m in
            guard let m else { return }
            ev.add("msg \(m.text ?? "null") from=\(m.fromStation ?? "null")")
        }
        t.subscribeSerialReplies { r in
            guard let r else { return }
            ev.add("serial \(r.requestId ?? "null") \(r.serial)")
        }
    }

    static func mqtt(_ sc: Scenario, _ out: Out) throws {
        let broker = try Broker()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mcl-gate-mqtt-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let o = sc.options
        let closes = TransportCloses()
        let t = MqttSyncTransport(host: "127.0.0.1", port: broker.listener.port, clientId: "OP1", username: o["user"],
                                  password: o["pass"], persistenceDir: dir, trust: nil,
                                  transportFactory: closes.factory(MqttTransports.standard))
        if let offline = o["offline"] {
            t.setOfflineStatus(try wire(offline, StationStatusWire.self))
        }
        let ev = Events()
        let gate = Gate()
        try subscribe(t, ev, gate)
        let names: [Int: String] = [broker.listener.port: "<port>"]
        var pending: Pending?
        steps: for (at, f) in sc.body.enumerated() {
            var result: String?
            switch f[0] {
            case "bg":
                let p = Pending()
                let name = f[1]
                let json: String? = f.count > 2 ? f[2] : nil
                let thread = Thread {
                    do {
                        try op(t, name, json)
                        p.complete("OK")
                    } catch {
                        p.complete(exc(error))
                    }
                }
                thread.name = "gate-bg"
                thread.start()
                pending = p
            case "join": result = ports(pending?.join() ?? "<no bg>", names)
            case "call":
                do {
                    try op(t, f[1], f.count > 2 ? f[2] : nil)
                    result = "OK"
                } catch {
                    result = ports(exc(error), names)
                }
            case "accept":
                broker.conn = broker.listener.accept()
                if broker.conn == nil { result = "<timeout>" }
            case "expect":
                let got = broker.read()
                let type: String = got.hasPrefix("<") ? got : packetTypes[Int(String(got.prefix(1)), radix: 16) ?? 0]
                result = type == f[1] ? got : "<" + type + "> " + got
            case "expectset":
                // Order independent of the Paho threads (DUP PUBLISH from recovery × SUBSCRIBE from connectComplete): sorted.
                let got: [String] = (0..<(Int(f[1]) ?? 0)).map { _ in broker.read() }
                result = got.sorted().joined(separator: " + ")
            case "connack": broker.send(unhex("2003" + String(format: "%02x", Int(f[1]) ?? 0) + f[2] + "00"))
            case "suback":
                let codes: [UInt8] = unhex(f[1])
                let head: [UInt8] = [0x90, UInt8(3 + codes.count), UInt8(broker.subscribeId >> 8), UInt8(broker.subscribeId & 0xFF), 0]
                broker.send(head + codes)
            case "puback":
                let id = String(format: "%04x", broker.publishId)
                broker.send(unhex(f.count > 1 ? "4003" + id + f[1] : "4002" + id))
            case "publish":
                broker.publish(qos: Int(f[1]) ?? 0, retain: f[2] == "1", topic: f[3], payload: Array(field(f[4]).utf8))
            case "disconnect": broker.send(unhex("e001" + f[1]))
            case "drop": broker.conn?.close()
            case "connected": result = String(t.isConnected)
            case "waitoffline":
                // Event-based: the client clears `isConnected` before it closes the lost transport.
                result = closes.awaitOffline { t.isConnected } ? "offline" : "<timeout>"
            case "await": result = String(ev.await(Int(f[1]) ?? 0))
            case "gate": gate.close()
            case "release": gate.open()
            case "pending": result = String(broker.conn?.available ?? -1)
            default: Issue.record("mqtt: \(f[0])")
            }
            if let result {
                out.step(at, result)
                if result.contains("<timeout>") || result.contains("<eof>") { break steps }
            }
        }
        gate.open()
        let closed = Pending()
        let closer = Thread {
            t.close()
            closed.complete("OK")
        }
        closer.start()
        _ = closed.join()
        broker.conn?.close()
        broker.listener.close()
        out.list("ev", ev.snapshot)
    }
}

// MARK: - POSIX TCP stand-ins (127.0.0.1 only)

/// Listening socket on `127.0.0.1:0`; `accept` with a safety limit.
final class GateTcpListener: @unchecked Sendable {
    let port: Int
    private let lock = NSLock()
    private var fd: Int32

    init() throws {
        let fd: Int32 = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        var sin = sockaddr_in()
        sin.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        sin.sin_family = sa_family_t(AF_INET)
        sin.sin_addr.s_addr = in_addr_t(UInt32(0x7F00_0001).bigEndian)
        let bound: Int32 = withUnsafePointer(to: &sin) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0, listen(fd, 16) == 0 else {
            let code = errno
            _ = Darwin.close(fd)
            throw POSIXError(.init(rawValue: code) ?? .EIO)
        }
        var actual = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &actual) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        self.fd = fd
        self.port = Int(UInt16(bigEndian: actual.sin_port))
    }

    deinit {
        close()
    }

    /// Accepts a connection (`nil` only after the hang guard `hangGuardMs`).
    func accept() -> GateTcp? {
        let listening: Int32 = lock.withLock { fd }
        guard listening >= 0 else { return nil }
        var pfd = pollfd(fd: listening, events: Int16(POLLIN), revents: 0)
        guard poll(&pfd, 1, NetConversationScripts.hangGuardMs) > 0 else { return nil }
        let c: Int32 = Darwin.accept(listening, nil, nil)
        guard c >= 0 else { return nil }
        var one: Int32 = 1
        _ = setsockopt(c, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        return GateTcp(fd: c)
    }

    func close() {
        lock.withLock {
            if fd >= 0 {
                _ = Darwin.close(fd)
                fd = -1
            }
        }
    }
}

/// Accepted connection of the stand-in; used only by the script thread.
final class GateTcp: @unchecked Sendable {
    enum Read {
        case bytes([UInt8])
        case eof
        case timeout
    }

    private var fd: Int32
    private var buffer: [UInt8] = []
    private(set) var lastFailure = "<eof>"

    init(fd: Int32) {
        self.fd = fd
    }

    deinit {
        close()
    }

    private func fill() -> Read {
        guard fd >= 0 else { return .eof }
        var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        guard poll(&pfd, 1, NetConversationScripts.hangGuardMs) > 0 else { return .timeout }
        var chunk = [UInt8](repeating: 0, count: 65_536)
        let n: Int = chunk.withUnsafeMutableBytes { recv(fd, $0.baseAddress, $0.count, 0) }
        guard n > 0 else { return .eof }
        buffer += chunk[0..<n]
        return .bytes([])
    }

    /// Exactly `count` bytes, otherwise end/safety limit (`lastFailure`).
    func readExact(_ count: Int) -> Read {
        while buffer.count < count {
            switch fill() {
            case .bytes: continue
            case .eof:
                lastFailure = "<eof>"
                return .eof
            case .timeout:
                lastFailure = "<timeout>"
                return .timeout
            }
        }
        let out: [UInt8] = Array(buffer[0..<count])
        buffer.removeFirst(count)
        return .bytes(out)
    }

    /// Bytes up to and including CRLF as ISO-8859-1; `<eof>`/`<timeout>` after the received beginning.
    func readLine() -> String {
        var line: [UInt8] = []
        while true {
            guard case .bytes(let b) = readExact(1) else {
                return RigConversationScripts.latin1(line) + lastFailure
            }
            line += b
            if line.count >= 2 && line[line.count - 2] == 0x0D && line[line.count - 1] == 0x0A {
                return RigConversationScripts.latin1(line)
            }
        }
    }

    func write(_ bytes: [UInt8]) {
        var offset = 0
        while offset < bytes.count && fd >= 0 {
            let n: Int = bytes[offset...].withUnsafeBytes { Darwin.send(fd, $0.baseAddress, $0.count, 0) }
            if n <= 0 {
                if n < 0 && errno == EINTR { continue }
                return
            }
            offset += n
        }
    }

    /// Bytes from the client currently sitting in the kernel (+ the unread rest of the buffer).
    var available: Int {
        guard fd >= 0 else { return -1 }
        var n: Int32 = 0
        // `FIONREAD` = `_IOR('f', 127, int)`; Swift does not import the macro.
        let fionread: UInt = 0x4004_667F
        _ = ioctl(fd, fionread, &n)
        return Int(n) + buffer.count
    }

    func shutdownWrite() {
        if fd >= 0 { _ = shutdown(fd, SHUT_WR) }
    }

    func reset() {
        guard fd >= 0 else { return }
        var linger = Darwin.linger(l_onoff: 1, l_linger: 0)
        _ = setsockopt(fd, SOL_SOCKET, SO_LINGER, &linger, socklen_t(MemoryLayout<Darwin.linger>.size))
        close()
    }

    func close() {
        if fd >= 0 {
            _ = Darwin.close(fd)
            fd = -1
        }
    }
}
