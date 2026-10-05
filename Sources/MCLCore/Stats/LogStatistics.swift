import Foundation

/// Pivot statistics of the log (N1MM Statistics, DXLog Summary/Statistics): QSO counts in a
/// row × column table by the chosen dimensions (hour, band, mode, continent, country, operator, day,
/// Run/S&P). Deleted QSOs are not counted. Port of `stats/LogStatistics.java` (Java v1.1.1) — `pivot`,
/// `Dimension` and `Pivot`, which `LogExports.summary` needs, and
/// `perHour` (for the statistics window).
///
/// Keys are compared as Java `String` (by UTF-16, not canonically) and sorted by `compareTo`.
public enum LogStatistics {

    /// Pivot dimension. Case names = Java constant names.
    public enum Dimension: String, CaseIterable, Sendable {
        case HOUR, DAY, BAND, MODE, CONTINENT, COUNTRY, OPERATOR, RUN_SP, NONE

        public var label: String {
            switch self {
            case .HOUR: "Hodina UTC"
            case .DAY: "Den"
            case .BAND: "Pásmo"
            case .MODE: "Mód"
            case .CONTINENT: "Kontinent"
            case .COUNTRY: "Země"
            case .OPERATOR: "Operátor"
            case .RUN_SP: "Run / S&P"
            case .NONE: "—"
            }
        }
    }

    /// Result: row and column labels (sorted), counts and totals.
    public struct Pivot: Equatable, Sendable {
        public let rows: [String]
        public let cols: [String]
        public let total: Int
        private let counts: [JavaStringKey: [JavaStringKey: Int]]
        private let rowTotals: [JavaStringKey: Int]
        private let colTotals: [JavaStringKey: Int]

        init(rows: [String], cols: [String], counts: [JavaStringKey: [JavaStringKey: Int]],
             rowTotals: [JavaStringKey: Int], colTotals: [JavaStringKey: Int], total: Int) {
            self.rows = rows
            self.cols = cols
            self.counts = counts
            self.rowTotals = rowTotals
            self.colTotals = colTotals
            self.total = total
        }

        /// Count in a cell; a missing cell = 0.
        public func count(_ row: String, _ col: String) -> Int {
            counts[JavaStringKey(row)]?[JavaStringKey(col)] ?? 0
        }

        /// `rowTotals().get(row)` — `nil` for an unknown row (Java `null`).
        public func rowTotal(_ row: String) -> Int? {
            rowTotals[JavaStringKey(row)]
        }

        /// `colTotals().get(col)` — `nil` for an unknown column.
        public func colTotal(_ col: String) -> Int? {
            colTotals[JavaStringKey(col)]
        }
    }

    public static func pivot(_ qsos: [Qso], _ rowDim: Dimension, _ colDim: Dimension) -> Pivot {
        var counts: [JavaStringKey: [JavaStringKey: Int]] = [:]
        var rowTotals: [JavaStringKey: Int] = [:]
        var colTotals: [JavaStringKey: Int] = [:]
        // Order of first occurrence (`LinkedHashMap.keySet`) — input of the stable sort.
        var rowOrder: [String] = []
        var colOrder: [String] = []
        var total = 0
        for q in qsos where !q.deleted {
            let r = key(rowDim, q)
            let c = key(colDim, q)
            let rk = JavaStringKey(r)
            let ck = JavaStringKey(c)
            counts[rk, default: [:]][ck, default: 0] += 1
            if rowTotals[rk] == nil { rowOrder.append(r) }
            rowTotals[rk, default: 0] += 1
            if colTotals[ck] == nil { colOrder.append(c) }
            colTotals[ck, default: 0] += 1
            total += 1
        }
        return Pivot(rows: sorted(rowOrder, rowDim, rowTotals), cols: sorted(colOrder, colDim, colTotals),
                     counts: counts, rowTotals: rowTotals, colTotals: colTotals, total: total)
    }

    /// QSOs by hour (for the graph): "MM-dd HHZ" → count, chronologically — Java `TreeMap`
    /// (`compareTo` ordering). Deleted QSOs and QSOs without a time are not counted.
    public static func perHour(_ qsos: [Qso]) -> JavaLinkedMap<Int> {
        var counts: [JavaStringKey: Int] = [:]
        var order: [String] = []
        for q in qsos where !q.deleted && q.timestampUtc != nil {
            let k: String = key(.HOUR, q)
            let jk = JavaStringKey(k)
            if counts[jk] == nil { order.append(k) }
            counts[jk, default: 0] += 1
        }
        let sortedKeys: [String] = order.sorted { (a: String, b: String) -> Bool in JavaText.compare(a, b) < 0 }
        var out = JavaLinkedMap<Int>()
        for k in sortedKeys {
            out.put(k, counts[JavaStringKey(k)])
        }
        return out
    }

    static func key(_ d: Dimension, _ q: Qso) -> String {
        switch d {
        case .HOUR:
            guard let t = q.timestampUtc, let s = UtcStamp(t) else { return "?" }
            return s.MM + "-" + s.dd + " " + s.HH + "Z"
        case .DAY:
            guard let t = q.timestampUtc, let s = UtcStamp(t) else { return "?" }
            return s.yyyy + "-" + s.MM + "-" + s.dd
        case .BAND:
            return q.band?.adif ?? "?"
        case .MODE:
            return q.mode?.rawValue ?? "?"
        case .CONTINENT:
            return blank(q.continent)
        case .COUNTRY:
            return blank(q.dxccName)
        case .OPERATOR:
            return blank(q.operator)
        case .RUN_SP:
            // Java `getRunMode() == null ? "?"` — in Swift `runMode` is non-optional.
            return q.runMode.rawValue
        case .NONE:
            return "Celkem"
        }
    }

    private static func blank(_ s: String) -> String {
        JavaText.isBlank(s) ? "?" : s
    }

    /// Hours and days by `compareTo`, bands by `lowHz` (unknown at the end), others by
    /// count descending and then `compareTo`. The sort is stable (`List.sort`).
    private static func sorted(_ keys: [String], _ d: Dimension, _ totals: [JavaStringKey: Int]) -> [String] {
        let indexed: [(offset: Int, element: String)] = Array(keys.enumerated())
        let ordered: [(offset: Int, element: String)]
        switch d {
        case .HOUR, .DAY:
            ordered = indexed.sorted { a, b in
                let order = JavaText.compare(a.element, b.element)
                return order != 0 ? order < 0 : a.offset < b.offset
            }
        case .BAND:
            ordered = indexed.sorted { a, b in
                let la = Band.from(adif: a.element)?.lowHz ?? Int.max
                let lb = Band.from(adif: b.element)?.lowHz ?? Int.max
                return la != lb ? la < lb : a.offset < b.offset
            }
        default:
            ordered = indexed.sorted { a, b in
                let ta = totals[JavaStringKey(a.element)] ?? 0
                let tb = totals[JavaStringKey(b.element)] ?? 0
                if ta != tb { return ta > tb }
                let order = JavaText.compare(a.element, b.element)
                return order != 0 ? order < 0 : a.offset < b.offset
            }
        }
        return ordered.map(\.element)
    }
}
