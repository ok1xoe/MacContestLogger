import Foundation

/// Presence of stations in the network log (N1MM Network Status) — Java `cluster.StationNetwork`: publishes
/// the state of this station (immediately on change, otherwise as a heartbeat every `heartbeat`) and keeps an overview of the others. A station
/// without a heartbeat for longer than `stale` is reported as inactive. Messages (chat, pass, stack) and the serial server go
/// over the same transport.
///
/// Threads: Java keeps peers in a `ConcurrentHashMap` and listeners in `volatile` fields (`lastPublished*` without
/// synchronisation); here a single lock guards all state and listeners are called outside it, on the thread that
/// delivered the event.
public final class StationNetwork: @unchecked Sendable {

    public static let heartbeat: Duration = .seconds(30)
    public static let stale: Duration = .seconds(90)

    /// A station in the network: its last state, when it arrived, whether it is online and how old it is.
    public struct Peer: Equatable, Sendable {
        public let status: StationStatusWire
        public let receivedAt: JavaInstant
        public let online: Bool
        public let age: Duration

        public init(status: StationStatusWire, receivedAt: JavaInstant, online: Bool, age: Duration) {
            self.status = status
            self.receivedAt = receivedAt
            self.online = online
            self.age = age
        }
    }

    private let transport: SyncTransport
    public let stationId: String
    private let clock: @Sendable () -> JavaInstant
    private let newId: @Sendable () -> String
    private let lock = NSLock()
    /// Key = `stationId` of the peer (by UTF-16 like a Java map).
    private var peerMap: [[UInt16]: Peer] = [:]
    private var lastPublished: StationStatusWire?
    private var lastPublishedAt: JavaInstant = .epoch
    private var onChange: @Sendable () -> Void = {}
    private var onMessage: @Sendable (NetMessageWire) throws -> Void = { _ in }

    /// - Parameters:
    ///   - clock: Java `Clock.instant()` (app: `JavaInstant.now`)
    ///   - newId: id of the sent message (Java `UUID.randomUUID().toString()`; deterministic in tests)
    public init(transport: SyncTransport, stationId: String, clock: @escaping @Sendable () -> JavaInstant,
                newId: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }) {
        self.transport = transport
        self.stationId = stationId
        self.clock = clock
        self.newId = newId
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    /// Sets the Last Will and subscribes to states — call before connecting the transport.
    public func start(_ onChange: (@Sendable () -> Void)?) throws {
        locked { self.onChange = onChange ?? {} }
        transport.setOfflineStatus(StationStatusWire.offline(stationId))
        try transport.subscribeStatus { [self] status in
            self.onStatus(status)
        }
    }

    /// Reception of messages for this station (chat, pass, stack) — subscribe before connecting. Lets through a message with
    /// a sender that is meant for this station (`NetMessageWire.isFor`).
    public func onMessages(_ handler: (@Sendable (NetMessageWire) throws -> Void)?) {
        locked { self.onMessage = handler ?? { _ in } }
        let me: String = stationId
        transport.subscribeMessages { [self] message in
            if let message, message.fromStation != nil, message.isFor(me) {
                let current = self.locked { self.onMessage }
                try current(message)
            }
        }
    }

    /// Sends a message; `to` empty/`nil` = to everyone. Returns the sent message (for the own history).
    @discardableResult
    public func send(_ type: String?, operator: String?, to: String?, text: String?, call: String?, freqHz: Int,
                     mode: String?) throws -> NetMessageWire {
        let message = NetMessageWire(type: type, id: newId(), fromStation: stationId, fromOperator: `operator`,
                                     toStation: to ?? "", text: text ?? "", call: call ?? "", freqHz: freqHz,
                                     mode: mode ?? "", timestampUtc: clock().toString())
        try transport.publishMessage(message)
        return message
    }

    /// Reception of assigned serial numbers for this station — subscribe before connecting.
    public func onSerialReplies(_ handler: @escaping @Sendable (SerialReply) throws -> Void) {
        let me: String = stationId
        transport.subscribeSerialReplies { reply in
            if let reply, JavaText.equals(me, reply.stationId) {
                try handler(reply)
            }
        }
    }

    /// Asks the serial server for the next number; the reply arrives with this `requestId`.
    public func requestSerial(_ requestId: String?) throws {
        try transport.requestSerial(SerialRequest(stationId: stationId, requestId: requestId))
    }

    func onStatus(_ status: StationStatusWire?) {
        guard let status, let id = status.stationId, !JavaText.equals(stationId, id) else { return }
        let now: JavaInstant = clock()
        let callback: @Sendable () -> Void = locked {
            peerMap[Array(id.utf16)] = Peer(status: status, receivedAt: now, online: status.online, age: .zero)
            return onChange
        }
        callback()
    }

    /// Publishes the state if it changed (regardless of time), or the heartbeat elapsed; returns whether it published.
    /// The published state carries the ID of this station, `online = true` and the send time (`Instant.toString()`).
    @discardableResult
    public func publish(_ status: StationStatusWire) throws -> Bool {
        let now: JavaInstant = clock()
        let (previous, previousAt): (StationStatusWire?, JavaInstant) = locked { (lastPublished, lastPublishedAt) }
        let changed: Bool = previous.map { !Self.sameContent($0, status) } ?? true
        if !changed && previousAt.duration(to: now) < Self.heartbeat {
            return false
        }
        let stamped = StationStatusWire(stationId: stationId, operator: status.operator,
                                        stationType: status.stationType, band: status.band, mode: status.mode,
                                        freqHz: status.freqHz, runMode: status.runMode, qsoCount: status.qsoCount,
                                        transmitting: status.transmitting, online: true,
                                        timestampUtc: now.toString(), entryCall: status.entryCall)
        try transport.publishStatus(stamped)
        locked {
            lastPublished = stamped
            lastPublishedAt = now
        }
        return true
    }

    /// Other stations sorted by ID (`Comparator.comparing(stationId)` = by UTF-16); online = reported
    /// as online and the last report is not older than `stale`.
    public func peers() -> [Peer] {
        let now: JavaInstant = clock()
        let snapshot: [Peer] = locked { Array(peerMap.values) }
        var out: [Peer] = snapshot.map { p in
            let age: Duration = p.receivedAt.duration(to: now)
            return Peer(status: p.status, receivedAt: p.receivedAt, online: p.status.online && age <= Self.stale,
                        age: age)
        }
        out.sort { a, b in
            Array((a.status.stationId ?? "").utf16).lexicographicallyPrecedes(Array((b.status.stationId ?? "").utf16))
        }
        return out
    }

    /// Publishes the offline state (on orderly disconnect).
    public func goOffline() throws {
        try transport.publishStatus(StationStatusWire.offline(stationId))
    }

    static func sameContent(_ a: StationStatusWire, _ b: StationStatusWire) -> Bool {
        let texts: Bool = eq(a.operator, b.operator) && eq(a.stationType, b.stationType) && eq(a.band, b.band)
            && eq(a.mode, b.mode) && eq(a.runMode, b.runMode) && eq(a.entryCall, b.entryCall)
        return texts && a.freqHz == b.freqHz && a.qsoCount == b.qsoCount && a.transmitting == b.transmitting
    }

    static func eq(_ a: String?, _ b: String?) -> Bool {
        guard let a else { return b == nil }
        return JavaText.equals(a, b)
    }
}
