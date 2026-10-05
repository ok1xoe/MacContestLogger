import Foundation

/// Score breakdown by band and mode (N1MM Score Summary / DXLog Summary). Computed by
/// replaying the logbook into a fresh session, so it matches the score recomputation. A multiplier is
/// credited to the band and mode where it was first made (for scope ONCE thus only once).
///
/// Port of Java `contest/runtime/ScoreBreakdown.java`. Like Java it counts
/// **uncounted QSOs** into the cells too (FT8 in a CW contest, a mode outside the contest), so `total.qsos`
/// may be greater than `score.qsoCount`. The order of all lists is Java's: bands by
/// definition (unknown ones at the end in order of occurrence), modes and rows in order of occurrence (chronological),
/// `multIds` in definition order. Keys (band, mode, binding id) are compared by UTF-16.
public struct ScoreBreakdown: Sendable {

    /// One breakdown cell (band × mode, a band, mode or overall total). Numbers are Java
    /// `int`/`long` (they wrap, they do not crash).
    public struct Cell: Equatable, Sendable {
        public private(set) var qsos: Int32 = 0
        public private(set) var dupes: Int32 = 0
        public private(set) var points: Int64 = 0
        /// New multipliers per binding (id → count), a Java `LinkedHashMap` (a `nil` id is allowed).
        private var multCounts = JavaLinkedMap<Int32>()

        public init() {}

        /// New multipliers per binding (id → count); an unknown id → 0.
        public func mults(_ bindingId: String?) -> Int32 {
            multCounts[bindingId] ?? 0
        }

        public var multTotal: Int32 {
            multCounts.entries.reduce(Int32(0)) { JavaMath.addInt($0, $1.value ?? 0) }
        }

        mutating func add(_ r: ContestSession.LogResult) {
            qsos = JavaMath.addInt(qsos, 1)
            if r.dupe {
                dupes = JavaMath.addInt(dupes, 1)
            }
            points = JavaMath.addLong(points, Int64(r.points))
            for m in r.multipliers where m.isNew && m.countsAsMultiplier {
                multCounts.put(m.bindingId, JavaMath.addInt(multCounts[m.bindingId] ?? 0, 1))
            }
        }
    }

    /// Table row: band × mode.
    public struct Row: Equatable, Sendable {
        public let band: String
        public let mode: String
        public let cell: Cell
    }

    /// Ids of the multiplier bindings in definition order (also a `nil` id; a `nil` binding is omitted —
    /// Java fails on it).
    public let multIds: [String?]
    private let multLabels: JavaLinkedMap<String>
    private let byBandMode: JavaLinkedMap<JavaLinkedMap<Cell>>
    private let byBand: JavaLinkedMap<Cell>
    private let byMode: JavaLinkedMap<Cell>
    public let total: Cell
    /// Score of the whole replayed session (incl. bonuses).
    public let score: ScoreState
    /// How many QSOs could not be replayed (Java `skipped`).
    public let skipped: Int
    /// The first replay error (Java swallows it); `nil` = none. For a UI message.
    public let firstError: ContestSessionError?

    /// Replays `qsos` into the fresh session `fresh` and builds the breakdown. `now` = "now" for QSOs
    /// without a time (`ContestReplay.replay(_:_:now:)`).
    ///
    /// - Throws: a score computation error (`score()`), like Java.
    public static func compute(_ fresh: ContestSession, _ qsos: [Qso],
                               now: () -> Date = Date.init) throws(ExpressionError) -> ScoreBreakdown {
        var multIds: [String?] = []
        var multLabels = JavaLinkedMap<String>()
        for case let m? in fresh.definition.multipliers ?? [] {
            multIds.append(m.id)
            let label = m.label.flatMap { JavaText.isBlank($0) ? nil : $0 }
            multLabels.put(m.id, label ?? m.id)
        }
        var byBandMode = JavaLinkedMap<JavaLinkedMap<Cell>>()
        var byBand = JavaLinkedMap<Cell>()
        var byMode = JavaLinkedMap<Cell>()
        var total = Cell()
        let outcome = ContestReplay.replay(fresh, qsos, now: now) { q, r in
            // The replayer calls the listener only for QSOs with a band.
            guard let band = q.band?.adif else { return }
            let mode = q.mode?.rawValue ?? "?"
            var modes = byBandMode[band] ?? JavaLinkedMap<Cell>()
            Self.add(&modes, mode, r)
            byBandMode.put(band, modes)
            Self.add(&byBand, band, r)
            Self.add(&byMode, mode, r)
            total.add(r)
        }
        return ScoreBreakdown(multIds: multIds, multLabels: multLabels, byBandMode: byBandMode, byBand: byBand,
                              byMode: byMode, total: total, score: try outcome.session.score(),
                              skipped: outcome.skipped, firstError: outcome.firstError)
    }

    /// Java `computeIfAbsent(key, k -> new Cell()).add(r)`.
    private static func add(_ map: inout JavaLinkedMap<Cell>, _ key: String, _ r: ContestSession.LogResult) {
        var cell = map[key] ?? Cell()
        cell.add(r)
        map.put(key, cell)
    }

    /// Binding label: `label` when non-empty, otherwise the id; an unknown id → the id itself.
    public func multLabel(_ id: String?) -> String? {
        multLabels.containsKey(id) ? multLabels[id] : id
    }

    /// Bands in definition order (only those with QSOs), outside the definition at the end in order of occurrence.
    /// Java `order.indexOf` (by UTF-16) and a stable sort.
    public func bands(_ order: [String?]?) -> [String] {
        let keys = byBand.keys.compactMap { $0 }
        let ranked = keys.enumerated().map { offset, band -> (Int, Int, String) in
            let index = order?.firstIndex { $0.map { JavaText.equals($0, band) } ?? false }
            return (index ?? Int.max, offset, band)
        }
        return ranked.sorted { ($0.0, $0.1) < ($1.0, $1.1) }.map(\.2)
    }

    /// Modes in order of occurrence (`?` = a QSO without a mode).
    public var modes: [String] {
        byMode.keys.compactMap { $0 }
    }

    /// Band × mode rows (bands in definition order, modes in order of occurrence).
    public func rows(_ bandOrder: [String?]?) -> [Row] {
        var out: [Row] = []
        for band in bands(bandOrder) {
            for entry in (byBandMode[band] ?? JavaLinkedMap()).entries {
                guard let mode = entry.key, let cell = entry.value else { continue }
                out.append(Row(band: band, mode: mode, cell: cell))
            }
        }
        return out
    }

    /// Band cell; unknown → an empty cell (Java `new Cell()`).
    public func band(_ band: String?) -> Cell {
        byBand[band] ?? Cell()
    }

    /// Mode cell; unknown → an empty cell.
    public func mode(_ mode: String?) -> Cell {
        byMode[mode] ?? Cell()
    }

    /// Band × mode cell; unknown → an empty cell.
    public func cell(_ band: String?, _ mode: String?) -> Cell {
        byBandMode[band]?[mode] ?? Cell()
    }
}
