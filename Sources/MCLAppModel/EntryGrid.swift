import Foundation
import MCLCore

/// The band × mode grid of the entry window (Kotlin `BandColumns`/`BandColumn`, `K:EntryPanel.kt:1708-1786`, over
/// `AppState.entryGridColumns`, `entryGridBands`, `entryGridRowBands`, `KA:3766-3991`): which columns and rows are
/// shown, which cells are clickable, which one is active, and what a click tunes to.
public struct EntryGrid: Equatable, Sendable {

    /// One cell of the grid.
    public struct Cell: Equatable, Sendable {
        /// Segment start the click tunes to; `nil` = the band has no segment for this mode.
        public let kHz: Double?
        /// Clickable: the band is allowed and has a segment.
        public let enabled: Bool
        /// The current band in the current mode's column.
        public let active: Bool
    }

    /// Shown columns in the fixed Kotlin order CW, PH, RY, DI.
    public let columns: [EntryGridPolicy.ModeColumn]
    /// Shown rows (`BAND_ROWS` filtered by the definition's bands).
    public let rows: [BandRows.Row]
    /// Clickable bands (the BAND category).
    public let enabledBands: Set<Band>

    public init(columns: Set<EntryGridPolicy.ModeColumn>, enabledBands: Set<Band>, rowBands: Set<Band>) {
        self.columns = EntryGridPolicy.ModeColumn.allCases.filter { columns.contains($0) }
        self.rows = BandRows.all.filter { rowBands.contains($0.band) }
        self.enabledBands = enabledBands
    }

    /// The grid for the active contest; outside a contest every column and band.
    @MainActor
    public static func of(_ contest: ContestModel) -> EntryGrid {
        guard contest.isActive else {
            // Without a contest the grid looks as before: the 13 Java bands (microwaves only in a contest that lists them).
            let all = Set(Band.javaV111Cases)
            return EntryGrid(columns: Set(EntryGridPolicy.ModeColumn.allCases), enabledBands: all, rowBands: all)
        }
        let definition: ContestDefinition? = contest.definition
        let category: [String: String] = contest.activeSetup?.category ?? [:]
        let columns = EntryGridPolicy.columnsFor(category["MODE"], definition?.modes ?? [])
        let bands = EntryGridPolicy.bandsFor(category["BAND"], definition?.bands ?? [])
        let defined = EntryGridPolicy.bandsFor("ALL", definition?.bands ?? [])
        let rowBands: Set<Band> = defined.isEmpty ? Set(Band.javaV111Cases) : defined
        return EntryGrid(columns: columns, enabledBands: bands, rowBands: rowBands)
    }

    public func cell(_ row: BandRows.Row, _ column: EntryGridPolicy.ModeColumn, currentBand: Band?,
                     currentMode: Mode) -> Cell {
        let kHz: Double? = row.startKHz(Self.bandRowsColumn(column))
        let enabled: Bool = enabledBands.contains(row.band) && kHz != nil
        let active: Bool = enabled && Self.isActive(column, mode: currentMode) && row.band == currentBand
        return Cell(kHz: kHz, enabled: enabled, active: active)
    }

    /// Column header (Kotlin literals).
    public static func title(_ column: EntryGridPolicy.ModeColumn) -> String {
        switch column {
        case .CW: return "CW"
        case .PH: return "PH"
        case .RY: return "RY"
        case .DI: return "DI"
        }
    }

    /// The mode a click in the column sets (Kotlin `onQsy(f, Mode.CW|SSB|RTTY|DIGITAL)`).
    public static func mode(_ column: EntryGridPolicy.ModeColumn) -> Mode {
        switch column {
        case .CW: return .cw
        case .PH: return .ssb
        case .RY: return .rtty
        case .DI: return .digital
        }
    }

    /// Kotlin `columnActive`: CW → CW; SSB/FM/AM → PH; RTTY → RY; PSK/FT8/FT4/DIGITAL → DI (JT65 → none).
    public static func isActive(_ column: EntryGridPolicy.ModeColumn, mode: Mode) -> Bool {
        switch column {
        case .CW: return mode == .cw
        case .PH: return mode == .ssb || mode == .fm || mode == .am
        case .RY: return mode == .rtty
        case .DI: return mode == .psk || mode == .ft8 || mode == .ft4 || mode == .digital
        }
    }

    private static func bandRowsColumn(_ column: EntryGridPolicy.ModeColumn) -> BandRows.Column {
        switch column {
        case .CW: return .cw
        case .PH: return .ph
        case .RY: return .ry
        case .DI: return .di
        }
    }
}
