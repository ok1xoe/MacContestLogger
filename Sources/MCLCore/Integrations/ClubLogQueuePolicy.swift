import Foundation

/// The decisions of the Club Log live stream (`AppState`, v1.1.1): which QSOs are queued, what the sender does with
/// each outcome and which status it shows. The queue itself (in memory, dropped at quit) and the HTTP call live in
/// the app layer.
public enum ClubLogQueuePolicy {

    /// What the sender does with the record it took from the queue.
    public enum Action: Equatable, Sendable {
        /// Sent — go on with the next one.
        case done
        /// Refused for good (bad login or data) — the record is dropped, no delay.
        case drop
        /// Network trouble — put the record back at the front and wait `delayMs` before the next attempt.
        case retryFront(delayMs: Int)
    }

    /// `clubLogQueue.poll(5, SECONDS)`.
    public static let pollSeconds: Int = 5
    /// `delay(60_000)` after a RETRY.
    public static let retryDelayMs: Int = 60_000
    /// The status before anything was sent (`tr` key).
    public static let idleStatus = "Club Log: zatím nic neodesláno"

    /// `queueClubLog(qso)`: only with the Club Log enabled and filled in (`config.clubLog.configured()`).
    public static func shouldQueue(configured: Bool) -> Bool {
        configured
    }

    /// `cl.callsign.ifBlank { config.station.call }` — the callsign sent to Club Log.
    public static func callsign(configured: String, stationCall: String) -> String {
        KotlinText.isBlank(configured) ? stationCall : configured
    }

    /// The action and status for an upload outcome. `queued` is the number of records still waiting **after** the
    /// sent one was taken from the queue; a RETRY puts it back, so its text counts it (`queued + 1`).
    public static func handle(_ outcome: ClubLogClient.Outcome, queued: Int) -> (action: Action, status: EntryStatus) {
        switch outcome {
        case .OK:
            return (.done, .tr("Club Log: QSO odesláno (ve frontě %s)", .int(queued)))
        case .REJECTED:
            return (.drop, .tr("Club Log odmítl QSO (přihlášení nebo data) — zkontroluj nastavení"))
        case .RETRY:
            return (.retryFront(delayMs: retryDelayMs),
                    .tr("Club Log nedostupný — zkusím znovu (ve frontě %s)", .int(queued + 1)))
        }
    }

    /// The `clublog.log` note for an outcome (`queued` as in `handle`).
    public static func logNote(_ outcome: ClubLogClient.Outcome, queued: Int) -> String {
        switch outcome {
        case .OK: return "sent (queued \(queued))"
        case .REJECTED: return "dropped (rejected)"
        case .RETRY: return "retry in \(retryDelayMs / 1000) s (queued \(queued + 1))"
        }
    }
}
