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
                                 runMode: RunMode) -> BroadcastXml.RadioData? {
        guard catConnected, let rig else { return nil }
        return BroadcastXml.RadioData(stationName: stationCall, freqHz: rig.freqHz, mode: rig.mode?.rawValue ?? "",
                                      opCall: operatorCall, isRunning: runMode == .run)
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
}
