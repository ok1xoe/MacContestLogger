import Foundation

/// Builds N1MM UDP XML datagrams. Port of Java `broadcast/BroadcastXml`: no I/O, no XML header
/// and no indentation; frequency in tens of Hz (`freqHz / 10`, division truncating toward zero).
///
/// Java `null` (strings, `Integer`, `Instant`) gives an empty tag `<x></x>`. Time
/// `yyyy-MM-dd HH:mm:ss` in UTC (era year as in `java.time`: 12026 → `+12026`, year −1 → `0002`).
public enum BroadcastXml {

    public static let app = "MacContestLogger"

    public struct ContactData: Equatable, Sendable {
        public var contestName: String?
        public var contestNr: Int32
        public var timestamp: Date?
        public var myCall: String?
        public var rxFreqHz: Int64
        public var txFreqHz: Int64
        public var mode: String?
        public var call: String?
        public var continent: String?
        public var snt: String?
        public var sntNr: Int32?
        public var rcv: String?
        public var rcvNr: Int32?
        public var points: Int32
        public var isMultiplier: Bool
        public var id: String?
        public var stationName: String?

        public init(contestName: String?, contestNr: Int32, timestamp: Date?, myCall: String?,
                    rxFreqHz: Int64, txFreqHz: Int64, mode: String?, call: String?, continent: String?,
                    snt: String?, sntNr: Int32?, rcv: String?, rcvNr: Int32?, points: Int32,
                    isMultiplier: Bool, id: String?, stationName: String?) {
            self.contestName = contestName
            self.contestNr = contestNr
            self.timestamp = timestamp
            self.myCall = myCall
            self.rxFreqHz = rxFreqHz
            self.txFreqHz = txFreqHz
            self.mode = mode
            self.call = call
            self.continent = continent
            self.snt = snt
            self.sntNr = sntNr
            self.rcv = rcv
            self.rcvNr = rcvNr
            self.points = points
            self.isMultiplier = isMultiplier
            self.id = id
            self.stationName = stationName
        }
    }

    public struct RadioData: Equatable, Sendable {
        public var stationName: String?
        public var freqHz: Int64
        public var mode: String?
        public var opCall: String?
        public var isRunning: Bool

        public init(stationName: String?, freqHz: Int64, mode: String?, opCall: String?, isRunning: Bool) {
            self.stationName = stationName
            self.freqHz = freqHz
            self.mode = mode
            self.opCall = opCall
            self.isRunning = isRunning
        }
    }

    public struct ScoreData: Equatable, Sendable {
        public var contest: String?
        public var call: String?
        public var ops: String?
        public var score: Int64
        public var timestamp: Date?

        public init(contest: String?, call: String?, ops: String?, score: Int64, timestamp: Date?) {
            self.contest = contest
            self.call = call
            self.ops = ops
            self.score = score
            self.timestamp = timestamp
        }
    }

    public struct AppInfoData: Equatable, Sendable {
        public var dbName: String?
        public var contestNr: Int32
        public var contestName: String?
        public var stationName: String?
        public var myCall: String?

        public init(dbName: String?, contestNr: Int32, contestName: String?, stationName: String?, myCall: String?) {
            self.dbName = dbName
            self.contestNr = contestNr
            self.contestName = contestName
            self.stationName = stationName
            self.myCall = myCall
        }
    }

    public static func contactInfo(_ c: ContactData) -> String {
        contact("contactinfo", c, oldCall: nil, oldTs: nil)
    }

    public static func contactReplace(_ c: ContactData, oldCall: String?, oldTs: Date?) -> String {
        contact("contactreplace", c, oldCall: oldCall, oldTs: oldTs)
    }

    private static func contact(_ root: String, _ c: ContactData, oldCall: String?, oldTs: Date?) -> String {
        var b = "<" + root + ">"
        b += tag("app", app)
        b += tag("contestname", c.contestName)
        b += tag("contestnr", String(c.contestNr))
        b += tag("timestamp", ts(c.timestamp))
        b += tag("mycall", c.myCall)
        b += tag("band", n1mmBand(c.rxFreqHz))
        b += tag("rxfreq", String(tensOfHz(c.rxFreqHz)))
        b += tag("txfreq", String(tensOfHz(c.txFreqHz)))
        b += tag("mode", c.mode)
        b += tag("call", c.call)
        b += tag("countryprefix", "")
        b += tag("wpxprefix", "")
        b += tag("stationprefix", c.myCall)
        b += tag("continent", c.continent)
        b += tag("snt", c.snt)
        b += tag("sntnr", c.sntNr.map { String($0) })
        b += tag("rcv", c.rcv)
        b += tag("rcvnr", c.rcvNr.map { String($0) })
        b += tag("points", String(c.points))
        b += tag("ismultiplier1", c.isMultiplier ? "1" : "0")
        b += tag("ismultiplier2", "0")
        b += tag("ismultiplier3", "0")
        b += tag("ID", c.id)
        b += tag("IsOriginal", "True")
        b += tag("IsClaimedQso", "1")
        b += tag("StationName", c.stationName)
        if let oldCall {
            b += tag("oldcall", oldCall)
            b += tag("oldtimestamp", ts(oldTs))
        }
        b += "</" + root + ">"
        return b
    }

    public static func contactDelete(_ c: ContactData) -> String {
        var b = "<contactdelete>"
        b += tag("app", app)
        b += tag("timestamp", ts(c.timestamp))
        b += tag("mycall", c.myCall)
        b += tag("band", n1mmBand(c.rxFreqHz))
        b += tag("call", c.call)
        b += tag("contestnr", String(c.contestNr))
        b += tag("StationName", c.stationName)
        b += tag("ID", c.id)
        b += "</contactdelete>"
        return b
    }

    public static func radioInfo(_ r: RadioData) -> String {
        let freq = String(tensOfHz(r.freqHz))
        var b = "<RadioInfo>"
        b += tag("app", app)
        b += tag("StationName", r.stationName)
        b += tag("RadioNr", "1")
        b += tag("Freq", freq)
        b += tag("TXFreq", freq)
        b += tag("Mode", r.mode)
        b += tag("OpCall", r.opCall)
        b += tag("IsRunning", r.isRunning ? "True" : "False")
        b += tag("FocusRadioNr", "1")
        b += tag("ActiveRadioNr", "1")
        b += tag("IsTransmitting", "False")
        b += tag("IsStereo", "False")
        b += tag("IsSplit", "False")
        b += "</RadioInfo>"
        return b
    }

    public static func dynamicResults(_ s: ScoreData) -> String {
        var b = "<dynamicresults>"
        b += tag("contest", s.contest)
        b += tag("call", s.call)
        b += tag("ops", s.ops)
        b += tag("score", String(s.score))
        b += tag("timestamp", ts(s.timestamp))
        b += "</dynamicresults>"
        return b
    }

    public static func appInfo(_ a: AppInfoData) -> String {
        var b = "<AppInfo>"
        b += tag("app", app)
        b += tag("dbname", a.dbName)
        b += tag("contestnr", String(a.contestNr))
        b += tag("contestname", a.contestName)
        b += tag("StationName", a.stationName)
        b += tag("mycall", a.myCall)
        b += "</AppInfo>"
        return b
    }

    /// Java `freqHz / 10` (truncation toward zero: −15 → −1).
    static func tensOfHz(_ freqHz: Int64) -> Int64 {
        freqHz / 10
    }

    /// `DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss").withZone(UTC)`; `null` → `""`.
    static func ts(_ instant: Date?) -> String {
        guard let instant else { return "" }
        return formatUtc(instant)
    }

    /// `yyyy-MM-dd HH:mm:ss` in UTC like `java.time` (shared by `ScoreXml`). An instant outside the
    /// `Int64` seconds range (Java cannot represent such an `Instant`) gives empty text.
    static func formatUtc(_ instant: Date) -> String {
        guard let parts = JavaLocalDate.split(instant) else { return "" }
        let date = JavaLocalDate.civil(epochDay: parts.epochDay)
        let second = parts.secondOfDay
        var s = JavaLocalDate.formatYearOfEra(date.year)
        s += "-" + JavaLocalDate.twoDigits(date.month)
        s += "-" + JavaLocalDate.twoDigits(date.day)
        s += " " + JavaLocalDate.twoDigits(second / 3600)
        s += ":" + JavaLocalDate.twoDigits(second / 60 % 60)
        s += ":" + JavaLocalDate.twoDigits(second % 60)
        return s
    }

    /// N1MM band designation from a frequency (Java `double` MHz), e.g. `"3.5"`, `"14"`; otherwise `""`.
    static func n1mmBand(_ freqHz: Int64) -> String {
        let mhz = Double(freqHz) / 1_000_000.0
        for (low, high, name) in bandTable where mhz >= low && mhz < high {
            return name
        }
        return ""
    }

    private static let bandTable: [(Double, Double, String)] = [
        (1.8, 2.0, "1.8"), (3.5, 4.0, "3.5"), (7.0, 7.3, "7"), (10.1, 10.15, "10"),
        (14.0, 14.35, "14"), (18.0, 18.2, "18"), (21.0, 21.45, "21"), (24.8, 25.0, "24"),
        (28.0, 29.7, "28"), (50.0, 54.0, "50"), (144.0, 148.0, "144"),
    ]

    private static func tag(_ name: String, _ value: String?) -> String {
        // In steps: the older compiler in CI (Xcode 16) cannot type-check a long `+` chain in time.
        let escaped: String = esc(value ?? "")
        return "<\(name)>\(escaped)</\(name)>"
    }

    /// Java `BroadcastXml.esc`: `& < > " '` (including the apostrophe — unlike `ScoreXml.esc`).
    static func esc(_ s: String?) -> String {
        guard let s, !s.isEmpty else { return "" }
        var b = ""
        b.reserveCapacity(s.utf8.count)
        for scalar in s.unicodeScalars {
            switch scalar {
            case "&": b += "&amp;"
            case "<": b += "&lt;"
            case ">": b += "&gt;"
            case "\"": b += "&quot;"
            case "'": b += "&apos;"
            default: b.unicodeScalars.append(scalar)
            }
        }
        return b
    }
}
