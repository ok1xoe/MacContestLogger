import Foundation
import Testing
@testable import MCLCore

/// Session state without a socket (MQTT point 5): packet numbers, in-flight with Receive Maximum, DUP after
/// CONNACK, CONNACK properties, keep-alive per Paho `checkForActivity` (including "2× keep-alive without a write"),
/// restore from persistence and reconnect delays.
@Suite struct MqttSessionTests {

    static let second: UInt64 = 1_000_000_000

    static func connack(_ properties: [MqttProperty] = []) -> MqttConnack {
        MqttConnack(sessionPresent: false, reasonCode: 0, properties: MqttProperties(properties))
    }

    @Test func everyPublishConsumesAnIdAndQos1StaysInflight() throws {
        var s = MqttSession(clientId: "OP1", keepAliveSeconds: 45)
        let first: MqttPublish = try s.beginPublish(topic: "a", payload: [1], qos: 1, retain: false)
        let spot: MqttPublish = try s.beginPublish(topic: "spot/new", payload: [2], qos: 0, retain: false)
        let second: MqttPublish = try s.beginPublish(topic: "b", payload: [3], qos: 1, retain: true)
        #expect(first.packetId == 1)
        #expect(spot.packetId == nil)
        #expect(second.packetId == 3)
        #expect(s.inflight.map(\.packetId) == [1, 3])
        let acked: Bool = s.acknowledge(1)
        let orphan: Bool = s.acknowledge(1)
        #expect(acked)
        #expect(!orphan, "orphaned PUBACK")
        #expect(s.inflight.map(\.packetId) == [3])
    }

    @Test func receiveMaximumLimitsInflightQos1Only() throws {
        var s = MqttSession(clientId: "OP1", keepAliveSeconds: 45)
        let maximum = MqttProperty(MqttProperties.Id.receiveMaximum, .u16(2))
        _ = s.connected(Self.connack([maximum]))
        #expect(s.receiveMaximum == 2)
        _ = try s.beginPublish(topic: "a", payload: [], qos: 1, retain: false)
        _ = try s.beginPublish(topic: "a", payload: [], qos: 1, retain: false)
        #expect(throws: MqttClientError(code: 32_202)) {
            _ = try s.beginPublish(topic: "a", payload: [], qos: 1, retain: false)
        }
        _ = try s.beginPublish(topic: "spot/new", payload: [], qos: 0, retain: false)
        #expect(MqttClientError(code: 32_202).description == "Too many publishes in progress (32202)")
        // Without the property back to 65,535 (Paho `MqttConnectionState`).
        _ = s.connected(Self.connack())
        #expect(s.receiveMaximum == 65_535)
    }

    @Test func connackMarksInflightDupInSendOrder() throws {
        var s = MqttSession(clientId: "OP1", keepAliveSeconds: 45)
        _ = try s.beginPublish(topic: "x", payload: [1], qos: 1, retain: false)
        _ = try s.beginPublish(topic: "y", payload: [2], qos: 1, retain: false)
        s.disconnected()
        let resend: [MqttPublish] = s.connected(Self.connack())
        #expect(resend.map(\.topic) == ["x", "y"])
        #expect(resend.map(\.dup) == [true, true])
    }

    @Test func serverKeepAliveAndAssignedClientIdAreAdopted() {
        var s = MqttSession(clientId: "", keepAliveSeconds: 45)
        let props: [MqttProperty] = [
            MqttProperty(MqttProperties.Id.serverKeepAlive, .u16(7)),
            MqttProperty(MqttProperties.Id.assignedClientIdentifier, .string("auto-1")),
        ]
        _ = s.connected(Self.connack(props))
        #expect(s.keepAliveNanos == 7 * Self.second)
        #expect(s.clientId == "auto-1")
        // A new connection again starts with the keep-alive from CONNECT; the Client ID stays assigned (Paho `mqttSession`).
        s.connecting(now: 0)
        #expect(s.keepAliveNanos == 45 * Self.second)
        #expect(s.clientId == "auto-1")
    }

    @Test func restoreContinuesCounterFromHighestPersistedId() throws {
        var s = MqttSession(clientId: "OP1", keepAliveSeconds: 45)
        let persisted: [MqttPublish] = [
            MqttPublish(topic: "qso/cmd/insert", packetId: 9, qos: 1, retain: false, payload: [1]),
            MqttPublish(topic: "qso/cmd/update", packetId: 4, qos: 1, retain: false, payload: [2]),
        ]
        s.restore(persisted)
        #expect(s.inflight.map(\.packetId) == [9, 4])
        #expect(s.inflight.map(\.dup) == [true, true])
        #expect(s.lastPacketId == 9)
        let next: UInt16 = try s.nextPacketId()
        #expect(next == 10)
    }

    @Test func keepAliveFollowsPahoCheckForActivity() {
        let ka: UInt64 = 10 * Self.second
        let delta: UInt64 = MqttSession.delta
        var s = MqttSession(clientId: "OP1", keepAliveSeconds: 10)
        s.connecting(now: 0)
        _ = s.connected(Self.connack())
        // Freshly after a write: wait until the keep-alive.
        #expect(s.checkForActivity(now: 2 * Self.second) == .wait(nanos: ka - 2 * Self.second))
        // `keepAlive − delta` without a write → PINGREQ, the next check after a whole keep-alive.
        #expect(s.checkForActivity(now: ka - delta) == .ping(nextCheckNanos: ka))
        s.noteSent(now: ka - delta, ping: true)
        #expect(s.pingOutstanding == 1)
        // PINGREQ out and nothing came `keepAlive + delta` → 32000.
        let late: UInt64 = ka + delta
        #expect(s.checkForActivity(now: late) == .fail(MqttClientError(code: 32_000)))
        // PINGRESP came in time → waiting again.
        s.noteReceived(now: ka)
        s.pingResponse()
        #expect(s.checkForActivity(now: ka + Self.second) == .wait(nanos: ka - Self.second - delta))
    }

    @Test func twoKeepAlivesWithoutWriteIsWriteTimeout() {
        var s = MqttSession(clientId: "OP1", keepAliveSeconds: 10)
        s.connecting(now: 0)
        s.noteReceived(now: 15 * Self.second)
        // The PINGREQ write got stuck (not finished → `pingOutstanding` 0, `lastOutbound` stands).
        #expect(s.checkForActivity(now: 20 * Self.second) == .fail(MqttClientError(code: 32_002)))
        #expect(MqttClientError(code: 32_002).description == "Timed out while waiting to write messages to the server (32002)")
        let off = MqttSession(clientId: "OP1", keepAliveSeconds: 0)
        #expect(off.checkForActivity(now: 99 * Self.second) == .disabled)
    }

    @Test func reconnectDelaysDoubleFromOneTo128Seconds() {
        var backoff = MqttBackoff()
        var delays: [Int] = []
        for _ in 0..<10 {
            delays.append(backoff.currentMs)
            backoff.failed()
        }
        #expect(delays == [1_000, 2_000, 4_000, 8_000, 16_000, 32_000, 64_000, 128_000, 128_000, 128_000])
        backoff.reset()
        #expect(backoff.currentMs == 1_000)
    }

    @Test func errorTextsArePahoToString() {
        let lost = MqttClientError(code: 32_109, cause: "java.io.EOFException")
        #expect(lost.description == "Connection lost (32109) - java.io.EOFException")
        #expect(MqttClientError.notConnected.description == "Client is not connected (32104)")
        #expect(MqttClientError(code: 0x87).description == "Not authorized. (135)")
        #expect(MqttClientError(code: 0).description == "Untranslated MqttException - RC: 0 (0)")
        let takeover = MqttClientError(code: 32_204, disconnectReasonCode: 142)
        #expect(takeover.description == "The Server Disconnected the client. Disconnect RC: 142 (32204)")
        let reason = MqttClientError(code: 32_204, disconnectReasonCode: 0x98, disconnectReasonString: "admin")
        #expect(reason.message == "The Server Disconnected the client. Disconnect RC: 152 Disconnect Reason: admin")
    }
}

/// Persistence of unacknowledged QoS 1 in an own format.
@Suite struct MqttOutboxTests {

    static func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mcl-outbox-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func messagesSurviveInSendOrderAndAreRemovedAfterPuback() throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let outbox = MqttOutbox(persistenceDir: dir, clientId: "OP/1", serverUri: "tcp://127.0.0.1:1883")
        #expect(outbox.directory.lastPathComponent == "OP%2F1-tcp%3A%2F%2F127%2E0%2E0%2E1%3A1883")
        let a = MqttPublish(topic: "qso/cmd/insert", packetId: 9, qos: 1, retain: false, dup: true, payload: [1, 2])
        let b = MqttPublish(topic: "qso/cmd/delete", packetId: 2, qos: 1, retain: false, payload: [3])
        try outbox.put(a)
        try outbox.put(b)
        let reopened = MqttOutbox(persistenceDir: dir, clientId: "OP/1", serverUri: "tcp://127.0.0.1:1883")
        let loaded: [MqttPublish] = reopened.load()
        #expect(loaded.map(\.packetId) == [9, 2])
        #expect(loaded.map(\.dup) == [false, false])
        #expect(loaded[0].payload == [1, 2])
        reopened.remove(9)
        #expect(MqttOutbox(persistenceDir: dir, clientId: "OP/1", serverUri: "tcp://127.0.0.1:1883").load().map(\.packetId) == [2])
    }

    @Test func pahoFilesAreNeitherReadNorDeleted() throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let paho = dir.appendingPathComponent("OP1-tcp1270011883", isDirectory: true)
        try FileManager.default.createDirectory(at: paho, withIntermediateDirectories: true)
        let pahoFile = paho.appendingPathComponent("s-6.msg")
        try Data([0x32, 0x00]).write(to: pahoFile)
        let outbox = MqttOutbox(persistenceDir: dir, clientId: "OP1", serverUri: "tcp://127.0.0.1:1883")
        #expect(outbox.load().isEmpty)
        try outbox.put(MqttPublish(topic: "t", packetId: 6, qos: 1, retain: false, payload: []))
        outbox.remove(6)
        #expect(FileManager.default.fileExists(atPath: pahoFile.path))
        // An unreadable file in the own directory is skipped and left.
        try FileManager.default.createDirectory(at: outbox.directory, withIntermediateDirectories: true)
        let junk = outbox.directory.appendingPathComponent("0000000000000099-7.publish")
        try Data([0xFF]).write(to: junk)
        #expect(outbox.load().isEmpty)
        #expect(FileManager.default.fileExists(atPath: junk.path))
    }

    /// A corrupt file with a valid name among valid ones: it is skipped (and stays), the others are loaded in order.
    @Test func corruptFileWithValidNameIsSkippedBetweenValidOnes() throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let outbox = MqttOutbox(persistenceDir: dir, clientId: "OPX", serverUri: "tcp://127.0.0.1:1")
        try outbox.put(MqttPublish(topic: "a", packetId: 1, qos: 1, retain: false, payload: [1]))
        let corrupt = outbox.directory.appendingPathComponent("0000000000000002-5.publish")
        try Data([0x32, 0x7F, 0x00]).write(to: corrupt)
        // A valid packet, but QoS 0 (without a number) — persistence does not accept it.
        let qos0: [UInt8] = try MqttPacket.publish(MqttPublish(topic: "q", packetId: nil, qos: 0, retain: false, payload: [])).encode()
        try Data(qos0).write(to: outbox.directory.appendingPathComponent("0000000000000003-6.publish"))
        let reopened = MqttOutbox(persistenceDir: dir, clientId: "OPX", serverUri: "tcp://127.0.0.1:1")
        try reopened.put(MqttPublish(topic: "b", packetId: 9, qos: 1, retain: false, payload: [2]))
        let loaded: [MqttPublish] = MqttOutbox(persistenceDir: dir, clientId: "OPX", serverUri: "tcp://127.0.0.1:1").load()
        #expect(loaded.map(\.topic) == ["a", "b"])
        #expect(FileManager.default.fileExists(atPath: corrupt.path))
    }
}
