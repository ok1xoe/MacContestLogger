import Foundation

/// What the DX Cluster console's text storage must do to go from the lines it shows to the log's current lines. The
/// log is append-only except for its line cap (the oldest lines drop off the head) and „Vymazat"; so the common change
/// is "delete a head range, append a tail", and only a clear or an unrelated log needs a full rebuild.
public enum ConsoleDiff: Equatable, Sendable {
    /// Nothing changed.
    case none
    /// Delete the first `deleteUTF16` UTF-16 units (whole lines with their separators), then append `append` (it
    /// carries its own leading separator when text remains).
    case update(deleteUTF16: Int, append: String)
    /// Replace everything.
    case rebuild

    /// The same plan over lines that carry more than their text (the console's colour-coded lines): a line whose
    /// style changed is a different line, so a restyle (a new filter) rebuilds.
    public enum LineEdit<Line: Equatable>: Equatable {
        case none
        /// Delete the first `deleteUTF16` UTF-16 units, then append `append` (each line after a `"\n"` when text
        /// remains).
        case update(deleteUTF16: Int, append: [Line])
        case rebuild
    }

    /// The lines are shown joined by `"\n"`.
    public static func plan(old: [String], new: [String]) -> ConsoleDiff {
        switch plan(old: old, new: new, text: { $0 }) {
        case .none: return .none
        case .rebuild: return .rebuild
        case .update(let deleted, let tail):
            let text: String = tail.isEmpty ? "" : "\n" + tail.joined(separator: "\n")
            return .update(deleteUTF16: deleted, append: text)
        }
    }

    public static func plan<Line: Equatable>(old: [Line], new: [Line], text: (Line) -> String) -> LineEdit<Line> {
        if old == new { return .none }
        if old.isEmpty || new.isEmpty { return .rebuild }
        // The old lines that survive are a suffix of `old` that is a prefix of `new`; try each head cut that lines up.
        for cut in old.indices where old[cut] == new[0] {
            let kept: Int = old.count - cut
            guard kept <= new.count, old[cut...].elementsEqual(new[..<kept]) else { continue }
            let deleted: Int = old[..<cut].reduce(0) { $0 + text($1).utf16.count + 1 }
            return .update(deleteUTF16: deleted, append: Array(new[kept...]))
        }
        return .rebuild
    }
}
