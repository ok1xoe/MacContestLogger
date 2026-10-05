/// Check partial from three sources (N1MM Check window, DXLog Check partials) — Java `scp/PartialCheck`:
/// own log, spots from the cluster and `master.scp`. For the same match the log takes precedence over spots and those
/// over `master.scp`; a callsign appears once, with the strongest source.
///
/// Java collections with `null` (the whole collection and elements) are skipped — in Swift that is an empty array, resp.
/// a missing element. Text as in `ScpDatabase` (`trim`, `toUpperCase` without locale, UTF-16).
public enum PartialCheck {

    /// Suggestion source, in priority order (Java `ordinal`).
    public enum Source: Int, Sendable, CustomStringConvertible {
        case LOG, SPOT, SCP

        public var description: String {
            switch self {
            case .LOG: return "LOG"
            case .SPOT: return "SPOT"
            case .SCP: return "SCP"
            }
        }
    }

    public struct Suggestion: Equatable, Sendable {
        public let call: String
        public let source: Source

        public init(call: String, source: Source) {
            self.call = call
            self.source = source
        }

        /// Java record equality: `call` by UTF-16 units.
        public static func == (lhs: Suggestion, rhs: Suggestion) -> Bool {
            lhs.source == rhs.source && JavaText.equals(lhs.call, rhs.call)
        }
    }

    /// - Parameter scpMatches: suggestions from `ScpDatabase.find` (already filtered by text).
    public static func merge(_ partial: String?, logCalls: [String], spotCalls: [String], scpMatches: [String],
                             limit: Int) -> [Suggestion] {
        let query: [UInt16] = Array(normalized(partial ?? "").utf16)
        if query.count < ScpDatabase.minQuery || limit <= 0 { return [] }
        var best: [JavaStringKey: Source] = [:]
        var order: [String] = []
        let sources: [(calls: [String], source: Source)] = [(logCalls, .LOG), (spotCalls, .SPOT), (scpMatches, .SCP)]
        for (calls, source) in sources {
            for raw in calls {
                let call = normalized(raw)
                let units: [UInt16] = Array(call.utf16)
                guard !units.isEmpty, JavaText.indexOf(units, query) >= 0 else { continue }
                let key = JavaStringKey(call)
                if best[key] == nil {
                    best[key] = source
                    order.append(call)
                }
            }
        }
        var ranked: [(rank: Int, units: [UInt16], suggestion: Suggestion)] = order.map { call in
            let units: [UInt16] = Array(call.utf16)
            let suggestion = Suggestion(call: call, source: best[JavaStringKey(call)]!)
            return (ScpDatabase.rank(units, query), units, suggestion)
        }
        ranked.sort { left, right in
            if left.rank != right.rank { return left.rank < right.rank }
            let leftSource: Int = left.suggestion.source.rawValue
            let rightSource: Int = right.suggestion.source.rawValue
            if leftSource != rightSource { return leftSource < rightSource }
            if left.units.count != right.units.count { return left.units.count < right.units.count }
            return left.units.lexicographicallyPrecedes(right.units)
        }
        return ranked.prefix(limit).map { $0.suggestion }
    }

    /// N+1 (DXLog Check N+1, N1MM N+1 window): callsigns that differ from the entered one by exactly one character —
    /// substitution, insertion or deletion. The query is at least 3 UTF-16 units; the result without duplicates sorted
    /// by Java `compareTo` (`TreeSet`), at most `limit`.
    public static func nPlusOne(_ typed: String?, candidates: [String], limit: Int) -> [String] {
        nPlusOne(typed, normalizedCandidates: candidates.map(normalized), limit: limit)
    }

    /// `nPlusOne` over candidates to which `trim().toUpperCase()` has already been applied.
    static func nPlusOne(_ typed: String?, normalizedCandidates: [String], limit: Int) -> [String] {
        let query: [UInt16] = Array(normalized(typed ?? "").utf16)
        if query.count < 3 || limit <= 0 { return [] }
        var seen = Set<JavaStringKey>()
        var hits: [[UInt16]] = []
        for candidate in normalizedCandidates {
            let units: [UInt16] = Array(candidate.utf16)
            guard isOneOff(query, units), seen.insert(JavaStringKey(candidate)).inserted else { continue }
            hits.append(units)
        }
        hits.sort { $0.lexicographicallyPrecedes($1) }
        return hits.prefix(limit).map { String(decoding: $0, as: UTF16.self) }
    }

    /// Do the strings differ by exactly one edit (substitution, insertion, deletion)? By UTF-16 units like
    /// Java `charAt` — a character outside the BMP is two units.
    public static func isOneOff(_ a: String, _ b: String) -> Bool {
        isOneOff(Array(a.utf16), Array(b.utf16))
    }

    static func isOneOff(_ a: [UInt16], _ b: [UInt16]) -> Bool {
        let la = a.count
        let lb = b.count
        if abs(la - lb) > 1 || a == b { return false }
        if la == lb {
            var diff = 0
            var i = 0
            while i < la && diff < 2 {
                if a[i] != b[i] { diff += 1 }
                i += 1
            }
            return diff == 1
        }
        let short = la < lb ? a : b
        let long = la < lb ? b : a
        var i = 0
        while i < short.count && short[i] == long[i] {
            i += 1
        }
        return short[i...].elementsEqual(long[(i + 1)...])
    }

    /// Java `trim().toUpperCase(Locale.ROOT)`.
    static func normalized(_ text: String) -> String {
        JavaText.toUpperCase(JavaText.trim(text))
    }
}
