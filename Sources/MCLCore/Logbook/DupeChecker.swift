import Foundation

/// Fast duplicate check (dupe check) as in N1MM+. In Phase 1 a QSO is
/// a duplicate if the given callsign was already worked on the same band.
///
/// The dupe rule (per band / per band+mode) will later be driven by the contest
/// definition; the index is therefore built over the callsign+band key.
///
/// Port of `DupeChecker.java`.
public struct DupeChecker: Sendable {

    /// Index key: the normalised callsign and the band (Java `call.trim().toUpperCase() + '|' + band.name()`).
    /// Shared with `DupeIndex`, so the key, its guards and the normalisation exist once.
    struct Key: Hashable, Sendable {
        let call: String
        let band: Band
    }

    private var worked: Set<Key> = []

    public init(existing: [Qso]) {
        for q in existing {
            add(q)
        }
    }

    /// Records a QSO into the index. Deleted (tombstone) QSOs are ignored.
    public mutating func add(_ qso: Qso) {
        guard let key = Self.key(of: qso) else { return }
        worked.insert(key)
    }

    /// Is the given callsign on the given band a duplicate?
    public func isDupe(call: String?, band: Band?) -> Bool {
        guard let key = Self.key(call: call, band: band) else { return false }
        return worked.contains(key)
    }

    /// The key a QSO is indexed under; `nil` = the QSO is not indexed (a tombstone, no callsign or no band —
    /// Java `isDeleted() || getCall() == null || getBand() == null`, the Swift `""` standing for Java `null`).
    static func key(of qso: Qso) -> Key? {
        guard !qso.deleted, !qso.call.isEmpty, let band = qso.band else { return nil }
        return Key(call: normalize(qso.call), band: band)
    }

    /// The key a query looks up; `nil` = never a dupe.
    static func key(call: String?, band: Band?) -> Key? {
        guard let call, let band else { return nil }
        return Key(call: normalize(call), band: band)
    }

    /// Index key exactly like Java `DupeChecker.key`: `call.trim().toUpperCase()`.
    ///
    /// The trim is **Java `trim()`** (`JavaText.trim`), not Swift's
    /// `.whitespacesAndNewlines` — they are different character sets. Java discards characters
    /// ≤ U+0020 (including control U+0001 and tab), but it **keeps** the non-breaking space
    /// U+00A0, U+2007, U+202F and DEL (U+007F); Swift's trim does
    /// exactly the opposite. For dupes this shows immediately: a callsign from a cluster spot or
    /// a web paste commonly carries U+00A0, and Swift's trim would merge it with the clean
    /// callsign, so the operator would reject a valid contact as a duplicate.
    ///
    /// `toUpperCase()` in Java has no `Locale`, so it follows the default locale.
    /// The reference is `en`, where the result is identical to `Locale.ROOT`; measured for
    /// all 1,112,064 code points (see the note on Unicode 15 vs. 16).
    private static func normalize(_ call: String) -> String {
        JavaText.trim(call).uppercased()
    }
}
