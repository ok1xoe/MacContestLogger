/// Packet Identifier allocation like Paho 1.2.5 (`ClientState.getNextMessageId`): the next free number after the
/// last one allocated (1…65 535 round and round), skipping occupied ones and continuing across reconnect. Paho allocates a number
/// to every PUBLISH, including QoS 0 (it does not go on the wire and is released at once) — hence in the transcript `0007` (status) is followed by
/// `0009` (message).
///
/// Exhaustion: Paho walks the range at most twice (hits the starting number twice) and then throws `MqttException`
/// 32001 (`REASON_CODE_NO_MESSAGE_IDS_AVAILABLE`); here `next()` returns `nil` after the same number of steps
/// (2 × 65 535). Difference: a Paho that has allocated nothing yet (starting number 0) would search forever with a full table
/// — here it ends in that case too (a deliberate divergence from Java v1.1.1).
struct MqttPacketIdAllocator: Sendable {
    private var last = 0
    private var inUse: Set<UInt16> = []

    /// Next free number (marks it as occupied), or `nil` when all are occupied.
    mutating func next() -> UInt16? {
        let start: Int = last
        var passes = 0
        var steps = 0
        repeat {
            last += 1
            if last > 65_535 {
                last = 1
            }
            steps += 1
            if last == start {
                passes += 1
            }
            if passes == 2 || steps > 2 * 65_535 {
                return nil
            }
        } while inUse.contains(UInt16(last))
        let id = UInt16(last)
        inUse.insert(id)
        return id
    }

    mutating func release(_ id: UInt16) {
        inUse.remove(id)
    }

    /// Occupies a number from outside (state recovery, tests).
    mutating func markInUse(_ id: UInt16) {
        inUse.insert(id)
    }

    /// Last allocated number (Paho `nextMsgId`).
    var lastAssigned: Int { last }

    init(last: Int = 0) {
        self.last = last
    }
}
