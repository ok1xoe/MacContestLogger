import Foundation
import MCLCore
import Observation

/// The Available Multipliers window (`AvailableMultipliersWindow.kt`, N1MM Available): the spot rows of the
/// current analysis over the buffer, filtered by Mults/Mults & Qs and the bands and modes, the band matrix, the table
/// sort, a click that tunes to the spot and the row menu.
///
/// The filter is app state that is not saved (Kotlin `availMultsOnly`, `availBands`, `availModes`); an opening contest
/// activation resets the bands and modes to the definition's (`setDefaults`, `AS:3605-3610`). The sort is the window's
/// (Kotlin `remember`): `resetSort()` when the window opens.
@Observable @MainActor
public final class AvailMultModel {

    /// What the window shows (one consistent computation).
    public struct Snapshot: Equatable, Sendable {
        /// The filtered rows in the table order.
        public let rows: [SpotRow]
        /// The band matrix of the filtered rows (a band without rows is absent: `Counts.zero`).
        public let matrix: [Band?: AvailableMults.Counts]
        /// The filtered rows' counts (the title).
        public let counts: AvailableMults.Counts

        public static let empty = Snapshot(rows: [], matrix: [:], counts: .zero)
    }

    /// Kotlin `availMultsOnly` (the Mults / Mults & Qs button).
    public var multsOnly = false
    /// Kotlin `availBands` (empty = all).
    public var bands: Set<Band> = []
    /// Kotlin `availModes` — mode categories CW / PHONE / DIGI (empty = all).
    public var modes: Set<String> = []
    /// Kotlin `showAvailFilter`: the bands and modes sheet.
    public var showFilter = false
    /// The sorted column (Kotlin `sortCol`, `FREQ` when the window opens).
    public private(set) var sortColumn: AvailableMults.SortColumn = .freq
    /// Kotlin `sortAsc`.
    public private(set) var ascending = true

    @ObservationIgnored private let feed: SpotFeed
    @ObservationIgnored private let analysis: SpotAnalysisModel
    @ObservationIgnored let contest: ContestModel
    @ObservationIgnored private let blacklist: BlacklistModel
    @ObservationIgnored private let callbook: CallbookModel
    @ObservationIgnored private let rig: RigModel
    @ObservationIgnored private var cache: (key: CacheKey, snapshot: Snapshot)?

    private struct CacheKey: Equatable {
        let feed: Int
        let analysis: Int
        let active: Bool
        let multsOnly: Bool
        let bands: Set<Band>
        let modes: Set<String>
        let column: AvailableMults.SortColumn
        let ascending: Bool
    }

    struct Dependencies {
        let feed: SpotFeed
        let analysis: SpotAnalysisModel
        let contest: ContestModel
        let blacklist: BlacklistModel
        let callbook: CallbookModel
        let rig: RigModel
    }

    init(_ dependencies: Dependencies) {
        feed = dependencies.feed
        analysis = dependencies.analysis
        contest = dependencies.contest
        blacklist = dependencies.blacklist
        callbook = dependencies.callbook
        rig = dependencies.rig
    }

    /// Kotlin `!state.contest.isActive` → „Žádný aktivní závod."
    public var contestActive: Bool {
        contest.isActive
    }

    /// The rows, the matrix and the counts now (recomputed when the spots, the analysis or the filter changed).
    public func snapshot() -> Snapshot {
        let key = CacheKey(feed: feed.revision, analysis: analysis.revision, active: contest.isActive,
                           multsOnly: multsOnly, bands: bands, modes: modes, column: sortColumn,
                           ascending: ascending)
        if let cache, cache.key == key {
            return cache.snapshot
        }
        let computed: Snapshot = compute(active: key.active)
        cache = (key, computed)
        return computed
    }

    private func compute(active: Bool) -> Snapshot {
        guard active else { return .empty }
        let all: [SpotRow] = analysis.current().spotRows(feed.filteredSnapshot())
        let filtered: [SpotRow] = AvailableMults.filter(rows: all, multsOnly: multsOnly, bands: bands, modes: modes)
        return Snapshot(rows: AvailableMults.sorted(filtered, by: sortColumn, ascending: ascending),
                        matrix: AvailableMults.matrix(rows: filtered), counts: AvailableMults.Counts.of(filtered))
    }

    /// The title `tr("Dostupné — %s Mults, %s Qs z %s spotů", …)`.
    public func title(_ counts: AvailableMults.Counts) -> ContestMessage {
        ContestMessage("Dostupné — %s Mults, %s Qs z %s spotů", .int(counts.mults), .int(counts.qs),
                       .int(counts.total))
    }

    // MARK: - filter and sort

    /// Kotlin `setDefaultSpotFilters` (`AS:3605-3610`): the definition's bands and mode categories.
    public func setDefaults(bands: Set<Band>, modes: Set<String>) {
        self.bands = bands
        self.modes = modes
    }

    /// Kotlin `onSort(col)`: the same column flips the direction, another one sorts it ascending.
    public func sort(by column: AvailableMults.SortColumn) {
        if sortColumn == column {
            ascending.toggle()
        } else {
            sortColumn = column
            ascending = true
        }
    }

    /// The window opened: Kotlin's `remember` starts with Freq ascending.
    public func resetSort() {
        sortColumn = .freq
        ascending = true
    }

    // MARK: - row actions

    /// A click on a row: tune to the call's spot, or (none left in the buffer) `qsy(freq, call)`.
    public func click(_ row: SpotRow) {
        if let spot = rig.spotForCall(row.call) {
            rig.tuneToSpot(spot)
        } else {
            rig.qsy(Int64(row.freqHz), call: row.call)
        }
    }

    /// „Odebrat spot": every spot of the call leaves the buffer.
    public func remove(_ row: SpotRow) {
        feed.buffer.remove(row.call)
    }

    /// `tr("Blacklist volačky %s")`.
    public func blacklistCall(_ row: SpotRow) {
        blacklist.blacklistCall(row.call)
    }

    /// „Blacklist spottera …".
    public func blacklistSpotter(_ row: SpotRow) {
        blacklist.blacklistSpotter(row.spotter)
    }

    /// „QRZ.com".
    public func openQrz(_ row: SpotRow) {
        callbook.openQrz(row.call)
    }

    /// „HamQTH".
    public func openHamQth(_ row: SpotRow) {
        callbook.openHamQth(row.call)
    }

    /// `tr("Smazat všechny spoty")`.
    public func clearSpots() {
        feed.buffer.clear()
    }
}
