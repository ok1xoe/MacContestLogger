import Darwin

/// Socket address after the Java `InetAddress.getByName` (JDK 21, default `java.net.preferIPv6Addresses=false`):
/// `nil`/`""` → loopback `127.0.0.1` (measured `CONN.emptyHost`, `UDP.emptyHost`, `UDP.nullHost`), otherwise
/// `getaddrinfo` and the **first IPv4** address (Java orders IPv4 before IPv6; `localhost` → `127.0.0.1`, measured
/// `CONN.localhostAddr`), without IPv4 the first IPv6. An unresolvable name → `UnknownHostException: <host>`.
///
/// An IPv6 literal in square brackets (`[::1]`, `Target` `[::1]:2237`) is accepted by Java (measured
/// `UdpIoProbe`, `GBN.` rows): the brackets are stripped and inside may be **only** an IPv6 literal (even with a zone
/// `%lo0`); `[127.0.0.1]`, `[localhost]`, `[]`, `[::1` → `UnknownHostException: <host>: invalid IPv6
/// address literal`. The same is reported for a name starting with a hex digit or `:` that contains `:` but
/// is not a literal (`::1]`). An IPv6 literal with a mapped IPv4 (`::ffff:127.0.0.1`) is an `Inet4Address` in Java.
///
/// Blocking (DNS) — call only from your own thread, not from a shared pool.
struct JavaInetAddress: Sendable, Equatable {
    let family: Int32
    /// `sockaddr_in`/`sockaddr_in6` with port 0 (the port is filled in on use).
    private let storage: sockaddr_storage

    static func byName(_ host: String?) throws(JavaSocketError) -> JavaInetAddress {
        guard let host, !host.isEmpty else {
            return loopback
        }
        if host.hasPrefix("[") {
            guard host.utf16.count > 2, host.hasSuffix("]") else {
                throw .invalidIPv6Literal(host)
            }
            let inner = String(host.dropFirst().dropLast())
            guard let literal = numericIPv6(inner) else {
                throw .invalidIPv6Literal(host)
            }
            return literal
        }
        if looksLikeIPv6Literal(host) {
            guard let literal = numericIPv6(host) else {
                throw .invalidIPv6Literal(host)
            }
            return literal
        }
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        var list: UnsafeMutablePointer<addrinfo>?
        let rc: Int32 = getaddrinfo(host, nil, &hints, &list)
        guard rc == 0, let first = list else {
            throw .unknownHost(host)
        }
        defer { freeaddrinfo(first) }
        var v6: JavaInetAddress?
        var cursor: UnsafeMutablePointer<addrinfo>? = first
        while let entry = cursor {
            if let addr = entry.pointee.ai_addr {
                if entry.pointee.ai_family == AF_INET {
                    return JavaInetAddress(copying: addr, length: entry.pointee.ai_addrlen, family: AF_INET)
                }
                if entry.pointee.ai_family == AF_INET6 && v6 == nil {
                    v6 = JavaInetAddress(copying: addr, length: entry.pointee.ai_addrlen, family: AF_INET6)
                }
            }
            cursor = entry.pointee.ai_next
        }
        guard let v6 else {
            throw .unknownHost(host)
        }
        return v6.unmappingIPv4()
    }

    /// Java `IPAddressUtil`: a string starting with a hex digit or `:` and containing `:` is taken as an IPv6
    /// literal (otherwise `invalid IPv6 address literal`), not as a DNS name.
    private static func looksLikeIPv6Literal(_ host: String) -> Bool {
        guard let first = host.unicodeScalars.first, host.contains(":") else { return false }
        return first == ":" || first.properties.isASCIIHexDigit
    }

    /// IPv6 literal (optionally with a zone) without DNS; mapped IPv4 → IPv4 as in Java.
    private static func numericIPv6(_ text: String) -> JavaInetAddress? {
        numeric(text, family: AF_INET6)?.unmappingIPv4()
    }

    private static func numeric(_ text: String, family: Int32) -> JavaInetAddress? {
        var hints = addrinfo()
        hints.ai_family = family
        hints.ai_socktype = SOCK_DGRAM
        hints.ai_flags = AI_NUMERICHOST
        var list: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(text, nil, &hints, &list) == 0, let first = list else {
            return nil
        }
        defer { freeaddrinfo(first) }
        guard let addr = first.pointee.ai_addr else { return nil }
        return JavaInetAddress(copying: addr, length: first.pointee.ai_addrlen, family: first.pointee.ai_family)
    }

    static var loopback: JavaInetAddress {
        var sin = sockaddr_in()
        sin.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        sin.sin_family = sa_family_t(AF_INET)
        sin.sin_addr.s_addr = in_addr_t(UInt32(0x7F00_0001).bigEndian)
        var storage = sockaddr_storage()
        withUnsafeMutableBytes(of: &storage) { dst in
            withUnsafeBytes(of: &sin) { src in
                dst.copyMemory(from: src)
            }
        }
        return JavaInetAddress(family: AF_INET, storage: storage)
    }

    private init(family: Int32, storage: sockaddr_storage) {
        self.family = family
        self.storage = storage
    }

    private init(copying addr: UnsafePointer<sockaddr>, length: socklen_t, family: Int32) {
        var storage = sockaddr_storage()
        let count = min(Int(length), MemoryLayout<sockaddr_storage>.size)
        withUnsafeMutableBytes(of: &storage) { dst in
            dst.copyMemory(from: UnsafeRawBufferPointer(start: UnsafeRawPointer(addr), count: count))
        }
        self.family = family
        self.storage = storage
    }

    /// Calls `body` with the address and port (`sockaddr *`, length).
    func withSockAddr<R>(port: UInt16, _ body: (UnsafePointer<sockaddr>, socklen_t) -> R) -> R {
        var copy = storage
        if family == AF_INET6 {
            return withUnsafeMutablePointer(to: &copy) { raw in
                raw.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { sin6 in
                    sin6.pointee.sin6_port = port.bigEndian
                    sin6.pointee.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
                    return sin6.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                        body(sa, socklen_t(MemoryLayout<sockaddr_in6>.size))
                    }
                }
            }
        }
        return withUnsafeMutablePointer(to: &copy) { raw in
            raw.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sin in
                sin.pointee.sin_port = port.bigEndian
                sin.pointee.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                return sin.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    body(sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }
}

// MARK: - UDP: dual-stack sockets like the JDK

extension JavaInetAddress {

    /// Address from `recvfrom`/`getsockname`; mapped IPv4 (`::ffff:a.b.c.d`) → IPv4 like Java `Inet4Address`.
    init(socketAddress storage: sockaddr_storage) {
        self.init(family: Int32(storage.ss_family), storage: storage)
        self = unmappingIPv4()
    }

    static func == (lhs: JavaInetAddress, rhs: JavaInetAddress) -> Bool {
        lhs.family == rhs.family && lhs.addressBytes == rhs.addressBytes && lhs.scopeID == rhs.scopeID
    }

    /// Address bytes (4 or 16) without the port.
    var addressBytes: [UInt8] {
        var copy = storage
        if family == AF_INET6 {
            return withUnsafeBytes(of: &copy) { raw in
                let sin6 = raw.load(as: sockaddr_in6.self)
                return withUnsafeBytes(of: sin6.sin6_addr) { Array($0) }
            }
        }
        return withUnsafeBytes(of: &copy) { raw in
            let sin = raw.load(as: sockaddr_in.self)
            return withUnsafeBytes(of: sin.sin_addr) { Array($0) }
        }
    }

    var scopeID: UInt32 {
        guard family == AF_INET6 else { return 0 }
        var copy = storage
        return withUnsafeBytes(of: &copy) { $0.load(as: sockaddr_in6.self).sin6_scope_id }
    }

    /// Java `InetAddress.isMulticastAddress()` (224.0.0.0/4, ff00::/8).
    var isMulticast: Bool {
        let bytes: [UInt8] = addressBytes
        if family == AF_INET6 {
            return bytes[0] == 0xFF
        }
        return bytes[0] & 0xF0 == 0xE0
    }

    var isIPv4AnyLocal: Bool {
        family == AF_INET && addressBytes == [0, 0, 0, 0]
    }

    /// Java `getHostAddress()`: IPv4 dotted, IPv6 eight groups without compression (`0:0:0:0:0:0:0:1`) + `%zone`.
    var hostAddress: String {
        let bytes: [UInt8] = addressBytes
        if family != AF_INET6 {
            return bytes.map { String($0) }.joined(separator: ".")
        }
        var groups: [String] = []
        for i in stride(from: 0, to: 16, by: 2) {
            let value: Int = Int(bytes[i]) << 8 | Int(bytes[i + 1])
            groups.append(String(value, radix: 16))
        }
        let text: String = groups.joined(separator: ":")
        let scope: UInt32 = scopeID
        guard scope != 0 else { return text }
        var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE) + 1)
        if if_indextoname(scope, &name) != nil {
            let bytes: [UInt8] = name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
            return text + "%" + String(decoding: bytes, as: UTF8.self)
        }
        return text + "%" + String(scope)
    }

    /// `::ffff:a.b.c.d` → IPv4 (Java literals and addresses received on a dual-stack socket).
    func unmappingIPv4() -> JavaInetAddress {
        guard family == AF_INET6 else { return self }
        let bytes: [UInt8] = addressBytes
        let prefix: [UInt8] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xFF, 0xFF]
        guard Array(bytes[0..<12]) == prefix else { return self }
        var sin = sockaddr_in()
        sin.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        sin.sin_family = sa_family_t(AF_INET)
        withUnsafeMutableBytes(of: &sin.sin_addr) { dst in
            dst.copyBytes(from: bytes[12..<16])
        }
        var out = sockaddr_storage()
        withUnsafeMutableBytes(of: &out) { dst in
            withUnsafeBytes(of: &sin) { src in
                dst.copyMemory(from: src)
            }
        }
        return JavaInetAddress(family: AF_INET, storage: out)
    }

    /// `sockaddr_in6` for a dual-stack socket (JDK: IPv6 socket with `IPV6_V6ONLY=0`): IPv4 as `::ffff:a.b.c.d`,
    /// IPv4 wildcard `0.0.0.0` as `::` (a Java bind to `0.0.0.0` reports `local=/0:0:0:0:0:0:0:0`, `BIND.wild4`).
    func dualStackSockAddr(port: UInt16) -> sockaddr_in6 {
        var sin6 = sockaddr_in6()
        sin6.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
        sin6.sin6_family = sa_family_t(AF_INET6)
        sin6.sin6_port = port.bigEndian
        if family == AF_INET6 {
            var copy = storage
            let original: sockaddr_in6 = withUnsafeBytes(of: &copy) { $0.load(as: sockaddr_in6.self) }
            sin6.sin6_addr = original.sin6_addr
            sin6.sin6_scope_id = original.sin6_scope_id
            return sin6
        }
        if isIPv4AnyLocal {
            return sin6
        }
        var mapped: [UInt8] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xFF, 0xFF]
        mapped += addressBytes
        withUnsafeMutableBytes(of: &sin6.sin6_addr) { dst in
            dst.copyBytes(from: mapped)
        }
        return sin6
    }
}
