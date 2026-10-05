import Foundation

/// Merging logbooks (N1MM „Merge logs", DXLog Merge): QSOs from another logbook
/// that are not yet in the current one. The same QSO = the same callsign, band and mode and
/// time within `tolerance` (different station clocks, manual transcription of a paper log).
///
/// Mirrors the Java `final class LogMerger` (private constructor, only static
/// methods) — a stateless utility, hence a caseless enum. Port of `LogMerger.java`.
public enum LogMerger {

    /// Time tolerance for recognizing the same QSO.
    public static let tolerance: TimeInterval = 120 // 2 minutes

    /// Result: QSOs to add and the number of skipped duplicates.
    public struct Result: Equatable, Sendable {
        public let toAdd: [Qso]
        public let duplicates: Int
    }

    public static func merge(existing: [Qso], incoming: [Qso]) -> Result {
        var present = existing.filter { !$0.deleted }
        var add: [Qso] = []
        var duplicates = 0
        for q in incoming {
            // Java `q.getCall() == null || q.getCall().isBlank()` — that is
            // `Character.isWhitespace`, **not** `trim()`. U+00A0, U+2007 and U+202F
            // are not white (the QSO passes), U+3000 is white (the QSO is skipped).
            // Swift's `.whitespacesAndNewlines` has it the other way round.
            if q.deleted || JavaText.isBlank(q.call) {
                continue
            }
            if present.contains(where: { same($0, q) }) {
                duplicates += 1
                continue
            }
            add.append(q)
            present.append(q) // including duplicates within the log being merged
        }
        return Result(toAdd: add, duplicates: duplicates)
    }

    static func same(_ a: Qso, _ b: Qso) -> Bool {
        if !a.uuid.isEmpty, a.uuid == b.uuid {
            return true
        }
        // Java `getCall().trim().toUpperCase(Locale.ROOT)` — here it is
        // `trim()` (characters ≤ U+0020), a different set than `isBlank()` above in `merge`.
        guard JavaText.trim(a.call).uppercased() == JavaText.trim(b.call).uppercased() else {
            return false
        }
        guard a.band == b.band, a.mode == b.mode else {
            return false
        }
        guard let at = a.timestampUtc, let bt = b.timestampUtc else {
            return a.timestampUtc == b.timestampUtc
        }
        return abs(at.timeIntervalSince(bt)) <= tolerance
    }
}
