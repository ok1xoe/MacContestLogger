import Foundation
@testable import MCLAppModel
@testable import MCLCore

/// One station's view of a shared `InMemorySyncTransport` (the "broker" of a test with several stations): everything
/// is forwarded to the hub, and the station's own `close` only silences its own listeners (the hub's `close` would
/// drop every station's). Records what the station published and can hold the lane: a gate on `close`, on the
/// status publish or on the spot publish blocks the lane thread until the test releases it. Never a socket.
final class LinkedTransport: SyncTransport, @unchecked Sendable {

    private let hub: InMemorySyncTransport
    private let lock = NSLock()
    private var closed = false
    private var connectedFlag = false
    private var recordedStatuses: [StationStatusWire] = []
    private var recordedSpots: [SpotWire] = []
    private var recordedRequests: [SerialRequest] = []
    private var recordedClosings = 0
    private var statusCalls = 0
    private var messageListener: SyncListener<NetMessageWire>?
    private var replyListener: SyncListener<SerialReply>?
    private var statusListener: SyncListener<StationStatusWire>?

    /// `connect` throws this (a failed connect).
    var connectError: (any Error)?
    /// The serial server does not answer (the request is recorded and dropped).
    var dropSerialRequests = false
    /// `close` waits for this semaphore (a broker that does not answer the DISCONNECT).
    var closeGate: DispatchSemaphore?
    /// `publishStatus` waits for this semaphore.
    var statusGate: DispatchSemaphore?
    /// `publishSpot` waits for this semaphore.
    var spotGate: DispatchSemaphore?

    init(hub: InMemorySyncTransport) {
        self.hub = hub
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    var isClosed: Bool { locked { closed } }
    var closings: Int { locked { recordedClosings } }
    /// Calls of `publishStatus` that reached the transport (also the one waiting at the gate).
    var statusAttempts: Int { locked { statusCalls } }
    var statusPublishes: [StationStatusWire] { locked { recordedStatuses } }
    var spotPublishes: [SpotWire] { locked { recordedSpots } }
    var serialRequests: [SerialRequest] { locked { recordedRequests } }

    /// The transport reports itself disconnected from now on.
    func dropConnection() {
        locked { connectedFlag = false }
    }

    // MARK: - SyncTransport

    func connect() throws {
        if let connectError {
            throw connectError
        }
        hub.connect()
        locked { connectedFlag = true }
    }

    var isConnected: Bool {
        locked { connectedFlag && !closed }
    }

    private func ensureOpen() throws {
        if isClosed {
            throw SyncTransportError("closed")
        }
    }

    func publishInsert(_ command: QsoCommand) throws {
        try ensureOpen()
        try hub.publishInsert(command)
    }

    func publishUpdate(_ command: QsoCommand) throws {
        try ensureOpen()
        try hub.publishUpdate(command)
    }

    func publishDelete(_ command: DeleteCommand) throws {
        try ensureOpen()
        try hub.publishDelete(command)
    }

    /// A listener that goes silent once this station's transport is closed.
    private func guarded<T>(_ listener: @escaping SyncListener<T>) -> SyncListener<T> {
        { [self] value in
            if !isClosed {
                try listener(value)
            }
        }
    }

    func subscribeState(_ listener: @escaping SyncListener<QsoState>) throws {
        try hub.subscribeState(guarded(listener))
    }

    func publishSpot(_ spot: SpotWire) throws {
        try ensureOpen()
        spotGate?.wait()
        locked { recordedSpots.append(spot) }
        try hub.publishSpot(spot)
    }

    func subscribeSpots(_ listener: @escaping SyncListener<SpotWire>) {
        hub.subscribeSpots(guarded(listener))
    }

    func publishStatus(_ status: StationStatusWire) throws {
        try ensureOpen()
        locked { statusCalls += 1 }
        statusGate?.wait()
        locked { recordedStatuses.append(status) }
        try hub.publishStatus(status)
    }

    func subscribeStatus(_ listener: @escaping SyncListener<StationStatusWire>) throws {
        let silenced: SyncListener<StationStatusWire> = guarded(listener)
        locked { statusListener = silenced }
        try hub.subscribeStatus(silenced)
    }

    func publishMessage(_ message: NetMessageWire) throws {
        try ensureOpen()
        try hub.publishMessage(message)
    }

    func subscribeMessages(_ listener: @escaping SyncListener<NetMessageWire>) {
        let silenced: SyncListener<NetMessageWire> = guarded(listener)
        locked { messageListener = silenced }
        hub.subscribeMessages(silenced)
    }

    func requestSerial(_ request: SerialRequest) throws {
        try ensureOpen()
        locked { recordedRequests.append(request) }
        if dropSerialRequests {
            return
        }
        try hub.requestSerial(request)
    }

    func subscribeSerialReplies(_ listener: @escaping SyncListener<SerialReply>) {
        let silenced: SyncListener<SerialReply> = guarded(listener)
        locked { replyListener = silenced }
        hub.subscribeSerialReplies(silenced)
    }

    func close() {
        locked { recordedClosings += 1 }
        closeGate?.wait()
        locked { closed = true }
    }

    // MARK: - what the broker would deliver

    /// A message straight to this station's listener (not through the hub).
    func deliver(_ message: NetMessageWire) throws {
        let listener: SyncListener<NetMessageWire>? = locked { messageListener }
        try listener?(message)
    }

    /// A reply of the serial server straight to this station's listener.
    func deliver(_ reply: SerialReply) throws {
        let listener: SyncListener<SerialReply>? = locked { replyListener }
        try listener?(reply)
    }
}
