import Foundation
import Network
import Security
import Testing
@testable import MCLCore

/// Test PKI generated **at test run time** by the system `openssl` into a temporary directory (no keys in the repo):
/// the CA "MCL Test CA" and a server certificate for `DNS:localhost` only, valid for 30 days. The server gets its identity
/// from a PKCS#12 imported into memory only (`kSecImportToMemoryOnly`, macOS 15+) — the Keychain stays untouched.
struct MqttTestPki: @unchecked Sendable {
    let ca: SecCertificate
    let identity: SecIdentity

    static let openssl = "/usr/bin/openssl"

    static var available: Bool {
        if #available(macOS 15, *) {
            return FileManager.default.isExecutableFile(atPath: openssl)
        }
        return false
    }

    /// Blocks (launches processes) — call from its own thread.
    static func generate() throws -> MqttTestPki {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mcl-tls-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let ext = "subjectAltName=DNS:localhost\nextendedKeyUsage=serverAuth\nbasicConstraints=CA:FALSE\n"
        try Data(ext.utf8).write(to: dir.appendingPathComponent("ext.cnf"))
        let steps: [[String]] = [
            ["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", "ca.key", "-out", "ca.pem", "-days", "30",
             "-subj", "/CN=MCL Test CA", "-addext", "basicConstraints=critical,CA:TRUE",
             "-addext", "keyUsage=critical,keyCertSign,cRLSign"],
            ["req", "-newkey", "rsa:2048", "-nodes", "-keyout", "srv.key", "-out", "srv.csr", "-subj", "/CN=localhost"],
            ["x509", "-req", "-in", "srv.csr", "-CA", "ca.pem", "-CAkey", "ca.key", "-CAcreateserial", "-out", "srv.pem",
             "-days", "30", "-extfile", "ext.cnf"],
            ["pkcs12", "-export", "-inkey", "srv.key", "-in", "srv.pem", "-out", "srv.p12", "-passout", "pass:test",
             "-certpbe", "PBE-SHA1-3DES", "-keypbe", "PBE-SHA1-3DES", "-macalg", "sha1"],
            ["x509", "-in", "ca.pem", "-outform", "der", "-out", "ca.der"],
        ]
        for arguments in steps {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: openssl)
            process.arguments = arguments
            process.currentDirectoryURL = dir
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw POSIXError(.EIO)
            }
        }
        let caData = try Data(contentsOf: dir.appendingPathComponent("ca.der"))
        guard let ca = SecCertificateCreateWithData(nil, caData as CFData) else {
            throw POSIXError(.EINVAL)
        }
        let p12 = try Data(contentsOf: dir.appendingPathComponent("srv.p12"))
        return MqttTestPki(ca: ca, identity: try importIdentity(p12))
    }

    private static func importIdentity(_ p12: Data) throws -> SecIdentity {
        guard #available(macOS 15, *) else {
            throw POSIXError(.ENOTSUP)
        }
        let options: [String: Any] = [
            kSecImportExportPassphrase as String: "test",
            kSecImportToMemoryOnly as String: true,
        ]
        var items: CFArray?
        let status: OSStatus = SecPKCS12Import(p12 as CFData, options as CFDictionary, &items)
        guard status == errSecSuccess, let list = items as? [[String: Any]], let first = list.first,
              let value = first[kSecImportItemIdentity as String] else {
            throw POSIXError(.EINVAL)
        }
        return value as! SecIdentity
    }
}

/// A minimal broker behind TLS (`NWListener` on 127.0.0.1, its own serial queue): CONNECT → CONNACK,
/// PUBLISH QoS 1 → PUBACK; records the received packets.
final class TlsTestBroker: @unchecked Sendable {
    let listener: NWListener
    let port: Int
    private let queue = DispatchQueue(label: "tls-test-broker")
    let received = MqttRecorder<MqttPacket>()

    init(identity: SecIdentity) throws {
        let tls = NWProtocolTLS.Options()
        guard let secIdentity = sec_identity_create(identity) else {
            throw POSIXError(.EINVAL)
        }
        sec_protocol_options_set_local_identity(tls.securityProtocolOptions, secIdentity)
        let parameters = NWParameters(tls: tls)
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            if case .ready = state {
                ready.signal()
            }
        }
        let received = self.received
        let queue = self.queue
        listener.newConnectionHandler = { connection in
            connection.start(queue: queue)
            Self.serve(connection, frames: MqttFrameReader(), received: received)
        }
        listener.start(queue: queue)
        guard ready.wait(timeout: .now() + 30) == .success, let port = listener.port else {
            listener.cancel()
            throw POSIXError(.ETIMEDOUT)
        }
        self.port = Int(port.rawValue)
    }

    private static func serve(_ connection: NWConnection, frames: MqttFrameReader, received: MqttRecorder<MqttPacket>) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, complete, error in
            var frames = frames
            if let data {
                frames.append([UInt8](data))
            }
            while let packet = try? frames.nextPacket() {
                received.add(packet)
                switch packet {
                case .connect:
                    let ack = (try? MqttPacket.connack(FakeBroker.ok).encode()) ?? []
                    connection.send(content: Data(ack), completion: .idempotent)
                case .publish(let p):
                    if let id = p.packetId {
                        let ack = (try? MqttPacket.puback(MqttPuback(packetId: id)).encode()) ?? []
                        connection.send(content: Data(ack), completion: .idempotent)
                    }
                default:
                    break
                }
            }
            if complete || error != nil {
                connection.cancel()
                return
            }
            serve(connection, frames: frames, received: received)
        }
    }

    func stop() {
        listener.cancel()
    }
}

/// The TLS transport: a chain against the own test CA, the host name is verified; the system
/// trust does not know the test CA. Skipped without `openssl` or below macOS 15.
@Suite(.serialized, .ioSafetyNet, .enabled(if: MqttTestPki.available, "/usr/bin/openssl or macOS 15 missing"))
struct MqttTlsTransportTests {

    static func options(host: String, port: Int, trust: MqttTlsTrust) -> MqttClient.Options {
        let connect = MqttClient.stationConnect(clientId: "OPTLS", username: nil, password: nil, will: nil)
        var o = MqttClient.Options(endpoint: MqttEndpoint(host: host, port: port, trust: trust), connect: connect,
                                   subscriptions: [])
        o.automaticReconnect = false
        o.connectTimeoutMs = 20_000
        return o
    }

    @Test func connectsAndPublishesOverTlsWithTestCa() async throws {
        let pki: MqttTestPki = try await onOwnThread { try MqttTestPki.generate() }
        let broker: TlsTestBroker = try await onOwnThread { try TlsTestBroker(identity: pki.identity) }
        defer { broker.stop() }
        let options = Self.options(host: "localhost", port: broker.port, trust: .anchors([pki.ca]))
        let reason: UInt8 = try await onOwnThread {
            let client = MqttClient(options: options, onMessage: { _ in })
            try client.connect()
            let code: UInt8 = try client.publish(topic: "qso/cmd/insert", payload: [1, 2, 3], qos: 1, retain: false)
            client.disconnect()
            return code
        }
        #expect(reason == 0)
        #expect(options.endpoint.serverUri == "ssl://localhost:\(broker.port)")
        let packets: [MqttPacket] = broker.received.all
        #expect(packets.count >= 2)
        if case .connect(let c)? = packets.first {
            #expect(c.clientId == "OPTLS")
        } else {
            Issue.record("the first packet over TLS is not CONNECT")
        }
    }

    /// The certificate is only for `localhost`; a connection to `127.0.0.1` must fail on host name verification.
    @Test func hostnameMismatchFails() async throws {
        let pki: MqttTestPki = try await onOwnThread { try MqttTestPki.generate() }
        let broker: TlsTestBroker = try await onOwnThread { try TlsTestBroker(identity: pki.identity) }
        defer { broker.stop() }
        let options = Self.options(host: "127.0.0.1", port: broker.port, trust: .anchors([pki.ca]))
        let error: (any Error)? = await onOwnThread { () -> (any Error)? in
            let client = MqttClient(options: options, onMessage: { _ in })
            do {
                try client.connect()
                client.disconnect()
                return nil
            } catch {
                return error
            }
        }
        let mqtt = try #require(error as? MqttClientError)
        #expect(mqtt.code == 32_103)
        #expect(mqtt.cause?.hasPrefix("javax.net.ssl.SSLHandshakeException") == true, "\(mqtt)")
    }

    /// The application (system trust) does not know the test CA → TLS fails, `MqttSyncTransport` reports the Java text with `ssl://`.
    @Test func systemTrustRejectsTestCa() async throws {
        let pki: MqttTestPki = try await onOwnThread { try MqttTestPki.generate() }
        let broker: TlsTestBroker = try await onOwnThread { try TlsTestBroker(identity: pki.identity) }
        defer { broker.stop() }
        let port: Int = broker.port
        let error: (any Error)? = await onOwnThread { () -> (any Error)? in
            let t = MqttSyncTransport(host: "localhost", port: port, clientId: "OPTLS", username: nil, password: nil,
                                      persistenceDir: nil, tls: true)
            defer { t.close() }
            do {
                try t.connect()
                return nil
            } catch {
                return error
            }
        }
        let sync = try #require(error as? SyncTransportError)
        #expect(sync.message == "Nelze se připojit k MQTT brokeru ssl://localhost:\(port)")
        #expect(sync.cause?.hasPrefix("Unable to connect to server (32103) - javax.net.ssl.SSLHandshakeException") == true,
                "\(sync.cause ?? "")")
    }
}
