/// MQTT 5 codec error. Decoding bytes from the network never crashes — every malformed input ends as one of these
/// cases (MQTT 5.0 §1.5, §2, §3: "Malformed Packet"), which the client turns into a connection loss.
public enum MqttCodecError: Error, Equatable, Sendable {
    /// Variable Byte Integer has a fifth byte with continuation (§1.5.5: at most 4 bytes).
    case variableByteIntegerTooLong
    /// Value to encode is outside 0…268 435 455.
    case variableByteIntegerOutOfRange(Int)
    /// The packet (or a field inside it) ends earlier than the field allows.
    case truncated
    /// The remaining length from the fixed header does not match the packet's byte count.
    case remainingLengthMismatch(declared: Int, actual: Int)
    /// Bytes are left over after the packet's last field.
    case trailingBytes(Int)
    /// Packet type 0 (reserved).
    case reservedPacketType
    /// A type the client does not use (QoS 2, UNSUBSCRIBE, AUTH).
    case unsupportedPacketType(UInt8)
    /// Fixed-header flags do not match the type (§2.1.3).
    case invalidFixedHeaderFlags(type: UInt8, flags: UInt8)
    /// QoS 3 (PUBLISH, Will, subscription options).
    case invalidQos(UInt8)
    /// PUBLISH s QoS 0 a DUP = 1 (§3.3.1.1).
    case dupWithQos0
    /// Packet Identifier 0 (§2.2.1).
    case zeroPacketIdentifier
    /// The string contains a character Paho rejects (`validateUTF8String`: a control character including U+0000,
    /// a noncharacter); carries the UTF-16 unit from the Paho message `Invalid UTF-8 char: [%04x]`.
    case invalidCharacter(UInt16)
    /// String or binary data to encode longer than 65 535 bytes.
    case fieldTooLong(Int)
    /// Unknown property identifier (§2.2.2.2).
    case unknownProperty(UInt8)
    /// A property that may occur only once appears twice in the block (Paho `REASON_CODE_DUPLICATE_PROPERTY`).
    case duplicateProperty(UInt8)
    /// The properties length exceeds the packet, or the last property overflows it.
    case propertyLengthMismatch
    /// CONNECT with a protocol name or version other than "MQTT" 5.
    case unsupportedProtocol
    /// Reserved bit in the CONNECT (§3.1.2.3) or CONNACK (§3.2.2.1) flags.
    case reservedFlagSet
    /// Will QoS or Will Retain without the Will flag (inconsistent CONNECT flags, §3.1.2.6–3.1.2.7).
    case inconsistentConnectFlags
    /// SUBSCRIBE without a topic or SUBACK without a reason code (§3.8.3, §3.9.3).
    case emptyPayload
    /// Reserved bits of the subscription options (§3.8.3.1).
    case invalidSubscriptionOptions(UInt8)
    /// The packet is longer than the client's configured maximum.
    case packetTooLarge(Int)
    /// A reason code Paho does not know for the given packet type (`validateReturnCode` →
    /// `REASON_CODE_INVALID_RETURN_CODE` 50001).
    case invalidReasonCode(type: UInt8, code: UInt8)
}
