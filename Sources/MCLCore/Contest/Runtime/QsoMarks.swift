import Foundation

/// Marks for the logbook table (N1MM „Marking Multipliers"): QSO points, dupe and the new
/// multipliers the QSO brought. Computed by replaying the logbook in chronological
/// order, so a multiplier always has the first QSO that made it next to it.
///
/// Port of Java `contest/runtime/QsoMarks.java`.
public enum QsoMarks {

    /// Mark of one QSO. `newMults` = values of new multipliers (zone 14, country DL…)
    /// in the order of the definition's bindings.
    public struct Mark: Equatable, Sendable {
        /// Java `int`.
        public let points: Int32
        public let dupe: Bool
        public let newMults: [String]

        public init(points: Int32, dupe: Bool, newMults: [String]) {
            self.points = points
            self.dupe = dupe
            self.newMults = newMults
        }

        public var isMultiplier: Bool {
            !newMults.isEmpty
        }

        /// Text for the „Mult" column: values separated by a space.
        public var multText: String {
            newMults.joined(separator: " ")
        }
    }

    /// - Returns: QSO id → mark (a QSO without an id, an X-QSO and a deleted one are missing; a QSO without an id is however replayed into the
    ///   session). The same id twice → the later one in time order applies (Java `put`).
    ///   `now` = "now" for QSOs without a time (`ContestReplay.replay(_:_:now:)`).
    public static func compute(_ fresh: ContestSession, _ qsos: [Qso],
                               now: () -> Date = Date.init) -> [Int64: Mark] {
        var out: [Int64: Mark] = [:]
        var labels = Labels(session: fresh)
        _ = ContestReplay.replay(fresh, qsos, now: now) { q, r in
            guard let id = q.id else { return }
            out[id] = mark(of: r, labels: &labels)
        }
        return out
    }

    /// The mark of one replayed QSO: its points, dupe and the labels of the new counting multipliers.
    static func mark(of result: ContestSession.LogResult, labels: inout Labels) -> Mark {
        var mults: [String] = []
        for m in result.multipliers where m.isNew && m.countsAsMultiplier {
            guard let key = m.key else { continue }
            mults.append(labels.label(setId: m.setId, key: key))
        }
        return Mark(points: result.points, dupe: result.dupe, newMults: mults)
    }

    /// Multiplier labels by set, read from the session once per set (a set without a label shows the key).
    struct Labels: Sendable {
        let session: ContestSession
        /// Labels by setId; key by UTF-16 like a Java HashMap (also a `nil` setId).
        private var cache = JavaLinkedMap<JavaLinkedMap<String>>()

        init(session: ContestSession) {
            self.session = session
        }

        mutating func label(setId: String?, key: String) -> String {
            let setLabels: JavaLinkedMap<String>
            if let cached = cache[setId] {
                setLabels = cached
            } else {
                setLabels = session.multiplierLabels(setId: setId)
                cache.put(setId, setLabels)
            }
            return setLabels[key] ?? key
        }
    }
}
