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
        /// The full N1MM field set (Swift-only); `nil` = the v1.1.1 packet.
        public var extras: ContactExtras?

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

    /// What N1MM's `contactinfo` carries beyond the v1.1.1 packet: the prefixes, the received exchange split by
    /// meaning, the operator, Run/S&P, the radio and the sent exchange. With it the contact packets use N1MM's whole
    /// tag list in N1MM's order.
    public struct ContactExtras: Equatable, Sendable {
        public var countryPrefix: String = ""
        public var wpxPrefix: String = ""
        public var gridSquare: String = ""
        public var exchange1: String = ""
        public var section: String = ""
        public var comment: String = ""
        public var qth: String = ""
        public var name: String = ""
        public var power: String = ""
        public var zone: String = ""
        public var precedence: String = ""
        public var check: String = ""
        public var `operator`: String = ""
        public var isRunQso: Bool = false
        public var radioNr: Int = 1
        public var sentExchange: String = ""
        /// `false` = a contact another station logged and this one forwards (N1MM „All QSOs").
        public var isOriginal: Bool = true

        public init() {}
    }

    /// What N1MM's `RadioInfo` carries beyond the v1.1.1 packet (Swift-only). With it the packet uses N1MM's whole
    /// tag list in N1MM's order.
    public struct RadioExtras: Equatable, Sendable {
        public var radioNr: Int = 1
        /// The transmit frequency (split); `0` = the receive one.
        public var txFreqHz: Int64 = 0
        public var myCall: String = ""
        /// The antenna code selected (`-1` = none).
        public var antenna: Int = -1
        public var focusRadioNr: Int = 1
        public var activeRadioNr: Int = 1
        public var isStereo: Bool = false
        public var isSplit: Bool = false
        public var isTransmitting: Bool = false
        public var radioName: String = ""
        public var isConnected: Bool = true

        public init() {}
    }

    public struct RadioData: Equatable, Sendable {
        public var stationName: String?
        public var freqHz: Int64
        public var mode: String?
        public var opCall: String?
        public var isRunning: Bool
        /// N1MM `{AUXANTSEL nn}`: the antenna selected by the macro (its code and name), `nil` = none (Swift-only).
        public var auxAntennaCode: Int?
        public var auxAntennaName: String = ""
        /// The full N1MM field set; `nil` = the v1.1.1 packet.
        public var extras: RadioExtras?

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
        /// The class, club, QTH and breakdown of N1MM's `dynamicresults` (Swift-only); `nil` = the v1.1.1 packet.
        public var extras: ScoreExtras?

        public init(contest: String?, call: String?, ops: String?, score: Int64, timestamp: Date?) {
            self.contest = contest
            self.call = call
            self.ops = ops
            self.score = score
            self.timestamp = timestamp
        }
    }

    /// One `<qso>`, `<point>` or `<mult>` row of the score breakdown (`band` like `20` or `total`, `mode` like `CW`
    /// or `ALL`).
    public struct BreakdownRow: Equatable, Sendable {
        public var kind: String
        public var band: String
        public var mode: String
        public var value: Int64

        public init(kind: String, band: String, mode: String, value: Int64) {
            self.kind = kind
            self.band = band
            self.mode = mode
            self.value = value
        }
    }

    /// The parts of N1MM's score packet beyond contest, call, ops, score and time.
    public struct ScoreExtras: Equatable, Sendable {
        /// Cabrillo category values by key (`POWER`, `ASSISTED`, `TRANSMITTER`, `OPERATOR`, `BAND`, `MODE`, `OVERLAY`).
        public var category: [String: String] = [:]
        public var club: String = ""
        public var dxccCountry: String = ""
        public var cqZone: String = ""
        public var iaruZone: String = ""
        public var arrlSection: String = ""
        public var stateProvince: String = ""
        public var grid: String = ""
        public var breakdown: [BreakdownRow] = []

        public init() {}
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
        if let extras = c.extras {
            return fullContact(root, c, extras, oldCall: oldCall, oldTs: oldTs)
        }
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

    /// N1MM's whole `contactinfo` / `contactreplace` / `lookupinfo` tag list in N1MM's order (the N1MM+ UDP
    /// broadcast documentation). Fields MCL does not keep (`misctext`, `RoverLocation`, the network numbers) are
    /// empty tags like N1MM's own when they are unused.
    static func fullContact(_ root: String, _ c: ContactData, _ x: ContactExtras, oldCall: String?,
                            oldTs: Date?) -> String {
        var b = "<" + root + ">"
        b += tag("app", app)
        b += tag("contestname", c.contestName)
        b += tag("contestnr", String(c.contestNr))
        b += tag("timestamp", ts(c.timestamp))
        b += tag("mycall", c.myCall)
        b += tag("band", n1mmBand(c.rxFreqHz))
        b += tag("rxfreq", String(tensOfHz(c.rxFreqHz)))
        b += tag("txfreq", String(tensOfHz(c.txFreqHz)))
        b += tag("operator", x.operator)
        b += tag("mode", c.mode)
        b += tag("call", c.call)
        b += tag("countryprefix", x.countryPrefix)
        b += tag("wpxprefix", x.wpxPrefix)
        b += tag("stationprefix", c.myCall)
        b += tag("continent", c.continent)
        b += tag("snt", c.snt)
        b += tag("sntnr", c.sntNr.map { String($0) })
        b += tag("rcv", c.rcv)
        b += tag("rcvnr", c.rcvNr.map { String($0) })
        b += tag("gridsquare", x.gridSquare)
        b += tag("exchange1", x.exchange1)
        b += tag("section", x.section)
        b += tag("comment", x.comment)
        b += tag("qth", x.qth)
        b += tag("name", x.name)
        b += tag("power", x.power)
        b += tag("misctext", "")
        b += tag("zone", x.zone)
        b += tag("prec", x.precedence)
        b += tag("ck", x.check)
        b += tag("ismultiplier1", c.isMultiplier ? "1" : "0")
        b += tag("ismultiplier2", "0")
        b += tag("ismultiplier3", "0")
        b += tag("points", String(c.points))
        b += tag("radionr", String(x.radioNr))
        b += tag("run1run2", String(x.radioNr))
        b += tag("RoverLocation", "")
        b += tag("RadioInterfaced", "1")
        b += tag("NetworkedCompNr", "0")
        b += tag("IsOriginal", x.isOriginal ? "True" : "False")
        b += tag("NetBiosName", c.stationName)
        b += tag("IsRunQSO", x.isRunQso ? "1" : "0")
        b += tag("StationName", c.stationName)
        b += tag("ID", c.id)
        b += tag("IsClaimedQso", "1")
        if let oldCall {
            b += tag("oldtimestamp", ts(oldTs))
            b += tag("oldcall", oldCall)
        }
        b += tag("SentExchange", x.sentExchange)
        b += "</" + root + ">"
        return b
    }

    /// N1MM `lookupinfo`: the contact's tag list for a call typed but not logged yet (Space/Tab in the call field).
    public static func lookupInfo(_ c: ContactData) -> String {
        fullContact("lookupinfo", c, c.extras ?? ContactExtras(), oldCall: nil, oldTs: nil)
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
        if let extras = r.extras {
            return fullRadioInfo(r, extras)
        }
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
        if let code = r.auxAntennaCode {
            b += tag("AuxAntSelected", String(code))
            b += tag("AuxAntSelectedName", r.auxAntennaName)
        }
        b += "</RadioInfo>"
        return b
    }

    /// N1MM's whole `RadioInfo` tag list in N1MM's order. `FocusEntry`/`EntryWindowHwnd` are Windows handles: `0`.
    static func fullRadioInfo(_ r: RadioData, _ x: RadioExtras) -> String {
        let tx: Int64 = x.txFreqHz > 0 ? x.txFreqHz : r.freqHz
        var b = "<RadioInfo>"
        b += tag("app", app)
        b += tag("StationName", r.stationName)
        b += tag("RadioNr", String(x.radioNr))
        b += tag("Freq", String(tensOfHz(r.freqHz)))
        b += tag("TXFreq", String(tensOfHz(tx)))
        b += tag("Mode", r.mode)
        b += tag("mycall", x.myCall)
        b += tag("OpCall", r.opCall)
        b += tag("IsRunning", r.isRunning ? "True" : "False")
        b += tag("FocusEntry", "0")
        b += tag("EntryWindowHwnd", "0")
        b += tag("Antenna", String(x.antenna))
        b += tag("Rotors", "")
        b += tag("FocusRadioNr", String(x.focusRadioNr))
        b += tag("IsStereo", x.isStereo ? "True" : "False")
        b += tag("IsSplit", x.isSplit ? "True" : "False")
        b += tag("ActiveRadioNr", String(x.activeRadioNr))
        b += tag("IsTransmitting", x.isTransmitting ? "True" : "False")
        b += tag("FunctionKeyCaption", "")
        b += tag("RadioName", x.radioName)
        b += tag("AuxAntSelected", String(r.auxAntennaCode ?? -1))
        b += tag("AuxAntSelectedName", r.auxAntennaName)
        b += tag("IsConnected", x.isConnected ? "True" : "False")
        b += "</RadioInfo>"
        return b
    }

    public static func dynamicResults(_ s: ScoreData) -> String {
        if let extras = s.extras {
            return fullDynamicResults(s, extras)
        }
        var b = "<dynamicresults>"
        b += tag("contest", s.contest)
        b += tag("call", s.call)
        b += tag("ops", s.ops)
        b += tag("score", String(s.score))
        b += tag("timestamp", ts(s.timestamp))
        b += "</dynamicresults>"
        return b
    }

    /// N1MM's score packet with the class, club, QTH and breakdown (one line, no header, like the other packets).
    static func fullDynamicResults(_ s: ScoreData, _ x: ScoreExtras) -> String {
        var b = "<dynamicresults>"
        b += tag("contest", s.contest)
        b += tag("call", s.call)
        b += tag("ops", s.ops)
        b += "<class"
        for (attribute, key) in [("power", "POWER"), ("assisted", "ASSISTED"), ("transmitter", "TRANSMITTER"),
                                 ("ops", "OPERATOR"), ("bands", "BAND"), ("mode", "MODE"), ("overlay", "OVERLAY")] {
            let value: String = esc(x.category[key] ?? "")
            b += " \(attribute)=\"\(value)\""
        }
        b += "></class>"
        b += tag("club", x.club)
        b += "<qth>"
        b += tag("dxcccountry", x.dxccCountry)
        b += tag("cqzone", x.cqZone)
        b += tag("iaruzone", x.iaruZone)
        b += tag("arrlsection", x.arrlSection)
        b += tag("stprvoth", x.stateProvince)
        b += tag("grid6", x.grid)
        b += "</qth>"
        b += "<breakdown>"
        for row in x.breakdown {
            let band: String = esc(row.band)
            let mode: String = esc(row.mode)
            b += "<\(row.kind) band=\"\(band)\" mode=\"\(mode)\">\(row.value)</\(row.kind)>"
        }
        b += "</breakdown>"
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
