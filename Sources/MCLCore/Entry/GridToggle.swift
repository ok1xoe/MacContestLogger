/// N1MM's grid square keys for VHF and up (Alt+- here as in N1MM): the grid field cycles through the grid squares the
/// call history knows for the typed call (at most two, N1MM's Loc1/Loc2) and the grid the operator typed — three at
/// most. Pure value logic; the entry window keeps the typed grid and applies the result.
public enum GridToggle {

    /// The call history columns that hold a grid square, in order (N1MM `Loc1`, `Loc2`; `Grid` of other files).
    static let columns: [String] = ["loc1", "loc2", "grid"]

    /// The most grid squares the call history contributes.
    public static let historyLimit = 2

    /// The grid squares of a call history record: valid Maidenhead locators (4 or 6 characters) from the grid
    /// columns, upper case, without repeats, at most `historyLimit`.
    public static func historyGrids(_ record: JavaLinkedMap<String>?) -> [String] {
        guard let record else { return [] }
        var out: [String] = []
        for column in columns {
            guard let raw = record[column] else { continue }
            let grid: String = JavaText.toUpperCase(JavaText.trim(raw))
            guard QsoSearch.isLocator(grid), !out.contains(grid) else { continue }
            out.append(grid)
            if out.count == historyLimit {
                break
            }
        }
        return out
    }

    /// The grid squares Alt+- goes through: the typed grid first (when it is one and not already from the call
    /// history), then the call history's.
    public static func candidates(entered: String?, history: [String]) -> [String] {
        var out: [String] = []
        if let entered {
            let grid: String = JavaText.toUpperCase(JavaText.trim(entered))
            if !grid.isEmpty, !history.contains(grid) {
                out.append(grid)
            }
        }
        for grid in history where !out.contains(grid) {
            out.append(grid)
        }
        return out
    }

    /// The grid that follows `current` in `candidates` (after the last one the first again); a current value that is
    /// not among them starts at the first call history grid. `nil` = nothing to toggle (no call history grid).
    public static func next(current: String, candidates: [String], history: [String]) -> String? {
        guard !history.isEmpty, !candidates.isEmpty else { return nil }
        let grid: String = JavaText.toUpperCase(JavaText.trim(current))
        guard let index = candidates.firstIndex(of: grid) else {
            return history[0]
        }
        return candidates[(index + 1) % candidates.count]
    }
}
