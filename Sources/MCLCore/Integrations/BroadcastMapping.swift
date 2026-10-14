import Foundation

/// The mapping of the application state to the N1MM broadcast records (`AppState.contactData`, `radioData`,
/// `scoreData`, `appInfoData`, v1.1.1) — pure functions over plain values, no service and no socket.
public enum BroadcastMapping {

    /// `(System.currentTimeMillis() and 0x7fffffff).toInt()` — the stable session number of N1MM `contestnr`.
    public static func contestNr(nowMs: Int64) -> Int32 {
        Int32(nowMs & 0x7fff_ffff)
    }

    /// `contactData(qso)`. `contestName` is `contest.activeName() ?: ""`.
    public static func contactData(_ qso: Qso, contestName: String?, contestNr: Int32, stationCall: String)
        -> BroadcastXml.ContactData {
        BroadcastXml.ContactData(
            contestName: contestName ?? "", contestNr: contestNr, timestamp: qso.timestampUtc, myCall: stationCall,
            rxFreqHz: Int64(qso.freqHz), txFreqHz: Int64(qso.freqHz), mode: qso.mode?.rawValue ?? "", call: qso.call,
            continent: qso.continent, snt: qso.rstSent, sntNr: qso.serialSent.map { Int32(truncatingIfNeeded: $0) },
            rcv: qso.rstRcvd, rcvNr: qso.serialRcvd.map { Int32(truncatingIfNeeded: $0) },
            points: Int32(truncatingIfNeeded: qso.points), isMultiplier: qso.multiplier, id: qso.uuid,
            stationName: stationCall)
    }

    /// The arguments of `sendContactReplace(contactData(qso), qso.call, qso.timestampUtc)`.
    public struct Replace: Equatable, Sendable {
        public let data: BroadcastXml.ContactData
        public let oldCall: String
        public let oldTimestamp: Date?
    }

    /// The replace of an edit: the **edited** QSO fills the contact fields, the QSO **as it was before the edit** gives
    /// `oldcall` and `oldtimestamp`, so a subscriber that looks the contact up by them (N1MM) finds the original.
    /// Deliberate divergence from Kotlin (`AppState.update`, `AS:2815-2817`), which passed the edited QSO's own call and
    /// time as the old ones (former); for an edit that changes neither the two behaviours coincide.
    public static func replace(old: Qso, new: Qso, contestName: String?, contestNr: Int32,
                               stationCall: String) -> Replace {
        Replace(data: contactData(new, contestName: contestName, contestNr: contestNr, stationCall: stationCall),
                oldCall: old.call, oldTimestamp: old.timestampUtc)
    }

    /// `radioData()`: nothing while the radio is not connected or reports no state.
    public static func radioData(stationCall: String, catConnected: Bool, rig: RigState?, operatorCall: String,
                                 runMode: RunMode, auxAntenna: AntennaEntry? = nil) -> BroadcastXml.RadioData? {
        guard catConnected, let rig else { return nil }
        var data = BroadcastXml.RadioData(stationName: stationCall, freqHz: rig.freqHz, mode: rig.mode?.rawValue ?? "",
                                          opCall: operatorCall, isRunning: runMode == .run)
        data.auxAntennaCode = auxAntenna?.code
        data.auxAntennaName = auxAntenna?.name ?? ""
        return data
    }

    /// `scoreData()`: nothing outside a contest or before the first score. The contest name falls back to the
    /// contest id and then to `""`.
    public static func scoreData(isContestActive: Bool, score: ScoreState?, activeName: String?, activeId: String?,
                                 stationCall: String, operatorCall: String, now: Date) -> BroadcastXml.ScoreData? {
        guard isContestActive, let score else { return nil }
        return BroadcastXml.ScoreData(contest: activeName ?? activeId ?? "", call: stationCall, ops: operatorCall,
                                      score: score.total, timestamp: now)
    }

    /// `appInfoData()`: the database name is the fixed `logbook.sqlite`.
    public static func appInfoData(contestNr: Int32, contestName: String?, stationCall: String)
        -> BroadcastXml.AppInfoData {
        BroadcastXml.AppInfoData(dbName: "logbook.sqlite", contestNr: contestNr, contestName: contestName ?? "",
                                 stationName: stationCall, myCall: stationCall)
    }

    // MARK: - the full N1MM packets (Swift-only)

    /// The received exchange split by meaning for `contactinfo`: the stored flat tokens matched to the contest's
    /// active received fields in order (as `ContestSession.receivedFromFlat`), each put where N1MM puts it — the
    /// locator into `gridsquare`, a zone into `zone`, a state, province, district, prefecture, HQ or IOTA into `qth`,
    /// and fields named like N1MM's own (`sec`/`section`, `name`, `power`/`pwr`, `prec`, `ck`/`check`) into those.
    public static func contactExtras(_ qso: Qso, receivedFields: [ContestDefinition.ExchangeField],
                                     countryPrefix: String, radioNr: Int) -> BroadcastXml.ContactExtras {
        var x = BroadcastXml.ContactExtras()
        x.countryPrefix = countryPrefix
        x.wpxPrefix = PrefixExtractor.wpx(qso.call)
        x.exchange1 = JavaText.trim(qso.exchangeRcvd)
        x.comment = qso.comment
        x.operator = qso.operator
        x.isRunQso = qso.runMode == .run
        x.radioNr = max(1, radioNr)
        let sent: String = JavaText.trim(qso.exchangeSent)
        x.sentExchange = sent.isEmpty ? (qso.serialSent.map { String($0) } ?? "") : sent
        let tokens: [Substring] = x.exchange1.split(whereSeparator: { $0 == " " || $0 == "\t" })
        for (field, token) in zip(receivedFields, tokens) {
            let value = String(token)
            if value == "-" { continue }
            let id: String = (field.id ?? "").lowercased()
            switch id {
            case "sec", "section", "arrlsection", "arrl_section":
                x.section = value
                continue
            case "name":
                x.name = value
                continue
            case "power", "pwr":
                x.power = value
                continue
            case "prec", "precedence":
                x.precedence = value
                continue
            case "ck", "check":
                x.check = value
                continue
            case "zone":
                x.zone = value
                continue
            default:
                break
            }
            switch field.type {
            case .LOCATOR?: x.gridSquare = value
            case .CQ_ZONE?, .ITU_ZONE?: x.zone = value
            case .STATE?, .PROVINCE?, .DISTRICT?, .NATIONAL?, .HQ?, .IOTA?: x.qth = value
            default: break
            }
        }
        return x
    }

    /// The second half of the full `RadioInfo` packet: the radio's number, split, transmitting, focus and stereo.
    public static func radioExtras(radioNr: Int, rig: RigState, stationCall: String, antenna: Int?,
                                   focusRadioNr: Int, activeRadioNr: Int, isStereo: Bool, isTransmitting: Bool,
                                   radioName: String) -> BroadcastXml.RadioExtras {
        var x = BroadcastXml.RadioExtras()
        x.radioNr = radioNr
        x.isSplit = rig.split
        x.txFreqHz = rig.split && rig.txFreqHz > 0 ? rig.txFreqHz : rig.freqHz
        x.myCall = stationCall
        x.antenna = antenna ?? -1
        x.focusRadioNr = focusRadioNr
        x.activeRadioNr = activeRadioNr
        x.isStereo = isStereo
        x.isTransmitting = isTransmitting
        x.radioName = radioName
        x.isConnected = true
        return x
    }

    /// N1MM's radio name from the hamlib model label (`"1035 — Yaesu FT-991"` → `"Yaesu FT-991"`).
    public static func radioName(modelLabel: String) -> String {
        if let range = modelLabel.range(of: " — ") {
            return String(modelLabel[range.upperBound...])
        }
        return modelLabel
    }

    /// The score packet's breakdown: QSOs and points per band and mode of the log, then the totals (QSOs, points
    /// and multipliers of the score). Bands as N1MM writes them (`20`, `0.7`… without the unit), modes CW/PH/DIG.
    public static func scoreBreakdown(_ qsos: [Qso], score: ScoreState) -> [BroadcastXml.BreakdownRow] {
        struct Cell { var qsos: Int64 = 0; var points: Int64 = 0 }
        var cells: [String: Cell] = [:]
        var order: [(band: Band, mode: String)] = []
        for q in qsos where !q.deleted && !q.xqso {
            guard let band = q.band else { continue }
            let mode: String = modeGroup(q.mode)
            let key: String = band.adif + "|" + mode
            if cells[key] == nil {
                order.append((band, mode))
            }
            cells[key, default: Cell()].qsos += 1
            cells[key, default: Cell()].points += Int64(q.points)
        }
        let bandIndex: [Band: Int] = Dictionary(uniqueKeysWithValues: Band.allCases.enumerated().map { ($1, $0) })
        order.sort { a, b in
            a.band != b.band ? (bandIndex[a.band] ?? 0) < (bandIndex[b.band] ?? 0) : a.mode < b.mode
        }
        var rows: [BroadcastXml.BreakdownRow] = []
        for (band, mode) in order {
            let cell: Cell = cells[band.adif + "|" + mode] ?? Cell()
            let name: String = n1mmBandName(band)
            rows.append(.init(kind: "qso", band: name, mode: mode, value: cell.qsos))
            rows.append(.init(kind: "point", band: name, mode: mode, value: cell.points))
        }
        rows.append(.init(kind: "qso", band: "total", mode: "ALL", value: Int64(score.qsoCount)))
        rows.append(.init(kind: "point", band: "total", mode: "ALL", value: score.qsoPoints))
        rows.append(.init(kind: "mult", band: "total", mode: "ALL", value: Int64(score.multTotal)))
        return rows
    }

    /// CW, PH or DIG like N1MM's breakdown.
    static func modeGroup(_ mode: Mode?) -> String {
        switch mode {
        case .cw?: return "CW"
        case .ssb?, .am?, .fm?: return "PH"
        case nil: return "ALL"
        default: return "DIG"
        }
    }

    /// The band as the online-score breakdown writes it (`ScoreXml`): `20m` → `20`, `70cm` → `70`.
    static func n1mmBandName(_ band: Band) -> String {
        JavaText.replace(JavaText.replace(band.adif, "m", ""), "c", "")
    }
}
