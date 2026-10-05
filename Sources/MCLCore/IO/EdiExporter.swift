import Foundation

/// Export of a VHF log to EDI (REG1TEST, IARU Region 1 — N1MM/DXLog "EDI export"): one file
/// per band, points = km between locators, new big squares and countries, the farthest QSO (ODX).
/// Port of `io/EdiExporter.java` (Java v1.1.1) including its quirks:
/// - an invalid locator (`XX00`) gives 0 points but **counts** as a new square (`CWWLs`);
/// - own locator = 1 point (`max(1, ceil(0))`); dupe and X-QSO 0 points;
/// - a number in the exchange of more than 4 digits stays without zero padding (`12345`), other text verbatim.
///
/// The output is a `String`; the file encoding is up to the caller. Java writes
/// `ISO_8859_1` and with `š č ř ž ů ě` in the header **silently writes nothing** — the app layer deals with that.
///
/// Java `null` in `dxccName` is `""` here: Java would count `""` as a country
/// (`CDXCs`), Swift does not — Java never gets `""` from the app (the resolver fills `null`).
/// `%03d` is locale-independent (Java without a locale would write `٠٠١` in `ar_EG`).
public enum EdiExporter {

    /// Header values that neither the definition nor the station know (section, power, antenna…).
    /// `nil` = Java `null` (written empty).
    public struct Header: Equatable, Sendable {
        public var section: String?
        public var power: String?
        public var antenna: String?
        public var operators: String?
        public var remarks: String?

        public init(section: String?, power: String?, antenna: String?, operators: String?, remarks: String?) {
            self.section = section
            self.power = power
            self.antenna = antenna
            self.operators = operators
            self.remarks = remarks
        }
    }

    /// EDI band name (`144 MHz`).
    public static func bandName(_ band: Band) -> String {
        switch band {
        case .m6: return "50 MHz"
        case .m2: return "144 MHz"
        case .cm70: return "432 MHz"
        // Post-port microwave bands: the REG1TEST `PBand` spelling (decimal comma, GHz).
        case .cm23: return "1,3 GHz"
        case .cm13: return "2,3 GHz"
        case .cm9: return "3,4 GHz"
        case .cm6: return "5,7 GHz"
        case .cm3: return "10 GHz"
        default: return JavaFormat.format("%d MHz", .int(band.lowHz / 1_000_000))
        }
    }

    /// EDI mode code: 1 SSB, 2 CW, 5 AM, 6 FM, 7 RTTY, 0 other.
    static func modeCode(_ m: Mode?) -> Int {
        switch m {
        case .ssb: return 1
        case .cw: return 2
        case .am: return 5
        case .fm: return 6
        case .rtty: return 7
        default: return 0
        }
    }

    /// - Parameters:
    ///   - receivedFields: received fields for the callsign (token order of the stored exchange); an error
    ///     propagates out (Java `Function` lets the exception through)
    ///   - sentLocator: my locator (6 characters)
    public static func export(_ def: ContestDefinition, _ station: StationConfig, _ header: Header, _ qsos: [Qso],
                              _ band: Band, _ sentLocator: String?,
                              _ receivedFields: (String) throws -> [ContestDefinition.ExchangeField]) rethrows
        -> String {
        let log = sortedLog(qsos, band)
        var records: [String] = []
        var seenCalls: Set<JavaStringKey> = []
        var wwls: Set<[UInt16]> = []
        var dxccs: Set<JavaStringKey> = []
        var points: Int64 = 0
        var valid = 0
        var odxCall = ""
        var odxLoc = ""
        var odxKm: Int64 = -1
        for q in log {
            let active = try receivedFields(q.call)
            let ex = fields(q, active)
            let loc = (ex[.LOCATOR] ?? "").uppercased()
            let rcvdNr = receivedNumber(q, ex[.SERIAL] ?? "")
            let sentNr = q.serialSent.map { JavaFormat.format("%03d", .int($0)) } ?? ""
            let firstCall = seenCalls.insert(JavaStringKey(q.call.uppercased())).inserted
            let dupe = !firstCall || q.xqso
            let km = Maidenhead.distanceKm(sentLocator, loc)
            let pts: Int64 = dupe || km < 0 ? 0 : max(1, javaLong(km.rounded(.up)))
            let locUnits = Array(loc.utf16)
            let newWwl = !dupe && locUnits.count >= 4 && wwls.insert(Array(locUnits[0..<4])).inserted
            let newDxcc = !dupe && !q.dxccName.isEmpty && dxccs.insert(JavaStringKey(q.dxccName)).inserted
            if !dupe {
                points += pts
                valid += 1
                // `km > odxKm` compares a double with a long converted to double.
                if km > Double(odxKm) {
                    odxKm = JavaMath.round(km)
                    odxCall = q.call
                    odxLoc = loc
                }
            }
            records.append(record(q, loc: loc, sentNr: sentNr, rcvdNr: rcvdNr, pts: pts,
                                  flags: (newWwl, newDxcc, dupe)))
        }
        let my = station.call.uppercased()
        var out = "[REG1TEST;1]\r\n"
        line(&out, "TName", def.metadata == nil ? def.id : def.metadata?.name)
        let first = log.first?.timestampUtc.map(yyyymmdd) ?? ""
        let last = log.last?.timestampUtc.map(yyyymmdd) ?? ""
        line(&out, "TDate", first + ";" + last)
        line(&out, "PCall", my)
        line(&out, "PWWLo", sentLocator?.uppercased() ?? "")
        line(&out, "PExch", "")
        line(&out, "PAdr1", station.address1)
        line(&out, "PAdr2", station.address2)
        line(&out, "PSect", header.section)
        line(&out, "PBand", bandName(band))
        line(&out, "PClub", station.club)
        line(&out, "RName", station.name)
        line(&out, "RCall", my)
        line(&out, "RAdr1", station.address1)
        line(&out, "RCity", station.city)
        line(&out, "RCoun", station.country)
        line(&out, "RHBBS", station.email)
        line(&out, "MOpe1", header.operators)
        line(&out, "SPowe", header.power)
        line(&out, "SAnte", header.antenna)
        line(&out, "CQSOs", String(valid) + ";1")
        line(&out, "CQSOP", String(points))
        line(&out, "CWWLs", String(wwls.count) + ";0;1")
        line(&out, "CWWLB", "0")
        line(&out, "CExcs", "0;0;1")
        line(&out, "CExcB", "0")
        line(&out, "CDXCs", String(dxccs.count) + ";0;1")
        line(&out, "CDXCB", "0")
        line(&out, "CToSc", String(points))
        line(&out, "CODXC", odxKm < 0 ? "" : odxCall.uppercased() + ";" + odxLoc + ";" + String(odxKm))
        out += "[Remarks]\r\n"
        if let remarks = header.remarks, !JavaText.isBlank(remarks) {
            out += JavaText.trim(remarks) + "\r\n"
        }
        out += "[QSORecords;" + String(records.count) + "]\r\n"
        for r in records {
            out += r + "\r\n"
        }
        return out
    }

    /// Non-deleted QSOs of the band with a time, sorted stably by time.
    private static func sortedLog(_ qsos: [Qso], _ band: Band) -> [Qso] {
        var timed: [(offset: Int, time: Date, qso: Qso)] = []
        for (offset, q) in qsos.enumerated() where !q.deleted && q.band == band {
            if let t = q.timestampUtc { timed.append((offset, t, q)) }
        }
        timed.sort { a, b in a.time != b.time ? a.time < b.time : a.offset < b.offset }
        return timed.map(\.qso)
    }

    /// `serialRcvd` as `%03d`; otherwise the number from the exchange when it is 1–4 ASCII digits
    /// (`\d{1,4}`, `Integer.parseInt`), otherwise the exchange text verbatim.
    private static func receivedNumber(_ q: Qso, _ exNr: String) -> String {
        if let serial = q.serialRcvd {
            return JavaFormat.format("%03d", .int(serial))
        }
        let units = Array(exNr.utf16)
        let digits = !units.isEmpty && units.count <= 4 && units.allSatisfy { $0 >= 0x30 && $0 <= 0x39 }
        guard digits, let value = Int(exNr) else { return exNr }
        return JavaFormat.format("%03d", .int(value))
    }

    private static func record(_ q: Qso, loc: String, sentNr: String, rcvdNr: String, pts: Int64,
                               flags: (newWwl: Bool, newDxcc: Bool, dupe: Bool)) -> String {
        // `getTimestampUtc()` is always set here (filter `sortedLog`); outside the `UtcStamp` range
        // (unreachable) date and time stay empty.
        let stamp: UtcStamp? = q.timestampUtc.flatMap { UtcStamp($0) }
        let date: String = stamp.map { $0.yy + $0.MM + $0.dd } ?? ""
        let time: String = stamp.map { $0.HH + $0.mm } ?? ""
        let parts: [String] = [
            date, time, q.call.uppercased(), String(modeCode(q.mode)),
            JavaText.trim(q.rstSent), sentNr, JavaText.trim(q.rstRcvd), rcvdNr, "", loc, String(pts), "",
            flags.newWwl ? "N" : "", flags.newDxcc ? "N" : "", flags.dupe ? "D" : "",
        ]
        return parts.joined(separator: ";")
    }

    private static func yyyymmdd(_ date: Date) -> String {
        guard let s = UtcStamp(date) else { return "" }
        return s.yyyy + s.MM + s.dd
    }

    /// Java `(long) d` for finite `d` (truncation, saturation at the `long` bounds).
    private static func javaLong(_ d: Double) -> Int64 {
        if d >= 9.223372036854775807e18 { return Int64.max }
        if d <= -9.223372036854775808e18 { return Int64.min }
        return Int64(d)
    }

    /// Values of the received exchange by field type (`LOCATOR`, `SERIAL`…): token `i` belongs to field `i`,
    /// the first occurrence of a type wins; without a `LOCATOR` field the **last** token is taken that is
    /// a valid locator and has at least 6 UTF-16 units.
    static func fields(_ q: Qso, _ fields: [ContestDefinition.ExchangeField])
        -> [ContestDefinition.FieldType: String] {
        var out: [ContestDefinition.FieldType: String] = [:]
        let flat = JavaText.trim(q.exchangeRcvd)
        let t: [String] = flat.isEmpty ? [] : ImportedExchange.splitOnJavaSpace(flat)
        var i = 0
        while i < fields.count && i < t.count {
            if let type = fields[i].type, out[type] == nil {
                out[type] = t[i]
            }
            i += 1
        }
        if out[.LOCATOR] == nil {
            for tok in t where Maidenhead.centerLatLon(tok) != nil && tok.utf16.count >= 6 {
                out[.LOCATOR] = tok
            }
        }
        return out
    }

    private static func line(_ out: inout String, _ key: String, _ value: String?) {
        out += key + "=" + (value ?? "") + "\r\n"
    }
}
