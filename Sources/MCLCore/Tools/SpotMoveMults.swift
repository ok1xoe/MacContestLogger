import Foundation

/// N1MM's Move Multipliers window over the spots: one row per spotted call and mode, a column per band with the new
/// multipliers (M1 / M2), the QSO points or the QSO count, the spotted bands shaded. Pure apart from the analyzer's
/// preview.
public enum SpotMoveMults {

    /// What the band cells show (N1MM Display Options › Type).
    public enum Display: String, CaseIterable, Sendable {
        case multipliers = "MULT"
        case points = "POINTS"
        case counts = "COUNTS"
    }

    /// Which spots are listed (N1MM Select Band & Mode › Modes).
    public enum ModeFilter: String, CaseIterable, Sendable {
        case contest = "CONTEST"
        case all = "ALL"
        case cw = "CW"
        case phone = "PHONE"
        case digi = "DIGI"
    }

    /// One band of a row.
    public struct Cell: Equatable, Sendable {
        /// New multipliers when worked on the band (0 = none).
        public let newMults: Int
        /// Points when worked on the band (0 for a dupe).
        public let points: Int
        /// QSOs already logged with the call in the row's mode on the band.
        public let count: Int
        /// The latest spot of the call on the band, when spotted there.
        public let spot: DxSpot?

        public init(newMults: Int, points: Int, count: Int, spot: DxSpot?) {
            self.newMults = newMults
            self.points = points
            self.count = count
            self.spot = spot
        }
    }

    /// One spotted call in one mode category.
    public struct Row: Equatable, Sendable, Identifiable {
        public let call: String
        /// `CW`, `PHONE` or `DIGI`.
        public let mode: String
        /// By ADIF band.
        public let cells: [String: Cell]

        public var id: String { call + "/" + mode }

        /// The spotted bands in the order of `bands`.
        public func spottedBands(_ bands: [Band]) -> [Band] {
            bands.filter { cells[$0.adif]?.spot != nil }
        }

        /// The points of the row (N1MM shows the same value in every band column): the best of the bands.
        public var points: Int {
            cells.values.map(\.points).max() ?? 0
        }

        /// The QSOs already logged with the call in the mode.
        public var count: Int {
            cells.values.reduce(0) { $0 + $1.count }
        }
    }

    /// The text of a cell: `M1` / `M2` (two or more) or blank; the row's points; the count or `-` where not worked.
    public static func text(_ row: Row, band: Band, display: Display) -> String {
        let cell: Cell? = row.cells[band.adif]
        switch display {
        case .multipliers:
            guard let mults = cell?.newMults, mults > 0 else { return "" }
            return mults == 1 ? "M1" : "M2"
        case .points:
            return String(row.points)
        case .counts:
            guard let count = cell?.count, count > 0 else { return "-" }
            return String(count)
        }
    }

    /// N1MM Display Count Range: `3-5` or `5` (0…100); anything else → the default 0–6.
    public static func range(_ text: String) -> ClosedRange<Int> {
        let parts: [Int] = text.split(separator: "-", omittingEmptySubsequences: false).compactMap {
            Int($0.trimmingCharacters(in: .whitespaces))
        }
        let valid: (Int) -> Bool = { $0 >= 0 && $0 <= 100 }
        if parts.count == 1, valid(parts[0]) {
            return parts[0]...parts[0]
        }
        if parts.count == 2, valid(parts[0]), valid(parts[1]), parts[0] <= parts[1] {
            return parts[0]...parts[1]
        }
        return defaultRange
    }

    public static let defaultRange: ClosedRange<Int> = 0...6

    /// The rows the display keeps: with multipliers those with a new multiplier on a band, with points or counts
    /// those whose value is in the range.
    public static func filter(_ rows: [Row], display: Display, range: ClosedRange<Int>) -> [Row] {
        rows.filter { row in
            switch display {
            case .multipliers: return row.cells.values.contains { $0.newMults > 0 }
            case .points: return range.contains(row.points)
            case .counts: return range.contains(row.count)
            }
        }
    }

    /// Whether a spot's mode category passes the filter (`contestCategories` = the contest's mode categories).
    public static func passes(_ category: String, _ filter: ModeFilter, contestCategories: Set<String>) -> Bool {
        switch filter {
        case .all: return true
        case .contest: return contestCategories.isEmpty || contestCategories.contains(category)
        case .cw: return category == SpotModeCategory.cw
        case .phone: return category == SpotModeCategory.phone
        case .digi: return category == SpotModeCategory.digi
        }
    }

    /// The QSOs with each call in each mode category on each band (X-QSOs and deleted ones left out):
    /// `CALL/CATEGORY` → band → count.
    public static func counts(_ qsos: [Qso]) -> [String: [String: Int]] {
        var out: [String: [String: Int]] = [:]
        for qso in qsos where !qso.deleted && !qso.xqso {
            guard let band = qso.band, let mode = qso.mode else { continue }
            let key: String = qso.call.uppercased() + "/" + SpotModeCategory.of(mode.rawValue)
            out[key, default: [:]][band.adif, default: 0] += 1
        }
        return out
    }
}

extension SpotAnalyzer {

    /// N1MM Move Multipliers over the spots: the spotted calls (not mine, not my own spots) whose mode passes
    /// `modes`, newest spot first, each evaluated by a preview on every band of `bands` in its mode.
    public func moveMultRows(spots: [DxSpot], bands: [Band], modes: SpotMoveMults.ModeFilter,
                             qsos: [Qso]) -> [SpotMoveMults.Row] {
        guard let session else { return [] }
        let contestCategories: Set<String> = Set((session.definition.modes ?? []).compactMap { $0 }
            .map(SpotModeCategory.of))
        let counts: [String: [String: Int]] = SpotMoveMults.counts(qsos)
        let received: [ContestDefinition.ExchangeField?] = session.definition.exchange?.received ?? []
        var order: [String] = []
        var latest: [String: (mode: String, category: String, spot: DxSpot, byBand: [String: DxSpot])] = [:]
        for spot in spots.reversed() {
            let call: String = spot.dxCall.uppercased()
            guard !KotlinText.isBlank(call), !spot.selfSpotted, !JavaText.equals(call, myCall.uppercased()),
                  let band = Band.from(frequencyHz: spot.freqHz) else { continue }
            let mode: String = resolveSpotMode(call: call, freqHz: spot.freqHz, comment: spot.comment)
            let category: String = SpotModeCategory.of(mode)
            guard SpotMoveMults.passes(category, modes, contestCategories: contestCategories) else { continue }
            let key: String = call + "/" + category
            if latest[key] == nil {
                order.append(key)
                latest[key] = (mode, category, spot, [:])
            }
            if latest[key]?.byBand[band.adif] == nil {
                latest[key]?.byBand[band.adif] = spot
            }
        }
        var rows: [SpotMoveMults.Row] = []
        for key in order {
            guard let entry = latest[key] else { continue }
            let call: String = entry.spot.dxCall.uppercased()
            let estimated = SpotExchangeEstimator.estimate(received, call, dxcc, hqCalls: hqCalls)
            let exchange = withHamQth(entry.spot, received, estimated)
            var cells: [String: SpotMoveMults.Cell] = [:]
            for band in bands {
                let result = try? session.preview(call: call, band: band.adif, mode: entry.mode,
                                                  receivedRaw: exchange, at: now())
                let mults: Int = result.map { $0.dupe ? 0 : Self.newMultCount($0) } ?? 0
                let points: Int = result.map { $0.dupe ? 0 : Int($0.points) } ?? 0
                cells[band.adif] = SpotMoveMults.Cell(newMults: mults, points: points,
                                                      count: counts[key]?[band.adif] ?? 0,
                                                      spot: entry.byBand[band.adif])
            }
            rows.append(SpotMoveMults.Row(call: call, mode: entry.category, cells: cells))
        }
        return rows
    }
}
