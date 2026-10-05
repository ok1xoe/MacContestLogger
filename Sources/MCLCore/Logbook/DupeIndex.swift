import Foundation

/// Dupe index of the open logbook (callsign + band) that follows inserts, edits and deletes.
///
/// Kotlin keeps a `DupeChecker` and rebuilds it with `DupeChecker(logbook.findAll())` after every edit, delete,
/// import and wipe — a full re-read of the logbook. This index gives the same answers without the re-read: it counts
/// the QSOs per key, so removing one of several QSOs that share a callsign/band keeps the key. The key, its guards
/// (tombstone, empty callsign, no band) and the normalisation are `DupeChecker`'s (`DupeChecker.key`), so the index
/// cannot drift from the Java rule.
///
/// Invariant (tested under seeded insert/update/delete/bulk/wipe sequences): after any sequence of `add`/`remove`/
/// `replace` that mirrors the logbook, `index == DupeIndex(existing: logbook)` and every `isDupe` answer equals
/// `DupeChecker(existing: logbook).isDupe`.
public struct DupeIndex: Equatable, Sendable {

    private var counts: [DupeChecker.Key: Int] = [:]

    public init(existing: [Qso]) {
        for q in existing {
            add(q)
        }
    }

    /// Takes a QSO into the index (an inserted QSO, or the new state of an edited one). Tombstones and QSOs without a
    /// callsign or band are ignored, as in `DupeChecker.add`.
    public mutating func add(_ qso: Qso) {
        guard let key = DupeChecker.key(of: qso) else { return }
        counts[key, default: 0] += 1
    }

    /// Takes a QSO out of the index (a deleted QSO, or the old state of an edited one). The QSO must be in the state
    /// in which it was added; one that was never indexed is ignored.
    public mutating func remove(_ qso: Qso) {
        guard let key = DupeChecker.key(of: qso), let count = counts[key] else { return }
        if count > 1 {
            counts[key] = count - 1
        } else {
            counts[key] = nil
        }
    }

    /// An edit: the old state leaves the index, the new one enters it.
    public mutating func replace(old: Qso, new: Qso) {
        remove(old)
        add(new)
    }

    /// Is the callsign on the band a duplicate?
    public func isDupe(call: String?, band: Band?) -> Bool {
        guard let key = DupeChecker.key(call: call, band: band) else { return false }
        return counts[key] != nil
    }
}
