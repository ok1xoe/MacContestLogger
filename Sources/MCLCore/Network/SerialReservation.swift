import Foundation

/// The serial number reserved at the serial server (`AppState` `reservedSerial`, `serialRequestId`,
/// `serialRequestedAt`; `AS:2735-2762`): the request is repeated every 3 s without a reply. The clock and the
/// request ID generator are handed in.
public struct SerialReservation: Sendable, Equatable {

    /// Milliseconds before a request without a reply is repeated.
    public static let retryMs: Int64 = 3_000

    /// The number reserved for the next QSO, `nil` = count locally.
    public private(set) var reserved: Int?
    private var requestId: String?
    private var requestedAtMs: Int64 = 0

    public init() {}

    /// The state of a reservation in progress (tests).
    init(reserved: Int?, requestId: String?, requestedAtMs: Int64) {
        self.reserved = reserved
        self.requestId = requestId
        self.requestedAtMs = requestedAtMs
    }

    /// The ID of the request waiting for its reply.
    var pendingRequestId: String? { requestId }
    var lastRequestAtMs: Int64 { requestedAtMs }

    /// `ensureSerialReservation`: returns the ID of a request to send (the transport call is the caller's, failures
    /// are ignored — the next try comes after the wait), `nil` when nothing is to be sent.
    /// - Parameters:
    ///   - nowMs: wall clock in milliseconds
    ///   - enabled: `cluster.serialServer`
    ///   - hasNet: the station network exists
    public mutating func tick(nowMs: Int64, enabled: Bool, hasNet: Bool, newId: () -> String) -> String? {
        if !enabled || reserved != nil {
            return nil
        }
        if !hasNet {
            return nil
        }
        if requestId != nil && nowMs - requestedAtMs < Self.retryMs {
            return nil
        }
        let id: String = newId()
        requestId = id
        requestedAtMs = nowMs
        return id
    }

    /// `onSerialReply`: only the reply to the pending request counts. Kotlin compares nullable IDs with `!=`, so a
    /// reply without an ID is accepted while no request is pending.
    public mutating func reply(_ reply: SerialReply) {
        if reply.requestId != requestId {
            return
        }
        requestId = nil
        reserved = Int(reply.serial)
    }

    /// `log`: the QSO that was just written carried the reserved number → it is used up (the caller asks for the next
    /// one with `tick`). `serialSent` of the QSO.
    public mutating func consumed(serial: Int?) -> Bool {
        guard let current = reserved, serial == current else { return false }
        reserved = nil
        return true
    }

    /// `stopCluster`: forget the reservation and the pending request.
    public mutating func reset() {
        reserved = nil
        requestId = nil
    }
}
