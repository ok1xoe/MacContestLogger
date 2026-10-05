import Darwin

/// Interface on which the Java `MulticastSocket.joinGroup(InetAddress)` joins the group on macOS: the JDK
/// (`DatagramSocketAdaptor.defaultNetworkInterface`) takes `java.net.DefaultInterface` — the **first** interface
/// that is up and multicast-capable, in preference order (without PPP and loopback): with both IPv4 and IPv6 and a non-link-local
/// address (immediately), with both IPv4 and IPv6, with a non-link-local address, any; then the first PPP, then the first loopback.
/// Index 0 (the kernel picks by itself) only when there is nothing of the kind — the kernel would otherwise choose a different interface
/// (measured with `netstat -g`: Java `en0`, `IPV6_JOIN_GROUP` with index 0 `en15`).
///
/// The enumeration order is Java `NetworkInterface.getNetworkInterfaces()` on BSD: first IPv6-only interfaces
/// (reversed by `getifaddrs`), then interfaces with IPv4 (reversed) — the JDK prepends them to the list during the IPv4 and IPv6
/// passes. The JDK stores the choice once per run (static initialization), same here.
enum DefaultMulticastInterface {

    struct Candidate: Equatable {
        let name: String
        let index: UInt32
        let flags: UInt32
        var ipv4 = false
        var ipv6 = false
        var nonLinkLocal = false
        /// The interface has at least one IPv4 address (even `0.0.0.0`) — the JDK found it in the IPv4 pass.
        var inV4Pass = false
    }

    /// Interface index for `IPV6_JOIN_GROUP` (0 = leave it to the kernel).
    static let index: UInt32 = choose(enumerate())?.index ?? 0

    /// Java `DefaultInterface.chooseDefaultInterface()` over candidates in Java order.
    static func choose(_ candidates: [Candidate]) -> Candidate? {
        var preferred: Candidate?
        var dual: Candidate?
        var nonLinkLocal: Candidate?
        var ppp: Candidate?
        var loopback: Candidate?
        for c in candidates {
            // Java `isUp()` = `IFF_UP` and `IFF_RUNNING`.
            let up: UInt32 = UInt32(IFF_UP) | UInt32(IFF_RUNNING)
            guard c.flags & up == up, c.flags & UInt32(IFF_MULTICAST) != 0 else { continue }
            let isLoopback: Bool = c.flags & UInt32(IFF_LOOPBACK) != 0
            let isPPP: Bool = c.flags & UInt32(IFF_POINTOPOINT) != 0
            if !isLoopback && !isPPP {
                if preferred == nil { preferred = c }
                if c.ipv4 && c.ipv6 {
                    if c.nonLinkLocal { return c }
                    if dual == nil { dual = c }
                }
                if nonLinkLocal == nil && c.nonLinkLocal { nonLinkLocal = c }
            }
            if ppp == nil && isPPP { ppp = c }
            if loopback == nil && isLoopback { loopback = c }
        }
        return dual ?? nonLinkLocal ?? preferred ?? ppp ?? loopback
    }

    /// Interfaces with addresses in the Java enumeration order.
    static func enumerate() -> [Candidate] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(first) }
        var withV4: [Candidate] = []
        var onlyV6: [Candidate] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            cursor = entry.pointee.ifa_next
            guard let sa = entry.pointee.ifa_addr else { continue }
            let family = Int32(sa.pointee.sa_family)
            guard family == AF_INET || family == AF_INET6 else { continue }
            let name = String(cString: entry.pointee.ifa_name)
            let address = JavaInetAddress(socketAddress: storage(of: sa))
            var c = Candidate(name: name, index: if_nametoindex(entry.pointee.ifa_name), flags: entry.pointee.ifa_flags)
            if let i = withV4.firstIndex(where: { $0.name == name }) {
                c = withV4.remove(at: i)
            } else if let i = onlyV6.firstIndex(where: { $0.name == name }) {
                c = onlyV6.remove(at: i)
            }
            if !isAnyLocal(address) {
                if family == AF_INET { c.ipv4 = true } else { c.ipv6 = true }
                if !isLinkLocal(address) { c.nonLinkLocal = true }
            }
            if family == AF_INET { c.inV4Pass = true }
            if c.inV4Pass {
                withV4.append(c)
            } else {
                onlyV6.append(c)
            }
        }
        let ordered: [Candidate] = withV4.sorted { order(of: $0.name, first) < order(of: $1.name, first) }
        let orderedV6: [Candidate] = onlyV6.sorted { order(of: $0.name, first) < order(of: $1.name, first) }
        // Step by step with types: Swift 6.1 (Xcode 16.4 in CI) reports an ambiguity for `reversed() + reversed()`.
        let v6: [Candidate] = Array(orderedV6.reversed())
        let v4: [Candidate] = Array(ordered.reversed())
        return v6 + v4
    }

    /// Order of the first occurrence of an interface in `getifaddrs`.
    private static func order(of name: String, _ first: UnsafeMutablePointer<ifaddrs>) -> Int {
        var position = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            if String(cString: entry.pointee.ifa_name) == name { return position }
            position += 1
            cursor = entry.pointee.ifa_next
        }
        return position
    }

    private static func storage(of sa: UnsafeMutablePointer<sockaddr>) -> sockaddr_storage {
        var out = sockaddr_storage()
        let count: Int = min(Int(sa.pointee.sa_len), MemoryLayout<sockaddr_storage>.size)
        withUnsafeMutableBytes(of: &out) { dst in
            dst.copyMemory(from: UnsafeRawBufferPointer(start: UnsafeRawPointer(sa), count: count))
        }
        return out
    }

    private static func isAnyLocal(_ a: JavaInetAddress) -> Bool {
        a.addressBytes.allSatisfy { $0 == 0 }
    }

    /// Java `isLinkLocalAddress`: 169.254/16, fe80::/10.
    private static func isLinkLocal(_ a: JavaInetAddress) -> Bool {
        let b: [UInt8] = a.addressBytes
        if a.family == AF_INET6 {
            return b[0] == 0xFE && b[1] & 0xC0 == 0x80
        }
        return b[0] == 169 && b[1] == 254
    }
}
