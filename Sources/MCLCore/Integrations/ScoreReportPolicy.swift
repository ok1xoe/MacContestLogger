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
        /// A non-2xx answer with the reason the server gave in the body.
        case rejected(Int, detail: String)
        /// The post failed; the message is the exception message (`nil` prints `null`).
        case failure(String?)
        /// The server could not be reached (connection refused, unknown host); the host is shown.
        case unreachable(host: String)
        /// The connection or the request timed out; the host is shown.
        case timedOut(host: String)
        /// The posting URL is not a valid address.
        case invalidAddress
    }

    /// Longest reason taken from a rejection body.
    public static let maxDetailLength = 80

    /// The first line of a short plain-text body, trimmed and capped at `maxDetailLength`; `nil` for an empty body or
    /// one that looks like HTML (an error page).
    public static func detail(fromBody body: String) -> String? {
        guard !body.contains("<"), !body.contains("\0") else { return nil }
        let line: Substring = body.split(whereSeparator: \.isNewline).first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
        let text: String = line.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return text.count > maxDetailLength ? String(text.prefix(maxDetailLength)) + "…" : text
    }

    /// Maps a failed post to a result with a readable text: unreachable / timeout / invalid address get their own
    /// Czech texts, anything else keeps the exception message.
    public static func result(failure error: JavaHttpError, url: String) -> PostResult {
        let host: String = URL(string: url)?.host ?? url
        switch error {
        case .illegalArgument:
            return .invalidAddress
        case .io(let io):
            switch io.javaClass {
            case "java.net.ConnectException", "java.net.UnknownHostException", "java.nio.channels.UnresolvedAddressException":
                return .unreachable(host: host)
            case "java.net.http.HttpTimeoutException", "java.net.http.HttpConnectTimeoutException":
                return .timedOut(host: host)
            default:
                return .failure(io.message)
            }
        }
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
        case .rejected(let code, let detail):
            return Outcome(status: .tr("Server vrátil HTTP %s: %s", .int(code), .string(detail)), accepted: false)
        case .failure(let message):
            return Outcome(status: .tr("Odeslání skóre selhalo: %s", .string(message)), accepted: false)
        case .unreachable(let host):
            return Outcome(status: .tr("Odeslání skóre selhalo: server nedostupný (%s)", .string(host)), accepted: false)
        case .timedOut(let host):
            return Outcome(status: .tr("Odeslání skóre selhalo: vypršel čas (%s)", .string(host)), accepted: false)
        case .invalidAddress:
            return Outcome(status: .tr("Odeslání skóre selhalo: neplatná adresa"), accepted: false)
        }
    }
}
