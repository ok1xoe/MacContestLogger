/// Canonical state `null` (MQTT payload `null`) — Java `SyncCoordinator.onState(null)` fails with
/// `NullPointerException` (Paho swallows it and drops the message).
public struct SyncNullStateError: Error, Equatable, Sendable {
    public init() {}
}

/// Connects the station's read model (`LogbookService`) with the network transport (`SyncTransport`) — Java
/// `cluster.SyncCoordinator`. A received canonical state is merged into the local replica by `uuid` (LWW by
/// `version`, tombstone → `markDeleted`); local writes/edits/deletes are published as commands. The network is purely
/// propagation — dupe/multiplier/score are always computed from the local logbook (local-first).
///
/// `onChange` is called after each applied remote state (the UI then redraws the list) on the transport thread;
/// hopping to the main thread is up to the caller, as in Kotlin. Access to `LogbookService`
/// from the transport thread is the same as in Java — concurrency with the main thread is guarded by the caller.
public final class SyncCoordinator: @unchecked Sendable {

    /// Runs `body` with the logbook service (Kotlin passes the service itself). The app hands in a call that takes the
    /// database handle's exclusive access, so a state arriving on the transport thread never touches the connection
    /// beside a job of the handle's queue.
    public typealias LogbookAccess = @Sendable (_ body: (LogbookService) throws -> Void) throws -> Void

    private let access: LogbookAccess
    private let transport: SyncTransport
    private let stationId: String
    private let onChange: @Sendable () -> Void

    public init(logbook: LogbookService, transport: SyncTransport, stationId: String,
                onChange: (@Sendable () -> Void)?) {
        nonisolated(unsafe) let service: LogbookService = logbook
        self.access = { body in try body(service) }
        self.transport = transport
        self.stationId = stationId
        self.onChange = onChange ?? {}
    }

    /// The logbook is reached through `access` (see `LogbookAccess`) instead of being held directly.
    public init(access: @escaping LogbookAccess, transport: SyncTransport, stationId: String,
                onChange: (@Sendable () -> Void)?) {
        self.access = access
        self.transport = transport
        self.stationId = stationId
        self.onChange = onChange ?? {}
    }

    /// Registers the state subscription and connects (triggers retained replay = bootstrap).
    public func start() throws {
        try transport.subscribeState { [self] state in
            try self.onState(state)
        }
        try transport.connect()
    }

    /// Applies an incoming canonical state to the replica (LWW; tombstone → `markDeleted`). A state without `uuid` is not found on
    /// delete (Java `uuid=NULL`), on insert `upsertByUuid` fails.
    func onState(_ state: QsoState?) throws {
        guard let state else { throw SyncNullStateError() }
        try access { logbook in
            try apply(state, to: logbook)
        }
        onChange()
    }

    private func apply(_ state: QsoState, to logbook: LogbookService) throws {
        if state.deleted {
            if let uuid = state.uuid {
                try logbook.markDeleted(uuid: uuid, version: state.version, updatedAtUtc: state.updatedAtUtc?.date)
            }
        } else {
            var qso: Qso = WireMapper.toQso(state)
            qso.contestId = try Self.filingContest(logbook)
            if state.qso?.call == nil {
                try rejectNullCall(qso, logbook)
            }
            try logbook.upsertByUuid(qso)
        }
    }

    /// The contest an incoming state is filed under: the logbook's active contest. In free logging (none) it is
    /// the last opened contest (`meta.last_contest_id`), as when Kotlin's logbook kept its contest after
    /// „Žádný": the cluster's QSOs never land in the free-logging log.
    static func filingContest(_ logbook: LogbookService) throws -> String {
        if !logbook.activeContestId.isEmpty {
            return logbook.activeContestId
        }
        return try logbook.repository.metaGet("last_contest_id") ?? ""
    }

    /// A state without a callsign (`qso == null` or `call == null`) is not written by the Java logbook: `upsertByUuid` binds
    /// `call` as SQL `NULL` and the column is `NOT NULL` → `LogbookException` with the text `insert` ("Nelze uložit
    /// QSO") or `update` ("Nelze aktualizovat QSO"); the cause (`SQLException`) `LogbookError` does not carry. The Swift
    /// `Qso` has an empty text instead of `null` (a deliberate divergence from Java v1.1.1), so we report the Java error here — only
    /// when `upsertByUuid` would really write (a new `uuid`, or a higher `version`); an older version is
    /// dropped in Java without an error.
    private func rejectNullCall(_ qso: Qso, _ logbook: LogbookService) throws {
        guard !JavaText.isBlank(qso.uuid) else { return } // upsertByUuid throws its own error
        guard let existing = try logbook.repository.findByUuid(qso.uuid) else {
            throw LogbookError("Nelze uložit QSO")
        }
        if qso.version > existing.version {
            throw LogbookError("Nelze aktualizovat QSO")
        }
    }

    public func publishInsert(_ qso: Qso) throws {
        try transport.publishInsert(WireMapper.toInsertCommand(stationId, qso))
    }

    public func publishUpdate(_ qso: Qso) throws {
        try transport.publishUpdate(WireMapper.toInsertCommand(stationId, qso))
    }

    public func publishDelete(_ qso: Qso) throws {
        try transport.publishDelete(WireMapper.toDeleteCommand(stationId, qso))
    }

    /// Telnet sharing (N1MM Multi-User): incoming spots of other stations are passed to `onSpot` (own ones and `nil` are ignored).
    public func shareSpots(_ onSpot: @escaping @Sendable (SpotWire) throws -> Void) {
        let me: String = stationId
        transport.subscribeSpots { spot in
            if let spot, !JavaText.equals(me, spot.stationId) {
                try onSpot(spot)
            }
        }
    }

    /// Sends a spot from my DX cluster to the other stations — only when the transport is connected.
    public func publishSpot(spotter: String?, freqHz: Int, dxCall: String?, comment: String?) throws {
        if transport.isConnected {
            try transport.publishSpot(SpotWire(stationId: stationId, spotter: spotter, freqHz: freqHz, dxCall: dxCall,
                                               comment: comment))
        }
    }

    public var isConnected: Bool {
        transport.isConnected
    }

    /// Disconnects the transport (releases the MQTT client).
    public func close() {
        transport.close()
    }
}
