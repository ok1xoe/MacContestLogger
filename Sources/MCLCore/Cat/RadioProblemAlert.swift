import Foundation

/// N1MM band map „Transceiver timeout" / „Radio Problem": when the rig has had no contact for the configured number
/// of seconds after its connection was lost, the band map shows an alert with a „Reset Radio" button. Pure; the
/// time comes from the caller.
public enum RadioProblemAlert {

    /// Seconds from `now` until the alert is due for a rig whose last contact was at `lastContact`; `nil` = never
    /// (the timeout 0 turns the alert off, as in N1MM).
    public static func delay(timeoutSeconds: Int, lastContact: Date, now: Date) -> TimeInterval? {
        guard timeoutSeconds > 0 else { return nil }
        return max(0, lastContact.addingTimeInterval(TimeInterval(timeoutSeconds)).timeIntervalSince(now))
    }

    /// The alert shows: the connection was lost (not closed on purpose), the rig is not connected again and the
    /// timeout has passed since the last contact.
    public static func isDue(lost: Bool, connected: Bool, timeoutSeconds: Int, lastContact: Date, now: Date) -> Bool {
        guard lost, !connected, let wait = delay(timeoutSeconds: timeoutSeconds, lastContact: lastContact, now: now)
        else { return false }
        return wait <= 0
    }
}
