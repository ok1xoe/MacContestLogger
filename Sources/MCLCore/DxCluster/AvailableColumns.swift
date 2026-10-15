import Foundation

/// The columns of the Available window's spot list (N1MM Available: Call, Freq, Dir, Mode, SNR, Time, Spotter, the
/// points and the speaker of a spot heard in the spectrum). Which columns show, their order and their widths are the
/// user's (`DxClusterConfig.availColumns`, `availColumnWidths`); every column sorts. Post-port: v1.1.1 had a fixed
/// table sorted by Freq, Dir and Pts only (`AvailableMults.SortColumn`, kept for its parity).
public enum AvailableColumn: String, CaseIterable, Sendable {
    case call
    case freq
    case dir
    case mode
    case mult
    case snr
    case time
    case spotter
    case pts
    case heard

    /// The order of a fresh window: v1.1.1's columns with the spot time before the spotter; the speaker column is
    /// off until the user adds it (it needs the waterfall).
    public static let defaultOrder: [AvailableColumn] = [.call, .freq, .dir, .mode, .mult, .snr, .time, .spotter, .pts]

    /// The header (N1MM's short titles, not translated).
    public var title: String {
        switch self {
        case .call: "Call"
        case .freq: "Freq"
        case .dir: "Dir"
        case .mode: "Md"
        case .mult: "Mlt"
        case .snr: "SN"
        case .time: "Time"
        case .spotter: "Spotter"
        case .pts: "Pts"
        case .heard: "Sig"
        }
    }

    /// The share of the width a column starts with (hundredths; v1.1.1's weights).
    public var defaultWidth: Int {
        switch self {
        case .call, .spotter: 130
        case .freq: 100
        case .dir: 70
        case .mode, .time: 60
        case .mult, .snr, .pts: 50
        case .heard: 40
        }
    }

    /// The narrowest and widest share a drag can give a column.
    public static let widthRange: ClosedRange<Int> = 20...600

    /// The visible columns of a saved list in its order: unknown ids and repeats are dropped; an empty result is the
    /// default order. The call always shows (a row without it means nothing), first when the list lost it.
    public static func visible(_ ids: [String]) -> [AvailableColumn] {
        var out: [AvailableColumn] = []
        for id in ids {
            guard let column = AvailableColumn(rawValue: id), !out.contains(column) else { continue }
            out.append(column)
        }
        if out.isEmpty {
            return defaultOrder
        }
        if !out.contains(.call) {
            out.insert(.call, at: 0)
        }
        return out
    }

    /// Every column in the chooser's order: the visible ones as shown, then the hidden ones in their natural order.
    public static func chooserOrder(_ visible: [AvailableColumn]) -> [AvailableColumn] {
        visible + allCases.filter { !visible.contains($0) }
    }

    /// The saved width of a column, or its default (clamped into `widthRange`).
    public func width(in widths: [String: Int]) -> Int {
        let raw: Int = widths[rawValue] ?? defaultWidth
        return Swift.min(Self.widthRange.upperBound, Swift.max(Self.widthRange.lowerBound, raw))
    }
}

/// What a row of the Available window shows beyond `SpotRow`: when the spot arrived and whether its signal is seen in
/// the waterfall (the sort of those two columns needs them).
public struct AvailableRowFacts: Equatable, Sendable {
    public var spottedAt: Date?
    public var heard: Bool

    public init(spottedAt: Date? = nil, heard: Bool = false) {
        self.spottedAt = spottedAt
        self.heard = heard
    }
}

extension AvailableMults {

    /// The sort of any column. Freq, Dir and Pts keep v1.1.1's order exactly (`sorted(_:by:ascending:)`); the other
    /// columns sort stably by their value, descending is the reversed ascending order, and a row without the value
    /// (no SNR, no time) goes last either way. Time ascending is the newest spot first (the smallest age).
    public static func sorted(_ rows: [SpotRow], by column: AvailableColumn, ascending: Bool,
                              facts: (SpotRow) -> AvailableRowFacts = { _ in AvailableRowFacts() }) -> [SpotRow] {
        switch column {
        case .freq:
            return sorted(rows, by: SortColumn.freq, ascending: ascending)
        case .dir:
            return sorted(rows, by: SortColumn.dir, ascending: ascending)
        case .pts:
            return sorted(rows, by: SortColumn.pts, ascending: ascending)
        case .call:
            return ordered(rows, ascending) { $0.call.uppercased() }
        case .mode:
            return ordered(rows, ascending) { $0.mode.uppercased() }
        case .spotter:
            return ordered(rows, ascending) { $0.spotter.uppercased() }
        case .mult:
            return ordered(rows, ascending) { $0.newMultCount }
        case .heard:
            return ordered(rows, ascending) { facts($0).heard ? 1 : 0 }
        case .snr:
            return orderedPresent(rows, ascending) { $0.snr }
        case .time:
            // Newest first ascending: the later arrival sorts first.
            return orderedPresent(rows, ascending) { row in facts(row).spottedAt.map { -$0.timeIntervalSince1970 } }
        }
    }

    private static func ordered<Key: Comparable>(_ rows: [SpotRow], _ ascending: Bool,
                                                 _ key: (SpotRow) -> Key) -> [SpotRow] {
        let indexed: [(offset: Int, element: SpotRow)] = Array(rows.enumerated())
        let sorted: [SpotRow] = indexed.sorted { lhs, rhs in
            let a: Key = key(lhs.element)
            let b: Key = key(rhs.element)
            return a != b ? a < b : lhs.offset < rhs.offset
        }.map(\.element)
        return ascending ? sorted : Array(sorted.reversed())
    }

    private static func orderedPresent<Key: Comparable>(_ rows: [SpotRow], _ ascending: Bool,
                                                        _ key: (SpotRow) -> Key?) -> [SpotRow] {
        var present: [(row: SpotRow, key: Key)] = []
        var absent: [SpotRow] = []
        for row in rows {
            if let value = key(row) {
                present.append((row, value))
            } else {
                absent.append(row)
            }
        }
        let indexed: [(offset: Int, element: (row: SpotRow, key: Key))] = Array(present.enumerated())
        let sorted: [SpotRow] = indexed.sorted { lhs, rhs in
            lhs.element.key != rhs.element.key ? lhs.element.key < rhs.element.key : lhs.offset < rhs.offset
        }.map(\.element.row)
        return (ascending ? sorted : Array(sorted.reversed())) + absent
    }

    /// The bands of the summary panel: the user's choice (in band order), otherwise the active contest's bands,
    /// otherwise v1.1.1's six HF bands.
    public static func summaryBands(configured: [String], contestBands: Set<Band>) -> [Band] {
        let chosen: Set<Band> = Set(configured.compactMap { Band.from(adif: $0) })
        if !chosen.isEmpty {
            return Band.allCases.filter { chosen.contains($0) }
        }
        if !contestBands.isEmpty {
            return Band.allCases.filter { contestBands.contains($0) }
        }
        return matrixBands
    }

    /// N1MM highlights the best band of the summary: the most new multipliers, then the most new QSOs (the lower band
    /// on a tie); `nil` when no band has a workable spot.
    public static func bestBand(_ matrix: [Band?: Counts], bands: [Band]) -> Band? {
        var best: Band?
        var bestCounts: Counts = .zero
        for band in bands {
            let counts: Counts = matrix[band] ?? .zero
            guard counts.mults > 0 || counts.qs > 0 else { continue }
            if best == nil || counts.mults > bestCounts.mults
                || (counts.mults == bestCounts.mults && counts.qs > bestCounts.qs) {
                best = band
                bestCounts = counts
            }
        }
        return best
    }
}
