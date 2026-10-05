import Foundation

/// Callsign database from the `master.scp` file for suggestions (Super Check Partial) — Java
/// `scp/ScpDatabase`.
///
/// Searching is by **inner match**, not just by prefix; suggestion order: exact match, then callsigns starting with
/// the entered text, then the others; within a group shorter first, finally Java `compareTo`.
///
/// Immutable — only read after loading, so searching can be called from any thread. The set for `contains`
/// is built in `init` (Java builds it lazily via `volatile`; the result is the same).
///
/// Text as in Java: `trim()` (characters ≤ U+0020), `toUpperCase()` **without locale** (`ß` → `SS`, `ÿ` → U+0178,
/// `µ` → U+039C — `JavaText.toUpperCase`), length, `contains`, `startsWith`, equality and ordering by UTF-16
/// units (not Swift canonical `==`/`<`: `É` and `E` + U+0301 are two different callsigns).
public final class ScpDatabase: Sendable {

    /// Shorter text returns too many matches and is of no use.
    public static let minQuery = 2

    private let calls: [String]
    /// UTF-16 units of `calls` (searching by Java `char`s).
    private let units: [[UInt16]]
    /// `trim().toUpperCase()` of each item again — Java `nPlusOne` calls them on the database items.
    private let nPlusOneForms: [String]
    private let exact: Set<JavaStringKey>

    private init(calls: [String]) {
        self.calls = calls
        self.units = calls.map { Array($0.utf16) }
        self.nPlusOneForms = calls.map { JavaText.toUpperCase(JavaText.trim($0)) }
        self.exact = Set(calls.map { JavaStringKey($0) })
    }

    public static func empty() -> ScpDatabase {
        ScpDatabase(calls: [])
    }

    /// Java `of(Collection)`. Java skips a `null` element (normalises it to an empty line); Swift
    /// `[String]` has no `nil`.
    public static func of(_ calls: [String]) -> ScpDatabase {
        ScpDatabase(calls: normalize(calls))
    }

    /// Loads `master.scp` (Java `Files.lines(file, ISO_8859_1)`: each byte is one character, lines split by
    /// `\n`, `\r` and `\r\n`). A missing or unreadable file or a directory gives an empty database — you can log
    /// without suggestions, not with a crashed app.
    public static func load(_ path: String?) -> ScpDatabase {
        guard let path, access(path, R_OK) == 0 else { return empty() }
        guard case .data(let data) = RawFileSystem.readFile(RawPath(path)) else { return empty() }
        return ScpDatabase(calls: normalize(JavaLines.split(latin1(data))))
    }

    /// Bytes as Java `ISO_8859_1`: byte = code point U+0000…U+00FF.
    static func latin1(_ data: Data) -> String {
        var scalars = String.UnicodeScalarView()
        for byte in data {
            scalars.append(Unicode.Scalar(byte))
        }
        return String(scalars)
    }

    /// Upper case, without blank lines, comments and duplicates (order of first occurrence, `LinkedHashSet`).
    private static func normalize(_ lines: [String]) -> [String] {
        var seen = Set<JavaStringKey>()
        var unique: [String] = []
        for line in lines {
            let call = JavaText.toUpperCase(JavaText.trim(line))
            if call.isEmpty || call.utf16.first == 0x23 { continue }
            if seen.insert(JavaStringKey(call)).inserted {
                unique.append(call)
            }
        }
        return unique
    }

    /// Callsign at index `i` (0 to `size` − 1) — for random selection in the simulator.
    public func get(_ i: Int) -> String {
        calls[i]
    }

    /// Is the callsign in the database (exact match)? Empty text and text of only whitespace (`isBlank`) → `false`.
    public func contains(_ call: String?) -> Bool {
        guard let call, !JavaText.isBlank(call) else { return false }
        return exact.contains(JavaStringKey(JavaText.toUpperCase(JavaText.trim(call))))
    }

    public var size: Int { calls.count }

    /// Suggestions for the typed text, sorted by relevance, at most `limit`. Empty for text shorter than
    /// `minQuery` UTF-16 units (after `trim` and upper-casing — so `ß` is long enough).
    public func find(_ partial: String?, limit: Int) -> [String] {
        guard let partial, limit > 0 else { return [] }
        let query: [UInt16] = Array(JavaText.toUpperCase(JavaText.trim(partial)).utf16)
        if query.count < Self.minQuery { return [] }
        var matches: [(rank: Int, index: Int)] = []
        for index in units.indices where JavaText.indexOf(units[index], query) >= 0 {
            matches.append((Self.rank(units[index], query), index))
        }
        matches.sort { left, right in
            if left.rank != right.rank { return left.rank < right.rank }
            let leftUnits = units[left.index]
            let rightUnits = units[right.index]
            if leftUnits.count != rightUnits.count { return leftUnits.count < rightUnits.count }
            return leftUnits.lexicographicallyPrecedes(rightUnits)
        }
        return matches.prefix(limit).map { calls[$0.index] }
    }

    /// N+1: callsigns differing from the entered one by exactly one character (see `PartialCheck.nPlusOne`).
    public func nPlusOne(_ typed: String?, limit: Int) -> [String] {
        PartialCheck.nPlusOne(typed, normalizedCandidates: nPlusOneForms, limit: limit)
    }

    /// 0 = exact match, 1 = starts with the entered text, 2 = inner match.
    static func rank(_ call: [UInt16], _ query: [UInt16]) -> Int {
        if call == query { return 0 }
        return call.starts(with: query) ? 1 : 2
    }
}
