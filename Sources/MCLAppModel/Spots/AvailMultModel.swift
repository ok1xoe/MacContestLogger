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
///
/// Post-port (N1MM Available): every column sorts, the columns, their order and widths and the summary panel's bands
/// are saved in `config.dxCluster`, the focus-radio filter shows only the active radio's band, Alt+A / Shift+Alt+A
/// grab the next / previous spot of the list, the rows show the split, skimmer and gray-line marks, the spot's time
/// and (with the waterfall open) whether its signal is seen.
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
        /// When each row's spot arrived, by the upper-case call (the Time column).
        public let spottedAt: [String: Date]

        public init(rows: [SpotRow], matrix: [Band?: AvailableMults.Counts], counts: AvailableMults.Counts,
                    spottedAt: [String: Date] = [:]) {
            self.rows = rows
            self.matrix = matrix
            self.counts = counts
            self.spottedAt = spottedAt
        }

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
    /// N1MM „Focus radio": only the spots on the band of the radio / VFO with the focus.
    public var focusRadioOnly = false
    /// The second Available window (`availMult2`): bound to radio 2 / VFO B — its „Focus radio" band is that radio's
    /// and a click tunes it (the other radio, the focus staying, when it has no focus). `nil` = the focused radio.
    public internal(set) var radio: Int?

    /// The window is bound to the radio without the entry focus.
    var bindsOtherRadio: Bool {
        guard let radio, rig.vfo.twoEntryWindows else { return false }
        return radio != rig.vfo.activeVfo
    }

    /// The band „Focus radio" shows: the bound radio's, otherwise the focused one's.
    var focusedBand: Band? {
        bindsOtherRadio ? rig.otherRadioBand : rig.currentBand
    }
    /// The sheet of the columns and the summary panel.
    public var showColumns = false
    /// The call Alt+A / Shift+Alt+A took last (the list's cursor; the row is highlighted).
    public internal(set) var grabbedCall: String?
    /// The call under the pointer (a middle click deletes its spot).
    public var hoveredCall: String?
    /// Column widths while a header divider is dragged (saved when the drag ends).
    public internal(set) var draggedWidths: [String: Int] = [:]
    /// The sorted column (Kotlin `sortCol`, `FREQ` when the window opens).
    public private(set) var sortColumn: AvailableColumn = .freq
    /// Kotlin `sortAsc`.
    public private(set) var ascending = true

    @ObservationIgnored let feed: SpotFeed
    @ObservationIgnored let analysis: SpotAnalysisModel
    @ObservationIgnored let contest: ContestModel
    @ObservationIgnored private let blacklist: BlacklistModel
    @ObservationIgnored private let callbook: CallbookModel
    @ObservationIgnored let rig: RigModel
    @ObservationIgnored let config: ConfigModel
    @ObservationIgnored let status: StatusModel
    @ObservationIgnored let now: @Sendable () -> Date
    @ObservationIgnored private var cache: (key: CacheKey, snapshot: Snapshot)?
    /// The bands before a click on the summary narrowed the filter to one band (a second click restores them).
    @ObservationIgnored var bandsBeforeSummary: Set<Band>?
    /// The waterfall's newest rows (`nil` while the waterfall window is closed); wired by the app model.
    @ObservationIgnored public var spectrum: @MainActor () -> SignalHeard.Spectrum? = { nil }
    /// Turns the rotator to a call (the row menu); wired by the app model.
    @ObservationIgnored var rotorTurner: @MainActor (String, String?) -> Void = { _, _ in }

    private struct CacheKey: Equatable {
        let feed: Int
        let analysis: Int
        let active: Bool
        let multsOnly: Bool
        let bands: Set<Band>
        let modes: Set<String>
        let focusBand: Band?
        let column: AvailableColumn
        let ascending: Bool
    }

    struct Dependencies {
        let feed: SpotFeed
        let analysis: SpotAnalysisModel
        let contest: ContestModel
        let blacklist: BlacklistModel
        let callbook: CallbookModel
        let rig: RigModel
        let config: ConfigModel
        let status: StatusModel
        let now: @Sendable () -> Date
    }

    init(_ dependencies: Dependencies) {
        feed = dependencies.feed
        analysis = dependencies.analysis
        contest = dependencies.contest
        blacklist = dependencies.blacklist
        callbook = dependencies.callbook
        rig = dependencies.rig
        config = dependencies.config
        status = dependencies.status
        now = dependencies.now
    }

    /// Kotlin `!state.contest.isActive` → „Žádný aktivní závod."
    public var contestActive: Bool {
        contest.isActive
    }

    /// The rows, the matrix and the counts now (recomputed when the spots, the analysis or the filter changed).
    public func snapshot() -> Snapshot {
        let key = CacheKey(feed: feed.revision, analysis: analysis.revision, active: contest.isActive,
                           multsOnly: multsOnly, bands: bands, modes: modes,
                           focusBand: focusRadioOnly ? focusedBand : nil, column: sortColumn,
                           ascending: ascending)
        // The speaker column changes with the waterfall, not with the spots: it is never cached.
        if sortColumn == .heard {
            return compute(active: key.active, focusBand: key.focusBand)
        }
        if let cache, cache.key == key {
            return cache.snapshot
        }
        let computed: Snapshot = compute(active: key.active, focusBand: key.focusBand)
        cache = (key, computed)
        return computed
    }

    private func compute(active: Bool, focusBand: Band?) -> Snapshot {
        guard active else { return .empty }
        let spots: [DxSpot] = feed.filteredSnapshot()
        let all: [SpotRow] = analysis.current().spotRows(spots)
        var filtered: [SpotRow] = AvailableMults.filter(rows: all, multsOnly: multsOnly, bands: bands, modes: modes)
        if focusRadioOnly {
            // No band (no frequency yet) shows nothing: the filter is about the radio's band.
            filtered = filtered.filter { focusBand != nil && Band.from(frequencyHz: $0.freqHz) == focusBand }
        }
        var times: [String: Date] = [:]
        for row in filtered {
            if let spotted = feed.buffer.find(row.call) {
                times[row.call.uppercased()] = spotted.spottedAt
            }
        }
        let heard: SignalHeard.Spectrum? = sortColumn == .heard ? spectrum() : nil
        let sorted: [SpotRow] = AvailableMults.sorted(filtered, by: sortColumn, ascending: ascending) { row in
            AvailableRowFacts(spottedAt: times[row.call.uppercased()],
                              heard: heard?.hears(freqHz: row.freqHz) ?? false)
        }
        return Snapshot(rows: sorted, matrix: AvailableMults.matrix(rows: filtered),
                        counts: AvailableMults.Counts.of(filtered), spottedAt: times)
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
    public func sort(by column: AvailableColumn) {
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

    /// The row's spotter is a preferred one (N1MM's ★ column).
    public func isPreferred(_ row: SpotRow) -> Bool {
        feed.spotFilter().isPreferred(row.spotter)
    }

    /// A click on a row: tune to the call's spot, or (none left in the buffer) `qsy(freq, call)`. With two radios a
    /// spot on the other radio's band first takes the focus there (N1MM focus follows spot).
    public func click(_ row: SpotRow) {
        if bindsOtherRadio {
            if let spot = rig.spotForCall(row.call) {
                rig.tuneOtherToSpot(spot)
            } else {
                rig.qsyOtherRadio(Int64(row.freqHz))
            }
            return
        }
        rig.focusRadio(forSpotHz: row.freqHz)
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
