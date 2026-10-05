import Foundation

/// In-memory loop simulating the authority without a broker — for station tests (Java `sync.InMemorySyncTransport`).
/// A received command gets a monotonic `version` per `uuid` (`previous + 1`, first 1), is stored as a retained state
/// and distributed to subscribers; a late subscriber gets a retained replay (bootstrap). A tombstone keeps the last payload.
/// Serial server: `1 + max(sent number in non-deleted states, last issued)`.
///
/// Listeners are called synchronously on the caller's thread, in registration order, over a copy of the list (Java
/// `new ArrayList<>(listeners)`); a listener error aborts the distribution and propagates to the caller. The Java class is not
/// thread-safe; here a lock guards the state (listeners are called outside it) so it can be passed through `Sendable`.
public final class InMemorySyncTransport: SyncTransport, @unchecked Sendable {

    private let lock = NSLock()
    private var retained: [(uuid: String?, state: QsoState)] = []
    private var listeners: [SyncListener<QsoState>] = []
    private var spotListeners: [SyncListener<SpotWire>] = []
    private var statuses: [(stationId: String?, status: StationStatusWire)] = []
    private var statusListeners: [SyncListener<StationStatusWire>] = []
    private var messageListeners: [SyncListener<NetMessageWire>] = []
    private var serialListeners: [SyncListener<SerialReply>] = []
    private var lastSerial: Int32 = 0
    private var connected = false

    public init() {}

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    public func connect() {
        locked { connected = true }
    }

    public var isConnected: Bool {
        locked { connected }
    }

    public func subscribeState(_ listener: @escaping SyncListener<QsoState>) throws {
        let snapshot: [QsoState] = locked {
            listeners.append(listener)
            return retained.map(\.state)
        }
        for state in snapshot {
            try listener(state)
        }
    }

    public func publishInsert(_ command: QsoCommand) throws {
        try publishState(command.uuid, command.stationId, command.qso, deleted: false)
    }

    public func publishUpdate(_ command: QsoCommand) throws {
        try publishState(command.uuid, command.stationId, command.qso, deleted: false)
    }

    public func publishDelete(_ command: DeleteCommand) throws {
        let previous: QsoState? = locked { retainedIndex(command.uuid).map { retained[$0].state } }
        try publishState(command.uuid, command.stationId, previous?.qso, deleted: true)
    }

    /// Index into `retained` by `uuid` (`LinkedHashMap`: `null` is a valid key, order of first insertion).
    private func retainedIndex(_ uuid: String?) -> Int? {
        retained.firstIndex { entry in
            guard let key = entry.uuid else { return uuid == nil }
            guard let uuid else { return false }
            return JavaText.equals(key, uuid)
        }
    }

    private func publishState(_ uuid: String?, _ stationId: String?, _ qso: QsoWire?, deleted: Bool) throws {
        let (state, targets): (QsoState, [SyncListener<QsoState>]) = locked {
            let index: Int? = retainedIndex(uuid)
            let version: Int64 = index.map { retained[$0].state.version &+ 1 } ?? 1
            let state = QsoState(uuid: uuid, stationId: stationId, version: version,
                                 updatedAtUtc: qso?.timestampUtc, deleted: deleted, qso: qso)
            if let index {
                retained[index].state = state
            } else {
                retained.append((uuid, state))
            }
            return (state, listeners)
        }
        for listener in targets {
            try listener(state)
        }
    }

    public func publishSpot(_ spot: SpotWire) throws {
        let targets: [SyncListener<SpotWire>] = locked { spotListeners }
        for listener in targets {
            try listener(spot)
        }
    }

    public func subscribeSpots(_ listener: @escaping SyncListener<SpotWire>) {
        locked { spotListeners.append(listener) }
    }

    public func publishStatus(_ status: StationStatusWire) throws {
        let targets: [SyncListener<StationStatusWire>] = locked {
            let index: Int? = statuses.firstIndex { entry in
                guard let key = entry.stationId else { return status.stationId == nil }
                guard let id = status.stationId else { return false }
                return JavaText.equals(key, id)
            }
            if let index {
                statuses[index].status = status
            } else {
                statuses.append((status.stationId, status))
            }
            return statusListeners
        }
        for listener in targets {
            try listener(status)
        }
    }

    public func subscribeStatus(_ listener: @escaping SyncListener<StationStatusWire>) throws {
        let snapshot: [StationStatusWire] = locked {
            statusListeners.append(listener)
            return statuses.map(\.status)
        }
        for status in snapshot {
            try listener(status)
        }
    }

    public func publishMessage(_ message: NetMessageWire) throws {
        let targets: [SyncListener<NetMessageWire>] = locked { messageListeners }
        for listener in targets {
            try listener(message)
        }
    }

    public func subscribeMessages(_ listener: @escaping SyncListener<NetMessageWire>) {
        locked { messageListeners.append(listener) }
    }

    public func requestSerial(_ request: SerialRequest) throws {
        let (reply, targets): (SerialReply, [SyncListener<SerialReply>]) = locked {
            var max: Int32?
            for entry in retained where !entry.state.deleted {
                if let serial = entry.state.qso?.serialSent {
                    max = Swift.max(max ?? serial, serial)
                }
            }
            lastSerial = Swift.max(lastSerial, max ?? 0) &+ 1
            return (SerialReply(stationId: request.stationId, requestId: request.requestId, serial: lastSerial),
                    serialListeners)
        }
        for listener in targets {
            try listener(reply)
        }
    }

    public func subscribeSerialReplies(_ listener: @escaping SyncListener<SerialReply>) {
        locked { serialListeners.append(listener) }
    }

    public func close() {
        locked {
            connected = false
            serialListeners.removeAll()
            messageListeners.removeAll()
            statusListeners.removeAll()
            listeners.removeAll()
            spotListeners.removeAll()
        }
    }
}
