import Foundation

/// Callsign suggestions under the entry fields (`EP:623-651, 1193-1246, 1402-1440`): Check partial (own log, cluster
/// spots, `master.scp`), N+1 and the "worked before" strip.
public enum EntrySuggestions {

    /// Kotlin `SCP_SUGGESTIONS` and `N_PLUS_ONE`.
    public static let limit = 8

    /// `WORKED_BEFORE_BANDS` — the band order outside a contest (`EP:1406`).
    public static let workedBeforeBands: [String] = ["160m", "80m", "40m", "20m", "15m", "10m"]

    /// Check partial: the **untyped** call text (no trim) of at least 2 UTF-16 units, otherwise nothing;
    /// `PartialCheck.merge(query, logCalls, spotCalls, scp.find(query, 8), 8)`.
    public static func partial(query: String, logCalls: [String], spotCalls: [String],
                               scp: ScpDatabase) -> [PartialCheck.Suggestion] {
        guard query.utf16.count >= 2 else { return [] }
        return PartialCheck.merge(query, logCalls: logCalls, spotCalls: spotCalls,
                                  scpMatches: scp.find(query, limit: limit), limit: limit)
    }

    /// N+1: the Kotlin-trimmed call of at least 3 UTF-16 units, otherwise nothing;
    /// `(PartialCheck.nPlusOne(q, logCalls + spotCalls, 8) + scp.nPlusOne(q, 8)).distinct().sorted().take(8)` —
    /// `sorted()` is the natural `String` order (UTF-16 units), `distinct()` by UTF-16 equality.
    public static func nPlusOne(query: String, logCalls: [String], spotCalls: [String], scp: ScpDatabase) -> [String] {
        let q: String = KotlinStrings.trim(query)
        guard q.utf16.count >= 3 else { return [] }
        let fromLog: [String] = PartialCheck.nPlusOne(q, candidates: logCalls + spotCalls, limit: limit)
        let all: [String] = fromLog + scp.nPlusOne(q, limit: limit)
        var seen = Set<JavaStringKey>()
        let distinct: [String] = all.filter { seen.insert(JavaStringKey($0)).inserted }
        let sorted: [String] = distinct.sorted { JavaText.compare($0, $1) < 0 }
        return Array(sorted.prefix(limit))
    }

    /// The worked-before strip: shown for a Kotlin-trimmed call of at least 3 UTF-16 units that is in the log
    /// (`anyWorked`); bands in the contest order (`contest.bandOrder()`), otherwise `workedBeforeBands`.
    public static func workedBefore(qsos: [Qso], call: String, contestBandOrder: [String]?) -> WorkedBefore.Result? {
        guard KotlinStrings.trim(call).utf16.count >= 3 else { return nil }
        let result: WorkedBefore.Result = WorkedBefore.of(qsos: qsos, call: call,
                                                          bandOrder: contestBandOrder ?? workedBeforeBands)
        return result.anyWorked ? result : nil
    }

    /// The strip's caption: `tr("Pracováno %s×", count)` + `", naposledy HHmmZ"` (not translated) + `":"`.
    public static func workedBeforeCaption(_ result: WorkedBefore.Result) -> EntryStatus {
        let last: String = result.last.map { ", naposledy " + EntryTexts.hhmmZ($0) } ?? ""
        return EntryStatus.tr("Pracováno %s×", .int(result.count)).appending(.verbatim(last + ":"))
    }

    /// One band chip: `band.removeSuffix("m")` plus `" " + modes.joinToString("/")` when worked.
    public static func workedBeforeChip(_ status: WorkedBefore.BandStatus) -> String {
        let units: [UInt16] = Array(status.band.utf16)
        let band: String = units.last == 0x6D ? JavaChar.string(Array(units.dropLast())) : status.band
        return status.worked ? band + " " + status.modes.joined(separator: "/") : band
    }
}
