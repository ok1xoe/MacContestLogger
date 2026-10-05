import Foundation

/// One step of logging a QSO, in the order Kotlin performs it. The caller executes them; the
/// pipeline itself touches nothing.
public enum LogEffect: Equatable, Sendable {
    /// Save into the logbook (`logbook.log(qso)` — assigns `uuid`/`id`, the contest and the time).
    case persist
    /// `logRevision++`.
    case bumpRevision
    /// Add the stored QSO to the dupe index.
    case addDupe
    /// Append the stored QSO to the in-memory list of the log table.
    case appendRow
    /// The reserved serial number was used: forget it and reserve the next one (serial server).
    case consumeReservedSerial
    /// Re-read the QSO count (`qsoCount = logbook.count()`).
    case refreshCount
    /// Publish the insert to the cluster (`SyncCoordinator.publishInsert`, off the main thread).
    case publishInsert
    /// Report the QSO to the pile-up simulator (`onLogged`) and refresh its views.
    case simulator
    /// N1MM „Clear RIT after logging": `setRit(0)`.
    case clearRit
    /// Queue the QSO for the Club Log live stream.
    case clubLog
    /// Fire the `QSO_LOGGED` plugins (no-op without plugins for that event).
    case plugin
    /// Send the contact to the N1MM UDP broadcast targets.
    case broadcast
    /// Send the QSO to the WSJT-X logged-ADIF listener.
    case wsjtx
    /// Log the contact into the contest session (`ContestController.log` after `state.log`).
    case contestLog
    /// Status line text — a Czech translation key the UI passes through `tr`.
    case status(String)
}

/// The logging path of a QSO (`AppState.log`, `ui/AppState.kt`, v1.1.1) as a pure function that
/// prepares the QSO and returns the effects in Kotlin order.
public enum QsoLogPipeline {

    /// Status text when no contest is open; the QSO is not saved.
    public static let noActiveContestStatus = "Není aktivní závod — QSO se neuložilo. Založ nebo otevři závod."

    /// What `AppState.log` reads from the application state.
    public struct Context: Sendable {
        /// Active contest of the logbook (`logbook.getActiveContest()`); blank = none.
        public var activeContestId: String?
        /// Current operator (`operatorCall`).
        public var operatorCall: String
        /// DXCC lookup of the contest environment (`contest.dxccLookup`); `nil` = nothing is filled.
        public var dxcc: (any DxccLookup)?
        /// `config.cluster.stationId` when cluster sync runs (`syncCoordinator != nil`), otherwise `nil`.
        public var syncStationId: String?
        /// Serial number reserved at the serial server; `nil` = counting locally.
        public var reservedSerial: Int?
        /// The pile-up simulator is running.
        public var simulatorActive: Bool
        /// Current RIT offset in Hz.
        public var ritHz: Int
        /// `config.isRitClearAfterLog`.
        public var ritClearAfterLog: Bool
        /// `config.clubLog.configured()`.
        public var clubLogConfigured: Bool
        /// The broadcast service runs.
        public var broadcastActive: Bool
        /// The WSJT-X sender runs.
        public var wsjtxActive: Bool
        /// The caller logs into the contest session afterwards (the contest path of the entry window).
        public var logToContest: Bool

        public init(
            activeContestId: String?,
            operatorCall: String,
            dxcc: (any DxccLookup)? = nil,
            syncStationId: String? = nil,
            reservedSerial: Int? = nil,
            simulatorActive: Bool = false,
            ritHz: Int = 0,
            ritClearAfterLog: Bool = false,
            clubLogConfigured: Bool = false,
            broadcastActive: Bool = false,
            wsjtxActive: Bool = false,
            logToContest: Bool = false
        ) {
            self.activeContestId = activeContestId
            self.operatorCall = operatorCall
            self.dxcc = dxcc
            self.syncStationId = syncStationId
            self.reservedSerial = reservedSerial
            self.simulatorActive = simulatorActive
            self.ritHz = ritHz
            self.ritClearAfterLog = ritClearAfterLog
            self.clubLogConfigured = clubLogConfigured
            self.broadcastActive = broadcastActive
            self.wsjtxActive = wsjtxActive
            self.logToContest = logToContest
        }
    }

    /// Prepares the QSO and lists the effects.
    ///
    /// Without an active contest only the status text is returned and the QSO is untouched.
    /// Otherwise the operator is filled when blank (imported QSOs bring their own), the missing
    /// country data is filled, the station id is set when sync runs, and the effects follow:
    /// persist → revision → dupe index → table row → reserved serial → count → cluster publish, then —
    /// only for a QSO that was not imported — simulator, RIT, Club Log, plugins, broadcast, WSJT-X.
    ///
    /// `contestLog` comes last when `context.logToContest` is set — also after a refusal, because the
    /// Kotlin entry window calls `contest.log` right after `state.log` whatever it did (the session is
    /// then normally inactive and ignores it).
    public static func plan(qso: Qso, isImported: Bool, context: Context) -> (Qso, [LogEffect]) {
        guard let contestId = context.activeContestId, !KotlinText.isBlank(contestId) else {
            var refused: [LogEffect] = [.status(noActiveContestStatus)]
            if context.logToContest {
                refused.append(.contestLog)
            }
            return (qso, refused)
        }
        var prepared = qso
        if KotlinText.isBlank(prepared.operator) {
            prepared.operator = context.operatorCall
        }
        if let dxcc = context.dxcc {
            DxccFiller.fill(&prepared, dxcc)
        }
        if let stationId = context.syncStationId {
            prepared.stationId = stationId
        }
        var effects: [LogEffect] = [.persist, .bumpRevision, .addDupe, .appendRow]
        if let reserved = context.reservedSerial, prepared.serialSent == reserved {
            effects.append(.consumeReservedSerial)
        }
        effects.append(.refreshCount)
        if context.syncStationId != nil {
            effects.append(.publishInsert)
        }
        if !isImported {
            effects.append(contentsOf: liveEffects(context))
        }
        if context.logToContest {
            effects.append(.contestLog)
        }
        return (prepared, effects)
    }

    /// Effects only for a QSO logged here (not imported from WSJT-X/N1MM/ADIF).
    private static func liveEffects(_ context: Context) -> [LogEffect] {
        var effects: [LogEffect] = []
        if context.simulatorActive {
            effects.append(.simulator)
        }
        if context.ritHz != 0 && context.ritClearAfterLog {
            effects.append(.clearRit)
        }
        if context.clubLogConfigured {
            effects.append(.clubLog)
        }
        effects.append(.plugin)
        if context.broadcastActive {
            effects.append(.broadcast)
        }
        if context.wsjtxActive {
            effects.append(.wsjtx)
        }
        return effects
    }
}
