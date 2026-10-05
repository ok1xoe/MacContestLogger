import Foundation
import os

/// Resolves a callsign to a DXCC entity using the `prefixRegex` from the data
/// `~/dxcc-json/dxcc.json`. With multiple matches it picks the most specific
/// (longest matching prefix). Deleted entities are ignored. Results are memoized.
///
/// Port of the Java `dxcc/DxccResolver.java`. Without exact-call exceptions (CTY.DAT) --
/// for the minimal version `prefixRegex` suffices; the more precise resolution is done by
/// `CtyDxccResolver`.
///
/// **No paths.** The Java version takes an `InputStream` and does not open the file itself;
/// the port takes `Data`. That is precisely why the tests can run without the external data
/// set `~/dxcc-json/` (which is not copied into the repo) -- the caller handles the path.
///
/// It is a `final class`, because the Java version memoizes into a `ConcurrentHashMap`
/// and `resolve` thus must be usable on a value the caller holds as a
/// constant. The type is `Sendable`: the Java cache is concurrent and the resolver is shared between the
/// live session and a background replay, so the memoization is behind an `OSAllocatedUnfairLock`
/// (the package targets macOS 14, `Mutex` is only from macOS 15).
///
/// Compiled patterns: Swift's `Regex<AnyRegexOutput>` is **not** `Sendable` (the SDK does not even have
/// a conditional conformance), so two threads must not use it concurrently. Earlier, the lookup
/// of a new callsign was therefore serialized entirely under the lock -- when the gate ran concurrently
/// over the corpus that was a ceiling: 8 threads were no faster than one. Now there are several
/// pattern **sets**: a lookup **borrows** a set from the pool under the lock **exclusively for itself**,
/// matches outside the lock and returns it; if the pool is empty, it compiles a new set from the same pattern
/// texts (so there are at most as many sets as threads searching at once). "Unchecked" applies only to
/// the pool -- each set is at every moment either in it or with a single thread.
/// Memoization has its own separate lock; concurrent lookups of the same new callsign give
/// the same result and whichever is written.
public final class DxccResolver: DxccLookup {

    /// Error message of the Java version (`DxccException("Nelze parsovat DXCC data", e)`).
    private static let parseMessage = "Nelze parsovat DXCC data"

    /// Suffixes dropped during normalization. In Java this is a private
    /// `Set<String> SUFFIXES` -- the set has to be replicated by hand, it is not exported.
    private static let suffixes: Set<String> = ["P", "M", "MM", "AM", "QRP", "A", "R", "LH", "B", "J"]

    /// Entity with its compiled regex and list of prefixes.
    private struct Compiled {
        let entity: DxccEntity
        let pattern: Regex<AnyRegexOutput>
        let prefixes: [String]
    }

    /// Entity pattern as text -- further sets are compiled from it (`Sendable`).
    private struct Source: Sendable {
        let entity: DxccEntity
        let pattern: String
        let prefixes: [String]
    }

    /// Entities in pattern order -- outside the lock, they are `Sendable` and immutable.
    private let allEntities: [DxccEntity]
    /// Pattern texts in file order (after filtering) for compiling further sets.
    private let sources: [Source]
    /// Memoization as in Java: the key is the **normalized** callsign, the value includes "nothing".
    /// The cache is never discarded, just like in Java.
    private let cache = OSAllocatedUnfairLock<[String: DxccEntity?]>(initialState: [:])
    /// Free sets of compiled patterns (non-`Sendable`), each borrowed exclusively.
    private let pool: OSAllocatedUnfairLock<[[Compiled]]>

    private init(_ compiled: [Compiled], sources: [Source]) {
        self.allEntities = compiled.map(\.entity)
        self.sources = sources
        self.pool = OSAllocatedUnfairLock(uncheckedState: [compiled])
    }

    /// Record from the file after mapping, before filtering -- the Java `RawEntity`.
    private struct Raw {
        var entityCode = 0
        var name: String?
        var countryCode: String?
        var continent: [String?]?
        var cq: [Int?]?
        var itu: [Int?]?
        var prefix: String?
        var prefixRegex: String?
        var deleted = false
    }

    /// The nine creator properties of the Java `RawEntity`. The count is part of the behaviour:
    /// once all nine appear in one object, any further occurrence of them is
    /// an error of the whole file (see `DxccJson.walkCreatorProperties`).
    private static let creatorKeys: Set<String> = [
        "entityCode", "name", "countryCode", "continent", "cq", "itu", "prefix", "prefixRegex", "deleted",
    ]

    /// Maps one object to `Raw` -- property by property in order of occurrence,
    /// like the Java `PropertyValueBuffer`.
    private static func map(_ object: DxccJson.Object) throws -> Raw {
        var raw = Raw()
        try DxccJson.walkCreatorProperties(object, creatorKeys: creatorKeys, message: parseMessage) { key, value in
            switch key {
            case "entityCode":
                raw.entityCode = try DxccJson.int(value, key: key, message: parseMessage)
            case "name":
                raw.name = try DxccJson.string(value, key: key, message: parseMessage)
            case "countryCode":
                raw.countryCode = try DxccJson.string(value, key: key, message: parseMessage)
            case "continent":
                raw.continent = try DxccJson.stringList(value, key: key, message: parseMessage)
            case "cq":
                raw.cq = try DxccJson.intList(value, key: key, message: parseMessage)
            case "itu":
                raw.itu = try DxccJson.intList(value, key: key, message: parseMessage)
            case "prefix":
                raw.prefix = try DxccJson.string(value, key: key, message: parseMessage)
            case "prefixRegex":
                raw.prefixRegex = try DxccJson.string(value, key: key, message: parseMessage)
            default:
                raw.deleted = try DxccJson.bool(value, key: key, message: parseMessage)
            }
        }
        return raw
    }

    /// Builds the resolver from the contents of `dxcc.json`.
    ///
    /// A broken record (`deleted`, missing/empty or uncompilable
    /// `prefixRegex`) is **silently skipped**; an error happens only at the level of the whole file.
    ///
    /// - Throws: `DxccError` with `kind == .parse` when the input cannot be parsed
    ///   (the Java `DxccException`), or with `kind == .nullPointer` when the `dxcc` field
    ///   is missing / is `null` or has a `null` element -- there the Java version fails with
    ///   `NullPointerException`, i.e. a different exception than for broken JSON.
    public static func fromData(_ data: Data) throws -> DxccResolver {
        let root = try DxccJson.parse(data, message: parseMessage)
        guard let values = try DxccJson.entityValues(root, message: parseMessage) else {
            throw DxccError(kind: .nullPointer, message: parseMessage,
                            cause: "pole dxcc chybí nebo je null")
        }
        // 1st phase = mapping. Jackson maps the **whole** file before anything
        // is filtered: a type error therefore fails the file even in a record that would be
        // skipped anyway, and a `null` element is mapped to a `null` record (still without an error).
        var raws: [Raw?] = []
        raws.reserveCapacity(values.count)
        for value in values {
            guard case .object(let object) = value else {
                raws.append(nil)
                continue
            }
            raws.append(try map(object))
        }
        // 2nd phase = filtering and compiling the regexes.
        var out: [Compiled] = []
        var sources: [Source] = []
        for raw in raws {
            guard let raw else {
                // Java `e.deleted()` on a `null` element -> NullPointerException.
                throw DxccError(kind: .nullPointer, message: parseMessage,
                                cause: "prvek pole dxcc je null")
            }
            guard !raw.deleted, let prefixRegex = raw.prefixRegex, !JavaText.isBlank(prefixRegex) else {
                continue
            }
            guard let pattern = try? Regex(prefixRegex) else {
                continue // skip a broken regex
            }
            let prefixes = raw.prefix == nil ? [] : splitPrefixList(raw.prefix!.uppercased())
            // Primary prefix = first in the list (OK, K, DL...); otherwise the ISO countryCode.
            let primaryPrefix = prefixes.isEmpty ? raw.countryCode : prefixes[0]
            let entity = DxccEntity(entityCode: raw.entityCode, name: raw.name, countryCode: raw.countryCode,
                                    continents: raw.continent, cq: raw.cq, itu: raw.itu,
                                    lat: .nan, lon: .nan, primaryPrefix: primaryPrefix)
            out.append(Compiled(entity: entity, pattern: pattern, prefixes: prefixes))
            sources.append(Source(entity: entity, pattern: prefixRegex, prefixes: prefixes))
        }
        return DxccResolver(out, sources: sources)
    }

    /// All (non-deleted) DXCC entities -- for enumerating a multiplier set.
    /// The order is the order in the JSON `dxcc` array after filtering.
    public func entities() -> [DxccEntity] {
        allEntities
    }

    /// Resolves a callsign to a DXCC entity (`nil` if not recognized).
    ///
    /// Emptiness is tested with Java `isBlank()` and normalization with Java `trim()`
    /// (`JavaText`) -- these are two different sets of whitespace characters and a callsign gets into the resolver
    /// even from the import of a foreign log, where a non-breaking space is not unthinkable.
    public func resolve(_ callsign: String?) -> DxccEntity? {
        guard let callsign, !JavaText.isBlank(callsign) else {
            return nil
        }
        let key = Self.normalize(callsign)
        if let memoized = cache.withLock({ $0[key] }) {
            return memoized
        }
        let patterns = pool.withLockUnchecked { $0.popLast() } ?? compileSources()
        let found = Self.match(key, patterns)
        pool.withLockUnchecked { $0.append(patterns) }
        cache.withLock { $0[key] = found }
        return found
    }

    /// Another set of patterns from the same texts. Each text has already been compiled once (`fromData`
    /// dropped the uncompilable patterns) and the compilation is deterministic.
    private func compileSources() -> [Compiled] {
        sources.map { source in
            guard let pattern = try? Regex(source.pattern) else {
                preconditionFailure("vzor DXCC zkompilovaný při načtení teď nejde zkompilovat")
            }
            return Compiled(entity: source.entity, pattern: pattern, prefixes: source.prefixes)
        }
    }

    private static func match(_ call: String, _ compiled: [Compiled]) -> DxccEntity? {
        var best: Compiled?
        var bestScore = -1
        for candidate in compiled {
            guard (try? candidate.pattern.wholeMatch(in: call)) != nil else { continue }
            let score = prefixScore(call, candidate.prefixes)
            // A strict ">" means that with an equal score the first record in the array wins.
            if score > bestScore {
                bestScore = score
                best = candidate
            }
        }
        return best?.entity
    }

    /// Length of the longest entity prefix that is a prefix of the callsign (for disambiguation).
    private static func prefixScore(_ call: String, _ prefixes: [String]) -> Int {
        var max = 0
        for prefix in prefixes where !prefix.isEmpty && call.hasPrefix(prefix) {
            if prefix.count > max { max = prefix.count }
        }
        return max
    }

    /// For DXCC: drops suffixes (/P, /MM...) and single-digit indicators; for portable
    /// callsigns picks the prefix.
    ///
    /// In Java `normalize` is package-private and is also called by `CtyDxccResolver`
    /// and `DxccSpecialCases`, so here it is `internal` -- available in the module, not outside.
    static func normalize(_ callsign: String) -> String {
        let up = JavaText.trim(callsign).uppercased()
        if !up.contains("/") {
            return up
        }
        var tokens: [String] = []
        for token in up.components(separatedBy: "/") {
            if token.isEmpty || suffixes.contains(token) || isSingleDigit(token) {
                continue
            }
            tokens.append(token)
        }
        if tokens.isEmpty {
            return up.replacingOccurrences(of: "/", with: "")
        }
        if tokens.count == 1 {
            return tokens[0]
        }
        // multiple tokens -> portable prefix override = the shortest (DL/W1ABC -> DL, W1/OK1XOE -> W1)
        var shortest = tokens[0]
        for token in tokens where token.count < shortest.count {
            shortest = token
        }
        return shortest
    }

    /// Java regex `\d` without `UNICODE_CHARACTER_CLASS` = exactly one ASCII digit.
    private static func isSingleDigit(_ token: String) -> Bool {
        guard token.count == 1, let char = token.first else { return false }
        return char.isASCII && char.isNumber
    }

    /// Java `prefix.split("\\s*,\\s*")`: spaces around the comma are consumed,
    /// spaces at the edges of the string are not. `String.split` drops trailing empty
    /// elements, but for input **without** a comma it returns a one-element array even for an empty
    /// string -- both are measured behaviour on which `primaryPrefix` depends.
    private static func splitPrefixList(_ value: String) -> [String] {
        let parts = value.components(separatedBy: ",")
        if parts.count == 1 {
            return parts // no comma -> the whole input as a single element (even empty)
        }
        var out = parts.enumerated().map { index, part -> String in
            var text = Substring(part)
            if index > 0 {
                text = text.drop(while: isJavaSpace)
            }
            if index < parts.count - 1 {
                while let last = text.last, isJavaSpace(last) {
                    text = text.dropLast()
                }
            }
            return String(text)
        }
        while let last = out.last, last.isEmpty {
            out.removeLast()
        }
        return out
    }

    /// Java `\s` without `UNICODE_CHARACTER_CLASS`: `[ \t\n\u{0B}\f\r]`.
    private static func isJavaSpace(_ char: Character) -> Bool {
        char == " " || char == "\t" || char == "\n" || char == "\u{0B}"
            || char == "\u{0C}" || char == "\r"
    }
}
