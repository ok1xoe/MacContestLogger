import Foundation

/// The most recently opened contests of one database, newest first (File → Open recent). The list is kept in the
/// database's own `meta` table, so it belongs to that database and goes with its file.
public enum RecentContests {

    /// How many contests the list keeps.
    public static let limit = 9

    /// The `meta` key holding the list (a JSON array of contest ids).
    public static let metaKey = "recent_contests"

    /// `id` moved (or added) to the front, the rest in their order, at most `limit` entries.
    public static func push(_ ids: [String], _ id: String) -> [String] {
        Array(([id] + ids.filter { $0 != id }).prefix(limit))
    }

    /// Only the ids that are still `known`, in order, without repeats, at most `limit`.
    public static func prune(_ ids: [String], keeping known: Set<String>) -> [String] {
        var seen: Set<String> = []
        var out: [String] = []
        for id in ids where known.contains(id) && seen.insert(id).inserted {
            out.append(id)
        }
        return Array(out.prefix(limit))
    }

    /// The stored text as a list; a missing, empty or damaged value is an empty list.
    public static func decode(_ text: String?) -> [String] {
        guard let text, let data = text.data(using: .utf8),
              let ids = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Array(ids.prefix(limit))
    }

    public static func encode(_ ids: [String]) -> String {
        guard let data = try? JSONEncoder().encode(ids), let text = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return text
    }

    /// The menu text of a contest: its name (or id) and the year when known.
    public static func title(_ summary: ContestStore.ContestSummary) -> String {
        let name: String = summary.name.flatMap { $0.isEmpty ? nil : $0 } ?? summary.contestId
        let year: String = ContestActivation.browserRow(summary, setup: nil).year
        return year == "—" ? name : name + " " + year
    }
}
