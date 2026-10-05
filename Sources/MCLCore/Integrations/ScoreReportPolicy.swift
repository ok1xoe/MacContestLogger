import Foundation

/// The decisions of the online score reporting (`AppState.reportScoreIfDue`, v1.1.1) over plain values: when a report
/// is due, who the station is in it and what the outcome of the post means. The XML (`ScoreXml`) and the HTTP post
/// are elsewhere; the app layer feeds this with a snapshot taken on the main actor.
public enum ScoreReportPolicy {

    /// The loop period of the app layer (`delay(60_000)`).
    public static let loopSeconds: Int = 60
    /// The status before anything was posted (`tr` key).
    public static let idleStatus = "Skóre se zatím neodesílalo"

    /// Is a report due now? Enabled or forced, a contest definition exists, and — unless forced — the log changed
    /// since the last accepted report and `minutes` (whole minutes, truncated) passed since the last attempt.
    public static func due(force: Bool, enabled: Bool, hasDefinition: Bool = true, revision: Int64,
                           lastRevision: Int64, now: JavaInstant, lastAt: JavaInstant, minutes: Int) -> Bool {
        if !enabled && !force { return false }
        if !hasDefinition { return false }
        if force { return true }
        if revision == lastRevision { return false }
        return wholeMinutes(from: lastAt, to: now) >= Int64(minutes)
    }

    /// `Duration.between(lastAt, now).toMinutes()`: the seconds between the instants (nanoseconds borrow a second),
    /// divided by 60 truncating toward zero.
    static func wholeMinutes(from lastAt: JavaInstant, to now: JavaInstant) -> Int64 {
        var seconds: Int64 = now.epochSecond - lastAt.epochSecond
        if now.nano < lastAt.nano {
            seconds -= 1
        }
        return seconds / 60
    }

    /// The contest name of the report: the Cabrillo contest name, or the definition id when there is no Cabrillo
    /// block (Kotlin `?:` — an empty name stays empty).
    public static func contestName(cabrilloName: String?, definitionId: String?) -> String? {
        cabrilloName ?? definitionId
    }

    /// The station of the report. `operators` is the contest setup's operators text (blank or missing → the station
    /// call), `category` the setup's category map (missing → empty).
    public static func station(call: String, operators: String?, club: String, cqZone: String, ituZone: String,
                               gridSquare: String, category: [String: String]?) -> ScoreXml.Station {
        let ops: String
        if let operators, !KotlinText.isBlank(operators) {
            ops = operators
        } else {
            ops = call
        }
        return ScoreXml.Station(call: call, ops: ops, club: club, cqZone: cqZone, ituZone: ituZone, grid: gridSquare,
                                category: category ?? [:])
    }

    /// The result of the post.
    public enum PostResult: Equatable, Sendable {
        /// The server answered with this HTTP status.
        case http(Int)
        /// The post failed; the message is the exception message (`nil` prints `null`).
        case failure(String?)
    }

    public struct Outcome: Equatable, Sendable {
        public let status: EntryStatus
        /// 2xx: the log revision is remembered as reported. (The attempt time is remembered whatever the result.)
        public let accepted: Bool
    }

    /// `tr("Skóre %s odesláno %s (HTTP %s)", total, now, code)` for 200…299, `tr("Server vrátil HTTP %s", code)`
    /// otherwise, `tr("Odeslání skóre selhalo: %s", message)` on a failure.
    public static func outcome(_ result: PostResult, total: Int64, now: JavaInstant) -> Outcome {
        switch result {
        case .http(let code) where (200...299).contains(code):
            let status: EntryStatus = .tr("Skóre %s odesláno %s (HTTP %s)", .int(Int(total)), .string(now.toString()),
                                          .int(code))
            return Outcome(status: status, accepted: true)
        case .http(let code):
            return Outcome(status: .tr("Server vrátil HTTP %s", .int(code)), accepted: false)
        case .failure(let message):
            return Outcome(status: .tr("Odeslání skóre selhalo: %s", .string(message)), accepted: false)
        }
    }
}
