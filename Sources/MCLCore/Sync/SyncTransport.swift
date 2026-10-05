/// Transport message listener. The value may be `nil` — the MQTT transport passes what `WireJson` reads, and a payload
/// `null` is Java `null` (cluster sync listeners have `s != null` guards in Java, `SyncCoordinator.onState`
/// crashes with a `NullPointerException`). A listener error propagates to whoever delivered the message (for the in-memory transport
/// to the caller of `publish…`, like a Java unchecked exception).
public typealias SyncListener<T> = @Sendable (T?) throws -> Void

/// Cluster sync transport abstraction (Java `sync.SyncTransport`): keeps the core independent of the protocol (MQTT for now).
/// The station publishes commands through it and subscribes to the canonical state; tested via `InMemorySyncTransport`.
/// Publishing is "fire-and-forget" (delivery is guaranteed by the transport — MQTT QoS 1 + persistent session); a transport
/// error is `SyncTransportError`.
///
/// Methods with a Java default implementation (`default` = nothing) have a default implementation in a protocol extension.
public protocol SyncTransport: AnyObject, Sendable {

    /// Establishes the connection (and for MQTT restores subscriptions / retained replay).
    func connect() throws

    var isConnected: Bool { get }

    func publishInsert(_ command: QsoCommand) throws

    func publishUpdate(_ command: QsoCommand) throws

    func publishDelete(_ command: DeleteCommand) throws

    /// Listener of the canonical state (`qso/state/#`); also called for the retained replay on (re)connect.
    func subscribeState(_ listener: @escaping SyncListener<QsoState>) throws

    /// Distributes a DX spot to the other stations (telnet sharing).
    func publishSpot(_ spot: SpotWire) throws

    /// Subscription to spots from other stations.
    func subscribeSpots(_ listener: @escaping SyncListener<SpotWire>)

    /// State that the broker publishes on connection loss (MQTT Last Will). Call before `connect()`.
    func setOfflineStatus(_ offline: StationStatusWire)

    /// Publishes the state of this station (retained).
    func publishStatus(_ status: StationStatusWire) throws

    /// Subscription to the states of all stations (including retained states on connect).
    func subscribeStatus(_ listener: @escaping SyncListener<StationStatusWire>) throws

    /// Sends a message to the other stations.
    func publishMessage(_ message: NetMessageWire) throws

    /// Subscription to station messages (all of them — the recipient is filtered by `StationNetwork`).
    func subscribeMessages(_ listener: @escaping SyncListener<NetMessageWire>)

    /// Asks the authority for a serial number.
    func requestSerial(_ request: SerialRequest) throws

    /// Subscription to assigned numbers for this station.
    func subscribeSerialReplies(_ listener: @escaping SyncListener<SerialReply>)

    func close()
}

/// Java `default` interface methods: do nothing (a response to `requestSerial` never arrives).
public extension SyncTransport {
    func publishSpot(_ spot: SpotWire) throws {}
    func subscribeSpots(_ listener: @escaping SyncListener<SpotWire>) {}
    func setOfflineStatus(_ offline: StationStatusWire) {}
    func publishStatus(_ status: StationStatusWire) throws {}
    func subscribeStatus(_ listener: @escaping SyncListener<StationStatusWire>) throws {}
    func publishMessage(_ message: NetMessageWire) throws {}
    func subscribeMessages(_ listener: @escaping SyncListener<NetMessageWire>) {}
    func requestSerial(_ request: SerialRequest) throws {}
    func subscribeSerialReplies(_ listener: @escaping SyncListener<SerialReply>) {}
}
