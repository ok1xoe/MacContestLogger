import Foundation

/// Sorting of the logbook for the table in the „Přehled spojení" window.
///
/// QSOs with an empty value in the sort column (missing time, callsign, number…)
/// always stay at the end — in both directions. The secondary key is time
/// ascending, so that contacts with an equal value keep chronological order.
///
/// The Java version relies on `List.sort` being stable (merge sort) — QSOs with an
/// equal key keep their original order. Swift's `Array.sort`/`sorted` has been stable since
/// SE-0372 too (verified also by experiment: thousands of elements with an equal
/// key over dozens of shuffled runs, no loss of order) — nevertheless the sort here
/// goes through the index as an explicit tiebreak (`stableSort`), so that stability is
/// guaranteed by our own code, not by a note in the stdlib documentation, which could
/// theoretically change. Belt-and-braces, not a fix for real instability.
public enum QsoSort {

    /// Column to sort by.
    public enum Key {
        case time, call, band, mode, rstSent, rstRcvd, serialSent, serialRcvd, exchange, note
    }

    /// Returns a new sorted copy; does not modify the input.
    public static func sort(_ qsos: [Qso], key: Key, ascending: Bool) -> [Qso] {
        var present: [Qso] = []
        var missing: [Qso] = []
        for q in qsos {
            if hasValue(q, key: key) {
                present.append(q)
            } else {
                missing.append(q)
            }
        }
        var sortedPresent = stableSort(present, by: comparator(for: key))
        if !ascending {
            sortedPresent.reverse()
        }
        sortedPresent.append(contentsOf: missing)
        return sortedPresent
    }

    /// Sorts by `compare` (< 0, 0, > 0), preserving the order of elements with an
    /// equal key. `Array.sorted` is stable even without this tiebreak
    /// (SE-0372, verified by experiment), but the index as the last comparator
    /// guarantees stability at the level of our code, not on a stdlib promise.
    private static func stableSort(_ items: [Qso], by compare: (Qso, Qso) -> Int) -> [Qso] {
        items.enumerated()
            .sorted { a, b in
                let c = compare(a.element, b.element)
                if c != 0 { return c < 0 }
                return a.offset < b.offset
            }
            .map(\.element)
    }

    private static func comparator(for key: Key) -> (Qso, Qso) -> Int {
        if key == .time {
            return byTime
        }
        let primary = primaryComparator(for: key)
        return { a, b in
            let c = primary(a, b)
            return c != 0 ? c : byTime(a, b)
        }
    }

    private static func byTime(_ a: Qso, _ b: Qso) -> Int {
        compareOptional(a.timestampUtc, b.timestampUtc)
    }

    private static func primaryComparator(for key: Key) -> (Qso, Qso) -> Int {
        switch key {
        case .call:
            return textComparator { $0.call }
        // We sort the band by frequency — this groups QSOs by band
        // and within a band they go ascending by frequency.
        case .band:
            return { a, b in compareInt(a.freqHz, b.freqHz) }
        case .mode:
            return textComparator { $0.mode?.rawValue }
        case .rstSent:
            return textComparator { $0.rstSent }
        case .rstRcvd:
            return textComparator { $0.rstRcvd }
        case .serialSent:
            return numberComparator { $0.serialSent }
        case .serialRcvd:
            return numberComparator { $0.serialRcvd }
        case .exchange:
            return textComparator { $0.exchangeRcvd }
        case .note:
            return textComparator { $0.comment }
        case .time:
            preconditionFailure("TIME nemá primární komparátor — řeší se přímo v comparator(for:)")
        }
    }

    private static func textComparator(_ get: @escaping (Qso) -> String?) -> (Qso, Qso) -> Int {
        { a, b in
            let av = get(a)?.uppercased()
            let bv = get(b)?.uppercased()
            return compareOptional(av, bv)
        }
    }

    private static func numberComparator(_ get: @escaping (Qso) -> Int?) -> (Qso, Qso) -> Int {
        { a, b in compareOptional(get(a), get(b)) }
    }

    private static func compareInt(_ a: Int, _ b: Int) -> Int {
        a == b ? 0 : (a < b ? -1 : 1)
    }

    /// `nil` (a missing value) always after any existing value.
    private static func compareOptional<T: Comparable>(_ a: T?, _ b: T?) -> Int {
        switch (a, b) {
        case (nil, nil):
            return 0
        case (nil, _):
            return 1
        case (_, nil):
            return -1
        case let (x?, y?):
            return x == y ? 0 : (x < y ? -1 : 1)
        }
    }

    /// Does the QSO have a value in the given column? Empty ones always go to the end.
    private static func hasValue(_ q: Qso, key: Key) -> Bool {
        switch key {
        case .time:
            return q.timestampUtc != nil
        case .call:
            return notBlank(q.call)
        case .band:
            return q.band != nil
        case .mode:
            return q.mode != nil
        case .rstSent:
            return notBlank(q.rstSent)
        case .rstRcvd:
            return notBlank(q.rstRcvd)
        case .serialSent:
            return q.serialSent != nil
        case .serialRcvd:
            return q.serialRcvd != nil
        case .exchange:
            return notBlank(q.exchangeRcvd)
        case .note:
            return notBlank(q.comment)
        }
    }

    private static func notBlank(_ s: String) -> Bool {
        !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
