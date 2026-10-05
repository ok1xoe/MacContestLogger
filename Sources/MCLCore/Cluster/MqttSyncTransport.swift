import Foundation

/// MQTT implementation of `SyncTransport` (Java `cluster.MqttSyncTransport` v1.1.1 over Paho v5; here over
/// `MqttClient`). The station is only a client of the central broker: it publishes the commands `qso/cmd/*` (QoS 1, not retained)
/// and subscribes to the canonical state `qso/state/#` (retained replay = bootstrap). A persistent session (Clean Start 0,
/// stable Client ID = `stationId`) survives short outages; unacknowledged QoS 1 messages survive a restart too (`MqttOutbox`
/// in `persistenceDir`).
///
/// Listeners are called on the client's delivery thread (Paho `CommsCallback`), not on the main one — hopping is up to the
/// caller. A message is routed by topic (`spot/new` → `serial/reply/…` → `station/msg` →
/// `station/status/…` → `qso/state/<uuid>`), an empty payload is ignored, JSON is read by `WireJson.fromBytes`
/// (a root `null` = `nil` to listeners). A read or listener error is swallowed (Paho), the PUBACK still goes out
/// and the remaining listeners of the same message are not called (Java `forEach`). `close()` clears the listeners — **unlike Java** (breaks the cycle
/// coordinator ↔ transport).
///
/// **Threads:** `connect`, `publish*`, `requestSerial` and `close` block (network, waiting for CONNACK/SUBACK/PUBACK,
/// DISCONNECT) — call from your own thread (like Kotlin `Dispatchers.IO`), never from Swift's shared pool
/// (`Task`) or from the main thread. `connect` and `close` are mutually serialised (Java `synchronized`).
public final class MqttSyncTransport: SyncTransport, @unchecked Sendable {

    private static let qos: UInt8 = 1

    public let serverUri: String
    private let endpoint: MqttEndpoint
    private let clientId: String
    private let username: String?
    private let password: String?
    private let persistenceDir: URL?
    private let transportFactory: MqttTransportFactory
    private let configure: @Sendable (inout MqttClient.Options) -> Void

    private let lock = NSLock()
    /// Java `synchronized` on `connect`/`close`; never held at the same time as `lock` in the opposite order.
    private let lifecycle = NSLock()
    private var listeners: [SyncListener<QsoState>] = []
    private var spotListeners: [SyncListener<SpotWire>] = []
    private var statusListeners: [SyncListener<StationStatusWire>] = []
    private var messageListeners: [SyncListener<NetMessageWire>] = []
    private var serialListeners: [SyncListener<SerialReply>] = []
    private var offlineStatus: StationStatusWire?
    private var client: MqttClient?

    /// Java constructor `MqttSyncTransport(host, port, clientId, username, password, persistenceDir, tls)`.
    /// - Parameters:
    ///   - password: `nil` = no password; otherwise it is always sent, even an empty one (`AppState` passes `toCharArray()`).
    ///   - tls: `ssl://` with system trust and host name verification, otherwise `tcp://`.
    public convenience init(host: String, port: Int, clientId: String, username: String?, password: String?,
                            persistenceDir: URL?, tls: Bool = false) {
        self.init(host: host, port: port, clientId: clientId, username: username, password: password,
                  persistenceDir: persistenceDir, trust: tls ? .system : nil)
    }

    /// Tests: custom TLS roots, transport replacement, client option tweaks (shorter reconnect delays).
    init(host: String, port: Int, clientId: String, username: String?, password: String?,
         persistenceDir: URL?, trust: MqttTlsTrust?,
         transportFactory: @escaping MqttTransportFactory = MqttTransports.standard,
         configure: @escaping @Sendable (inout MqttClient.Options) -> Void = { _ in }) {
        self.endpoint = MqttEndpoint(host: host, port: port, trust: trust)
        self.serverUri = endpoint.serverUri
        self.clientId = clientId
        self.username = username
        self.password = password
        self.persistenceDir = persistenceDir
        self.transportFactory = transportFactory
        self.configure = configure
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    private var currentClient: MqttClient? {
        locked { client }
    }

    // MARK: - Connection

    /// Java `connect()`: a new client (like `new MqttClient` — restores unacknowledged messages from persistence),
    /// CONNECT with a Will (offline state, QoS 1, retained) and five subscriptions. `MqttClientError` → `SyncTransportError(
    /// "Nelze se připojit k MQTT brokeru <uri>")`; a Client ID that Paho cannot encode is a Java
    /// `IllegalArgumentException` and propagates to the caller as is (`JavaIllegalArgumentError`).
    public func connect() throws {
        lifecycle.lock()
        defer { lifecycle.unlock() }
        try MqttClient.validateClientId(clientId)
        let offline: StationStatusWire? = locked { offlineStatus }
        var will: MqttWill?
        if let offline {
            will = MqttWill(topic: Topics.status(offline.stationId), payload: WireJson.toBytes(offline), qos: Self.qos, retain: true)
        }
        let connectPacket: MqttConnect = MqttClient.stationConnect(
            clientId: clientId, username: username, password: password, will: will)
        var options = MqttClient.Options(
            endpoint: endpoint, connect: connectPacket, subscriptions: MqttClient.stationSubscriptions(clientId: clientId))
        options.transportFactory = transportFactory
        if let persistenceDir {
            options.outbox = MqttOutbox(persistenceDir: persistenceDir, clientId: clientId, serverUri: serverUri)
        }
        configure(&options)
        let created = MqttClient(options: options, onMessage: { [weak self] message in
            self?.messageArrived(message)
        })
        // Java assigns `client` before `client.connect` — it keeps it even after a connect error (and `close` cleans it up).
        let previous: MqttClient? = locked {
            let old = client
            client = created
            return old
        }
        previous?.disconnect()
        do {
            try created.connect()
        } catch {
            throw SyncTransportError("Nelze se připojit k MQTT brokeru \(serverUri)", cause: error.description)
        }
    }

    public var isConnected: Bool {
        currentClient?.isConnected ?? false
    }

    /// Java `close()`: DISCONNECT (the broker does not publish the Will), closing the client. Unlike Java it also clears the listeners
    /// (the Java lists stay) — breaks the cycle coordinator ↔ transport (a deliberate divergence from Java v1.1.1).
    public func close() {
        lifecycle.lock()
        defer { lifecycle.unlock() }
        let old: MqttClient? = locked {
            let c = client
            client = nil
            listeners.removeAll()
            spotListeners.removeAll()
            statusListeners.removeAll()
            messageListeners.removeAll()
            serialListeners.removeAll()
            return c
        }
        old?.disconnect()
    }

    /// Number of registered listeners of all kinds (tests: `close` clears them).
    var listenerCount: Int {
        locked {
            let counts: [Int] = [listeners.count, spotListeners.count, statusListeners.count, messageListeners.count,
                                 serialListeners.count]
            return counts.reduce(0, +)
        }
    }

    // MARK: - Publishing

    public func publishInsert(_ command: QsoCommand) throws {
        try publish(Topics.cmdInsert, WireJson.toBytes(command))
    }

    public func publishUpdate(_ command: QsoCommand) throws {
        try publish(Topics.cmdUpdate, WireJson.toBytes(command))
    }

    public func publishDelete(_ command: DeleteCommand) throws {
        try publish(Topics.cmdDelete, WireJson.toBytes(command))
    }

    /// Commands QoS 1 without retain. A client error → `SyncTransportError("Nelze publikovat na <téma>")`; a message
    /// unacknowledged due to an outage stays in the client and goes out after reconnect with DUP. Without a client (before `connect`,
    /// after `close`) Java fails with `NullPointerException` — here the same error as for not connected (divergence).
    private func publish(_ topic: String, _ payload: [UInt8]) throws {
        guard let c = currentClient else {
            throw SyncTransportError("Nelze publikovat na \(topic)", cause: MqttClientError.notConnected.description)
        }
        do {
            try c.publish(topic: topic, payload: payload, qos: Self.qos, retain: false)
        } catch let error as MqttClientError {
            throw SyncTransportError("Nelze publikovat na \(topic)", cause: error.description)
        }
    }

    /// Spots QoS 0 without retain; not connected = silently nothing.
    public func publishSpot(_ spot: SpotWire) throws {
        guard let c = currentClient, c.isConnected else { return }
        do {
            try c.publish(topic: Topics.spots, payload: WireJson.toBytes(spot), qos: 0, retain: false)
        } catch let error as MqttClientError {
            throw SyncTransportError("Nelze publikovat spot", cause: error.description)
        }
    }

    public func setOfflineStatus(_ offline: StationStatusWire) {
        locked { offlineStatus = offline }
    }

    /// Station state QoS 1 retained; not connected = silently nothing.
    public func publishStatus(_ status: StationStatusWire) throws {
        guard let c = currentClient, c.isConnected else { return }
        do {
            try c.publish(topic: Topics.status(status.stationId), payload: WireJson.toBytes(status), qos: Self.qos, retain: true)
        } catch let error as MqttClientError {
            throw SyncTransportError("Nelze publikovat stav stanice", cause: error.description)
        }
    }

    public func publishMessage(_ message: NetMessageWire) throws {
        guard let c = currentClient, c.isConnected else {
            throw SyncTransportError("Nepřipojeno k brokeru")
        }
        do {
            try c.publish(topic: Topics.messages, payload: WireJson.toBytes(message), qos: Self.qos, retain: false)
        } catch let error as MqttClientError {
            throw SyncTransportError("Nelze poslat zprávu", cause: error.description)
        }
    }

    public func requestSerial(_ request: SerialRequest) throws {
        guard let c = currentClient, c.isConnected else {
            throw SyncTransportError("Nepřipojeno k brokeru")
        }
        do {
            try c.publish(topic: Topics.serialRequest, payload: WireJson.toBytes(request), qos: Self.qos, retain: false)
        } catch let error as MqttClientError {
            throw SyncTransportError("Nelze požádat o číslo", cause: error.description)
        }
    }

    // MARK: - Subscriptions

    public func subscribeState(_ listener: @escaping SyncListener<QsoState>) throws {
        locked { listeners.append(listener) }
    }

    public func subscribeSpots(_ listener: @escaping SyncListener<SpotWire>) {
        locked { spotListeners.append(listener) }
    }

    public func subscribeStatus(_ listener: @escaping SyncListener<StationStatusWire>) throws {
        locked { statusListeners.append(listener) }
    }

    public func subscribeMessages(_ listener: @escaping SyncListener<NetMessageWire>) {
        locked { messageListeners.append(listener) }
    }

    public func subscribeSerialReplies(_ listener: @escaping SyncListener<SerialReply>) {
        locked { serialListeners.append(listener) }
    }

    // MARK: - Delivery (Java `Callback.messageArrived`)

    private func messageArrived(_ message: MqttPublish) {
        do {
            try route(message.topic, message.payload)
        } catch {
            // Paho `CommsCallback.deliverMessage`: an exception from `messageArrived` is swallowed.
        }
    }

    private func route(_ topic: String, _ payload: [UInt8]) throws {
        if JavaText.equals(Topics.spots, topic) {
            try deliver(payload, SpotWire.self, locked { spotListeners })
            return
        }
        if Self.startsWith(topic, Topics.serialReplyPrefix) {
            try deliver(payload, SerialReply.self, locked { serialListeners })
            return
        }
        if JavaText.equals(Topics.messages, topic) {
            try deliver(payload, NetMessageWire.self, locked { messageListeners })
            return
        }
        if Self.startsWith(topic, Topics.statusPrefix) {
            try deliver(payload, StationStatusWire.self, locked { statusListeners })
            return
        }
        guard Topics.uuidFromStateTopic(topic) != nil else {
            return
        }
        try deliver(payload, QsoState.self, locked { listeners })
    }

    /// Java `String.startsWith` (by UTF-16 units).
    static func startsWith(_ text: String, _ prefix: String) -> Bool {
        let units: [UInt16] = Array(text.utf16)
        let head: [UInt16] = Array(prefix.utf16)
        return units.count >= head.count && Array(units[0..<head.count]) == head
    }

    private func deliver<T: WireMessage>(_ payload: [UInt8], _ type: T.Type, _ targets: [SyncListener<T>]) throws {
        guard !payload.isEmpty else {
            return
        }
        let value: T? = try WireJson.fromBytes(payload, as: type)
        for listener in targets {
            try listener(value)
        }
    }
}
