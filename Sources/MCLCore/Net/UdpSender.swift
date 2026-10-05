import Darwin

/// One-shot UDP datagram (POSIX `sendto`) — Java `try (DatagramSocket s = new DatagramSocket())
/// { s.send(new DatagramPacket(b, b.length, InetAddress.getByName(host), port)); }` from `N1mmRotorUdp.send`.
/// Errors synchronously like `DatagramSocket.send` (maintainer-only probe, `UDP.` rows):
///
/// - host via `InetAddress.getByName` (`nil`/`""` → `127.0.0.1`, unresolvable → `UnknownHostException`),
///   **then** port outside 0…65535 → `IllegalArgumentException: Port out of range:<n>`;
/// - port 0 → `SocketException: Can't send to port 0`;
/// - size: Java on macOS enlarges `SO_SNDBUF`, so up to 65 507 bytes go through (the IPv4 maximum); 65 508 →
///   `SocketException: Message too long`. The default macOS buffer (9 216) would already reject 9 217 — hence
///   `SO_SNDBUF` 65 535;
/// - to a closed port without a listener it is sent without error (connectionless UDP).
///
/// Blocking (DNS) — call from your own thread.
public enum UdpSender {

    /// Datagram socket with `FD_CLOEXEC` (like the JDK and other sockets: a child process such as `rigctld` does not inherit it).
    static func openSocket(family: Int32) throws(JavaSocketError) -> Int32 {
        let fd: Int32 = socket(family, SOCK_DGRAM, 0)
        guard fd >= 0 else {
            throw JavaSocketError.writeFailure(errno)
        }
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        return fd
    }

    public static func send(_ bytes: [UInt8], host: String?, port: Int) throws {
        let address: JavaInetAddress = try JavaInetAddress.byName(host)
        guard port >= 0 && port <= 65_535 else {
            throw JavaIllegalArgumentError(message: "Port out of range:" + String(port))
        }
        if port == 0 {
            throw JavaSocketError(kind: .other, javaClass: "java.net.SocketException", message: "Can't send to port 0")
        }
        let fd: Int32 = try openSocket(family: address.family)
        defer { _ = close(fd) }
        var size: Int32 = 65_535
        _ = setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &size, socklen_t(MemoryLayout<Int32>.size))
        let sent: Int = address.withSockAddr(port: UInt16(port)) { sa, len in
            bytes.withUnsafeBytes { raw in sendto(fd, raw.baseAddress, raw.count, 0, sa, len) }
        }
        if sent < 0 {
            throw JavaSocketError.writeFailure(errno)
        }
    }
}
