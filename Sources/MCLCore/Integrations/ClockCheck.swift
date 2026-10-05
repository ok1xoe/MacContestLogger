import Foundation

/// The decisions of the NTP clock check (`AppState.checkClock`, v1.1.1) over plain numbers and strings — the SNTP
/// query itself stays in the app layer.
public enum ClockCheck {

    /// `SntpClient.query(server, 123, 3000)`.
    public static let port: UInt16 = 123
    public static let timeoutMs: Int = 3000
    /// Re-check every half hour.
    public static let intervalSeconds: Int = 30 * 60
    /// Beyond this offset (ms) the status line warns and the message window gets a line.
    public static let warnThresholdMs: Int64 = 1000

    /// The clock status before the first check (`tr` key).
    public static let neverChecked = "Čas zatím neověřen"

    /// The status when no server is configured.
    public static let disabled: EntryStatus = .tr("Synchronizace času vypnutá")

    /// The server to query: `config.ntpServer.trim()` (Kotlin), `nil` when blank.
    public static func server(_ configured: String) -> String? {
        let trimmed: String = KotlinText.trim(configured)
        return KotlinText.isBlank(trimmed) ? nil : trimmed
    }

    public struct Result: Equatable, Sendable {
        /// The clock status (`Hodiny: odchylka %+.2f s od %s` — the literal part is not translated — plus the
        /// translated `(čas QSO opravován)` when the correction is on).
        public let status: EntryStatus
        /// `|offset| > 1000 ms`: show `warnStatus` and add `status` to the message window.
        public let warn: Bool
        /// The status line text for a large offset: `"⏰ " + status + tr(" — srovnej hodiny počítače")`.
        public let warnStatus: EntryStatus?
        /// The offset for `logbook.setClockOffset`: the measured one with the QSO time correction on, otherwise 0.
        public let applyOffsetMs: Int64
    }

    public static func result(offsetMs: Int64, server: String, correct: Bool) -> Result {
        let head: String = "Hodiny: odchylka " + signedSeconds(offsetMs) + " s od " + server
        var status: EntryStatus = .verbatim(head)
        if correct {
            status = status.appending(.tr(" (čas QSO opravován)"))
        }
        let warn: Bool = JavaMath.abs(offsetMs) > warnThresholdMs
        let warnStatus: EntryStatus? = warn
            ? EntryStatus.verbatim("⏰ ").appending(status).appending(.tr(" — srovnej hodiny počítače"))
            : nil
        return Result(status: status, warn: warn, warnStatus: warnStatus, applyOffsetMs: correct ? offsetMs : 0)
    }

    /// Java `%+.2f` of `offsetMs / 1000.0` (`Locale.US`): an explicit sign, two decimals, rounded half up on the
    /// decimal digits of the double. `JavaFormat` has no `+` flag, so the sign is added to the formatted magnitude
    /// (a negative value that rounds to zero keeps its `-`, as in Java).
    static func signedSeconds(_ offsetMs: Int64) -> String {
        let seconds: Double = Double(offsetMs) / 1000.0
        let magnitude: String = JavaFormat.format("%.2f", .double(Swift.abs(seconds)))
        return (seconds < 0 ? "-" : "+") + magnitude
    }

    /// `tr("NTP %s nedostupný: %s", server, it.message)` — a missing message prints `null`.
    public static func failure(server: String, message: String?) -> EntryStatus {
        .tr("NTP %s nedostupný: %s", .string(server), .string(message))
    }
}
