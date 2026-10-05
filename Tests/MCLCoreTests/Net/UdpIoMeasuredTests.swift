import Darwin
import Foundation
import Testing
@testable import MCLCore

/// UDP receive and broadcast against measured Java v1.1.1 (maintainer-only probe,
/// output `udp-io-probe.txt`; the row key is in the description of each check). Only 127.0.0.1 / ::1; multicast only
/// on the `lo0` loopback with TTL 0. Blocking calls (DNS, waiting for a datagram) from dedicated threads.
@Suite(.ioSafetyNet) struct UdpIoMeasuredTests {

    static func describe(_ error: any Error) -> String {
        if let e = error as? JavaSocketError {
            return "THROWS " + e.description
        }
        if let e = error as? JavaIllegalArgumentError {
            return "THROWS java.lang.IllegalArgumentException: " + e.message
        }
        return "THROWS " + String(describing: error)
    }

    static func className(_ a: JavaInetAddress) -> String {
        a.family == AF_INET6 ? "Inet6Address" : "Inet4Address"
    }

    /// The probe's Java `opts(...)` without `class=`.
    static func opts(_ r: UdpReceiver) -> String {
        let reuseAddr: Bool = (r.intOption(SOL_SOCKET, SO_REUSEADDR) ?? 0) != 0
        let reusePort: Bool = (r.intOption(SOL_SOCKET, SO_REUSEPORT) ?? 0) != 0
        let broadcast: Bool = (r.intOption(SOL_SOCKET, SO_BROADCAST) ?? 0) != 0
        let local: String = r.localAddress?.hostAddress ?? "?"
        return "reuseaddr=\(reuseAddr) reuseport=\(reusePort) broadcast=\(broadcast) local=/\(local)"
    }

    static func wsjtx(_ host: String, _ port: Int) async -> String {
        await onOwnThread {
            do {
                let l = try WsjtxListener(bindHost: host, bindPort: port, handler: .init(onLoggedAdif: { _ in }))
                defer { l.close() }
                return opts(l.receiver)
            } catch {
                return describe(error)
            }
        }
    }

    // MARK: - InetAddress.getByName with square brackets

    @Test func getByNameBrackets() async {
        let cases: [(String, String)] = [
            ("[::1]", "Inet6Address 0:0:0:0:0:0:0:1"),
            ("[::1", "THROWS java.net.UnknownHostException: [::1: invalid IPv6 address literal"),
            ("::1]", "THROWS java.net.UnknownHostException: ::1]: invalid IPv6 address literal"),
            ("[]", "THROWS java.net.UnknownHostException: []: invalid IPv6 address literal"),
            ("[127.0.0.1]", "THROWS java.net.UnknownHostException: [127.0.0.1]: invalid IPv6 address literal"),
            ("[localhost]", "THROWS java.net.UnknownHostException: [localhost]: invalid IPv6 address literal"),
            ("[::ffff:127.0.0.1]", "Inet4Address 127.0.0.1"),
            ("[0:0:0:0:0:0:0:1]", "Inet6Address 0:0:0:0:0:0:0:1"),
            ("[::1%lo0]", "Inet6Address 0:0:0:0:0:0:0:1%lo0"),
            ("[::1]:2237", "THROWS java.net.UnknownHostException: [::1]:2237: invalid IPv6 address literal"),
            ("[ ::1]", "THROWS java.net.UnknownHostException: [ ::1]: invalid IPv6 address literal"),
            ("[[::1]]", "THROWS java.net.UnknownHostException: [[::1]]: invalid IPv6 address literal"),
            ("[x]", "THROWS java.net.UnknownHostException: [x]: invalid IPv6 address literal"),
            ("[1]", "THROWS java.net.UnknownHostException: [1]: invalid IPv6 address literal"),
            ("::1", "Inet6Address 0:0:0:0:0:0:0:1"),
            ("localhost", "Inet4Address 127.0.0.1"),
        ]
        for (host, expected) in cases {
            let actual: String = await onOwnThread {
                do {
                    let a = try JavaInetAddress.byName(host)
                    return Self.className(a) + " " + a.hostAddress
                } catch {
                    return Self.describe(error)
                }
            }
            #expect(actual == expected, "GBN.\(host)")
        }
    }

    /// The target `[::1]:2237` from `Target.parseAll` (host `[::1]`) and `::1` both arrive (`UB.toV6`).
    @Test func broadcasterSendsToBracketedIPv6() async throws {
        let rx = UdpTestSocket(ipv6: true)
        // Failures are collected on the sending thread and reported only in the test's context (`Issue.record` on a bare thread
        // would not be attributed to the test).
        let failures = Failures()
        let b = try UdpBroadcaster(failureSink: { failures.add($0) })
        defer { b.close() }
        let port = Int32(rx.port)
        await onOwnThread { b.send("<6/>", [Target(host: "[::1]", port: port), Target(host: "::1", port: port)]) }
        #expect(await onOwnThread { rx.receive() }.map { String(decoding: $0.bytes, as: UTF8.self) } == "<6/>")
        #expect(await onOwnThread { rx.receive() }.map { String(decoding: $0.bytes, as: UTF8.self) } == "<6/>")
        #expect(failures.all.isEmpty, "failures: \(failures.all)")
    }

    // MARK: - Bind of listeners

    @Test func bindLikeJava() async {
        let cases: [(String, String, Int, String)] = [
            ("loop4", "127.0.0.1", 0, "reuseaddr=false reuseport=false broadcast=true local=/127.0.0.1"),
            ("wild4", "0.0.0.0", 0, "reuseaddr=false reuseport=false broadcast=true local=/0:0:0:0:0:0:0:0"),
            ("empty", "", 0, "reuseaddr=false reuseport=false broadcast=true local=/127.0.0.1"),
            ("localhost", "localhost", 0, "reuseaddr=false reuseport=false broadcast=true local=/127.0.0.1"),
            ("loop6", "::1", 0, "reuseaddr=false reuseport=false broadcast=true local=/0:0:0:0:0:0:0:1"),
            ("loop6br", "[::1]", 0, "reuseaddr=false reuseport=false broadcast=true local=/0:0:0:0:0:0:0:1"),
            ("unresolved", "no.such.host.invalid.", 0, "THROWS java.net.SocketException: Unresolved address"),
            ("port70000", "127.0.0.1", 70_000, "THROWS java.lang.IllegalArgumentException: port out of range:70000"),
            ("portNeg", "127.0.0.1", -1, "THROWS java.lang.IllegalArgumentException: port out of range:-1"),
            ("foreign", "192.0.2.1", 0, "THROWS java.net.BindException: Can't assign requested address"),
        ]
        for (name, host, port, expected) in cases {
            #expect(await Self.wsjtx(host, port) == expected, "BIND.\(name)")
        }
    }

    @Test func bindInUse() async throws {
        let held = UdpTestSocket()
        let port = held.port
        #expect(await Self.wsjtx("127.0.0.1", port) == "THROWS java.net.BindException: Address already in use", "BIND.inUse")
        #expect(await Self.wsjtx("0.0.0.0", port) == "THROWS java.net.BindException: Address already in use", "BIND.inUseWild")
    }

    @Test func adifAndN1mmBindErrors() async {
        let adif: String = await onOwnThread {
            do {
                _ = try AdifUdpListener(bindHost: "no.such.host.invalid.", bindPort: 0) { _ in }
                return "ok"
            } catch {
                return Self.describe(error)
            }
        }
        #expect(adif == "THROWS java.net.SocketException: Unresolved address", "ADIF.unresolved")
        let cases: [(String, String, Int, String)] = [
            ("unresolved", "no.such.host.invalid.", 0, "THROWS java.net.UnknownHostException: no.such.host.invalid."),
            ("port70000", "127.0.0.1", 70_000, "THROWS java.lang.IllegalArgumentException: port out of range:70000"),
            ("empty", "", 0, "reuseaddr=false reuseport=false broadcast=true local=/127.0.0.1"),
            ("unicastOpts", "127.0.0.1", 0, "reuseaddr=false reuseport=false broadcast=true local=/127.0.0.1"),
        ]
        for (name, host, port, expected) in cases {
            let actual: String = await onOwnThread {
                do {
                    let l = try N1mmListener(bindHost: host, bindPort: port) { _ in }
                    defer { l.close() }
                    return Self.opts(l.receiver)
                } catch {
                    return Self.describe(error)
                }
            }
            #expect(actual == expected, "N1MM.\(name)")
        }
    }

    // MARK: - Multicast (loopback lo0 only, TTL 0)

    static let loopbackIndex: UInt32 = if_nametoindex("lo0")

    /// A runner that cannot do multicast on the loopback (`IP_MULTICAST_IF` to 127.0.0.1) skips the tests.
    static let loopbackMulticastAvailable: Bool = {
        let fd: Int32 = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return false }
        defer { _ = Darwin.close(fd) }
        var lo = in_addr(s_addr: in_addr_t(UInt32(0x7F00_0001).bigEndian))
        return loopbackIndex != 0 && setsockopt(fd, IPPROTO_IP, IP_MULTICAST_IF, &lo, socklen_t(MemoryLayout<in_addr>.size)) == 0
    }()

    static func n1mmMulticast(_ port: Int, _ handler: @escaping @Sendable (String) -> Void = { _ in }) throws -> N1mmListener {
        try N1mmListener(bindHost: "239.255.42.99", bindPort: port, multicastInterface: loopbackIndex, handler: handler)
    }

    /// Sending to the group via `lo0` with TTL 0 (the packet does not leave the computer).
    static func sendMulticast(_ bytes: [UInt8], port: Int) {
        let fd: Int32 = socket(AF_INET, SOCK_DGRAM, 0)
        defer { _ = Darwin.close(fd) }
        var lo = in_addr(s_addr: in_addr_t(UInt32(0x7F00_0001).bigEndian))
        _ = setsockopt(fd, IPPROTO_IP, IP_MULTICAST_IF, &lo, socklen_t(MemoryLayout<in_addr>.size))
        var ttl: UInt8 = 0
        _ = setsockopt(fd, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, socklen_t(MemoryLayout<UInt8>.size))
        var group = UdpTestSocket.ipv4(0xEFFF_2A63, port: port)
        let sent: Int = withUnsafePointer(to: &group) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                bytes.withUnsafeBytes { sendto(fd, $0.baseAddress, $0.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size)) }
            }
        }
        precondition(sent == bytes.count, "sendto multicast")
    }

    @Test(.enabled(if: loopbackMulticastAvailable, "the runner cannot do multicast on the lo0 loopback"))
    func multicastSocketOptionsAndBindOrder() async throws {
        let first = try Self.n1mmMulticast(0)
        defer { first.close() }
        #expect(Self.opts(first.receiver) == "reuseaddr=true reuseport=true broadcast=true local=/0:0:0:0:0:0:0:0",
                "N1MM.mcastOpts")
        let v6 = try N1mmListener(bindHost: "ff15::4299", bindPort: 0, multicastInterface: Self.loopbackIndex) { _ in }
        #expect(Self.opts(v6.receiver) == "reuseaddr=true reuseport=true broadcast=true local=/0:0:0:0:0:0:0:0",
                "N1MM.mcastV6Opts")
        v6.close()
        let port = first.boundPort
        let second = try Self.n1mmMulticast(port)
        second.close()
        var unicast = "ok both"
        do {
            let u = try N1mmListener(bindHost: "127.0.0.1", bindPort: port) { _ in }
            u.close()
        } catch {
            unicast = Self.describe(error)
        }
        #expect(unicast == "THROWS java.net.BindException: Address already in use", "N1MM.mcastThenUnicast")
    }

    @Test(.enabled(if: loopbackMulticastAvailable, "the runner cannot do multicast on the lo0 loopback"))
    func unicastThenMulticastBinds() async throws {
        let unicast = try N1mmListener(bindHost: "127.0.0.1", bindPort: 0) { _ in }
        defer { unicast.close() }
        let multicast = try Self.n1mmMulticast(unicast.boundPort)
        multicast.close()
    }

    /// A group on `lo0` with TTL 0 (`N1MM.mcastDeliveryTtl0`) and a unicast to the port of the multicast socket over IPv4
    /// and IPv6 (`N1MM.mcastUnicastToPort`: wildcard `::` dual-stack).
    @Test(.enabled(if: loopbackMulticastAvailable, "the runner cannot do multicast on the lo0 loopback"))
    func multicastDeliversGroupAndUnicast() async throws {
        let received = Inbox<String>()
        let listener = try Self.n1mmMulticast(0) { received.offer($0) }
        defer { listener.close() }
        listener.start()
        let port = listener.boundPort
        await onOwnThread { Self.sendMulticast(Array("<contactinfo>m</contactinfo>".utf8), port: port) }
        #expect(await onOwnThread { received.take() } == "<contactinfo>m</contactinfo>")
        UdpTestSocket().send(Array("<contactinfo>4</contactinfo>".utf8), toPort: port)
        #expect(await onOwnThread { received.take() } == "<contactinfo>4</contactinfo>")
        UdpTestSocket(ipv6: true).send(Array("<contactinfo>6</contactinfo>".utf8), toPort: port)
        #expect(await onOwnThread { received.take() } == "<contactinfo>6</contactinfo>")
    }

    /// JDK `DefaultInterface`: the first with both IPv4 and IPv6 and a non-link-local address (enumeration order as on the probe machine:
    /// `utun5 … llw0 awdl0 … en0 en15 lo0` → `en0`, verified with `netstat -g`).
    @Test func defaultMulticastInterfaceChoice() {
        let upMulticast: UInt32 = UInt32(IFF_UP) | UInt32(IFF_RUNNING) | UInt32(IFF_MULTICAST)
        let ppp: UInt32 = upMulticast | UInt32(IFF_POINTOPOINT)
        let loop: UInt32 = upMulticast | UInt32(IFF_LOOPBACK)
        typealias C = DefaultMulticastInterface.Candidate
        let machine: [C] = [
            C(name: "utun5", index: 25, flags: ppp, ipv6: true),
            C(name: "llw0", index: 18, flags: upMulticast, ipv6: true),
            C(name: "awdl0", index: 17, flags: upMulticast, ipv6: true),
            C(name: "en0", index: 15, flags: upMulticast, ipv4: true, ipv6: true, nonLinkLocal: true, inV4Pass: true),
            C(name: "en15", index: 13, flags: upMulticast, ipv4: true, ipv6: true, nonLinkLocal: true, inV4Pass: true),
            C(name: "lo0", index: 1, flags: loop, ipv4: true, ipv6: true, nonLinkLocal: true, inV4Pass: true),
        ]
        #expect(DefaultMulticastInterface.choose(machine)?.name == "en0")
        let noDual: [C] = [machine[1], machine[0], machine[5]]
        #expect(DefaultMulticastInterface.choose(noDual)?.name == "llw0", "preferred")
        #expect(DefaultMulticastInterface.choose([machine[0], machine[5]])?.name == "utun5", "ppp")
        #expect(DefaultMulticastInterface.choose([machine[5]])?.name == "lo0", "loopback")
        let down = C(name: "en9", index: 9, flags: UInt32(IFF_MULTICAST), ipv4: true, ipv6: true, nonLinkLocal: true)
        #expect(DefaultMulticastInterface.choose([down]) == nil)
    }

    // MARK: - WsjtxListener: reply, sender address, close

    @Test func senderAddressAndClose() async throws {
        let got = Inbox<UdpEndpoint>()
        let listener = try WsjtxListener(bindHost: "127.0.0.1", bindPort: 0, handler: .init(
            onLoggedAdif: { _ in }, onDecode: { _, from in got.offer(from) }))
        listener.start()
        let tx = UdpTestSocket()
        let decode = WsjtxMessages.Decode(id: "W", isNew: true, timeMs: 0, snr: 0, deltaTime: 0, deltaFrequency: 0,
                                          mode: "~", message: "x", lowConfidence: false, offAir: false)
        tx.send(WsjtxMessages.encodeDecode(decode), toPort: listener.boundPort)
        let from: UdpEndpoint = try #require(await onOwnThread { got.take() })
        #expect(from.hostAddress == "127.0.0.1")
        #expect(from.port == tx.port)
        #expect(from.description == "/127.0.0.1:" + String(tx.port), "WSJ.fromAndAfterClose str")

        // closing from another thread ends the reader thread (without a time limit)
        await onOwnThread { listener.close() }
        await listener.waitUntilStopped()
        listener.close()
        #expect(listener.boundPort == -1)
        var after = "ok"
        do {
            try listener.send([1], to: from)
        } catch {
            after = Self.describe(error)
        }
        #expect(after == "THROWS java.net.SocketException: Socket closed")
    }

    @Test func closeBeforeStart() async throws {
        let listener = try WsjtxListener(bindHost: "127.0.0.1", bindPort: 0, handler: .init(onLoggedAdif: { _ in }))
        listener.close()
        listener.start()
        await listener.waitUntilStopped()
        #expect(listener.boundPort == -1)
    }

    @Test func sendErrors() async throws {
        let listener = try WsjtxListener(bindHost: "127.0.0.1", bindPort: 0, handler: .init(onLoggedAdif: { _ in }))
        defer { listener.close() }
        let cases: [(String, String, Int, Int, String)] = [
            ("sendPort0", "127.0.0.1", 0, 1, "THROWS java.net.SocketException: Can't send to port 0"),
            ("sendV6From4", "::1", 9, 1, "THROWS java.net.NoRouteToHostException: No route to host"),
            ("sendTooBig", "127.0.0.1", 9, 65_508, "THROWS java.net.SocketException: Message too long"),
            ("send65507", "127.0.0.1", 9, 65_507, "ok"),
        ]
        for (name, host, port, size, expected) in cases {
            let actual: String = await onOwnThread {
                do {
                    let to = try UdpEndpoint.resolve(host: host, port: port)
                    try listener.send([UInt8](repeating: 0, count: size), to: to)
                    return "ok"
                } catch {
                    return Self.describe(error)
                }
            }
            #expect(actual == expected, "WSJ.\(name)")
        }
    }

    @Test func bigDatagram() async throws {
        let received = Inbox<String>()
        let listener = try WsjtxListener(bindHost: "127.0.0.1", bindPort: 0,
                                         handler: .init(onLoggedAdif: { received.offer($0 ?? "null") }))
        defer { listener.close() }
        listener.start()
        let adif = String(repeating: "a", count: 65_000)
        let msg: [UInt8] = WsjtxMessages.encodeLoggedAdif(WsjtxMessages.LoggedAdif(adif: adif))
        #expect(msg.count == 65_036, "WSJ.bigDatagram sent")
        let tx = UdpTestSocket()
        var size: Int32 = 65_535
        _ = setsockopt(tx.fd, SOL_SOCKET, SO_SNDBUF, &size, socklen_t(MemoryLayout<Int32>.size))
        tx.send(msg, toPort: listener.boundPort)
        #expect(await onOwnThread { received.take() }?.utf16.count == 65_000, "WSJ.bigDatagram got")
    }

    // MARK: - UdpBroadcaster

    final class Failures: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String] = []
        func add(_ s: String) {
            lock.lock()
            items.append(s)
            lock.unlock()
        }
        var all: [String] {
            lock.lock()
            defer { lock.unlock() }
            return items
        }
    }

    @Test func broadcasterSocketHasBroadcastEnabled() throws {
        let b = try UdpBroadcaster()
        defer { b.close() }
        #expect(b.broadcastEnabled, "UB.opts broadcast=true")
    }

    /// Sockets (and the listener's wake-up pipe) have `FD_CLOEXEC` like the JDK: a subprocess launched by the application (`rigctld`)
    /// does not inherit them and port 2237/12060 is released after `close()`.
    @Test func socketsAreCloseOnExec() async throws {
        let b = try UdpBroadcaster()
        defer { b.close() }
        #expect(b.closeOnExec)
        let unicast = try WsjtxListener(bindHost: "127.0.0.1", bindPort: 0, handler: .init(onLoggedAdif: { _ in }))
        defer { unicast.close() }
        #expect(unicast.receiver.closeOnExec) // multicast goes through the same `init` (socket, pipe)
    }

    /// Errors go only to the log and it continues with the next target (`UB.errors`, `UB.afterClose`); `127.255.255.255`
    /// passes without error (`UB.to127bcast`, on the loopback it is not delivered even in Java).
    @Test func broadcasterErrorsLikeJava() async throws {
        let failures = Failures()
        let b = try UdpBroadcaster(failureSink: { failures.add($0) })
        let expected: [String] = [
            "Broadcast na no.such.host.invalid.:12060 selhal | java.net.UnknownHostException: no.such.host.invalid.",
            "Broadcast na 127.0.0.1:0 selhal | java.net.SocketException: Can't send to port 0",
            "Broadcast na 127.0.0.1:70000 selhal | java.lang.IllegalArgumentException: Port out of range:70000",
            "Broadcast na 127.0.0.1:9 selhal | java.net.SocketException: Message too long",
            "Broadcast na [::1:9 selhal | java.net.UnknownHostException: [::1: invalid IPv6 address literal",
        ]
        await onOwnThread {
            b.send("<x/>", [Target(host: "no.such.host.invalid.", port: 12_060)])
            b.send("<x/>", [Target(host: "127.0.0.1", port: 0)])
            b.send("<x/>", [Target(host: "127.0.0.1", port: 70_000)])
            b.send([UInt8](repeating: 0, count: 65_508), [Target(host: "127.0.0.1", port: 9)])
            b.send("<x/>", [Target(host: "[::1", port: 9)])
            b.send("<x/>", [Target(host: "", port: 9)])
            b.send("<b/>", [Target(host: "127.255.255.255", port: 9)])
        }
        #expect(failures.all == expected)
        b.close()
        b.close()
        await onOwnThread { b.send("<x/>", [Target(host: "127.0.0.1", port: 9)]) }
        #expect(failures.all.last == "Broadcast na 127.0.0.1:9 selhal | java.net.SocketException: Socket closed")
    }

    /// One socket: the same source port for IPv4 and IPv6 targets (`UB.sourcePortStable`).
    @Test func broadcasterUsesOneSocket() async throws {
        let rx4 = UdpTestSocket()
        let rx6 = UdpTestSocket(ipv6: true)
        let b = try UdpBroadcaster()
        defer { b.close() }
        let p4 = Int32(rx4.port)
        let p6 = Int32(rx6.port)
        await onOwnThread {
            b.send("a", [Target(host: "127.0.0.1", port: p4)])
            b.send("b", [Target(host: "127.0.0.1", port: p4)])
            b.send("c", [Target(host: "::1", port: p6)])
        }
        let first = await onOwnThread { rx4.receive() }
        let second = await onOwnThread { rx4.receive() }
        let third = await onOwnThread { rx6.receive() }
        #expect(first?.port == second?.port)
        #expect(first?.port == third?.port)
    }

    // MARK: - Datagram text

    @Test func adifInvalidUtf8BecomesReplacement() async throws {
        let received = Inbox<String>()
        let listener = try AdifUdpListener(bindHost: "127.0.0.1", bindPort: 0) { received.offer($0) }
        defer { listener.close() }
        listener.start()
        let bytes: [UInt8] = Array("<CALL:1>".utf8) + [0xFF] + Array("<EOR>".utf8)
        UdpTestSocket().send(bytes, toPort: listener.boundPort)
        let text: String = try #require(await onOwnThread { received.take() })
        let units: String = text.utf16.map { String(format: "%04x", $0) }.joined(separator: " ")
        #expect(units == "003c 0043 0041 004c 004c 003a 0031 003e fffd 003c 0045 004f 0052 003e", "ADIF.invalidUtf8")
    }

    @Test func n1mmFilterLikeJava() async throws {
        let received = Inbox<String>()
        let listener = try N1mmListener(bindHost: "127.0.0.1", bindPort: 0) { received.offer($0) }
        defer { listener.close() }
        listener.start()
        let tx = UdpTestSocket()
        tx.send([], toPort: listener.boundPort)
        tx.send(Array("<ContactInfo>".utf8), toPort: listener.boundPort)
        tx.send(Array("x<contactinfo".utf8), toPort: listener.boundPort)
        #expect(await onOwnThread { received.take() } == "x<contactinfo", "N1MM.empty, N1MM.caseSensitive")
        #expect(received.count == 0)
    }
}
