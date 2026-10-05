import Foundation
import Testing
@testable import MCLCore

/// `MqttSyncTransport` against `FakeBroker` and the Java transcript of Paho (`Fixtures/mqtt-paho-transcript.tsv`,
/// scenarios `main` and `lost-puback`): bytes on the wire, error texts, routing of messages to listeners and double delivery
/// after a lost PUBACK (idempotence of `uuid` + LWW `version` in `SyncCoordinator`).
@Suite(.ioSafetyNet) struct MqttSyncTransportTests {

    static func transport(_ port: Int, clientId: String, username: String? = nil, password: String? = nil,
                          dir: URL? = nil) -> MqttSyncTransport {
        MqttSyncTransport(host: "127.0.0.1", port: port, clientId: clientId, username: username, password: password,
                          persistenceDir: dir, trust: nil, configure: { options in options.reconnectInitialMs = 20 })
    }

    static func failure(_ body: () throws -> Void) -> (any Error)? {
        do {
            try body()
            return nil
        } catch {
            return error
        }
    }

    /// `QsoWire w` from the probe `MqttTranscript.java`.
    static let wire = QsoWire(
        timestampUtc: JavaInstant.parseIsoInstant("2026-10-01T12:34:56Z"), call: "OK1ABC", freqHz: 14_025_000,
        band: "B20", mode: "CW", rstSent: "599", rstRcvd: "599", exchangeSent: "001", exchangeRcvd: "005",
        serialSent: 1, serialRcvd: 5, operator: "OK1XOE", comment: nil, dxccEntity: 503, dxccName: "Czech Republic",
        continent: "EU")

    static func command(_ station: String, _ uuid: String, _ at: String) -> QsoCommand {
        QsoCommand(stationId: station, uuid: uuid, clientTimestampUtc: JavaInstant.parseIsoInstant(at), qso: wire)
    }

    /// Client packets from the transcript per connection (a new connection starts with CONNECT), without PUBACK (those depend on what
    /// the broker sends) and with PUBLISH without Topic Alias.
    static func pahoConnections(_ scenario: String) throws -> [[[UInt8]]] {
        var out: [[[UInt8]]] = []
        for bytes in try MqttPahoTranscript.packets(scenario, "C") {
            let packet: MqttPacket = try MqttPacket.decode(bytes)
            switch packet {
            case .connect:
                out.append([bytes])
            case .puback:
                continue
            case .publish(var p):
                p.properties = p.properties.removing(MqttProperties.Id.topicAlias)
                out[out.count - 1].append(try MqttPacket.publish(p).encode())
            default:
                out[out.count - 1].append(bytes)
            }
        }
        return out
    }

    static func ours(_ broker: FakeBroker, _ connection: Int) -> [[UInt8]] {
        broker.received.filter { $0.connection == connection }.map(\.bytes).filter { $0.first != 0x40 }
    }

    static func events(_ scenario: String) throws -> [String] {
        try MqttPahoTranscript.load().filter { $0.scenario == scenario && $0.direction == "E" }.map(\.text)
    }

    // MARK: - Parity with Paho

    /// The whole `main` scenario: CONNECT with Will and credentials, 5× SUBSCRIBE, insert/status/spot/message/number request
    /// (JSON bytes from `WireJson.toBytes`), outage, the same CONNECT and subscriptions 11–15, another insert, DISCONNECT.
    @Test func mainScenarioIsByteIdenticalToPaho() async throws {
        let broker = try FakeBroker()
        defer { broker.stop() }
        let port = broker.port
        try await onOwnThread {
            let t = Self.transport(port, clientId: "OP1", username: "op1user", password: "secret")
            t.setOfflineStatus(StationStatusWire.offline("OP1"))
            try t.connect()
            try t.publishInsert(Self.command("OP1", "u-1", "2026-10-01T12:34:56.123Z"))
            try t.publishStatus(StationStatusWire(stationId: "OP1", operator: "OK1XOE", stationType: "RUN", band: "B20",
                                                  mode: "CW", freqHz: 14_025_000, runMode: "RUN", qsoCount: 3,
                                                  transmitting: false, online: true,
                                                  timestampUtc: "2026-10-01T12:35:00Z", entryCall: ""))
            try t.publishSpot(SpotWire(stationId: "OP1", spotter: "OK1XOE", freqHz: 14_025_000, dxCall: "DL1AAA", comment: "cq"))
            try t.publishMessage(NetMessageWire(type: "CHAT", id: "id1", fromStation: "OP1", fromOperator: "OK1XOE",
                                                toStation: "", text: "hi", call: "", freqHz: 0, mode: "",
                                                timestampUtc: "2026-10-01T12:35:00Z"))
            try t.requestSerial(SerialRequest(stationId: "OP1", requestId: "r1"))
            try waitUntil("number request") { Self.ours(broker, 0).count == 11 }
            broker.drop(connection: 0)
            try waitUntil("subscriptions after reconnect") { Self.ours(broker, 1).count == 6 }
            try t.publishInsert(Self.command("OP1", "u-3", "2026-10-01T12:41:00Z"))
            t.close()
            try waitUntil("DISCONNECT") { Self.ours(broker, 1).count == 8 }
        }
        let paho: [[[UInt8]]] = try Self.pahoConnections("main")
        #expect(paho.count == 2)
        #expect(Self.ours(broker, 0) == paho[0])
        #expect(Self.ours(broker, 1) == paho[1])
    }

    /// The `lost-puback` scenario (measured with the Java probe): a pending `publishInsert` during an outage
    /// throws "Nelze publikovat na qso/cmd/insert" with cause 32109, a publish during the outage 32104 (the number is not
    /// consumed), after reconnect CONNECT → DUP → SUBSCRIBE byte for byte like Paho.
    @Test func lostPubackScenarioMatchesPaho() async throws {
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
        let texts: [String] = try await onOwnThread {
            let t = Self.transport(port, clientId: "OPL")
            try t.connect()
            let thrown = MqttRecorder<String>()
            let publisher = Thread {
                if let error = Self.failure({ try t.publishInsert(Self.command("OPL", "u-lp", "2026-10-01T13:00:00Z")) }) as? SyncTransportError {
                    thrown.add("publish threw: \(error.message) | \(error.cause ?? "null")")
                }
            }
            publisher.start()
            try waitUntil("PUBLISH at the broker") { Self.ours(broker, 0).count == 7 }
            broker.drop(connection: 0)
            try waitUntil("error for the pending call") { !thrown.all.isEmpty }
            try waitUntil("second connection") { broker.connectionCount == 2 && !broker.packets(connection: 1).isEmpty }
            if let error = Self.failure({ try t.publishInsert(Self.command("OPL", "u-lp2", "2026-10-01T13:00:01Z")) }) as? SyncTransportError {
                thrown.add("outage publish threw: \(error.message) | \(error.cause ?? "null")")
            }
            gate.signal()
            try waitUntil("subscriptions after reconnect") { Self.ours(broker, 1).count == 7 }
            t.close()
            return thrown.all
        }
        let javaEvents: [String] = try Self.events("lost-puback").filter { $0.contains("threw") }
        #expect(texts == javaEvents)
        let paho: [[[UInt8]]] = try Self.pahoConnections("lost-puback")
        #expect(paho.count == 2)
        #expect(Self.ours(broker, 0) == paho[0])
        // Second connection: CONNECT, DUP, 5× SUBSCRIBE (the DISCONNECT from `close` is in the transcript only after the wait).
        #expect(Self.ours(broker, 1).prefix(7) == paho[1].prefix(7))
        #expect(paho[1].count == 8 && paho[1][7] == [0xE0, 0x02, 0x00, 0x00])
    }

    /// A lost PUBACK = double delivery of the command; the authority assigns two versions and the station ends up with one QSO
    /// at version 2 (idempotence by `uuid` + LWW by `version`).
    @Test func duplicateDeliveryAfterLostPubackIsIdempotent() async throws {
        let repo = try LogbookRepository.inMemory()
        defer { repo.close() }
        let logbook = LogbookService(repository: repo)
        logbook.activeContestId = "test-contest"
        let broker = try FakeBroker()
        defer { broker.stop() }
        broker.onPublish { _, connection in connection == 0 ? .swallow : .ack(0) }
        let versions = Counter()
        broker.onPacket { broker, connection, packet in
            guard case .publish(let p) = packet, p.topic == Topics.cmdInsert else { return }
            guard let command = try? WireJson.fromBytes(p.payload, as: QsoCommand.self) else { return }
            versions.increment()
            let state = QsoState(uuid: command.uuid, stationId: command.stationId, version: Int64(versions.value),
                                 updatedAtUtc: command.qso?.timestampUtc, deleted: false, qso: command.qso)
            let out = MqttPublish(topic: Topics.state(command.uuid), packetId: UInt16(200 + versions.value), qos: 1,
                                  retain: true, payload: WireJson.toBytes(state))
            broker.send(.publish(out), connection: connection)
        }
        let port = broker.port
        let changes = Counter()
        let t = Self.transport(port, clientId: "OP2")
        let coordinator = SyncCoordinator(logbook: logbook, transport: t, stationId: "OP2", onChange: { changes.increment() })
        try await onOwnThread {
            try coordinator.start()
            let publisher = Thread { _ = try? t.publishInsert(Self.command("OP1", "u-dup", "2026-10-01T13:00:00Z")) }
            publisher.start()
            try waitUntil("first state") { changes.value == 1 }
            broker.drop(connection: 0)
            try waitUntil("second state after DUP") { changes.value == 2 }
            coordinator.close()
        }
        let all: [Qso] = try logbook.findAll()
        #expect(all.count == 1)
        #expect(all.first?.uuid == "u-dup")
        #expect(all.first?.version == 2)
        #expect(versions.value == 2)
    }

    // MARK: - Delivery

    /// Routing by topic, empty payload ignored, unreadable JSON and a listener exception swallowed (the PUBACK
    /// still goes out, the remaining listeners of the same message are not called), root `null` = `nil` to listeners.
    @Test func routesMessagesAndSwallowsErrors() async throws {
        let broker = try FakeBroker()
        defer { broker.stop() }
        let stateBytes: [UInt8] = WireJson.toBytes(QsoState(uuid: "u-1", stationId: "OP9", version: 4, updatedAtUtc: nil,
                                                            deleted: false, qso: nil))
        let statusBad: [UInt8] = WireJson.toBytes(StationStatusWire.offline("BAD"))
        let statusOk: [UInt8] = WireJson.toBytes(StationStatusWire.offline("OP9"))
        let spot: [UInt8] = WireJson.toBytes(SpotWire(stationId: "OP9", spotter: "S", freqHz: 7_000_000, dxCall: "DX1", comment: nil))
        let reply: [UInt8] = WireJson.toBytes(SerialReply(stationId: "OPR", requestId: "r", serial: 12))
        let script: [(String, [UInt8])] = [
            (Topics.spots, spot), ("serial/reply/OPR", reply), (Topics.messages, Array("null".utf8)),
            ("station/status/BAD", statusBad), ("station/status/OP9", statusOk), ("qso/state/u-1", stateBytes),
            ("qso/state/u-2", []), ("qso/state/u-3", Array("not json".utf8)), ("qso/state/u-4", Array("null".utf8)),
            ("qso/other", stateBytes), ("qso/state/u-1", stateBytes),
        ]
        broker.onPacket { broker, connection, packet in
            guard case .subscribe(let s) = packet, s.subscriptions.first?.topicFilter == "serial/reply/OPR" else { return }
            for (index, item) in script.enumerated() {
                let message = MqttPublish(topic: item.0, packetId: UInt16(100 + index), qos: 1, retain: false, payload: item.1)
                broker.send(.publish(message), connection: connection)
            }
        }
        let port = broker.port
        let seen = MqttRecorder<String>()
        try await onOwnThread {
            let t = Self.transport(port, clientId: "OPR")
            t.subscribeSpots { seen.add("spot \($0?.dxCall ?? "nil")") }
            t.subscribeSerialReplies { seen.add("serial \($0?.serial ?? -1)") }
            t.subscribeMessages { seen.add("msg \($0?.text ?? "nil")") }
            try t.subscribeStatus { status in
                if status?.stationId == "BAD" {
                    throw SyncNullStateError()
                }
                seen.add("status1 \(status?.stationId ?? "nil")")
            }
            try t.subscribeStatus { seen.add("status2 \($0?.stationId ?? "nil")") }
            try t.subscribeState { seen.add("state \($0?.uuid ?? "nil") v\($0?.version ?? -1)") }
            try t.connect()
            try waitUntil("PUBACK for all") { broker.received.contains { $0.packet == .puback(MqttPuback(packetId: 110)) } }
            t.close()
        }
        #expect(seen.all == [
            "spot DX1", "serial 12", "msg nil", "status1 OP9", "status2 OP9", "state u-1 v4", "state nil v-1",
            "state u-1 v4",
        ])
        let acked: [UInt16] = broker.received.compactMap { if case .puback(let a) = $0.packet { a.packetId } else { nil } }
        #expect(acked == Array(100...110))
    }

    // MARK: - Errors and lifecycle

    @Test func errorTextsMatchJava() async throws {
        let port = FreeLoopbackPort.take()
        let (connectError, insert, spotOk, message, serial):
            (SyncTransportError?, SyncTransportError?, Bool, SyncTransportError?, SyncTransportError?) = await onOwnThread {
            let t = Self.transport(port, clientId: "OPE")
            let connectError = Self.failure { try t.connect() } as? SyncTransportError
            t.close()
            let fresh = Self.transport(port, clientId: "OPE")
            let insert = Self.failure { try fresh.publishInsert(Self.command("OPE", "u", "2026-10-01T13:00:00Z")) } as? SyncTransportError
            let spotOk: Bool = Self.failure {
                try fresh.publishSpot(SpotWire(stationId: "OPE", spotter: "S", freqHz: 1, dxCall: "D", comment: nil))
                try fresh.publishStatus(StationStatusWire.offline("OPE"))
            } == nil
            let message = Self.failure {
                try fresh.publishMessage(NetMessageWire(type: "CHAT", id: "i", fromStation: "OPE", fromOperator: "",
                                                        toStation: "", text: "x", call: "", freqHz: 0, mode: "",
                                                        timestampUtc: nil))
            } as? SyncTransportError
            let serial = Self.failure { try fresh.requestSerial(SerialRequest(stationId: "OPE", requestId: "r")) } as? SyncTransportError
            return (connectError, insert, spotOk, message, serial)
        }
        #expect(connectError == SyncTransportError(
            "Nelze se připojit k MQTT brokeru tcp://127.0.0.1:\(port)",
            cause: "Unable to connect to server (32103) - java.net.ConnectException: Connection refused"))
        #expect(insert == SyncTransportError("Nelze publikovat na qso/cmd/insert", cause: "Client is not connected (32104)"))
        #expect(spotOk)
        #expect(message == SyncTransportError("Nepřipojeno k brokeru"))
        #expect(serial == SyncTransportError("Nepřipojeno k brokeru"))
    }

    /// A client ID that Paho cannot encode (a tab from `stationId`) flies out of `connect` as a Java
    /// `IllegalArgumentException` — not as `SyncTransportError`.
    @Test func clientIdThatPahoRejectsEscapesConnect() async throws {
        let error: (any Error)? = await onOwnThread { () -> (any Error)? in
            let t = Self.transport(1, clientId: "OP\t1")
            return Self.failure { try t.connect() }
        }
        #expect(error as? JavaIllegalArgumentError == JavaIllegalArgumentError(message: "Invalid UTF-8 char: [0009]"))
    }

    /// `WireJson.toBytes` on the wire (astral character as an escaped pair), `close` sends DISCONNECT and clears
    /// the listeners (breaks the coordinator ↔ transport cycle).
    @Test func closeClearsListenersAndPayloadUsesToBytes() async throws {
        let broker = try FakeBroker()
        defer { broker.stop() }
        let port = broker.port
        let t = Self.transport(port, clientId: "OPC")
        let (before, after): (Int, Int) = try await onOwnThread {
            t.subscribeSpots { _ in }
            try t.subscribeState { _ in }
            try t.connect()
            try t.publishMessage(NetMessageWire(type: "CHAT", id: "i", fromStation: "OPC", fromOperator: "",
                                                toStation: "", text: "\u{1F600}", call: "", freqHz: 0, mode: "",
                                                timestampUtc: nil))
            let before: Int = t.listenerCount
            t.close()
            try waitUntil("DISCONNECT") { broker.received.contains { $0.bytes == [0xE0, 0x02, 0x00, 0x00] } }
            return (before, t.listenerCount)
        }
        #expect(before == 2)
        #expect(after == 0)
        #expect(!t.isConnected)
        let payload: [UInt8]? = broker.received.compactMap { if case .publish(let p) = $0.packet { p.payload } else { nil } }.first
        let text = String(decoding: payload ?? [], as: UTF8.self)
        #expect(text.contains("\"text\":\"\\uD83D\\uDE00\""))
    }

    // MARK: - Regression pins

    /// A name with a tab: Paho encodes it only on the sending thread → 32109 with `IllegalArgumentException`
    /// (Java transcript, scenario `cred-tab`; the proxy port differs in the text).
    @Test func usernameThatPahoCannotEncodeMatchesJava() async throws {
        let broker = try FakeBroker()
        defer { broker.stop() }
        let port = broker.port
        let error: (any Error)? = await onOwnThread { () -> (any Error)? in
            let t = Self.transport(port, clientId: "OPT", username: "op\tuser", password: "x")
            defer { t.close() }
            return Self.failure { try t.connect() }
        }
        let sync = try #require(error as? SyncTransportError)
        let ours = "connect threw: \(sync.message) | \(sync.cause ?? "null")"
        let java: String = try #require(try Self.events("cred-tab").first)
        let normalized: String = java.replacingOccurrences(of: #"127\.0\.0\.1:\d+"#, with: "127.0.0.1:\(port)",
                                                           options: .regularExpression)
        #expect(ours == normalized)
    }

    /// Session takeover (scenario `takeover`): a pending `publishInsert` throws with cause `… Disconnect RC: 142 (32204)`.
    @Test func sessionTakeoverMatchesJava() async throws {
        let broker = try FakeBroker()
        defer { broker.stop() }
        broker.onPublish { _, _ in .swallow }
        broker.onConnect { index in index == 0 ? .accept(FakeBroker.ok) : .silent }
        let port = broker.port
        let text: String? = try await onOwnThread {
            let t = Self.transport(port, clientId: "OPK")
            try t.connect()
            let thrown = MqttRecorder<String>()
            let publisher = Thread {
                if let error = Self.failure({ try t.publishInsert(Self.command("OPK", "u-tk", "2026-10-01T13:10:00Z")) }) as? SyncTransportError {
                    thrown.add("publish threw: \(error.message) | \(error.cause ?? "null")")
                }
            }
            publisher.start()
            try waitUntil("PUBLISH at the broker") { Self.ours(broker, 0).count == 7 }
            broker.send(.disconnect(MqttDisconnect(reasonCode: 0x8E)), connection: 0)
            try waitUntil("error for the pending call") { !thrown.all.isEmpty }
            t.close()
            return thrown.all.first
        }
        let java: [String] = try Self.events("takeover").filter { $0.hasPrefix("publish threw") }
        #expect(text.map { [$0] } == java)
    }

    /// `close()` from a listener (delivery thread): no freeze, DISCONNECT goes out, listeners cleared.
    @Test func closeFromListenerCallback() async throws {
        let broker = try FakeBroker()
        defer { broker.stop() }
        broker.onPacket { broker, connection, packet in
            guard case .subscribe(let s) = packet, s.subscriptions.first?.topicFilter == "serial/reply/OPZ" else { return }
            let bytes: [UInt8] = WireJson.toBytes(SpotWire(stationId: "X", spotter: "S", freqHz: 1, dxCall: "D", comment: nil))
            broker.send(.publish(MqttPublish(topic: Topics.spots, packetId: nil, qos: 0, retain: false, payload: bytes)), connection: connection)
        }
        let port = broker.port
        let t = Self.transport(port, clientId: "OPZ")
        let closed = Counter()
        t.subscribeSpots { _ in
            t.close()
            closed.increment()
        }
        try await onOwnThread {
            try t.connect()
            try waitUntil("close from the listener") { closed.value == 1 }
            try waitUntil("DISCONNECT") { broker.received.contains { $0.bytes == [0xE0, 0x02, 0x00, 0x00] } }
        }
        #expect(t.listenerCount == 0)
        #expect(!t.isConnected)
    }
}
