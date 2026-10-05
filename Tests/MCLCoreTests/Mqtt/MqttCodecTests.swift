import Testing
@testable import MCLCore

/// The MQTT 5 codec at the edges of the data types (§1.5) and broken packets: it never crashes, always `MqttCodecError`.
@Suite struct MqttCodecTests {

    static func hex(_ text: String) -> [UInt8] {
        var out: [UInt8] = []
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(index, offsetBy: 2)
            out.append(UInt8(text[index..<next], radix: 16) ?? 0)
            index = next
        }
        return out
    }

    static func decodeError(_ bytes: [UInt8]) -> MqttCodecError? {
        do {
            _ = try MqttPacket.decode(bytes)
            return nil
        } catch {
            return error
        }
    }

    // MARK: - Variable Byte Integer

    @Test(arguments: [
        (0, "00"), (127, "7f"), (128, "8001"), (16_383, "ff7f"), (16_384, "808001"),
        (2_097_151, "ffff7f"), (2_097_152, "80808001"), (268_435_455, "ffffff7f"),
    ])
    func varIntBoundaries(value: Int, encoded: String) throws {
        #expect(try MqttVarInt.encode(value) == Self.hex(encoded))
        let bytes: [UInt8] = Self.hex(encoded)
        let decoded = try #require(try MqttVarInt.decode(bytes[...], at: 0))
        #expect(decoded.value == value)
        #expect(decoded.count == bytes.count)
    }

    @Test func varIntOutOfRange() {
        #expect(throws: MqttCodecError.variableByteIntegerOutOfRange(268_435_456)) { try MqttVarInt.encode(268_435_456) }
        #expect(throws: MqttCodecError.variableByteIntegerOutOfRange(-1)) { try MqttVarInt.encode(-1) }
    }

    @Test func varIntFifthByteIsMalformed() {
        let bytes: [UInt8] = [0xFF, 0xFF, 0xFF, 0xFF, 0x01]
        #expect(throws: MqttCodecError.variableByteIntegerTooLong) { try MqttVarInt.decode(bytes[...], at: 0) }
        // As the remaining packet length.
        #expect(Self.decodeError([0x30, 0xFF, 0xFF, 0xFF, 0xFF, 0x01]) == .variableByteIntegerTooLong)
    }

    @Test func varIntIncompleteAndNonMinimal() throws {
        let partial: [UInt8] = [0x80, 0x80]
        #expect(try MqttVarInt.decode(partial[...], at: 0) == nil)
        // It accepts a redundant form (like Paho).
        let padded: [UInt8] = [0x80, 0x00]
        let decoded = try #require(try MqttVarInt.decode(padded[...], at: 0))
        #expect(decoded.value == 0 && decoded.count == 2)
    }

    // MARK: - UTF-8 and binary data

    static func publishWithTopic(_ topic: [UInt8]) -> [UInt8] {
        var body: [UInt8] = [0x00, UInt8(topic.count)]
        body += topic
        body.append(0x00)
        return [0x30, UInt8(body.count)] + body
    }

    /// Paho `decodeUTF8` = `new String(bytes, UTF_8)`: invalid UTF-8 is replaced with U+FFFD (per the JDK rules)
    /// and accepted. Values measured on Paho 1.2.5 (generator `mqtt.UTF8`).
    @Test(arguments: [
        ("c328", "\u{FFFD}("), ("eda080", "\u{FFFD}"), ("c080", "\u{FFFD}\u{FFFD}"),
        ("f8888080", "\u{FFFD}\u{FFFD}\u{FFFD}\u{FFFD}"), ("ff", "\u{FFFD}"), ("e282", "\u{FFFD}"),
    ])
    func malformedUtf8InTopicBecomesReplacement(utf8: String, topic: String) throws {
        let decoded = try MqttPacket.decode(Self.publishWithTopic(Self.hex(utf8)))
        guard case .publish(let p) = decoded else {
            Issue.record("expected PUBLISH")
            return
        }
        #expect(p.topic == topic)
    }

    /// Paho `validateUTF8String` rejects control characters (even U+0000) and noncharacters on both read and write.
    @Test(arguments: [
        ("00", UInt16(0x0000)), ("09", UInt16(0x0009)), ("1f", UInt16(0x001F)), ("7f", UInt16(0x007F)),
        ("c285", UInt16(0x0085)), ("c29f", UInt16(0x009F)), ("efb790", UInt16(0xFDD0)), ("efbfbe", UInt16(0xFFFE)),
        ("efbfbf", UInt16(0xFFFF)), ("f09fbfbe", UInt16(0xD83F)), ("f48fbfbf", UInt16(0xDBFF)),
    ])
    func pahoRejectsControlsAndNoncharacters(utf8: String, unit: UInt16) {
        #expect(Self.decodeError(Self.publishWithTopic(Self.hex(utf8))) == .invalidCharacter(unit))
        let text = String(decoding: Self.hex(utf8), as: UTF8.self)
        #expect(throws: MqttCodecError.invalidCharacter(unit)) {
            try MqttPacket.publish(MqttPublish(topic: "a" + text, packetId: nil, qos: 0, retain: false, payload: [])).encode()
        }
    }

    @Test(arguments: ["20", "7e", "c2a0", "efb78f", "efb7a0", "efbfbd", "f09f9880", "f0908080"])
    func pahoAcceptsOtherCharacters(utf8: String) throws {
        let text = String(decoding: Self.hex(utf8), as: UTF8.self)
        let p = MqttPublish(topic: text, packetId: nil, qos: 0, retain: false, payload: [])
        #expect(try MqttPacket.decode(MqttPacket.publish(p).encode()) == .publish(p))
    }

    @Test func multiByteUtf8RoundTrip() throws {
        let p = MqttPublish(topic: "stanice/Žluťoučký 😀", packetId: 7, qos: 1, retain: true, payload: Array("ďábel".utf8))
        let bytes: [UInt8] = try MqttPacket.publish(p).encode()
        #expect(try MqttPacket.decode(bytes) == .publish(p))
    }

    @Test func stringLengthPrefixBeyondPacket() {
        #expect(Self.decodeError(Self.hex("3003000561")) == .truncated)
    }

    @Test func fieldTooLongOnEncode() {
        let topic = String(repeating: "a", count: 65_536)
        #expect(throws: MqttCodecError.fieldTooLong(65_536)) {
            try MqttPacket.publish(MqttPublish(topic: topic, packetId: nil, qos: 0, retain: false, payload: [])).encode()
        }
    }

    // MARK: - Properties

    @Test func everyPropertyTypeRoundTrips() throws {
        let props = MqttProperties([
            MqttProperty(0x01, .byte(1)),
            MqttProperty(0x02, .u32(3_600)),
            MqttProperty(0x03, .string("application/json")),
            MqttProperty(0x09, .binary([0, 1, 255])),
            MqttProperty(0x0B, .varInt(268_435_455)),
            MqttProperty(0x23, .u16(10)),
            MqttProperty(0x26, .pair("k", "v")),
            MqttProperty(0x26, .pair("k", "w")),
        ])
        let p = MqttPublish(topic: "t", packetId: 1, qos: 1, retain: false, properties: props, payload: [1])
        #expect(try MqttPacket.decode(MqttPacket.publish(p).encode()) == .publish(p))
    }

    @Test func unknownPropertyIdentifier() {
        // CONNACK with property 0x7F.
        #expect(Self.decodeError(Self.hex("20050000027f00")) == .unknownProperty(0x7F))
        #expect(throws: MqttCodecError.unknownProperty(0x05)) {
            try MqttPacket.connack(MqttConnack(sessionPresent: false, reasonCode: 0, properties: MqttProperties([MqttProperty(0x05, .byte(0))]))).encode()
        }
    }

    @Test func duplicatePropertyRejectedLikePaho() throws {
        // CONNACK with two Receive Maximum.
        #expect(Self.decodeError(Self.hex("2009000006210014210014")) == .duplicateProperty(0x21))
        // User Property and Subscription Identifier may repeat.
        let repeated = MqttProperties([
            MqttProperty(0x0B, .varInt(1)), MqttProperty(0x0B, .varInt(2)),
            MqttProperty(0x26, .pair("a", "b")), MqttProperty(0x26, .pair("a", "b")),
        ])
        let p = MqttPublish(topic: "t", packetId: nil, qos: 0, retain: false, properties: repeated, payload: [])
        #expect(try MqttPacket.decode(MqttPacket.publish(p).encode()) == .publish(p))
    }

    @Test func propertyTypeMustMatchIdentifier() {
        let wrong = MqttProperties([MqttProperty(0x11, .u16(1))])
        #expect(throws: MqttCodecError.unknownProperty(0x11)) {
            try MqttPacket.connack(MqttConnack(sessionPresent: false, reasonCode: 0, properties: wrong)).encode()
        }
    }

    @Test func propertyLengthErrors() {
        // The properties length is 10, the packet has only 3 bytes after it.
        #expect(Self.decodeError(Self.hex("200600000a210014"))
            == .propertyLengthMismatch)
        // Length 2, but Receive Maximum needs 3 bytes.
        #expect(Self.decodeError(Self.hex("2006000002210014"))
            == .propertyLengthMismatch)
    }

    // MARK: - Fixed header and packets

    @Test func fixedHeaderFlags() {
        #expect(Self.decodeError(Self.hex("800700010000016100")) == .invalidFixedHeaderFlags(type: 8, flags: 0))
        #expect(Self.decodeError(Self.hex("2103000000")) == .invalidFixedHeaderFlags(type: 2, flags: 1))
        #expect(Self.decodeError(Self.hex("c100")) == .invalidFixedHeaderFlags(type: 12, flags: 1))
        #expect(Self.decodeError(Self.hex("36050001610000")) == .invalidQos(3))
        #expect(Self.decodeError(Self.hex("380400016100")) == .dupWithQos0)
        #expect(Self.decodeError(Self.hex("0000")) == .reservedPacketType)
        #expect(Self.decodeError(Self.hex("5002000a")) == .unsupportedPacketType(5))
        #expect(Self.decodeError(Self.hex("f000")) == .unsupportedPacketType(15))
    }

    @Test func lengthAndTrailingErrors() {
        #expect(Self.decodeError([]) == .truncated)
        #expect(Self.decodeError([0x30]) == .truncated)
        #expect(Self.decodeError(Self.hex("400300")) == .remainingLengthMismatch(declared: 3, actual: 1))
        #expect(Self.decodeError(Self.hex("c00100")) == .trailingBytes(1))
        #expect(Self.decodeError(Self.hex("40020000")) == .zeroPacketIdentifier)
        #expect(Self.decodeError(Self.hex("32050001610000")) == .zeroPacketIdentifier)
        #expect(Self.decodeError(Self.hex("9003000100")) == .emptyPayload)
        #expect(Self.decodeError(Self.hex("8203000100")) == .emptyPayload)
    }

    @Test func pubackBothForms() throws {
        #expect(try MqttPacket.decode(Self.hex("40020007")) == .puback(MqttPuback(packetId: 7)))
        #expect(try MqttPacket.decode(Self.hex("4003000610")) == .puback(MqttPuback(packetId: 6, reasonCode: 0x10)))
        let withReason = MqttPuback(packetId: 9, reasonCode: 0x87, properties: MqttProperties([MqttProperty(0x1F, .string("acl"))]))
        #expect(try MqttPacket.decode(MqttPacket.puback(withReason).encode()) == .puback(withReason))
        #expect(try MqttPacket.puback(MqttPuback(packetId: 2)).encode() == Self.hex("40020002"))
        #expect(try MqttPacket.puback(MqttPuback(packetId: 6, reasonCode: 0x10)).encode() == Self.hex("4003000610"))
    }

    @Test func disconnectForms() throws {
        #expect(try MqttPacket.disconnect(MqttDisconnect()).encode() == Self.hex("e0020000"))
        #expect(try MqttPacket.decode(Self.hex("e000")) == .disconnect(MqttDisconnect()))
        #expect(try MqttPacket.decode(Self.hex("e0018e")) == .disconnect(MqttDisconnect(reasonCode: 0x8E)))
        #expect(try MqttPacket.pingreq.encode() == Self.hex("c000"))
        #expect(try MqttPacket.decode(Self.hex("d000")) == .pingresp)
    }

    @Test func connackSessionPresentAndReservedBits() throws {
        #expect(try MqttPacket.decode(Self.hex("2003010000")) == .connack(MqttConnack(sessionPresent: true, reasonCode: 0)))
        #expect(Self.decodeError(Self.hex("2003020000")) == .reservedFlagSet)
        #expect(try MqttPacket.decode(Self.hex("2003008700")) == .connack(MqttConnack(sessionPresent: false, reasonCode: 0x87)))
    }

    @Test func subscribeOptionsValidation() {
        #expect(Self.decodeError(Self.hex("820700010000016103")) == .invalidQos(3))
        #expect(Self.decodeError(Self.hex("820700010000016130")) == .invalidSubscriptionOptions(0x30))
        #expect(Self.decodeError(Self.hex("820700010000016140")) == .invalidSubscriptionOptions(0x40))
        let ok = MqttSubscription(topicFilter: "a", qos: 1, noLocal: true, retainAsPublished: true, retainHandling: 2)
        let packet = MqttPacket.subscribe(MqttSubscribe(packetId: 1, subscriptions: [ok]))
        #expect((try? MqttPacket.decode(packet.encode())) == packet)
    }

    @Test func connectFlagsValidation() {
        // Reserved bit 0 of the CONNECT flags.
        #expect(Self.decodeError(Self.hex("100d00044d51545405010000000000")) == .reservedFlagSet)
        // Will QoS without the Will flag.
        #expect(Self.decodeError(Self.hex("100d00044d51545405080000000000")) == .inconsistentConnectFlags)
        // Version 4.
        #expect(Self.decodeError(Self.hex("100d00044d51545404020000000000")) == .unsupportedProtocol)
    }

    // MARK: - Stream and resilience

    @Test func frameReaderAcrossChunks() throws {
        let packets: [[UInt8]] = [Self.hex("40020007"), Self.hex("d000"), Self.hex("4003000610")]
        var stream: [UInt8] = []
        for p in packets {
            stream += p
        }
        var reader = MqttFrameReader()
        var frames: [[UInt8]] = []
        for byte in stream {
            reader.append([byte])
            while let frame = try reader.nextFrame() {
                frames.append(frame)
            }
        }
        #expect(frames == packets)
        #expect(reader.pendingCount == 0)
    }

    @Test func frameReaderLimits() {
        var reader = MqttFrameReader(maximumPacketSize: 100)
        reader.append(Self.hex("30ffff03"))
        #expect(throws: MqttCodecError.packetTooLarge(1 + 3 + 65_535)) { try reader.nextFrame() }
        var bad = MqttFrameReader()
        bad.append([0x30, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])
        #expect(throws: MqttCodecError.variableByteIntegerTooLong) { try bad.nextFrame() }
    }

    /// Random mutations of valid packets (byte shifts, truncation, extension) never bring the decoder down —
    /// the result is a packet or `MqttCodecError`. Swift would crash on an out-of-bounds read, so passing = not crashing.
    @Test func randomMutationsNeverCrash() throws {
        var seeds: [[UInt8]] = []
        for line in try MqttPahoTranscript.load() where line.direction != "E" {
            seeds.append(line.bytes)
        }
        var random = JavaRandom(seed: 0xA7)
        var decoded = 0
        var rejected = 0
        for _ in 0..<20_000 {
            var bytes: [UInt8] = seeds[Int(random.nextInt(bound: Int32(seeds.count)))]
            let edits = 1 + Int(random.nextInt(bound: 4))
            for _ in 0..<edits {
                let kind = random.nextInt(bound: 3)
                if kind == 0 && !bytes.isEmpty {
                    bytes[Int(random.nextInt(bound: Int32(bytes.count)))] = UInt8(random.nextInt(bound: 256))
                } else if kind == 1 && !bytes.isEmpty {
                    bytes.removeLast(1 + Int(random.nextInt(bound: Int32(bytes.count))))
                } else {
                    bytes.append(UInt8(random.nextInt(bound: 256)))
                }
            }
            if (try? MqttPacket.decode(bytes)) != nil {
                decoded += 1
            } else {
                rejected += 1
            }
            var reader = MqttFrameReader()
            reader.append(bytes)
            while (try? reader.nextPacket()) != nil {}
        }
        #expect(decoded + rejected == 20_000)
        #expect(rejected > 0)
    }
}
