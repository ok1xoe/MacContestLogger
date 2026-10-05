import Foundation
import Network
import Security

/// Transport over TLS on `NWConnection` (SecureTransport is deprecated) with a synchronous wrapper:
/// its own **serial** connection queue (never `.main` or a global one), the caller waits on a semaphore on the client's **own
/// thread** — never in a shared pool. The Java `SSLNetworkModule` (default `SSLSocketFactory`
/// with hostname verification): here system trust (Keychain instead of `cacerts`), the hostname is always verified
/// (default `NWProtocolTLS` policy, `SecPolicyCreateSSL(true, host)` for custom roots).
///
/// `.waiting` (e.g. ECONNREFUSED) is not waited out — it is a connection error at once with the Java text; the connect timeout is watched by
/// its own timer (0 = no limit like Java).
public final class MqttTlsTransport: MqttByteTransport, @unchecked Sendable {

    private let connection: NWConnection
    private let host: String
    private let lock = NSLock()
    private var closed = false

    private init(connection: NWConnection, host: String) {
        self.connection = connection
        self.host = host
    }

    /// One-shot result from the connection queue.
    private final class Outcome<T>: @unchecked Sendable {
        let semaphore = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var value: T?

        func finish(_ result: T) {
            lock.lock()
            let first: Bool = value == nil
            if first {
                value = result
            }
            lock.unlock()
            if first {
                semaphore.signal()
            }
        }

        var result: T? {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }

    static func connect(host: String, port: Int, timeoutMs: Int, trust: MqttTlsTrust) throws -> MqttTlsTransport {
        guard port >= 0 && port <= 65_535, let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            throw JavaIllegalArgumentError(message: "port out of range:" + String(port))
        }
        guard timeoutMs >= 0 else {
            throw JavaIllegalArgumentError(message: "connect: timeout can't be negative")
        }
        let queue = DispatchQueue(label: "mqtt-tls")
        let tls = NWProtocolTLS.Options()
        if case .anchors(let anchors) = trust {
            installAnchors(anchors, host: host, options: tls, queue: queue)
        }
        let parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: parameters)
        let outcome = Outcome<NWError?>()
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                outcome.finish(nil)
            case .waiting(let error), .failed(let error):
                outcome.finish(error)
            case .cancelled:
                outcome.finish(NWError.posix(.ECANCELED))
            default:
                break
            }
        }
        connection.start(queue: queue)
        let deadline: DispatchTime = timeoutMs == 0 ? .distantFuture : .now() + .milliseconds(timeoutMs)
        if outcome.semaphore.wait(timeout: deadline) == .timedOut {
            connection.cancel()
            throw JavaSocketError.connectTimedOut
        }
        if let failure = outcome.result, let error = failure {
            connection.cancel()
            throw connectError(error, host: host)
        }
        return MqttTlsTransport(connection: connection, host: host)
    }

    /// Chain validation only against the given roots, with the hostname (tests with a custom CA).
    private static func installAnchors(_ anchors: [SecCertificate], host: String, options: NWProtocolTLS.Options, queue: DispatchQueue) {
        let verify: sec_protocol_verify_t = { _, secTrust, complete in
            let trust: SecTrust = sec_trust_copy_ref(secTrust).takeRetainedValue()
            let policy: SecPolicy = SecPolicyCreateSSL(true, host as CFString)
            SecTrustSetPolicies(trust, policy)
            SecTrustSetAnchorCertificates(trust, anchors as CFArray)
            SecTrustSetAnchorCertificatesOnly(trust, true)
            var error: CFError?
            complete(SecTrustEvaluateWithError(trust, &error))
        }
        sec_protocol_options_set_verify_block(options.securityProtocolOptions, verify, queue)
    }

    /// `NWError` on connect → Java exception (`ConnectException`, `UnknownHostException`, `SSLHandshakeException`).
    static func connectError(_ error: NWError, host: String) -> JavaSocketError {
        switch error {
        case .posix(let code):
            return JavaSocketError.connectFailure(code.rawValue)
        case .dns:
            return JavaSocketError.unknownHost(host)
        case .tls(let status):
            return JavaSocketError(kind: .other, javaClass: "javax.net.ssl.SSLHandshakeException", message: statusText(status))
        default:
            return JavaSocketError(kind: .other, javaClass: "java.io.IOException", message: "\(error)")
        }
    }

    static func statusText(_ status: OSStatus) -> String {
        let text: CFString? = SecCopyErrorMessageString(status, nil)
        return (text as String?) ?? "OSStatus \(status)"
    }

    private var isClosed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return closed
    }

    private func ioError(_ error: NWError) -> JavaSocketError {
        if isClosed {
            return JavaSocketError.socketClosed
        }
        switch error {
        case .posix(let code):
            return JavaSocketError.readFailure(code.rawValue)
        case .tls(let status):
            return JavaSocketError(kind: .other, javaClass: "javax.net.ssl.SSLException", message: Self.statusText(status))
        default:
            return JavaSocketError(kind: .other, javaClass: "java.io.IOException", message: "\(error)")
        }
    }

    public func read() throws -> [UInt8]? {
        while true {
            if isClosed {
                throw JavaSocketError.socketClosed
            }
            let outcome = Outcome<(Data?, Bool, NWError?)>()
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, complete, error in
                outcome.finish((data, complete, error))
            }
            outcome.semaphore.wait()
            guard let (data, complete, error) = outcome.result else { continue }
            if let data, !data.isEmpty {
                return [UInt8](data)
            }
            if let error {
                throw ioError(error)
            }
            if complete {
                return nil
            }
        }
    }

    public func write(_ bytes: [UInt8]) throws {
        if isClosed {
            throw JavaSocketError.socketClosed
        }
        let outcome = Outcome<NWError?>()
        connection.send(content: Data(bytes), completion: .contentProcessed { error in
            outcome.finish(error)
        })
        outcome.semaphore.wait()
        if let failure = outcome.result, let error = failure {
            throw ioError(error)
        }
    }

    public func close() {
        lock.lock()
        let first: Bool = !closed
        closed = true
        lock.unlock()
        if first {
            connection.cancel()
        }
    }
}
