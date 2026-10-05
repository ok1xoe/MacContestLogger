import Foundation

/// Callsign check by band (N1MM Check / DXLog „Check callsign"): on
/// which bands and in which modes the callsign is already in the logbook. Deleted QSOs are
/// not counted, X-QSOs are (the station is in the logbook).
///
/// Port of `WorkedBefore.java`.
public enum WorkedBefore {

    /// State of one band: the modes in which the callsign was worked (empty = not worked).
    ///
    /// `modes` is a **sorted array**, not a set: Java has a `TreeSet<String>` here, i.e.
    /// iteration in natural (alphabetical) order, and the UI renders it directly that way
    /// (`EntryPanel.kt`: `b.modes().joinToString("/")` → `CW/SSB`). A Swift
    /// `Set<String>` iterates in an order given by the per-process random hashing seed —
    /// the same logbook could show differently on every launch (`CW/SSB` vs. `SSB/CW`).
    /// Mode names are pure ASCII (`Mode` constants + `"?"`), so Swift's
    /// `sorted()` gives the same order as Java `String.compareTo` in a `TreeSet`.
    public struct BandStatus: Equatable, Sendable {
        public let band: String
        public let modes: [String]

        public var worked: Bool { !modes.isEmpty }
    }

    /// Result for a callsign: bands in the given order + worked outside it, count and last QSO.
    public struct Result: Equatable, Sendable {
        public let bands: [BandStatus]
        public let count: Int
        public let last: Date?

        public var anyWorked: Bool { count > 0 }
    }

    public static func of(qsos: [Qso], call: String?, bandOrder: [String]) -> Result {
        // Java `call.trim().toUpperCase(Locale.ROOT)`. The trim is `JavaText.trim`
        // (characters ≤ U+0020), not Swift's `.whitespacesAndNewlines`: a non-breaking
        // space U+00A0 (and U+2007, U+202F, DEL) in a callsign **must** stay,
        // otherwise `\u{00A0}OK1XOE` from a cluster spot would match `OK1XOE`
        // and the UI would report worked where Java reports nothing.
        let c = JavaText.trim(call ?? "").uppercased()
        var byBand: [String: Set<String>] = [:]
        var order: [String] = []
        for b in bandOrder {
            byBand[b] = []
            order.append(b)
        }
        var count = 0
        var last: Date?
        if !c.isEmpty {
            for q in qsos {
                guard !q.deleted, !q.call.isEmpty, q.call.caseInsensitiveCompare(c) == .orderedSame else {
                    continue
                }
                count += 1
                if let ts = q.timestampUtc, last == nil || ts > last! {
                    last = ts
                }
                if let band = q.band {
                    let key = band.adif
                    if byBand[key] == nil {
                        byBand[key] = []
                        order.append(key)
                    }
                    byBand[key]?.insert(q.mode?.rawValue ?? "?")
                }
            }
        }
        // `sorted()` = Java `TreeSet` (natural order), see `BandStatus.modes`.
        let bands = order.map { BandStatus(band: $0, modes: (byBand[$0] ?? []).sorted()) }
        return Result(bands: bands, count: count, last: last)
    }
}
