import Foundation
import Security

/// Byte stream under the MQTT client (Paho `NetworkModule`): blocking read and write from the client's own threads,
/// **never from a shared pool**. `close` from any thread unblocks an in-progress `read`/`write`.
/// Errors are `JavaSocketError` (the Java `toString()` goes into the cause of `MqttClientError`).
public protocol MqttByteTransport: AnyObject, Sendable {
    /// Next available bytes; `nil` = end of stream (Paho then reports `java.io.EOFException`).
    func read() throws -> [UInt8]?
    /// Writes the bytes whole.
    func write(_ bytes: [UInt8]) throws
    func close()
}

/// Trust for TLS: in the app system trust only (Keychain, Java `cacerts` — divergence), the hostname
/// is always verified. `anchors` = only the given root certificates — **internal**, only for tests with a custom CA
/// generated in the test (`@testable`); the public API knows only `tls: Bool` like Java.
enum MqttTlsTrust: @unchecked Sendable {
    case system
    case anchors([SecCertificate])
}

/// Connection target (Java `serverUri`: `tcp://host:port` or `ssl://host:port`).
public struct MqttEndpoint: Sendable {
    public var host: String
    public var port: Int
    /// `nil` = no TLS.
    var tls: MqttTlsTrust?

    /// `tls` = `ssl://` with system trust (Java `MqttSyncTransport(…, tls)`).
    public init(host: String, port: Int, tls: Bool = false) {
        self.host = host
        self.port = port
        self.tls = tls ? .system : nil
    }

    init(host: String, port: Int, trust: MqttTlsTrust?) {
        self.host = host
        self.port = port
        self.tls = trust
    }

    public var isTls: Bool { tls != nil }

    /// Java `(tls ? "ssl://" : "tcp://") + host + ":" + port`.
    public var serverUri: String {
        let scheme: String = tls == nil ? "tcp" : "ssl"
        return "\(scheme)://\(host):\(port)"
    }
}

/// Opens a transport to the target (blocks at most `timeoutMs`); replaceable in tests.
public typealias MqttTransportFactory = @Sendable (MqttEndpoint, Int) throws -> MqttByteTransport

public enum MqttTransports {

    /// Default factory: POSIX socket (`LineSocket`) without TLS, `NWConnection` with a synchronous wrapper with TLS.
    public static let standard: MqttTransportFactory = { endpoint, timeoutMs in
        if let trust = endpoint.tls {
            return try MqttTlsTransport.connect(host: endpoint.host, port: endpoint.port, timeoutMs: timeoutMs, trust: trust)
        }
        return try MqttPlainTransport.connect(host: endpoint.host, port: endpoint.port, timeoutMs: timeoutMs)
    }
}

/// Transport without TLS over `LineSocket` (Java `TCPNetworkModule`: `Socket.connect` with a timeout, reading without
/// `SO_TIMEOUT`).
public final class MqttPlainTransport: MqttByteTransport, @unchecked Sendable {
    private let socket: LineSocket

    private init(socket: LineSocket) {
        self.socket = socket
    }

    public static func connect(host: String, port: Int, timeoutMs: Int) throws -> MqttPlainTransport {
        let socket: LineSocket = try LineSocket.connect(host: host, port: port, connectTimeoutMs: timeoutMs, readTimeoutMs: 0)
        return MqttPlainTransport(socket: socket)
    }

    public func read() throws -> [UInt8]? {
        try socket.readBytes(max: 65_536)
    }

    public func write(_ bytes: [UInt8]) throws {
        try socket.write(bytes)
    }

    public func close() {
        socket.close()
    }
}
