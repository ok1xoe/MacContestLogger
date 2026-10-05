import Darwin

/// UDP peer address (Java `InetSocketAddress` with a resolved address): the datagram sender
/// from `WsjtxListener.Handler.onDecode` and the target of `WsjtxListener.send` (Reply). A mapped IPv4 from a dual-stack
/// socket is IPv4 as in Java (`WSJ.fromAndAfterClose`: `Inet4Address 127.0.0.1`).
public struct UdpEndpoint: Sendable, Equatable, CustomStringConvertible {
    let address: JavaInetAddress
    public let port: Int

    init(address: JavaInetAddress, port: Int) {
        self.address = address
        self.port = port
    }

    /// Java `new InetSocketAddress(host, port)` without the unresolved variant: port outside 0…65535 →
    /// `IllegalArgumentException: port out of range:<n>` (before name resolution), the name via
    /// `InetAddress.getByName` (`UnknownHostException`). Blocking (DNS) — call from your own thread.
    public static func resolve(host: String, port: Int) throws -> UdpEndpoint {
        try UdpReceiver.checkPort(port)
        let address: JavaInetAddress = try JavaInetAddress.byName(host)
        return UdpEndpoint(address: address, port: port)
    }

    /// Java `getAddress().getHostAddress()` (`127.0.0.1`, `0:0:0:0:0:0:0:1`).
    public var hostAddress: String {
        address.hostAddress
    }

    /// Java `InetSocketAddress.toString()`: `/127.0.0.1:2237`, IPv6 in square brackets.
    public var description: String {
        let host: String = address.family == AF_INET6 ? "[" + hostAddress + "]" : hostAddress
        return "/" + host + ":" + String(port)
    }
}
