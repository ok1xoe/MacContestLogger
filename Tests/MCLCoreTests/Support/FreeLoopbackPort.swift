import Darwin

/// A free port on 127.0.0.1 for "nobody listens" tests (Java `new ServerSocket(0)` + `close`): a socket
/// is bound to port 0 **without `listen`** and closed at once, synchronously. `LoopbackListener.stop()` closes the listening
/// socket only asynchronously on its thread — the port from it may still accept connections for a while.
enum FreeLoopbackPort {
    static func take() -> Int {
        let fd: Int32 = socket(AF_INET, SOCK_STREAM, 0)
        precondition(fd >= 0, "socket")
        defer { _ = close(fd) }
        var sin = sockaddr_in()
        sin.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        sin.sin_family = sa_family_t(AF_INET)
        sin.sin_addr.s_addr = in_addr_t(UInt32(0x7F00_0001).bigEndian)
        sin.sin_port = 0
        let bound: Int32 = withUnsafePointer(to: &sin) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        precondition(bound == 0, "bind")
        var actual = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &actual) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) }
        }
        return Int(UInt16(bigEndian: actual.sin_port))
    }
}
