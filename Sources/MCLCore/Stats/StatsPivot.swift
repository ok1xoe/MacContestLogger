import Foundation

/// A dimension of the Statistics window's pivot (N1MM Statistics: Zone, Section, Points, Mult, WPX prefix, grid,
/// radio, Mode & Band, Exchange…, 5/10/15-minute rows). The fixed ones of `LogStatistics.Dimension` plus the ones
/// N1MM adds, and the active contest's own: its received exchange fields and its multipliers.
public enum StatsDimension: Hashable, Sendable {
    /// One of the fixed dimensions (hour, day, band, mode, continent, country, operator, Run/S&P, none).
    case base(LogStatistics.Dimension)
    /// Time rows of `n` minutes (5, 10, 15).
    case minutes(Int)
    /// Band and mode together (`20m CW`).
    case modeBand
    /// The QSO points by the contest rules.
    case points
    /// Whether the QSO brought a new multiplier.
    case newMultiplier
    /// The multi-op station the QSO was logged on.
    case station
    /// A received exchange field of the contest (its id).
    case exchange(String)
    /// A multiplier of the contest (its binding id) with its label.
    case multiplier(id: String, label: String)

    /// The rows the window offers before the contest's own: the fixed ones, the minute rows and N1MM's extras.
    public static let general: [StatsDimension] = LogStatistics.Dimension.allCases.filter { $0 != .NONE }
        .flatMap { dimension -> [StatsDimension] in
            dimension == .HOUR ? [.base(.HOUR)] + StatsPivot.minuteBuckets.map { .minutes($0) } : [.base(dimension)]
        } + [.modeBand, .station]

    /// The dimensions that need the contest's replay (points, multipliers, the parsed exchange).
    public var needsContest: Bool {
        switch self {
        case .points, .newMultiplier, .exchange, .multiplier: return true
        default: return false
        }
    }
}

/// What a contest replay says about one QSO for the statistics.
public struct StatsFact: Equatable, Sendable {
    public var points: Int
    public var dupe: Bool
    public var newMultiplier: Bool
    /// Received exchange values by field id (canonical).
    public var exchange: [String: String]
    /// Multiplier values by binding id (the set's label of the value).
    public var multipliers: [String: String]

    public init(points: Int, dupe: Bool, newMultiplier: Bool, exchange: [String: String] = [:],
                multipliers: [String: String] = [:]) {
        self.points = points
        self.dupe = dupe
        self.newMultiplier = newMultiplier
        self.exchange = exchange
        self.multipliers = multipliers
    }
}

/// The Statistics window's pivot over any `StatsDimension`.
public enum StatsPivot {

    /// N1MM's time rows of 5, 10 and 15 minutes.
    public static let minuteBuckets: [Int] = [5, 10, 15]

    /// The contest's own dimensions: its received exchange fields (without the report and the serial number) and
    /// its multipliers.
    public static func contestDimensions(_ definition: ContestDefinition?) -> [StatsDimension] {
        guard let definition else { return [.points, .newMultiplier] }
        var out: [StatsDimension] = [.points, .newMultiplier]
        for field in definition.exchange?.received ?? [] {
            guard let field, let id = field.id, !id.isEmpty else { continue }
            switch field.type {
            case .RST, .RS, .SERIAL, .QTC:
                continue
            default:
                out.append(.exchange(id))
            }
        }
        var seen: Set<String> = []
        for binding in definition.multipliers ?? [] {
            guard let binding, let id = binding.id ?? binding.set, !seen.contains(id) else { continue }
            seen.insert(id)
            out.append(.multiplier(id: id, label: binding.label ?? binding.set ?? id))
        }
        return out
    }

    /// Replays the log into a fresh session and keeps what the statistics need of every replayed QSO.
    public static func facts(_ fresh: ContestSession, _ qsos: [Qso], now: () -> Date = Date.init)
        -> [Int64: StatsFact] {
        var out: [Int64: StatsFact] = [:]
        var labels = QsoMarks.Labels(session: fresh)
        _ = ContestReplay.replay(fresh, qsos, now: now) { qso, result in
            guard let id = qso.id else { return }
            var exchange: [String: String] = [:]
            for entry in result.context.received?.entries ?? [] {
                guard let key = entry.key, let value = entry.value else { continue }
                let text: String = value.canonical ?? value.raw ?? ""
                if !text.isEmpty {
                    exchange[key] = text
                }
            }
            var multipliers: [String: String] = [:]
            var newMultiplier: Bool = false
            for m in result.multipliers {
                guard let key = m.key, let binding = m.bindingId ?? m.setId else { continue }
                if multipliers[binding] == nil {
                    multipliers[binding] = labels.label(setId: m.setId, key: key)
                }
                if m.isNew && m.countsAsMultiplier {
                    newMultiplier = true
                }
            }
            out[id] = StatsFact(points: Int(result.points), dupe: result.dupe, newMultiplier: newMultiplier,
                                exchange: exchange, multipliers: multipliers)
        }
        return out
    }

    /// The pivot of `qsos` by two dimensions. `includeDupes: false` leaves out the dupes and the X-QSOs (N1MM's
    /// „Include dupes and X-QSOs" off); deleted QSOs never count.
    public static func pivot(_ qsos: [Qso], rows: StatsDimension, columns: StatsDimension,
                             facts: [Int64: StatsFact] = [:], includeDupes: Bool = true) -> LogStatistics.Pivot {
        let counted: [Qso] = includeDupes ? qsos : qsos.filter { qso in
            !qso.xqso && !(qso.id.flatMap { facts[$0] }?.dupe ?? false)
        }
        let fact: (Qso) -> StatsFact? = { qso in qso.id.flatMap { facts[$0] } }
        return LogStatistics.pivot(counted, rowKey: { key(rows, $0, fact($0)) }, rowOrder: order(rows),
                                   colKey: { key(columns, $0, fact($0)) }, colOrder: order(columns))
    }

    /// The key of a QSO in a dimension (`?` = unknown).
    public static func key(_ dimension: StatsDimension, _ qso: Qso, _ fact: StatsFact?) -> String {
        switch dimension {
        case .base(let base):
            return LogStatistics.key(base, qso)
        case .minutes(let minutes):
            guard let time = qso.timestampUtc, let stamp = UtcStamp(time), let minute = Int(stamp.mm) else {
                return "?"
            }
            let bucket: Int = minute / max(minutes, 1) * max(minutes, 1)
            return stamp.MM + "-" + stamp.dd + " " + stamp.HH + ":" + (bucket < 10 ? "0" : "") + String(bucket)
        case .modeBand:
            return (qso.band?.adif ?? "?") + " " + (qso.mode?.rawValue ?? "?")
        case .points:
            return fact.map { String($0.points) } ?? "?"
        case .newMultiplier:
            guard let fact else { return "?" }
            return fact.newMultiplier ? "MULT" : "—"
        case .station:
            return KotlinText.isBlank(qso.stationId) ? "?" : qso.stationId
        case .exchange(let id):
            return fact?.exchange[id] ?? "?"
        case .multiplier(let id, _):
            return fact?.multipliers[id] ?? "?"
        }
    }

    static func order(_ dimension: StatsDimension) -> LogStatistics.Order {
        switch dimension {
        case .base(let base):
            return LogStatistics.order(base)
        case .minutes:
            return .chronological
        case .modeBand:
            return .band
        case .points, .exchange:
            return .numericOrCount
        case .newMultiplier, .station, .multiplier:
            return .byCount
        }
    }
}
