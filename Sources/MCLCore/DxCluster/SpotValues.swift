import Foundation

/// Status of a spotted station against the active contest (the band-map colour) — Kotlin `SpotStatus`
/// (`ui/contest/ContestController.kt:19-21`, v1.1.1). Outside a contest it is neutral (`false`, `0`).
public struct SpotStatus: Sendable, Equatable, Hashable {
    public let dupe: Bool
    public let newMultCount: Int

    public init(dupe: Bool, newMultCount: Int) {
        self.dupe = dupe
        self.newMultCount = newMultCount
    }

    /// Kotlin `newMult = newMultCount > 0`.
    public var newMult: Bool {
        newMultCount > 0
    }

    /// The neutral status (outside a contest, blank call, no band, irrelevant mode).
    public static let neutral = SpotStatus(dupe: false, newMultCount: 0)
}

/// One row of the available-spots overview (N1MM Available) — Kotlin `SpotRow` (`ContestController.kt:24-36`),
/// fields in the Kotlin order.
public struct SpotRow: Sendable, Equatable, Hashable {
    public let call: String
    public let freqHz: Int
    public let azimuth: Int?
    public let mode: String
    public let newMultCount: Int
    public let dupe: Bool
    public let snr: Int?
    public let points: Int
    public let spotter: String

    public init(call: String, freqHz: Int, azimuth: Int?, mode: String, newMultCount: Int, dupe: Bool, snr: Int?,
                points: Int, spotter: String) {
        self.call = call
        self.freqHz = freqHz
        self.azimuth = azimuth
        self.mode = mode
        self.newMultCount = newMultCount
        self.dupe = dupe
        self.snr = snr
        self.points = points
        self.spotter = spotter
    }

    /// Kotlin `isMult = newMultCount > 0`.
    public var isMult: Bool {
        newMultCount > 0
    }
}

/// State of one multiplier-grid cell (key × band) — Kotlin `MultCell` (`ContestController.kt:39`); `rawValue` is
/// the Kotlin constant name.
public enum MultCell: String, Sendable, Equatable, CaseIterable {
    case empty = "EMPTY"
    case worked = "WORKED"
    case spotted = "SPOTTED"
    case spottedDbl = "SPOTTED_DBL"
}

/// One row of the multiplier grid — Kotlin `MultGridRow` (`ContestController.kt:42-48`). `cells` is keyed by the
/// ADIF band of `SpotAnalyzer.multGridBands` (Kotlin `associate` keeps that order; iterate the bands for it).
public struct MultGridRow: Sendable, Equatable {
    public let key: String
    public let label: String
    public let prefix: String
    public let continent: String
    public let cells: [String: MultCell]

    public init(key: String, label: String, prefix: String, continent: String, cells: [String: MultCell]) {
        self.key = key
        self.label = label
        self.prefix = prefix
        self.continent = continent
        self.cells = cells
    }
}

/// The multiplier grid of one kind with worked/possible — Kotlin `MultGridView` (`ContestController.kt:51-62`).
public struct MultGridView: Sendable, Equatable {

    /// Kotlin `Pair<String, String>` key of `spotAt`: (multiplier key, ADIF band).
    public struct CellKey: Sendable, Hashable {
        public let key: String
        public let band: String

        public init(key: String, band: String) {
            self.key = key
            self.band = band
        }
    }

    public let available: Bool
    public let worked: Int
    /// `-1` for a non-enumerable set (grid fields, WPX).
    public let possible: Int
    public let rows: [MultGridRow]
    /// The spot on a cell (key, band) for tuning by a click — only spotted cells; the first spot in buffer order.
    public let spotAt: [CellKey: DxSpot]

    public init(available: Bool, worked: Int, possible: Int, rows: [MultGridRow], spotAt: [CellKey: DxSpot] = [:]) {
        self.available = available
        self.worked = worked
        self.possible = possible
        self.rows = rows
        self.spotAt = spotAt
    }

    /// Kotlin `MultGridView.UNAVAILABLE`.
    public static let unavailable = MultGridView(available: false, worked: 0, possible: 0, rows: [])
}
