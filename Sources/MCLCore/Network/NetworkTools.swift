import Foundation

/// What a station tells the others about its setup (N1MM: the computers are warned about a different program version,
/// contest or category). Sent as the text of a `HELLO` message, one `key=value` per line.
public struct StationProfile: Equatable, Sendable {
    public var version: String
    /// The contest (the definition's Cabrillo name, else its id); `""` = no contest open.
    public var contest: String
    /// The Cabrillo operator and transmitter categories, `OPERATOR=MULTI-OP TRANSMITTER=ONE`; `""` = not set.
    public var category: String
    /// This station is the master (N1MM: the master keeps the clocks of the others in sync).
    public var master: Bool

    public init(version: String = "", contest: String = "", category: String = "", master: Bool = false) {
        self.version = version
        self.contest = contest
        self.category = category
        self.master = master
    }

    /// The category text of a contest setup's `OPERATOR` and `TRANSMITTER` (blank and `N/A` values left out).
    public static func categoryText(_ category: [String: String]) -> String {
        var parts: [String] = []
        for key in ["OPERATOR", "TRANSMITTER"] {
            let value: String = KotlinText.trim(category[key] ?? "").uppercased()
            if !value.isEmpty && value != "N/A" {
                parts.append(key + "=" + value)
            }
        }
        return parts.joined(separator: " ")
    }

    /// The `HELLO` text; `request` asks the receivers to answer with their own profile.
    public func encoded(request: Bool) -> String {
        var lines: [String] = ["version=" + version, "contest=" + contest, "category=" + category]
        lines.append("master=" + (master ? "1" : "0"))
        if request {
            lines.append("req=1")
        }
        return lines.joined(separator: "\n")
    }

    /// A received `HELLO` text: the profile and whether an answer is asked for. Unknown lines are ignored.
    public static func decode(_ text: String) -> (profile: StationProfile, request: Bool) {
        var profile = StationProfile()
        var request = false
        for line in text.split(separator: "\n") {
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key: String = String(line[..<equals])
            let value: String = String(line[line.index(after: equals)...])
            switch key {
            case "version": profile.version = value
            case "contest": profile.contest = value
            case "category": profile.category = value
            case "master": profile.master = value == "1"
            case "req": request = value == "1"
            default: break
            }
        }
        return (profile, request)
    }

    /// The differences of another station's profile from this one (N1MM's configuration mismatch warnings); blank
    /// values on either side are not compared.
    public func mismatches(with other: StationProfile, station: String) -> [EntryStatus] {
        var out: [EntryStatus] = []
        if !version.isEmpty, !other.version.isEmpty, version != other.version {
            out.append(.tr(NetworkTools.versionMismatchKey, .string(station), .string(other.version), .string(version)))
        }
        if !contest.isEmpty, !other.contest.isEmpty, contest != other.contest {
            out.append(.tr(NetworkTools.contestMismatchKey, .string(station), .string(other.contest), .string(contest)))
        }
        if !category.isEmpty, !other.category.isEmpty, category != other.category {
            out.append(.tr(NetworkTools.categoryMismatchKey, .string(station), .string(other.category),
                           .string(category)))
        }
        return out
    }
}

/// One line of the Network Status Messages tab (N1MM's message trace): a message sent or received.
public struct NetTraceLine: Equatable, Sendable {
    /// UTC `HH:mm:ss`.
    public let time: String
    public let outgoing: Bool
    public let type: String
    /// The other station (`""` / `*` = all).
    public let peer: String
    public let text: String

    public init(time: String, outgoing: Bool, type: String, peer: String, text: String) {
        self.time = time
        self.outgoing = outgoing
        self.type = type
        self.peer = peer
        self.text = text
    }

    /// `12:34:56 → OP2 CHAT hello` / `12:34:56 ← OP2 PASS DL1ABC`.
    public var row: String {
        let target: String = peer.isEmpty ? "*" : peer
        let body: String = text.replacingOccurrences(of: "\n", with: " ")
        return time + " " + (outgoing ? "→ " : "← ") + target + " " + type + (body.isEmpty ? "" : " " + body)
    }
}

/// The multi-op network tools of N1MM's Network Status window that go beyond chat and PASS: the message trace, the
/// call for help, the configuration check (`HELLO`), the reset of the serial numbers at all stations and the time of
/// the master station. Pure logic; the app sends and receives.
public enum NetworkTools {

    public static let traceCap = 300

    // MARK: - texts

    public static let helpFromKey = "POMOC: stanice %s volá o pomoc"
    public static let helpSentKey = "Volání o pomoc odesláno: %s"
    public static let notConnectedKey = "Síťový deník není připojený"
    public static let versionMismatchKey = "Stanice %s má jinou verzi programu (%s, tato %s)"
    public static let contestMismatchKey = "Stanice %s má otevřený jiný závod (%s, tato %s)"
    public static let categoryMismatchKey = "Stanice %s má jinou kategorii (%s, tato %s)"
    public static let serialResetSentKey = "Pořadová čísla na všech stanicích pokračují od %s"
    public static let serialResetFromKey = "Stanice %s nastavila pořadová čísla: další je %s"
    public static let masterTimeKey = "Čas master stanice %s: odchylka %s s (čas QSO opravován)"
    public static let masterTimeNoMasterKey = "Žádná master stanice v síti"
    public static let everyoneKey = "všem"

    /// UTC `HH:mm:ss` of a moment.
    public static func traceTime(_ date: Date) -> String {
        MacroTime.format(date, "HH:mm:ss")
    }

    /// The trace with a new line (the oldest lines dropped beyond `traceCap`).
    public static func appending(_ trace: [NetTraceLine], _ line: NetTraceLine) -> [NetTraceLine] {
        var out: [NetTraceLine] = trace
        out.append(line)
        if out.count > traceCap {
            out.removeFirst(out.count - traceCap)
        }
        return out
    }

    /// The trace text of a message: its call, frequency and text, whichever it has.
    public static func traceText(_ m: NetMessageWire) -> String {
        var parts: [String] = []
        if let call = m.call, !call.isEmpty {
            parts.append(call)
        }
        if m.freqHz > 0, m.type != NetMessageWire.serialReset, m.type != NetMessageWire.time {
            parts.append(NetMessages.kHz(m.freqHz))
        }
        if let text = m.text, !text.isEmpty {
            parts.append(text)
        }
        return parts.joined(separator: " ")
    }

    // MARK: - serial numbers

    /// The highest serial sent in the log (deleted QSOs skipped), 0 without one.
    public static func maxSentSerial(_ qsos: [Qso]) -> Int {
        qsos.reduce(0) { best, qso in
            qso.deleted ? best : max(best, qso.serialSent ?? 0)
        }
    }

    // MARK: - master time

    /// The offset of this computer's clock from the master's (ms, positive = this clock is behind), NTP-style with
    /// the request's send and receive moments of this clock around the master's reading: `master − (t1 + t4) / 2`.
    public static func masterOffsetMs(sentAtMs t1: Int64, masterMs: Int64, receivedAtMs t4: Int64) -> Int64 {
        masterMs - (t1 + t4) / 2
    }

    /// The master's answer text: `<request id>;<epoch ms>`.
    public static func timeAnswer(requestId: String, masterMs: Int64) -> String {
        requestId + ";" + String(masterMs)
    }

    /// The request id and the master's time of an answer, `nil` for a malformed one.
    public static func parseTimeAnswer(_ text: String) -> (requestId: String, masterMs: Int64)? {
        guard let semicolon = text.lastIndex(of: ";"),
              let ms = Int64(text[text.index(after: semicolon)...]), ms > 0 else { return nil }
        return (String(text[..<semicolon]), ms)
    }

    /// How often a station that takes the time from the master asks again.
    public static let masterTimeIntervalMs: Int64 = 10 * 60 * 1000
    /// An answer later than this is dropped (the network delay makes it useless).
    public static let masterTimeTimeoutMs: Int64 = 5_000

    /// `+0.25` seconds of an offset in ms (`ClockCheck`'s format).
    public static func seconds(_ offsetMs: Int64) -> String {
        ClockCheck.signedSeconds(offsetMs)
    }
}
