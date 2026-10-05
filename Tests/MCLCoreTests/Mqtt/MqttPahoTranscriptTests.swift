import Foundation
import Testing
@testable import MCLCore

/// The Paho ↔ Mosquitto transcript (`Fixtures/mqtt-paho-transcript.tsv`, maintainer-only generator):
/// rows `<scenario>\t<C|B|E>\t<hex or event>`; C = Paho client → broker, B = broker → client.
struct MqttPahoTranscript {
    struct Line {
        let scenario: String
        let direction: String
        let text: String
        var bytes: [UInt8] { MqttCodecTests.hex(text) }
    }

    static func load() throws -> [Line] {
        let url = try #require(Bundle.module.url(forResource: "mqtt-paho-transcript", withExtension: "tsv"))
        let content = try String(contentsOf: url, encoding: .utf8)
        var lines: [Line] = []
        for raw in content.split(separator: "\n") {
            let parts = raw.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3 else { continue }
            lines.append(Line(scenario: String(parts[0]), direction: String(parts[1]), text: String(parts[2])))
        }
        return lines
    }

    static func packets(_ scenario: String, _ direction: String) throws -> [[UInt8]] {
        try load().filter { $0.scenario == scenario && $0.direction == direction }.map(\.bytes)
    }
}

/// Byte parity of the codec with Paho (point (a), offline).
@Suite struct MqttPahoTranscriptTests {

    /// `StationStatusWire.offline("OP1")` from Java (Jackson) — the Will payload.
    static let offlineOp1: String = #"{"stationId":"OP1","operator":"","stationType":"","band":"","mode":"","freqHz":0,"#
        + #""runMode":"","qsoCount":0,"transmitting":false,"online":false,"timestampUtc":null,"entryCall":""}"#

    static func decoded(_ bytes: [UInt8]) throws -> MqttPacket {
        try MqttPacket.decode(bytes)
    }

    @Test func everyCapturedPacketRoundTripsByteForByte() throws {
        let lines = try MqttPahoTranscript.load().filter { $0.direction != "E" }
        #expect(lines.count > 80)
        for line in lines {
            let packet: MqttPacket = try Self.decoded(line.bytes)
            #expect(try packet.encode() == line.bytes, "\(line.scenario) \(line.direction) \(line.text)")
        }
    }

    @Test func connectWithWillMatchesPaho() throws {
        let paho: [[UInt8]] = try MqttPahoTranscript.packets("main", "C").filter { $0.first == 0x10 }
        #expect(paho.count == 2)
        let will = MqttWill(topic: "station/status/OP1", payload: Array(Self.offlineOp1.utf8), qos: 1, retain: true)
        let connect = MqttClient.stationConnect(clientId: "OP1", username: "op1user", password: "secret", will: will)
        let ours: [UInt8] = try MqttPacket.connect(connect).encode()
        #expect(ours == paho[0])
        // Reconnect sends the same CONNECT.
        #expect(ours == paho[1])
    }

    @Test(arguments: [("cred-empty", "", ""), ("cred-blank-user", "  ", "x")])
    func connectCredentialsMatchPaho(scenario: String, user: String, password: String) throws {
        let paho = try #require(try MqttPahoTranscript.packets(scenario, "C").first)
        let connect = MqttClient.stationConnect(clientId: "OPX", username: user, password: password, will: nil)
        #expect(try MqttPacket.connect(connect).encode() == paho)
    }

    @Test func subscribesMatchPahoIncludingIdsAcrossReconnect() throws {
        let paho: [[UInt8]] = try MqttPahoTranscript.packets("main", "C").filter { $0.first == 0x82 }
        #expect(paho.count == 10)
        let subscriptions = MqttClient.stationSubscriptions(clientId: "OP1")
        var ours: [[UInt8]] = []
        for firstId in [1, 11] {
            for (offset, subscription) in subscriptions.enumerated() {
                let packet = MqttSubscribe(packetId: UInt16(firstId + offset), subscriptions: [subscription])
                ours.append(try MqttPacket.subscribe(packet).encode())
            }
        }
        #expect(ours == paho)
    }

    /// Packet numbers from the transcript: 5× SUBSCRIBE, insert, status, spot (QoS 0 consumes a number), message, number
    /// request; after reconnect 5× SUBSCRIBE and insert.
    @Test func packetIdsFollowPahoCounter() throws {
        var ids = MqttPacketIdAllocator()
        var sequence: [UInt16] = []
        for _ in 0..<5 {
            let idNext: UInt16? = ids.next()
            let id: UInt16 = try #require(idNext)
            sequence.append(id)
            ids.release(id)
        }
        let qos: [UInt8] = [1, 1, 0, 1, 1]
        for q in qos {
            let idNext: UInt16? = ids.next()
            let id: UInt16 = try #require(idNext)
            if q > 0 {
                sequence.append(id)
            }
            ids.release(id)
        }
        for _ in 0..<6 {
            let idNext: UInt16? = ids.next()
            let id: UInt16 = try #require(idNext)
            sequence.append(id)
            ids.release(id)
        }
        var paho: [UInt16] = []
        for bytes in try MqttPahoTranscript.packets("main", "C") {
            switch try Self.decoded(bytes) {
            case .subscribe(let s):
                paho.append(s.packetId)
            case .publish(let p):
                if let id = p.packetId {
                    paho.append(id)
                }
            default:
                break
            }
        }
        #expect(sequence == paho)
    }

    @Test func inUseIdsAreSkipped() throws {
        var ids = MqttPacketIdAllocator()
        let firstNext: UInt16? = ids.next()
        let first: UInt16 = try #require(firstNext)
        let secondNext: UInt16? = ids.next()
        let second: UInt16 = try #require(secondNext)
        ids.release(second)
        #expect(first == 1 && second == 2)
        #expect(ids.next() == 3)
    }

    /// PUBLISH out: without Topic Alias the bytes are identical to Paho after removing the alias property.
    @Test func outgoingPublishesMatchPahoWithoutTopicAlias() throws {
        var checked = 0
        for bytes in try MqttPahoTranscript.packets("main", "C") {
            guard case .publish(let paho) = try Self.decoded(bytes) else { continue }
            #expect(paho.properties.u16(MqttProperties.Id.topicAlias) != nil)
            let ours = MqttPublish(
                topic: paho.topic, packetId: paho.packetId, qos: paho.qos, retain: paho.retain, payload: paho.payload)
            var expected = paho
            expected.properties = paho.properties.removing(MqttProperties.Id.topicAlias)
            #expect(try MqttPacket.publish(ours).encode() == MqttPacket.publish(expected).encode())
            checked += 1
        }
        #expect(checked == 6)
    }

    @Test func pahoAcksAndDisconnect() throws {
        let client: [[UInt8]] = try MqttPahoTranscript.packets("main", "C")
        let pubacks: [[UInt8]] = client.filter { $0.first == 0x40 }
        #expect(!pubacks.isEmpty)
        for bytes in pubacks {
            guard case .puback(let p) = try Self.decoded(bytes) else {
                Issue.record("PUBACK")
                continue
            }
            #expect(try MqttPacket.puback(MqttPuback(packetId: p.packetId)).encode() == bytes)
        }
        #expect(client.last == (try MqttPacket.disconnect(MqttDisconnect()).encode()))
    }

    @Test func brokerSideOfTranscript() throws {
        let broker: [MqttPacket] = try MqttPahoTranscript.packets("main", "B").map(Self.decoded)
        var connacks: [MqttConnack] = []
        var reasons: Set<UInt8> = []
        var dupWill = false
        var retainedState = 0
        for packet in broker {
            switch packet {
            case .connack(let c):
                connacks.append(c)
            case .puback(let p):
                reasons.insert(p.reasonCode)
            case .publish(let p):
                if p.dup && p.qos == 1 && p.topic == "station/status/OP1" {
                    dupWill = true
                }
                if p.retain && p.topic == "qso/state/u-r1" {
                    retainedState += 1
                }
            default:
                break
            }
        }
        #expect(connacks.map(\.sessionPresent) == [false, true])
        #expect(connacks[0].properties.u16(MqttProperties.Id.receiveMaximum) == 20)
        #expect(connacks[0].properties.u16(MqttProperties.Id.topicAliasMaximum) == 10)
        #expect(connacks[0].properties.u32(MqttProperties.Id.maximumPacketSize) == 2_000_000)
        #expect(reasons == [0x00, 0x10])
        #expect(dupWill)
        #expect(retainedState == 2)
    }
}
