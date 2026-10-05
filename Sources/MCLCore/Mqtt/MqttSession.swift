/// Keep-alive decision (Paho `ClientState.checkForActivity`).
public enum MqttKeepAliveDecision: Equatable, Sendable {
    /// Send nothing; next check in `nanos`.
    case wait(nanos: UInt64)
    /// Send PINGREQ; next check after a whole keep-alive (PINGRESP must arrive by then).
    case ping(nextCheckNanos: UInt64)
    /// The connection is dead (32000 with no answer to PINGREQ, 32002 with no successful write).
    case fail(MqttClientError)
    /// Keep-alive disabled (0 s).
    case disabled
}

/// MQTT 5 client session state without a socket (Paho 1.2.5 `ClientState` + `MqttConnectionState`): packet numbers,
/// unacknowledged outgoing QoS 1 (in-flight) with the Receive Maximum limit, resend with DUP after CONNACK, the properties of
/// CONNACK (Server Keep Alive, Assigned Client Identifier, Receive Maximum) and the keep-alive rules. Times are
/// monotonic nanoseconds (`DispatchTime.uptimeNanoseconds`), so it can be tested without clocks or sockets.
public struct MqttSession: Sendable {

    /// Paho `checkForActivity`: `delta = 100000` ns (0,1 ms).
    static let delta: UInt64 = 100_000

    /// Keep-alive z CONNECT (s).
    public let configuredKeepAliveSeconds: UInt16
    /// Effective connection keep-alive in nanoseconds (Server Keep Alive from CONNACK takes precedence).
    public private(set) var keepAliveNanos: UInt64
    /// The broker's Receive Maximum (65 535 without the property, Paho `MqttConnectionState`).
    public private(set) var receiveMaximum: Int = 65_535
    /// Client ID for the next CONNECT and persistence (an Assigned Client Identifier replaces it, Paho
    /// `mqttSession.setClientId`).
    public private(set) var clientId: String
    /// Unacknowledged QoS 1 in send order (Paho `outboundQoS1`).
    public private(set) var inflight: [MqttPublish] = []
    public private(set) var lastOutbound: UInt64 = 0
    public private(set) var lastInbound: UInt64 = 0
    public private(set) var pingOutstanding = 0
    var ids = MqttPacketIdAllocator()

    public init(clientId: String, keepAliveSeconds: UInt16) {
        self.clientId = clientId
        self.configuredKeepAliveSeconds = keepAliveSeconds
        self.keepAliveNanos = UInt64(keepAliveSeconds) * 1_000_000_000
    }

    /// Last allocated packet number (Paho `nextMsgId`).
    public var lastPacketId: Int { ids.lastAssigned }

    // MARK: - Restoring from persistence (Paho `restoreState`)

    /// Messages from persistence after start: they stay unacknowledged with DUP, their numbers are occupied and the counter continues
    /// from the highest of them (Paho `nextMsgId = highestMsgId`).
    public mutating func restore(_ messages: [MqttPublish]) {
        var highest: Int = ids.lastAssigned
        for message in messages {
            guard let id = message.packetId, message.qos == 1 else { continue }
            guard !inflight.contains(where: { $0.packetId == id }) else { continue }
            var copy = message
            copy.dup = true
            inflight.append(copy)
            ids.markInUse(id)
            highest = max(highest, Int(id))
        }
        let inUse: [UInt16] = inflight.compactMap(\.packetId)
        ids = MqttPacketIdAllocator(last: highest)
        for id in inUse {
            ids.markInUse(id)
        }
    }

    // MARK: - Outgoing PUBLISH

    /// Prepares a PUBLISH (Paho `ClientState.send`): every publication gets a number (even QoS 0, which returns it at once);
    /// QoS 1 is queued among the unacknowledged. A full Receive Maximum window = 32202, exhausted numbers = 32001.
    public mutating func beginPublish(topic: String, payload: [UInt8], qos: UInt8, retain: Bool) throws(MqttClientError) -> MqttPublish {
        if qos > 0 && inflight.count >= receiveMaximum {
            throw MqttClientError(code: MqttClientError.maxInflight)
        }
        guard let id = ids.next() else {
            throw MqttClientError(code: MqttClientError.noMessageIds)
        }
        let message = MqttPublish(topic: topic, packetId: qos > 0 ? id : nil, qos: qos, retain: retain, payload: payload)
        if qos > 0 {
            inflight.append(message)
        } else {
            ids.release(id)
        }
        return message
    }

    /// Returns the prepared publication (encoding or persistence error before sending).
    public mutating func cancelPublish(_ id: UInt16) {
        inflight.removeAll { $0.packetId == id }
        ids.release(id)
    }

    /// PUBACK: removes the message from the unacknowledged and frees the number; `false` = orphan PUBACK (Paho ignores it).
    public mutating func acknowledge(_ id: UInt16) -> Bool {
        guard inflight.contains(where: { $0.packetId == id }) else {
            return false
        }
        inflight.removeAll { $0.packetId == id }
        ids.release(id)
        return true
    }

    // MARK: - SUBSCRIBE

    public mutating func nextPacketId() throws(MqttClientError) -> UInt16 {
        guard let id = ids.next() else {
            throw MqttClientError(code: MqttClientError.noMessageIds)
        }
        return id
    }

    public mutating func releasePacketId(_ id: UInt16) {
        ids.release(id)
    }

    // MARK: - Connection

    /// New connection before CONNACK: keep-alive from configuration, no PINGREQ outstanding, activity time = now.
    public mutating func connecting(now: UInt64) {
        keepAliveNanos = UInt64(configuredKeepAliveSeconds) * 1_000_000_000
        pingOutstanding = 0
        lastInbound = now
        lastOutbound = now
    }

    /// Successful CONNACK (Paho `ConnectActionListener.onSuccess` + `restoreInflightMessages`): takes over Receive
    /// Maximum, Server Keep Alive and Assigned Client Identifier and returns the unacknowledged messages to resend with DUP
    /// (in send order) — the client sends them right after CONNACK, before the subscriptions.
    public mutating func connected(_ ack: MqttConnack) -> [MqttPublish] {
        let maximum: UInt16? = ack.properties.u16(MqttProperties.Id.receiveMaximum)
        receiveMaximum = maximum.map { Int($0) } ?? 65_535
        if let serverKeepAlive = ack.properties.u16(MqttProperties.Id.serverKeepAlive) {
            keepAliveNanos = UInt64(serverKeepAlive) * 1_000_000_000
        }
        if let assigned = ack.properties.string(MqttProperties.Id.assignedClientIdentifier) {
            clientId = assigned
        }
        for index in inflight.indices {
            inflight[index].dup = true
        }
        return inflight
    }

    /// Connection lost (Paho `disconnected`): unacknowledged messages stay (Clean Start 0), the PINGREQ is forgotten.
    public mutating func disconnected() {
        pingOutstanding = 0
    }

    // MARK: - Keep-alive

    /// Write to the wire finished (Paho `notifySent`/`notifySentBytes`); a PINGREQ counts only after the write.
    public mutating func noteSent(now: UInt64, ping: Bool) {
        lastOutbound = now
        if ping {
            pingOutstanding += 1
        }
    }

    /// A packet arrived (Paho `notifyReceivedAck`/`notifyReceivedMsg`).
    public mutating func noteReceived(now: UInt64) {
        lastInbound = now
    }

    public mutating func pingResponse() {
        pingOutstanding = max(0, pingOutstanding - 1)
    }

    /// Paho `checkForActivity` literally: (1) PINGREQ outstanding and nothing arrived for `keepAlive + delta` → 32000;
    /// (2) no PINGREQ outstanding and nothing sent for `2 × keepAlive` → 32002; (3) PINGREQ when nothing arrived for
    /// `keepAlive − delta` (and none is outstanding) or nothing sent for `keepAlive − delta`; otherwise wait until
    /// `keepAlive − (now − last write)`.
    public func checkForActivity(now: UInt64) -> MqttKeepAliveDecision {
        let keepAlive: UInt64 = keepAliveNanos
        guard keepAlive > 0 else {
            return .disabled
        }
        let sinceIn: UInt64 = now &- lastInbound
        let sinceOut: UInt64 = now &- lastOutbound
        if pingOutstanding > 0 && sinceIn >= keepAlive + Self.delta {
            return .fail(MqttClientError(code: MqttClientError.clientTimeout))
        }
        if pingOutstanding == 0 && sinceOut >= 2 * keepAlive {
            return .fail(MqttClientError(code: MqttClientError.writeTimeout))
        }
        let threshold: UInt64 = keepAlive - min(keepAlive, Self.delta)
        let inboundIdle: Bool = pingOutstanding == 0 && sinceIn >= threshold
        if inboundIdle || sinceOut >= threshold {
            return .ping(nextCheckNanos: keepAlive)
        }
        return .wait(nanos: max(1_000_000, keepAlive - sinceOut))
    }
}

/// Paho 1.2.5 automatic reconnect delays (`MqttAsyncClient.reconnectDelay`): first attempt after 1 s, after each
/// failure double, while smaller than `maxReconnectDelay` (128 s) — 1, 2, 4 … 64, 128, 128 … s.
public struct MqttBackoff: Sendable {
    public let initialMs: Int
    public let maximumMs: Int
    public private(set) var currentMs: Int

    public init(initialMs: Int = 1_000, maximumMs: Int = 128_000) {
        self.initialMs = initialMs
        self.maximumMs = maximumMs
        self.currentMs = initialMs
    }

    /// Failed attempt (Paho `MqttReconnectActionListener.onFailure`).
    public mutating func failed() {
        if currentMs < maximumMs {
            currentMs *= 2
        }
    }

    /// Success (Paho `stopReconnectCycle`).
    public mutating func reset() {
        currentMs = initialMs
    }
}
