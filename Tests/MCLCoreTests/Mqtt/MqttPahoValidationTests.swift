import Testing
@testable import MCLCore

/// Codec checks taken from Paho 1.2.5: reason codes on read
/// (`validateReturnCode`) and exhaustion of packet numbers (`getNextMessageId`). Values measured on Paho
/// (generator `mqtt.RC`, `mqtt.ID`).
@Suite struct MqttPahoValidationTests {

    static func decodeError(_ bytes: [UInt8]) -> MqttCodecError? {
        do {
            _ = try MqttPacket.decode(bytes)
            return nil
        } catch {
            return error
        }
    }

    @Test func pubackReasonCodesAcceptedByPaho() {
        let accepted: [UInt8] = [0x00, 0x10, 0x80, 0x83, 0x87, 0x90, 0x97, 0x99]
        for code in 0...255 {
            let c = UInt8(code)
            let error = Self.decodeError([0x40, 0x03, 0x00, 0x01, c])
            if accepted.contains(c) {
                #expect(error == nil, "PUBACK \(code)")
            } else {
                #expect(error == .invalidReasonCode(type: 4, code: c), "PUBACK \(code)")
            }
        }
    }

    @Test func otherAckReasonCodes() {
        #expect(Self.decodeError([0x20, 0x03, 0x00, 0x86, 0x00]) == nil) // CONNACK Bad user name or password
        #expect(Self.decodeError([0x20, 0x03, 0x00, 0x8B, 0x00]) == .invalidReasonCode(type: 2, code: 0x8B))
        #expect(Self.decodeError([0x90, 0x04, 0x00, 0x01, 0x00, 0x02]) == nil) // SUBACK Granted QoS 2
        #expect(Self.decodeError([0x90, 0x05, 0x00, 0x01, 0x00, 0x01, 0x03]) == .invalidReasonCode(type: 9, code: 0x03))
        #expect(Self.decodeError([0xE0, 0x01, 0x8E]) == nil) // DISCONNECT Session taken over
        #expect(Self.decodeError([0xE0, 0x01, 0x05]) == .invalidReasonCode(type: 14, code: 0x05))
    }

    /// The full table: Paho goes through the range twice and throws 32001; here `nil`, the same number of steps.
    @Test func exhaustedPacketIdsEndWithoutLooping() {
        var ids = MqttPacketIdAllocator(last: 700)
        for id in 1...65_535 {
            ids.markInUse(UInt16(id))
        }
        #expect(ids.next() == nil)
        ids.release(9)
        #expect(ids.next() == 9)
        #expect(ids.next() == nil)
    }

    /// A Paho that has not allocated anything yet (default 0) would search forever with a full table; here it ends.
    @Test func exhaustedFromFreshAllocatorEnds() {
        var ids = MqttPacketIdAllocator()
        for id in 1...65_535 {
            ids.markInUse(UInt16(id))
        }
        #expect(ids.next() == nil)
    }

    /// A free default number is returned by Paho only after a whole round (the first pass through the start does not end).
    @Test func startingIdIsReusedAfterFullPass() {
        var ids = MqttPacketIdAllocator(last: 5)
        for id in 1...65_535 where id != 5 {
            ids.markInUse(UInt16(id))
        }
        #expect(ids.next() == 5)
        #expect(ids.next() == nil)
    }
}
