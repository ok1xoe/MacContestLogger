import Foundation
import Testing
@testable import MCLCore

/// A port of a local Mosquitto for live tests (`MCL_MQTT_LIVE_PORT`); without the variable the tests are skipped (CI has no
/// Mosquitto). Only 127.0.0.1 and a non-standard port — 1883, 4532 and 4533 are refused.
enum MqttLive {
    static var port: Int? {
        guard let text = ProcessInfo.processInfo.environment["MCL_MQTT_LIVE_PORT"], let port = Int(text) else {
            return nil
        }
        return [1_883, 4_532, 4_533].contains(port) || port <= 0 || port > 65_535 ? nil : port
    }

    static func uniqueId(_ prefix: String) -> String {
        prefix + "-" + String(UUID().uuidString.prefix(8))
    }
}

/// Points (a)–(d) over the resulting client against a live local Mosquitto: (a) CONNECT
/// byte-identical to Paho, (b) retained replay of `qso/state/#`, (c) after the connection is dropped a reconnect with session
/// present 1 and re-subscription, (d) a QoS 1 publish swallowed right before an outage **throws to the waiter**
/// (Paho 32109), after reconnect it goes out with DUP and the observer receives it. Plus keep-alive and `MqttSyncTransport`.
/// Run: `mosquitto -c a maintainer-only probe a
/// `MCL_MQTT_LIVE_PORT=18831 ./scripts/test.sh --filter MqttLive`.
@Suite(.serialized, .ioSafetyNet, .enabled(if: MqttLive.port != nil, "MCL_MQTT_LIVE_PORT not set (local Mosquitto)"))
struct MqttLiveTests {

    static func options(port: Int, connect: MqttConnect, subscriptions: [MqttSubscription]) -> MqttClient.Options {
        MqttClient.Options(endpoint: MqttEndpoint(host: "127.0.0.1", port: port), connect: connect, subscriptions: subscriptions)
    }

    static func plainConnect(_ clientId: String) -> MqttConnect {
        MqttClient.stationConnect(clientId: clientId, username: nil, password: nil, will: nil)
    }

    // (a)
    @Test func connectAndSubscribesAreByteIdenticalToPaho() async throws {
        let broker = try #require(MqttLive.port)
        let proxy = try MqttTestProxy(upstreamPort: broker)
        defer { proxy.stop() }
        let will = MqttWill(
            topic: "station/status/OP1", payload: Array(MqttPahoTranscriptTests.offlineOp1.utf8), qos: 1, retain: true)
        let connect = MqttClient.stationConnect(clientId: "OP1", username: "op1user", password: "secret", will: will)
        let options = Self.options(
            port: proxy.port, connect: connect, subscriptions: MqttClient.stationSubscriptions(clientId: "OP1"))
        try await onOwnThread {
            let client = MqttClient(options: options, onMessage: { _ in })
            try client.connect()
            client.disconnect()
            try waitUntil("DISCONNECT na proxy") { proxy.packets(connection: 0, fromClient: true).last == [0xE0, 0x02, 0x00, 0x00] }
        }
        let ours: [[UInt8]] = proxy.packets(connection: 0, fromClient: true)
        let paho: [[UInt8]] = try MqttPahoTranscript.packets("main", "C")
        let pahoSubscribes: [[UInt8]] = Array(paho.filter { $0.first == 0x82 }.prefix(5))
        #expect(ours.first == paho.first)
        // Only SUBSCRIBE: the rest of the OP1 session from an earlier run may insert PUBACKs of delivered messages between them.
        #expect(ours.filter { $0.first == 0x82 } == pahoSubscribes)
        #expect(ours.last == paho.last)
    }

    // (b)
    @Test func retainedStateReplayedOnSubscribe() async throws {
        let broker = try #require(MqttLive.port)
        let uuid = MqttLive.uniqueId("live")
        let topic = "qso/state/" + uuid
        let payload: [UInt8] = Array(#"{"uuid":"\#(uuid)","version":3,"deleted":false}"#.utf8)
        let seedOptions = Self.options(port: broker, connect: Self.plainConnect(MqttLive.uniqueId("SEED")), subscriptions: [])
        let messages = MqttRecorder<MqttPublish>()
        let subscriberId = MqttLive.uniqueId("OPB")
        let subOptions = Self.options(
            port: broker, connect: Self.plainConnect(subscriberId),
            subscriptions: MqttClient.stationSubscriptions(clientId: subscriberId))
        try await onOwnThread {
            let seed = MqttClient(options: seedOptions, onMessage: { _ in })
            try seed.connect()
            try seed.publish(topic: topic, payload: payload, qos: 1, retain: true)
            let subscriber = MqttClient(options: subOptions, onMessage: { messages.add($0) })
            try subscriber.connect()
            try waitUntil("retained \(topic)") { messages.all.contains { $0.topic == topic } }
            subscriber.disconnect()
            // Cleanup: an empty retained payload deletes the state from the broker.
            try seed.publish(topic: topic, payload: [], qos: 1, retain: true)
            seed.disconnect()
        }
        let replay = try #require(messages.all.first { $0.topic == topic })
        #expect(replay.retain)
        #expect(replay.qos == 1)
        #expect(replay.payload == payload)
    }

    // (c)
    @Test func reconnectsWithSessionPresentAndResubscribes() async throws {
        let broker = try #require(MqttLive.port)
        let proxy = try MqttTestProxy(upstreamPort: broker)
        defer { proxy.stop() }
        let clientId = MqttLive.uniqueId("OPC")
        let options = Self.options(
            port: proxy.port, connect: Self.plainConnect(clientId),
            subscriptions: MqttClient.stationSubscriptions(clientId: clientId))
        let events = MqttRecorder<MqttClient.Event>()
        let reconnectMs: Double = try await onOwnThread {
            let client = MqttClient(options: options, onMessage: { _ in }, onEvent: { events.add($0) })
            try client.connect()
            let dropped = Date()
            proxy.drop()
            try waitUntil("reconnect") { events.all.contains(.connected(sessionPresent: true, reconnect: true)) }
            let elapsed = Date().timeIntervalSince(dropped) * 1_000
            client.disconnect()
            return elapsed
        }
        #expect(events.all.first == .connected(sessionPresent: false, reconnect: false))
        #expect(events.all.contains { if case .connectionLost = $0 { true } else { false } })
        // Paho waits 1 s before the first attempt; the lower bound does not depend on load.
        #expect(reconnectMs >= 900)
        let first: [MqttPacket] = try proxy.packets(connection: 0, fromClient: true).map(MqttPacket.decode)
        let second: [MqttPacket] = try proxy.packets(connection: 1, fromClient: true).map(MqttPacket.decode)
        #expect(first.first == second.first)
        let ack = try MqttPacket.decode(try #require(proxy.packets(connection: 1, fromClient: false).first))
        #expect(ack == .connack(MqttConnack(sessionPresent: true, reasonCode: 0, properties: Self.connackProperties(ack))))
        let resubscribed: [MqttSubscribe] = second.compactMap { if case .subscribe(let s) = $0 { s } else { nil } }
        #expect(resubscribed.map(\.packetId) == [6, 7, 8, 9, 10])
        #expect(resubscribed.flatMap(\.subscriptions) == MqttClient.stationSubscriptions(clientId: clientId))
    }

    static func connackProperties(_ packet: MqttPacket) -> MqttProperties {
        if case .connack(let c) = packet { return c.properties }
        return MqttProperties()
    }

    // (d)
    @Test func inflightQos1ThrowsToWaiterAndIsResentWithDupAfterReconnect() async throws {
        let broker = try #require(MqttLive.port)
        let proxy = try MqttTestProxy(upstreamPort: broker)
        defer { proxy.stop() }
        let topic = "live/" + MqttLive.uniqueId("cmd")
        let payload: [UInt8] = Array(#"{"uuid":"u-dup"}"#.utf8)
        let observed = MqttRecorder<MqttPublish>()
        let observerOptions = Self.options(
            port: broker, connect: Self.plainConnect(MqttLive.uniqueId("OBS")),
            subscriptions: [MqttSubscription(topicFilter: topic, qos: 1)])
        let publisherId = MqttLive.uniqueId("OPD")
        let publisherOptions = Self.options(
            port: proxy.port, connect: Self.plainConnect(publisherId),
            subscriptions: MqttClient.stationSubscriptions(clientId: publisherId))
        let thrown: MqttClientError? = try await onOwnThread {
            let observer = MqttClient(options: observerOptions, onMessage: { observed.add($0) })
            try observer.connect()
            let publisher = MqttClient(options: publisherOptions, onMessage: { _ in })
            try publisher.connect()
            proxy.swallowFromClient = true
            let failure = MqttRecorder<MqttClientError>()
            let thread = Thread {
                do {
                    try publisher.publish(topic: topic, payload: payload, qos: 1, retain: false)
                } catch let error as MqttClientError {
                    failure.add(error)
                } catch {}
            }
            thread.start()
            try waitUntil("swallowed PUBLISH") { proxy.captured.contains { $0.swallowed && $0.bytes.first == 0x32 } }
            proxy.swallowFromClient = false
            proxy.drop()
            try waitUntil("error for the waiter") { !failure.all.isEmpty }
            try waitUntil("delivery to the observer after reconnect") { observed.all.contains { $0.topic == topic } }
            try waitUntil("PUBACK of the resent one") { publisher.sessionSnapshot.inflight.isEmpty }
            publisher.disconnect()
            observer.disconnect()
            return failure.all.first
        }
        #expect(thrown?.code == 32_109)
        let swallowed = try #require(proxy.captured.first { $0.swallowed })
        guard case .publish(let original) = try MqttPacket.decode(swallowed.bytes) else {
            Issue.record("the swallowed packet is not PUBLISH")
            return
        }
        #expect(!original.dup)
        let second: [MqttPacket] = try proxy.packets(connection: 1, fromClient: true).map(MqttPacket.decode)
        // Paho order: CONNECT, right away the resend of unacknowledged (DUP), then subscriptions.
        guard second.count > 1, case .publish(let resent) = second[1] else {
            Issue.record("no resend came after CONNECT: \(second)")
            return
        }
        #expect(resent.dup)
        #expect(resent.packetId == original.packetId)
        #expect(resent.payload == payload)
        #expect(observed.all.filter { $0.topic == topic }.map(\.payload) == [payload])
    }

    @Test func keepAlivePingsAndBrokerAnswers() async throws {
        let broker = try #require(MqttLive.port)
        let proxy = try MqttTestProxy(upstreamPort: broker)
        defer { proxy.stop() }
        var connect = Self.plainConnect(MqttLive.uniqueId("OPK"))
        connect.keepAliveSeconds = 1
        let options = Self.options(port: proxy.port, connect: connect, subscriptions: [])
        try await onOwnThread {
            let client = MqttClient(options: options, onMessage: { _ in })
            try client.connect()
            // Two PINGREQ/PINGRESP cycles on the first connection = keep-alive runs and does not report a false outage.
            try waitUntil("2× PINGREQ and PINGRESP") {
                proxy.packets(connection: 0, fromClient: true).filter { $0 == [0xC0, 0x00] }.count >= 2
                    && proxy.packets(connection: 0, fromClient: false).filter { $0 == [0xD0, 0x00] }.count >= 2
            }
            client.disconnect()
        }
        // No false keep-alive outage (PINGRESP manages to arrive before the next check).
        #expect(proxy.connectionCount == 1, "\(proxy.captured.map { ($0.connection, $0.fromClient, $0.bytes.first ?? 0) })")
    }

    /// `MqttSyncTransport` station ↔ observer via Mosquitto: a message with an astral character (`WireJson.toBytes`
    /// escapes a pair of surrogates) arrives and is read back.
    @Test func syncTransportRoundTripThroughMosquitto() async throws {
        let broker = try #require(MqttLive.port)
        let id = MqttLive.uniqueId("OPS")
        let observerId = MqttLive.uniqueId("OBT")
        let texts = MqttRecorder<String>()
        let text = "ahoj \u{1F600}"
        try await onOwnThread {
            let observer = MqttSyncTransport(host: "127.0.0.1", port: broker, clientId: observerId, username: nil,
                                             password: nil, persistenceDir: nil)
            observer.subscribeMessages { message in
                if let value = message?.text { texts.add(value) }
            }
            try observer.connect()
            let station = MqttSyncTransport(host: "127.0.0.1", port: broker, clientId: id, username: nil,
                                            password: "", persistenceDir: nil)
            try station.connect()
            let message = NetMessageWire(type: NetMessageWire.chat, id: "m1", fromStation: id, fromOperator: "OK1XOE",
                                         toStation: "", text: text, call: "", freqHz: 0, mode: "",
                                         timestampUtc: "2026-10-02T10:00:00Z")
            try station.publishMessage(message)
            try waitUntil("message via Mosquitto") { texts.all.contains(text) }
            station.close()
            observer.close()
        }
        #expect(texts.all.contains(text))
    }
}
