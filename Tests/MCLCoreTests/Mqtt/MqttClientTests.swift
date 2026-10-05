import Foundation
import Testing
@testable import MCLCore

/// The MQTT 5 client against a scripted broker stand-in (`FakeBroker`, without Mosquitto, runs on CI too): scenarios
/// measured on Java v1.1.1. Blocking client calls only on dedicated threads (`onOwnThread`), waiting
/// without wall-clock bounds on the successful path (`waitUntil` is only a guard).
@Suite(.ioSafetyNet) struct MqttClientTests {

    static func options(_ port: Int, clientId: String = "OPT", subscriptions: [MqttSubscription] = [],
                        reconnect: Bool = false) -> MqttClient.Options {
        let connect = MqttClient.stationConnect(clientId: clientId, username: nil, password: nil, will: nil)
        var o = MqttClient.Options(endpoint: MqttEndpoint(host: "127.0.0.1", port: port), connect: connect,
                                   subscriptions: subscriptions)
        o.automaticReconnect = reconnect
        o.reconnectInitialMs = 20
        o.reconnectMaxMs = 160
        return o
    }

    static func failure(_ body: () throws -> Void) -> (any Error)? {
        do {
            try body()
            return nil
        } catch {
            return error
        }
    }

    /// A short description of packets on the wire: C, S<id>, P<id|->[d][r], A<id>, D<reason>, ping.
    static func trace(_ packets: [MqttPacket]) -> [String] {
        packets.map { packet in
            switch packet {
            case .connect:
                return "C"
            case .subscribe(let s):
                return "S\(s.packetId)"
            case .publish(let p):
                let id: String = p.packetId.map { String($0) } ?? "-"
                let dup: String = p.dup ? "d" : ""
                let retain: String = p.retain ? "r" : ""
                return "P\(id)\(dup)\(retain)"
            case .puback(let a):
                return "A\(a.packetId)"
            case .disconnect(let d):
                return "D\(d.reasonCode)"
            case .pingreq:
                return "ping"
            default:
                return "?"
            }
        }
    }

    final class Box<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: T?

        var value: T? {
            get { lock.withLock { stored } }
            set { lock.withLock { stored = newValue } }
        }
    }

    // MARK: - Connecting

    @Test func refusedConnectionFails() async throws {
        let port = FreeLoopbackPort.take()
        let error: (any Error)? = await onOwnThread { () -> (any Error)? in
            let client = MqttClient(options: Self.options(port), onMessage: { _ in })
            return Self.failure { try client.connect() }
        }
        let mqtt = try #require(error as? MqttClientError)
        #expect(mqtt.description == "Unable to connect to server (32103) - java.net.ConnectException: Connection refused")
    }

    @Test func connackRejectionIsReported() async throws {
        let broker = try FakeBroker(connack: MqttConnack(sessionPresent: false, reasonCode: 0x87))
        defer { broker.stop() }
        let port = broker.port
        let error: (any Error)? = await onOwnThread { () -> (any Error)? in
            let client = MqttClient(options: Self.options(port), onMessage: { _ in })
            return Self.failure { try client.connect() }
        }
        #expect(error as? MqttClientError == MqttClientError(code: 135))
        #expect((error as? MqttClientError)?.description == "Not authorized. (135)")
    }

    /// A deliberate divergence: Paho 1.2.5 waits indefinitely for CONNACK, Swift throws 32000 after `connectTimeoutMs`.
    @Test func missingConnackTimesOutUnlikePaho() async throws {
        let broker = try FakeBroker()
        broker.onConnect { _ in .silent }
        defer { broker.stop() }
        var options = Self.options(broker.port)
        options.connectTimeoutMs = 200
        let error: (any Error)? = await onOwnThread { [options] () -> (any Error)? in
            let client = MqttClient(options: options, onMessage: { _ in })
            return Self.failure { try client.connect() }
        }
        #expect(error as? MqttClientError == MqttClientError(code: 32_000))
    }

    @Test func clientIdThatPahoCannotEncodeIsIllegalArgument() {
        #expect(throws: JavaIllegalArgumentError(message: "Invalid UTF-8 char: [0009]")) {
            try MqttClient.validateClientId("OP\t1")
        }
        #expect(throws: JavaIllegalArgumentError(message: "ClientId longer than 65535 characters")) {
            try MqttClient.validateClientId(String(repeating: "x", count: 65_536))
        }
        #expect(throws: Never.self) { try MqttClient.validateClientId("OP1") }
    }

    // MARK: - Conversation

    /// PUBACK in both shapes, an incoming QoS 1 acknowledged only after `onMessage`, broken bytes → an outage, not a crash.
    @Test func conversationWithBothPubackFormsAndMalformedBytes() async throws {
        let broker = try FakeBroker()
        defer { broker.stop() }
        let qos1 = Counter()
        broker.onPublish { _, _ in
            qos1.increment()
            return .ack(qos1.value == 1 ? 0x10 : 0x00)
        }
        broker.onPacket { broker, connection, packet in
            if case .publish(let p) = packet, p.qos == 1, qos1.value == 2 {
                let inbound = MqttPublish(topic: "station/msg", packetId: 77, qos: 1, retain: false, payload: Array("hi".utf8))
                broker.send(.publish(inbound), connection: connection)
            }
            if case .puback(let a) = packet, a.packetId == 77 {
                broker.sendRaw([0x00, 0x00], connection: connection)
            }
        }
        let port = broker.port
        let messages = MqttRecorder<MqttPublish>()
        let events = MqttRecorder<MqttClient.Event>()
        let subscriptions = MqttClient.stationSubscriptions(clientId: "OPF")
        let (reasons, subacks): ([UInt8], [[UInt8]]) = try await onOwnThread {
            let client = MqttClient(
                options: Self.options(port, clientId: "OPF", subscriptions: subscriptions),
                onMessage: { messages.add($0) }, onEvent: { events.add($0) })
            try client.connect()
            let first: UInt8 = try client.publish(topic: "qso/cmd/insert", payload: [1], qos: 1, retain: false)
            try client.publish(topic: "spot/new", payload: [2], qos: 0, retain: false)
            let second: UInt8 = try client.publish(topic: "station/status/OPF", payload: [3], qos: 1, retain: true)
            try waitUntil("outage after broken bytes") { events.all.count >= 2 }
            return ([first, second], client.lastSubackCodes)
        }
        #expect(reasons == [0x10, 0x00])
        #expect(subacks == [[1], [0], [1], [1], [1]])
        #expect(messages.all.map(\.topic) == ["station/msg"])
        #expect(events.all == [
            .connected(sessionPresent: false, reconnect: false),
            .connectionLost(MqttClientError(code: 50_002)),
        ])
        // Order on the wire: CONNECT, 5× SUBSCRIBE (1–5), PUBLISH 6, 7 (QoS 0 consumes a number), 8, PUBACK 77.
        #expect(Self.trace(broker.packets(connection: 0)) == ["C", "S1", "S2", "S3", "S4", "S5", "P6", "P-", "P8r", "A77"])
    }

    @Test func publishWhileDisconnectedFails() async throws {
        let error: (any Error)? = await onOwnThread { () -> (any Error)? in
            let client = MqttClient(options: Self.options(1), onMessage: { _ in })
            return Self.failure { try client.publish(topic: "qso/cmd/insert", payload: [], qos: 1, retain: false) }
        }
        #expect(error as? MqttClientError == MqttClientError(code: 32_104))
    }

    /// A topic encoding error is not a connection error: `MqttCodecError` flies out, the client stays
    /// connected and the number is returned.
    @Test func topicEncodingErrorIsNotAConnectionError() async throws {
        let broker = try FakeBroker()
        defer { broker.stop() }
        let port = broker.port
        let (error, connected, inflight): ((any Error)?, Bool, Int) = try await onOwnThread {
            let client = MqttClient(options: Self.options(port), onMessage: { _ in })
            try client.connect()
            let error = Self.failure { try client.publish(topic: "bad\u{0}topic", payload: [], qos: 1, retain: false) }
            let state = (client.isConnected, client.sessionSnapshot.inflight.count)
            client.disconnect()
            return (error, state.0, state.1)
        }
        #expect(error as? MqttCodecError == .invalidCharacter(0))
        #expect(connected)
        #expect(inflight == 0)
    }

    @Test func disconnectSendsPahoDisconnect() async throws {
        let broker = try FakeBroker()
        defer { broker.stop() }
        let port = broker.port
        try await onOwnThread {
            let client = MqttClient(options: Self.options(port), onMessage: { _ in })
            try client.connect()
            client.disconnect()
            try waitUntil("DISCONNECT") { broker.received.contains { $0.bytes == [0xE0, 0x02, 0x00, 0x00] } }
            #expect(Self.failure { try client.publish(topic: "t", payload: [], qos: 0, retain: false) } as? MqttClientError
                    == MqttClientError(code: 32_111))
        }
    }

    // MARK: - Outage

    /// A publish waiting for PUBACK during an outage throws 32109 (Paho `resolveOldTokens`); a publish during the outage
    /// 32104; after reconnect the unacknowledged message goes out with DUP right after CONNECT, before subscriptions (the Java transcript
    /// `lost-puback`), and the broker thus gets it a second time (a lost PUBACK = double delivery).
    @Test func publishDuringOutageThrowsToWaiterAndIsResentWithDup() async throws {
        let broker = try FakeBroker()
        defer { broker.stop() }
        let gate = DispatchSemaphore(value: 0)
        broker.onConnect { index in
            if index == 1 {
                _ = gate.wait(timeout: .now() + 60)
            }
            return .accept(FakeBroker.ok)
        }
        broker.onPublish { _, connection in connection == 0 ? .swallow : .ack(0) }
        let port = broker.port
        let subscriptions = MqttClient.stationSubscriptions(clientId: "OPO")
        let events = MqttRecorder<MqttClient.Event>()
        let (waiter, outage, inflight): (MqttClientError?, MqttClientError?, Int) = try await onOwnThread {
            let client = MqttClient(options: Self.options(port, clientId: "OPO", subscriptions: subscriptions, reconnect: true),
                                    onMessage: { _ in }, onEvent: { events.add($0) })
            try client.connect()
            let waiterError = MqttRecorder<MqttClientError>()
            let publisher = Thread {
                if let error = Self.failure({ try client.publish(topic: "qso/cmd/insert", payload: [7], qos: 1, retain: false) }) as? MqttClientError {
                    waiterError.add(error)
                }
            }
            publisher.start()
            try waitUntil("PUBLISH at the broker") { Self.trace(broker.packets(connection: 0)).contains("P6") }
            broker.drop(connection: 0)
            try waitUntil("error for the waiter") { !waiterError.all.isEmpty }
            try waitUntil("the second connection waits for CONNACK") { broker.connectionCount == 2 && !broker.packets(connection: 1).isEmpty }
            let outageError = Self.failure { try client.publish(topic: "qso/cmd/insert", payload: [8], qos: 1, retain: false) }
            gate.signal()
            try waitUntil("reconnect") { events.all.contains(.connected(sessionPresent: false, reconnect: true)) }
            try waitUntil("PUBACK of the resent one") { client.sessionSnapshot.inflight.isEmpty }
            let left: Int = client.sessionSnapshot.inflight.count
            client.disconnect()
            return (waiterError.all.first, outageError as? MqttClientError, left)
        }
        #expect(waiter?.description == "Connection lost (32109) - java.io.EOFException")
        #expect(outage?.description == "Client is not connected (32104)")
        #expect(inflight == 0)
        #expect(Self.trace(broker.packets(connection: 1)).prefix(7) == ["C", "P6d", "S7", "S8", "S9", "S10", "S11"])
        let delivered: [MqttPublish] = broker.received.compactMap { if case .publish(let p) = $0.packet { p } else { nil } }
        #expect(delivered.map(\.payload) == [[7], [7]])
        #expect(broker.packets(connection: 0).first == broker.packets(connection: 1).first)
    }

    @Test func receiveMaximumLimitsUnacknowledgedPublishes() async throws {
        let maximum = MqttProperty(MqttProperties.Id.receiveMaximum, .u16(1))
        let broker = try FakeBroker(connack: MqttConnack(sessionPresent: false, reasonCode: 0, properties: MqttProperties([maximum])))
        defer { broker.stop() }
        broker.onPublish { _, _ in .swallow }
        let port = broker.port
        let (second, first): (MqttClientError?, MqttClientError?) = try await onOwnThread {
            let client = MqttClient(options: Self.options(port), onMessage: { _ in })
            try client.connect()
            let firstError = MqttRecorder<MqttClientError>()
            let publisher = Thread {
                if let error = Self.failure({ try client.publish(topic: "a", payload: [], qos: 1, retain: false) }) as? MqttClientError {
                    firstError.add(error)
                }
            }
            publisher.start()
            try waitUntil("first PUBLISH") { Self.trace(broker.packets(connection: 0)).contains("P1") }
            let secondError = Self.failure { try client.publish(topic: "b", payload: [], qos: 1, retain: false) }
            client.disconnect()
            try waitUntil("the first waiter ended") { !firstError.all.isEmpty }
            return (secondError as? MqttClientError, firstError.all.first)
        }
        #expect(second == MqttClientError(code: 32_202))
        #expect(first?.description == "Client is currently disconnecting (32102)")
    }

    /// An unacknowledged message survives a "restart" (a new client over the same persistence): it goes out with DUP before subscriptions,
    /// after PUBACK it disappears from the file. Paho's files next to it stay untouched.
    @Test func persistedMessageIsResentAfterRestart() async throws {
        let dir = try MqttOutboxTests.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let broker = try FakeBroker()
        defer { broker.stop() }
        broker.onPublish { _, connection in connection == 0 ? .swallow : .ack(0) }
        let pahoFile = dir.appendingPathComponent("OPP-tcp12700111883").appendingPathComponent("s-1.msg")
        try FileManager.default.createDirectory(at: pahoFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0x32]).write(to: pahoFile)
        var options = Self.options(broker.port, clientId: "OPP", subscriptions: [MqttSubscription(topicFilter: "x", qos: 1)])
        options.outbox = MqttOutbox(persistenceDir: dir, clientId: "OPP", serverUri: options.endpoint.serverUri)
        let (stored, after): (Int, Int) = try await onOwnThread { [options] in
            let first = MqttClient(options: options, onMessage: { _ in })
            try first.connect()
            let publisher = Thread { _ = try? first.publish(topic: "qso/cmd/insert", payload: [9], qos: 1, retain: false) }
            publisher.start()
            try waitUntil("PUBLISH at the broker") { Self.trace(broker.packets(connection: 0)).contains("P2") }
            first.disconnect()
            let stored: Int = options.outbox?.load().count ?? -1
            let second = MqttClient(options: options, onMessage: { _ in })
            try second.connect()
            try waitUntil("PUBACK after restart") { second.sessionSnapshot.inflight.isEmpty }
            second.disconnect()
            return (stored, options.outbox?.load().count ?? -1)
        }
        #expect(stored == 1)
        #expect(after == 0)
        #expect(Self.trace(broker.packets(connection: 1)).prefix(3) == ["C", "P2d", "S3"])
        #expect(FileManager.default.fileExists(atPath: pahoFile.path))
    }

    // MARK: - CONNACK and keep-alive

    @Test func secondConnackIsProtocolErrorAndReconnects() async throws {
        let broker = try FakeBroker()
        defer { broker.stop() }
        let port = broker.port
        let events = MqttRecorder<MqttClient.Event>()
        try await onOwnThread {
            let client = MqttClient(options: Self.options(port, reconnect: true), onMessage: { _ in }, onEvent: { events.add($0) })
            try client.connect()
            broker.send(.connack(FakeBroker.ok), connection: 0)
            try waitUntil("reconnect") { events.all.contains(.connected(sessionPresent: false, reconnect: true)) }
            client.disconnect()
        }
        #expect(events.all.contains(.connectionLost(MqttClientError(code: 0x82))))
        #expect(MqttClientError(code: 0x82).description == "Protocol error. (130)")
        #expect(Self.trace(broker.packets(connection: 0)) == ["C", "D130"])
    }

    @Test func serverKeepAliveAndAssignedClientIdAreUsed() async throws {
        let props: [MqttProperty] = [
            MqttProperty(MqttProperties.Id.serverKeepAlive, .u16(1)),
            MqttProperty(MqttProperties.Id.assignedClientIdentifier, .string("auto-1")),
        ]
        let broker = try FakeBroker(connack: MqttConnack(sessionPresent: false, reasonCode: 0, properties: MqttProperties(props)))
        defer { broker.stop() }
        let port = broker.port
        let events = MqttRecorder<MqttClient.Event>()
        try await onOwnThread {
            let client = MqttClient(options: Self.options(port, clientId: "", reconnect: true), onMessage: { _ in },
                                    onEvent: { events.add($0) })
            try client.connect()
            // The keep-alive from CONNECT is 45 s; an earlier PINGREQ = the adopted Server Keep Alive of 1 s.
            try waitUntil("PINGREQ") { Self.trace(broker.packets(connection: 0)).contains("ping") }
            broker.drop(connection: 0)
            try waitUntil("reconnect") { events.all.contains(.connected(sessionPresent: false, reconnect: true)) }
            client.disconnect()
        }
        let reconnect = try #require(broker.packets(connection: 1).first)
        guard case .connect(let packet) = reconnect else {
            Issue.record("the first packet of the second connection is not CONNECT")
            return
        }
        #expect(packet.clientId == "auto-1")
        #expect(packet.keepAliveSeconds == 45)
    }

    @Test func unansweredPingTimesOut() async throws {
        let keepAlive = MqttProperty(MqttProperties.Id.serverKeepAlive, .u16(1))
        let broker = try FakeBroker(connack: MqttConnack(sessionPresent: false, reasonCode: 0, properties: MqttProperties([keepAlive])))
        defer { broker.stop() }
        broker.answerPings = false
        let port = broker.port
        let events = MqttRecorder<MqttClient.Event>()
        try await onOwnThread {
            let client = MqttClient(options: Self.options(port), onMessage: { _ in }, onEvent: { events.add($0) })
            try client.connect()
            try waitUntil("keep-alive outage") { events.all.count >= 2 }
            client.disconnect()
        }
        #expect(events.all.last == .connectionLost(MqttClientError(code: 32_000)))
    }

    // MARK: - Delivery

    /// A listener on its own thread: a synchronous `publish` QoS 1 from `onMessage` gets its PUBACK (the reader thread is not
    /// blocked); an incoming message is acknowledged only after the listener returns. A listener exception is swallowed.
    @Test func listenerRunsOnOwnThreadAndMayPublish() async throws {
        let broker = try FakeBroker()
        defer { broker.stop() }
        broker.onPacket { broker, connection, packet in
            if case .subscribe = packet {
                let first = MqttPublish(topic: "station/msg", packetId: 50, qos: 1, retain: false, payload: [1])
                let second = MqttPublish(topic: "station/msg", packetId: 51, qos: 1, retain: false, payload: [2])
                broker.send(.publish(first), connection: connection)
                broker.send(.publish(second), connection: connection)
            }
        }
        let port = broker.port
        let reply = Box<UInt8>()
        let holder = Box<MqttClient>()
        let threadNames = MqttRecorder<String>()
        let subscriptions = [MqttSubscription(topicFilter: "station/msg", qos: 1)]
        let client = MqttClient(options: Self.options(port, subscriptions: subscriptions), onMessage: { message in
            threadNames.add(Thread.current.name ?? "")
            if message.payload == [1] {
                reply.value = try holder.value?.publish(topic: "reply", payload: [], qos: 1, retain: false)
            } else {
                throw SyncNullStateError()
            }
        })
        holder.value = client
        try await onOwnThread {
            try client.connect()
            try waitUntil("PUBACK of both incoming") { Self.trace(broker.packets(connection: 0)).contains("A51") }
            client.disconnect()
            try waitUntil("DISCONNECT") { Self.trace(broker.packets(connection: 0)).contains("D0") }
        }
        #expect(reply.value == 0)
        #expect(threadNames.all == ["mqtt-callback", "mqtt-callback"])
        #expect(Self.trace(broker.packets(connection: 0)) == ["C", "S1", "P2", "A50", "A51", "D0"])
    }

    // MARK: - Reconnect

    /// Exponential backoff against a broker that refuses connections: delays 1 → 2 → … → max (here reduced to
    /// 20 → 160 ms; the real values 1 → 128 s are guarded by `MqttSessionTests`). Lower bounds only.
    @Test func reconnectBacksOffExponentially() async throws {
        let broker = try FakeBroker()
        defer { broker.stop() }
        broker.onConnect { index in index == 0 || index >= 7 ? .accept(FakeBroker.ok) : .close }
        let port = broker.port
        let events = MqttRecorder<MqttClient.Event>()
        let dropped: UInt64 = try await onOwnThread {
            let client = MqttClient(options: Self.options(port, reconnect: true), onMessage: { _ in }, onEvent: { events.add($0) })
            try client.connect()
            let start: UInt64 = DispatchTime.now().uptimeNanoseconds
            broker.drop(connection: 0)
            try waitUntil("reconnect after refusals") { events.all.contains(.connected(sessionPresent: false, reconnect: true)) }
            client.disconnect()
            return start
        }
        let times: [UInt64] = broker.acceptTimes
        #expect(times.count == 8)
        let expected: [UInt64] = [20, 40, 80, 160, 160, 160, 160]
        var previous: UInt64 = dropped
        for (index, delayMs) in expected.enumerated() where index + 1 < times.count {
            let gap: UInt64 = times[index + 1] &- previous
            #expect(gap >= delayMs * 1_000_000, "attempt \(index + 1): \(gap / 1_000_000) ms")
            previous = times[index + 1]
        }
    }

    // MARK: - Regression pins

    /// Persistence under a lock together with queuing into in-flight (Paho `ClientState.send`): the file exists before
    /// the PUBLISH reaches the broker, and after PUBACK (the return of `publish`) it disappears.
    @Test func outboxIsWrittenBeforeSendAndRemovedAfterPuback() async throws {
        let dir = try MqttOutboxTests.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let broker = try FakeBroker()
        defer { broker.stop() }
        var options = Self.options(broker.port, clientId: "OPW")
        let outbox = MqttOutbox(persistenceDir: dir, clientId: "OPW", serverUri: options.endpoint.serverUri)
        options.outbox = outbox
        let onWire = MqttRecorder<Int>()
        broker.onPublish { _, _ in
            onWire.add(outbox.load().count)
            return .ack(0)
        }
        let after: Int = try await onOwnThread { [options] in
            let client = MqttClient(options: options, onMessage: { _ in })
            try client.connect()
            for index in 0..<20 {
                try client.publish(topic: "qso/cmd/insert", payload: [UInt8(index)], qos: 1, retain: false)
            }
            client.disconnect()
            return outbox.load().count
        }
        #expect(onWire.all == Array(repeating: 1, count: 20))
        #expect(after == 0)
    }

    /// `disconnect` during the wait in backoff ends the reconnect — no further connection attempt.
    @Test func disconnectDuringBackoffStopsReconnect() async throws {
        let broker = try FakeBroker()
        defer { broker.stop() }
        var options = Self.options(broker.port, reconnect: true)
        options.reconnectInitialMs = 600_000
        let events = MqttRecorder<MqttClient.Event>()
        let count: Int = try await onOwnThread { [options] in
            let client = MqttClient(options: options, onMessage: { _ in }, onEvent: { events.add($0) })
            try client.connect()
            broker.drop(connection: 0)
            try waitUntil("outage") { events.all.count >= 2 }
            client.disconnect()
            return broker.connectionCount
        }
        #expect(count == 1)
        #expect(events.all.last == .connectionLost(MqttClientError(code: 32_109, cause: "java.io.EOFException")))
    }

    /// A DISCONNECT from the broker (session takeover 0x8E): text like Paho `MqttException(32204, MqttDisconnect)`.
    @Test func serverDisconnectCarriesReasonCode() async throws {
        let broker = try FakeBroker()
        defer { broker.stop() }
        let port = broker.port
        let events = MqttRecorder<MqttClient.Event>()
        try await onOwnThread {
            let client = MqttClient(options: Self.options(port), onMessage: { _ in }, onEvent: { events.add($0) })
            try client.connect()
            broker.send(.disconnect(MqttDisconnect(reasonCode: 0x8E)), connection: 0)
            try waitUntil("outage") { events.all.count >= 2 }
            client.disconnect()
        }
        guard case .connectionLost(let error)? = events.all.last else {
            Issue.record("outage missing")
            return
        }
        #expect(error.description == "The Server Disconnected the client. Disconnect RC: 142 (32204)")
    }
}
