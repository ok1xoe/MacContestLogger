import Foundation

/// The logic of the Available Multipliers window (`ui/AvailableMultipliersWindow.kt`, v1.1.1) without the view:
/// the row filter (`:129-135`), the band matrix (`:136-138`, `:219-243`) and the table sort (`:276-286`).
public enum AvailableMults {

    /// Bands of the matrix (Kotlin `MATRIX_BANDS`, `:58`).
    public static let matrixBands: [Band] = [.m160, .m80, .m40, .m20, .m15, .m10]

    /// Counts of one matrix column (Kotlin rows `Mults` / `Qs` / `Total`, `:229-233`).
    public struct Counts: Sendable, Equatable {
        /// Rows with a new multiplier (`isMult`).
        public let mults: Int
        /// Rows that are not dupes.
        public let qs: Int
        public let total: Int

        public init(mults: Int, qs: Int, total: Int) {
            self.mults = mults
            self.qs = qs
            self.total = total
        }

        public static let zero = Counts(mults: 0, qs: 0, total: 0)

        /// Counts of the given rows (also the window title: `%s Mults, %s Qs z %s spotů`, `:137-138`, `:159`).
        public static func of(_ rows: [SpotRow]) -> Counts {
            var mults = 0
            var qs = 0
            for row in rows {
                if row.isMult { mults += 1 }
                if !row.dupe { qs += 1 }
            }
            return Counts(mults: mults, qs: qs, total: rows.count)
        }
    }

    /// Sortable columns (Kotlin `SortCol`, `:276`).
    public enum SortColumn: String, Sendable, CaseIterable {
        case freq = "FREQ"
        case dir = "DIR"
        case pts = "PTS"
    }

    /// Kotlin filter (`:130-135`): `(!multsOnly || isMult) && (bands empty || band in bands) && (modes empty ||
    /// modeCategory(mode) in modes)`. An empty set means "all". The band is derived from the row frequency; a row
    /// without a band passes only an empty band set (spot rows never lack a band).
    public static func filter(rows: [SpotRow], multsOnly: Bool = false, bands: Set<Band>,
                              modes: Set<String>) -> [SpotRow] {
        rows.filter { row in
            if multsOnly && !row.isMult {
                return false
            }
            if !bands.isEmpty {
                guard let band = Band.from(frequencyHz: row.freqHz), bands.contains(band) else { return false }
            }
            if !modes.isEmpty && !modes.contains(SpotModeCategory.of(row.mode)) {
                return false
            }
            return true
        }
    }

    /// Kotlin `groupBy { band }` + the per-band counts (`:136`, `:236-237`). A missing band is `nil`; a band without
    /// rows is absent (the view shows `Counts.zero`).
    public static func matrix(rows: [SpotRow]) -> [Band?: Counts] {
        var grouped: [Band?: [SpotRow]] = [:]
        for row in rows {
            grouped[Band.from(frequencyHz: row.freqHz), default: []].append(row)
        }
        return grouped.mapValues { Counts.of($0) }
    }

    /// Kotlin `sortRows` (`:279-286`): a **stable** ascending sort, and the descending order is its `reversed()`
    /// — rows with equal keys come in reverse input order (pinned by a maintainer-only probe). By
    /// direction, rows without an azimuth always go last, in input order.
    public static func sorted(_ rows: [SpotRow], by column: SortColumn, ascending: Bool) -> [SpotRow] {
        switch column {
        case .freq:
            return directed(stableSorted(rows) { $0.freqHz }, ascending)
        case .pts:
            return directed(stableSorted(rows) { $0.points }, ascending)
        case .dir:
            let present: [SpotRow] = rows.filter { $0.azimuth != nil }
            let absent: [SpotRow] = rows.filter { $0.azimuth == nil }
            return directed(stableSorted(present) { $0.azimuth ?? 0 }, ascending) + absent
        }
    }

    private static func directed(_ rows: [SpotRow], _ ascending: Bool) -> [SpotRow] {
        ascending ? rows : Array(rows.reversed())
    }

    /// Kotlin `sortedBy` (stable).
    private static func stableSorted(_ rows: [SpotRow], _ key: (SpotRow) -> Int) -> [SpotRow] {
        let indexed: [(offset: Int, element: SpotRow)] = Array(rows.enumerated())
        let ordered = indexed.sorted { lhs, rhs in
            let a: Int = key(lhs.element)
            let b: Int = key(rhs.element)
            return a != b ? a < b : lhs.offset < rhs.offset
        }
        return ordered.map(\.element)
    }
}
