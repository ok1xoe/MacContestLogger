/// Splits the byte stream from the socket into whole MQTT packets (fixed header + remaining length). An incomplete packet waits
/// for the next `append`; a broken remaining length or a packet above `maximumPacketSize` is an error (the connection is then
/// dropped). It does not allocate bytes ahead by the declared length — only what actually arrived.
public struct MqttFrameReader: Sendable {

    public let maximumPacketSize: Int
    private var buffer: [UInt8] = []
    private var position = 0

    public init(maximumPacketSize: Int = 1 + 4 + MqttVarInt.max) {
        self.maximumPacketSize = maximumPacketSize
    }

    /// Number of bytes in the buffer that are not yet a whole packet.
    public var pendingCount: Int { buffer.count - position }

    public mutating func append(_ bytes: [UInt8]) {
        if position > 0 && position == buffer.count {
            buffer.removeAll(keepingCapacity: true)
            position = 0
        }
        buffer += bytes
    }

    /// Next whole packet (raw bytes), `nil` = still incomplete.
    public mutating func nextFrame() throws(MqttCodecError) -> [UInt8]? {
        guard position < buffer.count else {
            return nil
        }
        let slice: ArraySlice<UInt8> = buffer[position...]
        guard let (length, count) = try MqttVarInt.decode(slice, at: position + 1) else {
            return nil
        }
        let total = 1 + count + length
        guard total <= maximumPacketSize else {
            throw .packetTooLarge(total)
        }
        guard buffer.count - position >= total else {
            return nil
        }
        let frame = Array(buffer[position..<(position + total)])
        position += total
        if position > 65_536 {
            buffer.removeFirst(position)
            position = 0
        }
        return frame
    }

    /// Next whole packet, decoded.
    public mutating func nextPacket() throws(MqttCodecError) -> MqttPacket? {
        guard let frame = try nextFrame() else {
            return nil
        }
        return try MqttPacket.decode(frame)
    }
}
