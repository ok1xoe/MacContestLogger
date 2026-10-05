import Darwin

/// Java socket `IOException` (`java.net.*`) with a category for later mapping to `CatException`
/// and client texts. `javaClass` + `message` are the Java `getClass().getName()` and `getMessage()`
/// (measured by the maintainer-only probe, rows `CONN.`, `CLOSE.`, `WRITE.`, `RESET.`, `UDP.`).
///
/// End of stream is not an error — `LineSocket.readLine` returns `nil` (Java `readLine() == null`).
public struct JavaSocketError: Error, Equatable, Sendable, CustomStringConvertible {

    public enum Kind: Equatable, Sendable {
        /// `UnknownHostException: <host>` (the name did not resolve).
        case unknownHost
        /// `ConnectException: Connection refused`.
        case refused
        /// `SocketTimeoutException: Connect timed out`.
        case connectTimeout
        /// `SocketTimeoutException: Read timed out` — the socket stays usable.
        case readTimeout
        /// `SocketException: Socket closed` — closed by this side (even from another thread during a read).
        case closed
        /// `SocketException: Connection reset` — RST from the peer during a read.
        case reset
        /// Other I/O error (text = `strerror`, like Java native exceptions on macOS).
        case other
    }

    public let kind: Kind
    public let javaClass: String
    public let message: String?

    public init(kind: Kind, javaClass: String, message: String?) {
        self.kind = kind
        self.javaClass = javaClass
        self.message = message
    }

    /// Java `Throwable.toString()`.
    public var description: String {
        guard let message else { return javaClass }
        return javaClass + ": " + message
    }

    static func unknownHost(_ host: String) -> JavaSocketError {
        JavaSocketError(kind: .unknownHost, javaClass: "java.net.UnknownHostException", message: host)
    }

    /// Java `InetAddress.getByName` for a bad IPv6 literal (`[127.0.0.1]`, `[::1`, `::1]`).
    static func invalidIPv6Literal(_ host: String) -> JavaSocketError {
        JavaSocketError(kind: .unknownHost, javaClass: "java.net.UnknownHostException",
                        message: host + ": invalid IPv6 address literal")
    }

    static let connectTimedOut = JavaSocketError(
        kind: .connectTimeout, javaClass: "java.net.SocketTimeoutException", message: "Connect timed out")

    static let readTimedOut = JavaSocketError(
        kind: .readTimeout, javaClass: "java.net.SocketTimeoutException", message: "Read timed out")

    static let socketClosed = JavaSocketError(
        kind: .closed, javaClass: "java.net.SocketException", message: "Socket closed")

    /// `connect(2)` error (Java `Net.connect` → `ConnectException`/`BindException`/`NoRouteToHostException`).
    static func connectFailure(_ code: Int32) -> JavaSocketError {
        let text = errnoText(code)
        switch code {
        case ECONNREFUSED:
            return JavaSocketError(kind: .refused, javaClass: "java.net.ConnectException", message: text)
        case ETIMEDOUT:
            // Java reports `Connect timed out` only for its own timeout; the kernel ETIMEDOUT (timeout 0 = no limit)
            // would be `ConnectException: Operation timed out`. The clients do not use timeout 0.
            return connectTimedOut
        case EADDRINUSE, EADDRNOTAVAIL:
            return JavaSocketError(kind: .other, javaClass: "java.net.BindException", message: text)
        case EHOSTUNREACH:
            return JavaSocketError(kind: .other, javaClass: "java.net.NoRouteToHostException", message: text)
        default:
            return JavaSocketError(kind: .other, javaClass: "java.net.ConnectException", message: text)
        }
    }

    /// Read error (`ECONNRESET` → Java `Connection reset` without "by peer").
    static func readFailure(_ code: Int32) -> JavaSocketError {
        if code == ECONNRESET {
            return JavaSocketError(kind: .reset, javaClass: "java.net.SocketException", message: "Connection reset")
        }
        return JavaSocketError(kind: .other, javaClass: "java.net.SocketException", message: errnoText(code))
    }

    /// Write error (`EPIPE` → `Broken pipe`, measured `WRITE.peerClosed`).
    static func writeFailure(_ code: Int32) -> JavaSocketError {
        JavaSocketError(kind: .other, javaClass: "java.net.SocketException", message: errnoText(code))
    }

    /// UDP socket `bind`/`sendto` error per Java `handleSocketError` (JDK `Net.c`): `EHOSTUNREACH` →
    /// `NoRouteToHostException`, `EADDRINUSE`/`EADDRNOTAVAIL`/`EACCES` → `BindException`, `ECONNREFUSED`/`ETIMEDOUT`/
    /// `ENOTCONN` → `ConnectException`, otherwise `SocketException`; text = `strerror` (measured `BIND.inUse`,
    /// `BIND.foreign`, `WSJ.sendV6From4`, `WSJ.sendTooBig`).
    static func datagramFailure(_ code: Int32) -> JavaSocketError {
        let text = errnoText(code)
        let javaClass: String
        switch code {
        case EHOSTUNREACH:
            javaClass = "java.net.NoRouteToHostException"
        case EADDRINUSE, EADDRNOTAVAIL, EACCES:
            javaClass = "java.net.BindException"
        case ECONNREFUSED, ETIMEDOUT, ENOTCONN:
            javaClass = "java.net.ConnectException"
        case EPROTO:
            javaClass = "java.net.ProtocolException"
        default:
            javaClass = "java.net.SocketException"
        }
        return JavaSocketError(kind: .other, javaClass: javaClass, message: text)
    }

    /// `new DatagramSocket(new InetSocketAddress(host, port))` with an unresolvable name (`BIND.unresolved`).
    static let unresolvedAddress = JavaSocketError(
        kind: .unknownHost, javaClass: "java.net.SocketException", message: "Unresolved address")

    static func errnoText(_ code: Int32) -> String {
        String(cString: strerror(code))
    }
}
