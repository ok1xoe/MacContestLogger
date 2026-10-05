import Foundation

/// MQTT 5 client for cluster sync (custom, dependency-free) with the behaviour of Paho 1.2.5 `MqttClient`,
/// as used by the Java `MqttSyncTransport`:
///
/// - **Threads** (never a shared pool): per connection a reader, a writer (queue like Paho `CommsSender`, PINGREQ at the head)
///   and keep-alive; delivery to listeners on the client's own thread (Paho `CommsCallback`) — a slow listener
///   does not delay PINGRESP or PUBACK and a synchronous QoS 1 `publish` from `onMessage` does not hang. The PUBACK of an incoming QoS 1
///   goes out only after `onMessage` returns; a listener exception is swallowed (Paho "Ignoring Exception thrown from
///   messageArrived").
/// - **`connect`** blocks: transport (`MqttTransportFactory`, POSIX or TLS), CONNECT, CONNACK (its properties
///   are taken over by `MqttSession`), resend of unacknowledged QoS 1 with DUP, then subscriptions one by one with SUBACK
///   (CONNECT → DUP → SUBSCRIBE like Paho `restoreInflightMessages` + `connectComplete`).
/// - **`publish`** blocks; QoS 1 waits for PUBACK. A drop while waiting throws 32109 at the waiter (Paho
///   `resolveOldTokens`), the message stays unacknowledged (and in persistence) and goes out with DUP after reconnect. A disconnected
///   client = 32104.
/// - **Reconnect** after losing an established connection: 1 s × 2 up to 128 s (`MqttBackoff`), identical CONNECT, subscriptions again;
///   messages arriving during subscription recovery (retained replay) are delivered and PUBACKed only after the last SUBACK (Paho
///   restores subscriptions in `connectComplete` on the `CommsCallback` thread).
public final class MqttClient: @unchecked Sendable {

    public struct Options: Sendable {
        public var endpoint: MqttEndpoint
        public var connect: MqttConnect
        /// Each subscription as a separate SUBSCRIBE waiting for SUBACK, also after reconnect (`MqttSyncTransport`).
        public var subscriptions: [MqttSubscription]
        /// Paho `connectionTimeout` 30 s for the TCP/TLS connection; **plus** the same limit for waiting on CONNACK — Paho 1.2.5
        /// waits for CONNACK forever (`MqttClient.connect` → `waitForCompletion(-1)`), Swift throws 32000 after it
        /// (a deliberate divergence from Java v1.1.1: a stuck connection is worse for the operator); 0 = no limit.
        public var connectTimeoutMs = 30_000
        public var automaticReconnect = true
        public var reconnectInitialMs = 1_000
        public var reconnectMaxMs = 128_000
        /// Persistence of unacknowledged QoS 1 (`nil` = in memory only, Paho `MemoryPersistence`).
        public var outbox: MqttOutbox?
        public var transportFactory: MqttTransportFactory = MqttTransports.standard

        public init(endpoint: MqttEndpoint, connect: MqttConnect, subscriptions: [MqttSubscription]) {
            self.endpoint = endpoint
            self.connect = connect
            self.subscriptions = subscriptions
        }
    }

    public enum Event: Equatable, Sendable {
        case connected(sessionPresent: Bool, reconnect: Bool)
        case connectionLost(MqttClientError)
    }

    /// CONNECT as built by `MqttSyncTransport.connect` (Java v1.1.1): Clean Start 0, Session Expiry 86 400,
    /// keep-alive 45 s, username only if non-blank (`isBlank`), password whenever not `nil` (even empty).
    public static func stationConnect(clientId: String, username: String?, password: String?, will: MqttWill?) -> MqttConnect {
        let expiry = MqttProperty(MqttProperties.Id.sessionExpiryInterval, .u32(86_400))
        let user: String? = if let username, !JavaText.isBlank(username) { username } else { nil }
        let pass: [UInt8]? = password.map { Array($0.utf8) }
        return MqttConnect(
            clientId: clientId, cleanStart: false, keepAliveSeconds: 45, properties: MqttProperties([expiry]),
            will: will, username: user, password: pass)
    }

    /// Subscriptions of `MqttSyncTransport.connect` in the Java order and with the Java QoS (spots QoS 0, others 1).
    public static func stationSubscriptions(clientId: String) -> [MqttSubscription] {
        [
            MqttSubscription(topicFilter: Topics.stateWildcard, qos: 1),
            MqttSubscription(topicFilter: Topics.spots, qos: 0),
            MqttSubscription(topicFilter: Topics.statusWildcard, qos: 1),
            MqttSubscription(topicFilter: Topics.messages, qos: 1),
            MqttSubscription(topicFilter: Topics.serialReply(clientId), qos: 1),
        ]
    }

    /// Client ID check like the Paho `MqttAsyncClient` constructor: a character Paho cannot encode, or more than
    /// 65 535 bytes is a Java `IllegalArgumentException` (not `MqttException`) — thrown from `connect` to the caller.
    public static func validateClientId(_ clientId: String) throws(JavaIllegalArgumentError) {
        do {
            try MqttUtf8.validate(clientId)
        } catch {
            throw javaIllegalArgument(error)
        }
        if clientId.utf8.count > 65_535 {
            throw JavaIllegalArgumentError(message: "ClientId longer than 65535 characters")
        }
    }

    static func javaIllegalArgument(_ error: MqttCodecError) -> JavaIllegalArgumentError {
        if case .invalidCharacter(let unit) = error {
            return JavaIllegalArgumentError(message: String(format: "Invalid UTF-8 char: [%04x]", Int(unit)))
        }
        return JavaIllegalArgumentError(message: "\(error)")
    }

    // MARK: - Stav

    /// One connection: transport and write queue (under the client lock).
    private final class Link: @unchecked Sendable {
        let generation: Int
        let transport: MqttByteTransport
        var queue: [(bytes: [UInt8], ping: Bool)] = []
        var stopped = false
        /// Let the queue drain before closing (DISCONNECT 0x82 after a protocol error).
        var flushBeforeClose = false
        var enqueued = 0
        var written = 0

        init(generation: Int, transport: MqttByteTransport) {
            self.generation = generation
            self.transport = transport
        }
    }

    private enum Delivery {
        case message(MqttPublish, generation: Int)
        case event(Event)

        var isMessage: Bool {
            if case .message = self { return true }
            return false
        }
    }

    public let options: Options
    private let onMessage: @Sendable (MqttPublish) throws -> Void
    private let onEvent: @Sendable (Event) -> Void

    private let cond = NSCondition()
    private var session: MqttSession
    private var link: Link?
    private var generation = 0
    /// Generation whose connection is currently alive (an undetected drop).
    private var liveGeneration: Int?
    private var losses: [Int: MqttClientError] = [:]
    private var connected = false
    private var closing = false
    private var reconnectLoopRunning = false
    private var backoff: MqttBackoff
    private var connack: (generation: Int, packet: MqttConnack)?
    private var subacks: [UInt16: MqttSuback] = [:]
    private var waiters: Set<UInt16> = []
    private var pubackResults: [UInt16: UInt8] = [:]
    private var deliveries: [Delivery] = []
    private var deliveryThreadStarted = false
    /// After a reconnect, holds back message delivery until subscription recovery ends: Paho calls `connectComplete` (where
    /// `MqttSyncTransport` resubscribes and waits for SUBACK) on the `CommsCallback` thread, so messages arriving meanwhile
    /// (retained replay) and their PUBACK come only after the last SUBSCRIBE (`reconnectResubscribe`).
    private var holdMessages = false
    private var subackCodes: [[UInt8]] = []

    public init(options: Options, onMessage: @escaping @Sendable (MqttPublish) throws -> Void,
                onEvent: @escaping @Sendable (Event) -> Void = { _ in }) {
        self.options = options
        self.onMessage = onMessage
        self.onEvent = onEvent
        self.session = MqttSession(clientId: options.connect.clientId, keepAliveSeconds: options.connect.keepAliveSeconds)
        self.backoff = MqttBackoff(initialMs: options.reconnectInitialMs, maximumMs: options.reconnectMaxMs)
        // Paho `ClientState` constructor → `restoreState`: unacknowledged messages from the previous run.
        if let outbox = options.outbox {
            session.restore(outbox.load())
        }
    }

    public var isConnected: Bool {
        cond.lock()
        defer { cond.unlock() }
        return connected
    }

    /// SUBACK reason codes of the last (re)subscription, one list per SUBSCRIBE.
    public var lastSubackCodes: [[UInt8]] {
        cond.lock()
        defer { cond.unlock() }
        return subackCodes
    }

    /// A copy of the session state (tests, diagnostics).
    public var sessionSnapshot: MqttSession {
        cond.lock()
        defer { cond.unlock() }
        return session
    }

    // MARK: - Public operations

    /// Connects and subscribes (blocking). A first-connection failure does not start a reconnect (like Paho).
    public func connect() throws(MqttClientError) {
        cond.lock()
        if closing {
            cond.unlock()
            throw .closed
        }
        if connected {
            cond.unlock()
            throw MqttClientError(code: MqttClientError.clientConnected)
        }
        if !deliveryThreadStarted {
            deliveryThreadStarted = true
            let thread = Thread { [self] in deliveryLoop() }
            thread.name = "mqtt-callback"
            thread.start()
        }
        cond.unlock()
        try establish(reconnect: false)
    }

    /// Publishes (blocking). QoS 1 waits for PUBACK and returns its reason code (QoS 0: 0). Throws `MqttClientError`
    /// (32104 not connected, 32109 drop while waiting, 32202 window full, 32102 disconnecting) or `MqttCodecError`
    /// (a topic Paho cannot encode — an encoding error, not a connection error).
    @discardableResult
    public func publish(topic: String, payload: [UInt8], qos: UInt8, retain: Bool) throws -> UInt8 {
        cond.lock()
        guard !closing else {
            cond.unlock()
            throw MqttClientError.closed
        }
        guard connected, let current = link, liveGeneration == current.generation else {
            cond.unlock()
            throw MqttClientError.notConnected
        }
        let g: Int = current.generation
        let message: MqttPublish
        let bytes: [UInt8]
        do {
            message = try session.beginPublish(topic: topic, payload: payload, qos: qos, retain: retain)
        } catch {
            cond.unlock()
            throw error
        }
        do {
            bytes = try MqttPacket.publish(message).encode()
        } catch {
            if let id = message.packetId {
                session.cancelPublish(id)
            }
            cond.unlock()
            throw error
        }
        guard let id = message.packetId else {
            enqueue(bytes, on: current)
            cond.unlock()
            return 0
        }
        // Paho `ClientState.send`: `persistence.put` under `queueLock` together with the in-flight enqueue — the PUBACK
        // (reader thread, same lock) cannot overtake the file write and leave an acknowledged command on disk.
        if let outbox = options.outbox {
            do {
                try outbox.put(message)
            } catch {
                session.cancelPublish(id)
                cond.unlock()
                throw error
            }
        }
        waiters.insert(id)
        defer { cond.unlock() }
        enqueue(bytes, on: current)
        while pubackResults[id] == nil {
            if closing {
                waiters.remove(id)
                throw MqttClientError.disconnecting
            }
            if liveGeneration != g {
                waiters.remove(id)
                throw losses[g] ?? MqttClientError(code: MqttClientError.connectionLost)
            }
            cond.wait()
        }
        waiters.remove(id)
        return pubackResults.removeValue(forKey: id) ?? 0
    }

    /// Disconnects (`DISCONNECT e0 02 00 00` like Paho → the broker does not publish the Will), ends reconnect and delivery.
    /// Waiting operations end with 32102. Does not wait for unacknowledged messages (Paho `quiesce` up to 30 s — divergence).
    public func disconnect() {
        cond.lock()
        if closing {
            cond.unlock()
            return
        }
        closing = true
        let current: Link? = link
        let wasConnected = connected
        connected = false
        liveGeneration = nil
        var target = 0
        if wasConnected, let current, !current.stopped, let bytes = try? MqttPacket.disconnect(MqttDisconnect()).encode() {
            enqueue(bytes, on: current)
            target = current.enqueued
        }
        cond.broadcast()
        if let current, target > 0 {
            let deadline = Date(timeIntervalSinceNow: 10)
            while current.written < target && !current.stopped && cond.wait(until: deadline) {}
        }
        current?.stopped = true
        cond.broadcast()
        cond.unlock()
        current?.transport.close()
    }

    // MARK: - Connection

    private static func now() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }

    /// Call under the lock.
    private func enqueue(_ bytes: [UInt8], on target: Link, ping: Bool = false) {
        if target.stopped {
            return
        }
        if ping {
            target.queue.insert((bytes, true), at: 0)
        } else {
            target.queue.append((bytes, false))
        }
        target.enqueued += 1
        cond.broadcast()
    }

    private func deadline(_ ms: Int) -> Date {
        ms == 0 ? Date.distantFuture : Date(timeIntervalSinceNow: Double(ms) / 1_000)
    }

    private func establish(reconnect: Bool) throws(MqttClientError) {
        let transport: MqttByteTransport
        do {
            transport = try options.transportFactory(options.endpoint, options.connectTimeoutMs)
        } catch {
            throw MqttClientError(code: MqttClientError.serverConnectError, cause: "\(error)")
        }
        cond.lock()
        if closing {
            cond.unlock()
            transport.close()
            throw .closed
        }
        // Stop and close the previous connection (a concurrent `connect` during reconnect): otherwise its writer thread
        // would wait forever and the broker would see two connections with the same Client ID.
        let previous: Link? = link
        if let previous, !previous.stopped {
            previous.stopped = true
            cond.broadcast()
        }
        generation += 1
        let g: Int = generation
        let current = Link(generation: g, transport: transport)
        link = current
        liveGeneration = g
        connack = nil
        session.connecting(now: Self.now())
        var packet: MqttConnect = options.connect
        packet.clientId = session.clientId
        cond.unlock()
        previous?.transport.close()

        let reader = Thread { [self] in readLoop(current) }
        reader.name = "mqtt-reader"
        reader.start()
        let writer = Thread { [self] in writeLoop(current) }
        writer.name = "mqtt-writer"
        writer.start()

        let connectBytes: [UInt8]
        do {
            connectBytes = try MqttPacket.connect(packet).encode()
        } catch {
            // Paho throws the encoding error (name, Will topic) on the sender thread; `CommsSender.handleRunException`
            // wraps it as 32109 (measured by a probe, scenario `cred-tab`).
            let failure = MqttClientError(
                code: MqttClientError.connectionLost,
                cause: "java.lang.IllegalArgumentException: \(Self.javaIllegalArgument(error).message)")
            connectionLost(g, failure)
            throw failure
        }
        cond.lock()
        enqueue(connectBytes, on: current)
        let ack: MqttConnack
        do {
            ack = try waitConnack(g)
        } catch {
            cond.unlock()
            if error.code == MqttClientError.clientTimeout {
                connectionLost(g, error)
            }
            throw error
        }
        guard ack.reasonCode < 0x80 else {
            cond.unlock()
            let refused = MqttClientError(code: Int(ack.reasonCode))
            connectionLost(g, refused)
            throw refused
        }
        let resend: [MqttPublish] = session.connected(ack)
        connected = true
        holdMessages = reconnect
        for message in resend {
            if let bytes = try? MqttPacket.publish(message).encode() {
                enqueue(bytes, on: current)
            }
        }
        cond.unlock()
        if session.keepAliveNanos > 0 {
            let pinger = Thread { [self] in keepAliveLoop(current) }
            pinger.name = "mqtt-keepalive"
            pinger.start()
        }
        do {
            try subscribeAll(current)
        } catch {
            cond.lock()
            holdMessages = false
            cond.broadcast()
            cond.unlock()
            throw error
        }
        cond.lock()
        holdMessages = false
        backoff.reset()
        deliveries.append(.event(.connected(sessionPresent: ack.sessionPresent, reconnect: reconnect)))
        cond.broadcast()
        cond.unlock()
    }

    /// Under the lock.
    private func waitConnack(_ g: Int) throws(MqttClientError) -> MqttConnack {
        let end: Date = deadline(options.connectTimeoutMs)
        while true {
            if let (ackGeneration, packet) = connack, ackGeneration == g {
                return packet
            }
            if closing {
                throw .closed
            }
            if liveGeneration != g {
                throw losses[g] ?? MqttClientError(code: MqttClientError.connectionLost)
            }
            if !cond.wait(until: end) && Date() >= end {
                throw MqttClientError(code: MqttClientError.clientTimeout)
            }
        }
    }

    private func subscribeAll(_ current: Link) throws(MqttClientError) {
        let g: Int = current.generation
        var codes: [[UInt8]] = []
        for subscription in options.subscriptions {
            cond.lock()
            defer { cond.unlock() }
            let id: UInt16 = try session.nextPacketId()
            let packet = MqttPacket.subscribe(MqttSubscribe(packetId: id, subscriptions: [subscription]))
            guard let bytes = try? packet.encode() else {
                session.releasePacketId(id)
                throw MqttClientError(code: MqttClientError.malformedPacket)
            }
            enqueue(bytes, on: current)
            while subacks[id] == nil {
                if closing {
                    session.releasePacketId(id)
                    throw MqttClientError.disconnecting
                }
                if liveGeneration != g {
                    session.releasePacketId(id)
                    throw losses[g] ?? MqttClientError(code: MqttClientError.connectionLost)
                }
                cond.wait()
            }
            codes.append(subacks.removeValue(forKey: id)?.reasonCodes ?? [])
            session.releasePacketId(id)
        }
        cond.lock()
        subackCodes = codes
        cond.unlock()
    }

    // MARK: - Writer thread (Paho `CommsSender`)

    private func writeLoop(_ current: Link) {
        cond.lock()
        while true {
            while current.queue.isEmpty && !current.stopped {
                cond.wait()
            }
            if current.stopped {
                cond.unlock()
                return
            }
            let item = current.queue.removeFirst()
            cond.unlock()
            do {
                try current.transport.write(item.bytes)
            } catch {
                cond.lock()
                current.stopped = true
                cond.broadcast()
                cond.unlock()
                connectionLost(current.generation, MqttClientError(code: MqttClientError.connectionLost, cause: "\(error)"))
                return
            }
            cond.lock()
            session.noteSent(now: Self.now(), ping: item.ping)
            current.written += 1
            cond.broadcast()
        }
    }

    // MARK: - Reader thread (Paho `CommsReceiver`)

    private func readLoop(_ current: Link) {
        let g: Int = current.generation
        var frames = MqttFrameReader()
        while true {
            let chunk: [UInt8]?
            do {
                chunk = try current.transport.read()
            } catch {
                connectionLost(g, MqttClientError(code: MqttClientError.connectionLost, cause: "\(error)"))
                return
            }
            guard let chunk else {
                connectionLost(g, MqttClientError(code: MqttClientError.connectionLost, cause: "java.io.EOFException"))
                return
            }
            frames.append(chunk)
            do {
                while let packet = try frames.nextPacket() {
                    if let problem = handle(packet, current) {
                        connectionLost(g, problem)
                        return
                    }
                }
            } catch {
                connectionLost(g, MqttClientError.decoding(error))
                return
            }
        }
    }

    /// Processes an incoming packet; returns the drop reason, or `nil`.
    private func handle(_ packet: MqttPacket, _ current: Link) -> MqttClientError? {
        let g: Int = current.generation
        cond.lock()
        defer { cond.unlock() }
        guard liveGeneration == g else {
            return nil
        }
        session.noteReceived(now: Self.now())
        switch packet {
        case .connack(let p):
            // A second CONNACK on a live connection = Protocol Error (MQTT 5 §3.2; Paho ignores it as an orphan).
            if let (ackGeneration, _) = connack, ackGeneration == g {
                return protocolError(current)
            }
            connack = (g, p)
        case .suback(let p):
            subacks[p.packetId] = p
        case .puback(let p):
            if session.acknowledge(p.packetId) {
                options.outbox?.remove(p.packetId)
                if waiters.contains(p.packetId) {
                    pubackResults[p.packetId] = p.reasonCode
                }
            }
        case .pingresp:
            session.pingResponse()
        case .publish(let p):
            deliveries.append(.message(p, generation: g))
        case .disconnect(let d):
            // Paho `MqttException(32204, MqttDisconnect)`: "… Disconnect RC: <n>" (measured, scenario `takeover`).
            let reasonString: String? = d.properties.string(MqttProperties.Id.reasonString)
            return MqttClientError(code: MqttClientError.serverDisconnected, disconnectReasonCode: d.reasonCode,
                                   disconnectReasonString: reasonString)
        case .connect, .subscribe, .pingreq:
            return protocolError(current)
        }
        cond.broadcast()
        return nil
    }

    /// Under the lock: DISCONNECT with reason 0x82 (MQTT 5 §4.13) and a drop.
    private func protocolError(_ current: Link) -> MqttClientError {
        if let bytes = try? MqttPacket.disconnect(MqttDisconnect(reasonCode: 0x82)).encode() {
            enqueue(bytes, on: current)
            current.flushBeforeClose = true
        }
        return MqttClientError(code: MqttClientError.protocolError)
    }

    private func connectionLost(_ g: Int, _ reason: MqttClientError) {
        cond.lock()
        guard liveGeneration == g, let current = link, current.generation == g else {
            cond.unlock()
            return
        }
        let wasConnected = connected
        liveGeneration = nil
        connected = false
        losses[g] = reason
        losses.removeValue(forKey: g - 8)
        session.disconnected()
        // The writer still gets a chance to send DISCONNECT 0x82 (protocol error), then the transport is closed.
        if current.flushBeforeClose {
            let flushEnd = Date(timeIntervalSinceNow: 1)
            while current.written < current.enqueued && !current.stopped && cond.wait(until: flushEnd) {}
        }
        current.stopped = true
        let startReconnect: Bool = wasConnected && options.automaticReconnect && !closing && !reconnectLoopRunning
        if startReconnect {
            reconnectLoopRunning = true
        }
        if wasConnected {
            deliveries.append(.event(.connectionLost(reason)))
        }
        cond.broadcast()
        cond.unlock()
        current.transport.close()
        if startReconnect {
            let thread = Thread { [self] in reconnectLoop() }
            thread.name = "mqtt-reconnect"
            thread.start()
        }
    }

    // MARK: - Reconnect (Paho `startReconnectCycle`)

    private func reconnectLoop() {
        var again = true
        while again {
            reconnectCycle()
            cond.lock()
            // A drop right after a successful reconnect (the cycle was still running) needs a new cycle.
            again = !closing && !connected && liveGeneration == nil && options.automaticReconnect
            reconnectLoopRunning = again
            cond.unlock()
        }
    }

    private func reconnectCycle() {
        while true {
            cond.lock()
            let end: Date = deadline(backoff.currentMs)
            while !closing && Date() < end {
                _ = cond.wait(until: end)
            }
            let stop: Bool = closing
            cond.unlock()
            if stop {
                return
            }
            do {
                try establish(reconnect: true)
                return
            } catch {
                cond.lock()
                backoff.failed()
                cond.unlock()
            }
        }
    }

    // MARK: - Keep-alive (Paho `ClientState.checkForActivity` + `TimerPingSender`)

    private func keepAliveLoop(_ current: Link) {
        let g: Int = current.generation
        cond.lock()
        while liveGeneration == g && !closing {
            let decision: MqttKeepAliveDecision = session.checkForActivity(now: Self.now())
            let waitNanos: UInt64
            switch decision {
            case .disabled:
                cond.unlock()
                return
            case .fail(let error):
                cond.unlock()
                connectionLost(g, error)
                return
            case .ping(let next):
                enqueue([0xC0, 0x00], on: current, ping: true)
                waitNanos = next
            case .wait(let nanos):
                waitNanos = nanos
            }
            // Waking on another event (`broadcast`) does not hasten the check: wait until the deadline.
            let end = Date(timeIntervalSinceNow: Double(waitNanos) / 1_000_000_000)
            while liveGeneration == g && !closing && Date() < end {
                _ = cond.wait(until: end)
            }
        }
        cond.unlock()
    }

    // MARK: - Delivery (Paho `CommsCallback`)

    private func deliveryLoop() {
        cond.lock()
        while true {
            while (deliveries.isEmpty || holdMessages && deliveries[0].isMessage) && !closing {
                cond.wait()
            }
            if closing {
                deliveries.removeAll()
                cond.unlock()
                return
            }
            let item: Delivery = deliveries.removeFirst()
            cond.unlock()
            switch item {
            case .message(let message, let g):
                do {
                    try onMessage(message)
                } catch {
                    // Paho `deliverMessage`: "Ignoring Exception thrown from messageArrived"; the PUBACK goes out anyway.
                }
                if message.qos == 1, let id = message.packetId, let bytes = try? MqttPacket.puback(MqttPuback(packetId: id)).encode() {
                    cond.lock()
                    if liveGeneration == g, let current = link, current.generation == g {
                        enqueue(bytes, on: current)
                    }
                    cond.unlock()
                }
            case .event(let event):
                onEvent(event)
            }
            cond.lock()
        }
    }
}
