import Foundation
import os

/// Error reading `cty.dat` from a stream.
///
/// Port of the Java `UncheckedIOException("Nelze načíst cty.dat", e)` from
/// `CtyDxccResolver.fromStream`. **Deliberately not a `DxccError`.** The Java package
/// `dxcc/` reports the same category of error (I/O while reading the input) with two different types:
/// `DxccResolver` and `DxccCodeIndex` throw `DxccException`, but `CtyDxccResolver`
/// throws `UncheckedIOException`. The inconsistency is part of the v1.1.1 behaviour and the port does not
/// unify it -- whoever catches DXCC data errors must expect both, just like
/// in Java.
public struct CtyDxccIOError: Error, Equatable, Sendable, CustomStringConvertible {

    /// Message in Czech -- the same as in Java.
    public let message: String
    /// Description of the cause (the Java `cause`), or `nil`.
    public let cause: String?

    public init(message: String = "Nelze načíst cty.dat", cause: String? = nil) {
        self.message = message
        self.cause = cause
    }

    public var description: String {
        guard let cause else { return message }
        return "\(message): \(cause)"
    }
}

/// DXCC resolver from `cty.dat` (AD1C/country-files.com format) -- for contesting
/// more precise than `prefixRegex`: longest-prefix matching, **exceptions for specific
/// callsigns** (`=CALL`) and per-prefix override of the CQ zone `(n)`, ITU zone `[n]`
/// and continent `{XX}`.
///
/// Record: `Name: CQ: ITU: Cont: Lat: Lon: GMT: PrimaryPrefix:` followed by
/// a list of prefixes separated by commas and terminated by `;`. The entity's `countryCode`
/// = the primary prefix (e.g. OK, OM, K, VE) -- stable across sources.
///
/// Port of the Java `dxcc/CtyDxccResolver.java`.
///
/// **No paths.** The Java version takes an `InputStream` and does not open the file itself;
/// the port takes `Data` or `InputStream`. Thanks to that the tests can run without the external
/// data set `~/dxcc-json/` -- the caller handles the path.
///
/// It is a `final class`, because the Java version memoizes into a `ConcurrentHashMap`
/// and `resolve` thus must be usable on a value the caller holds as a
/// constant. The type is `Sendable` with memoization behind a lock -- the same decision as
/// for `DxccResolver`.
///
/// ## Why the map keys are arrays of UTF-16 units
///
/// The Java maps are `HashMap<String, ...>` and Java `String` equality is **exact
/// equality of UTF-16 units**, whereas Swift `String` equality is canonical
/// equivalence (`"Ä" == "A\u{0308}"`). Moreover `match` cuts the callsign with Java's
/// `substring(0, i)`, which is a cut **by UTF-16 units**, not by graphemes.
/// Measured on Java v1.1.1: the callsign `AA\u{0308}1X` (A, A, combining diaeresis)
/// **resolves** under the prefix `AA`, because `substring(0, 2)` is exactly `"AA"`;
/// a Swift cut by two `Character`s would give `"AÄ"` and resolve nothing. The `[UInt16]`
/// key removes both problems without further exceptions.
public final class CtyDxccResolver: DxccLookup {

    /// Map key -- a Java `String` in the form in which it is compared (UTF-16 units).
    private typealias Key = [UInt16]

    private let baseEntities: [DxccEntity]
    private let exactCalls: [Key: DxccEntity]
    private let prefixes: [Key: DxccEntity]
    /// Longest **non-exact** key, in UTF-16 units (Java `key.length()`).
    private let maxPrefixLen: Int
    /// Memoization as in Java: the key is `callsign.trim().toUpperCase()`, the value
    /// includes "nothing". The cache is never discarded. Behind a lock (the resolver is shared between threads).
    private let cache = OSAllocatedUnfairLock<[Key: DxccEntity?]>(initialState: [:])

    private init(baseEntities: [DxccEntity], exactCalls: [Key: DxccEntity],
                 prefixes: [Key: DxccEntity], maxPrefixLen: Int) {
        self.baseEntities = baseEntities
        self.exactCalls = exactCalls
        self.prefixes = prefixes
        self.maxPrefixLen = maxPrefixLen
    }

    // MARK: - Entry points

    /// Builds the resolver from the contents of `cty.dat` as bytes.
    ///
    /// Does not throw: the Java version throws `UncheckedIOException` only on an `IOException`
    /// from `readAllBytes()`, and `Data` has already been read. Broken bytes are decoded
    /// the same way as Java `new String(bytes, UTF_8)` -- invalid sequences are
    /// replaced with U+FFFD, the **BOM is not removed** (it stays in the name of the first entity,
    /// because Java `trim()` drops only characters <= U+0020).
    ///
    /// - Parameter codes: index from `dxcc.json`; `cty.dat` does not contain DXCC numbers,
    ///   so without it they stay unknown (`nil`), and that is correct -- the record order
    ///   in the file is not the entity number.
    public static func fromData(_ data: Data, codes: DxccCodeIndex? = nil) -> CtyDxccResolver {
        parse(String(decoding: data, as: UTF8.self), codes: codes)
    }

    /// Builds the resolver from a stream -- the only path on which an error can arise,
    /// just like in Java.
    ///
    /// - Throws: `CtyDxccIOError` (port of `UncheckedIOException`) when reading
    ///   the stream fails.
    public static func fromStream(_ input: InputStream, codes: DxccCodeIndex? = nil) throws -> CtyDxccResolver {
        if input.streamStatus == .notOpen {
            input.open()
        }
        let chunk = 16 * 1024
        var buffer = [UInt8](repeating: 0, count: chunk)
        var bytes: [UInt8] = []
        while true {
            let read = input.read(&buffer, maxLength: chunk)
            if read < 0 {
                throw CtyDxccIOError(cause: input.streamError.map { String(describing: $0) }
                    ?? "čtení streamu selhalo")
            }
            if read == 0 {
                break
            }
            bytes.append(contentsOf: buffer[0..<read])
        }
        return parse(String(decoding: bytes, as: UTF8.self), codes: codes)
    }

    // MARK: - Parsing

    /// Parses the contents of `cty.dat`. **Never throws** -- broken records are silently
    /// skipped (measured on Java v1.1.1: fewer than 9 `:`-separated fields,
    /// an unreadable CQ zone, an empty continent or an empty primary prefix ->
    /// `continue`, the rest of the file is loaded).
    ///
    /// Numbers are parsed with Java rules, not Swift ones -- see `javaParseInt`
    /// and `javaParseDouble`.
    public static func parse(_ content: String, codes: DxccCodeIndex? = nil) -> CtyDxccResolver {
        var bases: [DxccEntity] = []
        var exact: [Key: DxccEntity] = [:]
        var pfx: [Key: DxccEntity] = [:]
        var maxLen = 0
        var code = 0

        for record in content.components(separatedBy: ";") {
            let r = JavaText.trim(record)
            // Java `r.isEmpty()`, not `isBlank()` -- a lone non-breaking space
            // is not an empty record and passes on (and then fails on the field count).
            if r.isEmpty {
                continue
            }
            let parts = splitLimit9(r)
            if parts.count < 9 {
                continue
            }
            let name = JavaText.trim(parts[0])
            let cqDefault = javaParseInt(JavaText.trim(parts[1]))
            let ituDefault = javaParseInt(JavaText.trim(parts[2]))
            let contDefault = JavaText.trim(parts[3])
            let lat = javaParseDouble(JavaText.trim(parts[4])) ?? .nan
            let lonWest = javaParseDouble(JavaText.trim(parts[5])) ?? .nan
            // cty.dat lists west as **positive** -- flipping the sign is easy to
            // overlook and `0.00` thereby turns into `-0.0` (Antarctica
            // in real data), which `DxccEntity` distinguishes in equality.
            let lon = lonWest.isNaN ? Double.nan : -lonWest
            var primary = JavaText.trim(parts[7])
            if primary.utf16.first == 0x2A { // "*" = WAE-only entity
                primary = dropFirstUnit(primary)
            }
            if cqDefault == nil || contDefault.isEmpty || primary.isEmpty {
                continue
            }
            code += 1
            let myCode = code // internal identity (order in the file), not the DXCC number
            let adif = codes?.code(name, primary)
            bases.append(entity(code: myCode, name: name, countryCode: primary,
                                continent: contDefault, cq: cqDefault, itu: ituDefault,
                                lat: lat, lon: lon, adifDxcc: adif))

            for token in parts[8].components(separatedBy: ",") {
                let tok = JavaText.trim(token)
                if tok.isEmpty {
                    continue
                }
                let units = Array(tok.utf16)
                let isExact = units.first == 0x3D // "="
                // Overrides are read from the **original** token, the key from the cleaned one --
                // in that order, because the cleaning among other things deletes all "=".
                let cqO = extractInt(units, open: 0x28, close: 0x29) // ( )
                let ituO = extractInt(units, open: 0x5B, close: 0x5D) // [ ]
                let contO = extractContinent(units)
                let key = cleanKey(units)
                if key.isEmpty {
                    continue
                }
                let e = entity(code: myCode, name: name, countryCode: primary,
                               continent: contO ?? contDefault,
                               cq: cqO ?? cqDefault,
                               itu: ituO ?? ituDefault,
                               lat: lat, lon: lon, adifDxcc: adif)
                if isExact {
                    exact[key] = e
                } else {
                    // Java `HashMap.put`: the **last** record with the same key wins.
                    pfx[key] = e
                    maxLen = max(maxLen, key.count)
                }
            }
        }
        return CtyDxccResolver(baseEntities: bases, exactCalls: exact,
                               prefixes: pfx, maxPrefixLen: maxLen)
    }

    // MARK: - DxccLookup

    /// Entities from the **primary records** of the file -- not every alias/exception.
    /// Java `List.copyOf(baseEntities)`.
    public func entities() -> [DxccEntity] {
        baseEntities
    }

    /// Resolves a callsign to a DXCC entity (`nil` if not recognized).
    ///
    /// Emptiness is tested with Java `isBlank()`, but the key is built with Java `trim()` --
    /// these are two different sets of whitespace characters, so a callsign consisting of a lone non-breaking
    /// space passes the guard and is looked up literally (measured: `EMPTY`).
    public func resolve(_ callsign: String?) -> DxccEntity? {
        guard let callsign, !JavaText.isBlank(callsign) else {
            return nil
        }
        let up = JavaText.trim(callsign).uppercased()
        let cacheKey = Array(up.utf16)
        if let memoized = cache.withLock({ $0[cacheKey] }) {
            return memoized
        }
        // Lookup outside the lock; a concurrent computation of the same callsign gives the same result.
        let found = match(up)
        cache.withLock { $0[cacheKey] = found }
        return found
    }

    /// Java `match(String up)` -- a **double** attempt on the exact-call map (first
    /// the non-normalized uppercase callsign, then the normalized one) and only then
    /// longest-prefix from the longest key downwards.
    private func match(_ up: String) -> DxccEntity? {
        if let e = exactCalls[Array(up.utf16)] {
            return e
        }
        let norm = Array(DxccResolver.normalize(up).utf16)
        if let e = exactCalls[norm] {
            return e
        }
        var i = min(norm.count, maxPrefixLen)
        while i >= 1 {
            if let m = prefixes[Array(norm[0..<i])] {
                return m
            }
            i -= 1
        }
        return nil
    }

    // MARK: - Parsing helpers

    /// Java `new DxccEntity(code, name, countryCode, List.of(continent),
    /// List.of(cq), List.of(itu), lat, lon, countryCode, adifDxcc)` with the proviso that
    /// a missing value is an **empty list**, not `null` -- an `itu` without a number is
    /// `List.of()` in Java, and `primaryPrefix` is the same primary prefix as
    /// `countryCode`.
    private static func entity(code: Int, name: String, countryCode: String,
                               continent: String?, cq: Int?, itu: Int?,
                               lat: Double, lon: Double, adifDxcc: Int?) -> DxccEntity {
        DxccEntity(entityCode: code, name: name, countryCode: countryCode,
                   continents: continent.map { [$0] } ?? [],
                   cq: cq.map { [$0] } ?? [],
                   itu: itu.map { [$0] } ?? [],
                   lat: lat, lon: lon, primaryPrefix: countryCode, adifDxcc: adifDxcc)
    }

    /// Java `r.split(":", 9)`: at most 9 parts, the ninth carries **the whole rest including
    /// further colons**, and a positive limit does not drop trailing empty parts
    /// (measured: a record with ten colons is loaded and the excess remains
    /// in the prefix list).
    private static func splitLimit9(_ r: String) -> [String] {
        let parts = r.components(separatedBy: ":")
        if parts.count <= 9 {
            return parts
        }
        return Array(parts[0..<8]) + [parts[8...].joined(separator: ":")]
    }

    /// Drops the first UTF-16 unit (Java `substring(1)`). Swift `dropFirst()`
    /// would drop a whole grapheme, including a combining mark after `*`.
    private static func dropFirstUnit(_ s: String) -> String {
        String(decoding: Array(s.utf16).dropFirst(), as: UTF16.self)
    }

    /// Java `extractInt(tok, open, close)`: `indexOf(open)`, then `indexOf(close,
    /// a + 1)`. **Regardless of line endings** -- unlike the cleaning of the key, where
    /// the regex `.` does not cross a line ending. That asymmetry is in Java and is copied.
    private static func extractInt(_ units: [UInt16], open: UInt16, close: UInt16) -> Int? {
        guard let a = units.firstIndex(of: open) else { return nil }
        guard let b = units[(a + 1)...].firstIndex(of: close) else { return nil }
        let inner = String(decoding: units[(a + 1)..<b], as: UTF16.self)
        return javaParseInt(JavaText.trim(inner))
    }

    /// Java `extractContinent`: the contents of `{...}` after `trim()`, empty -> `nil`.
    private static func extractContinent(_ units: [UInt16]) -> String? {
        guard let a = units.firstIndex(of: 0x7B) else { return nil } // {
        guard let b = units[(a + 1)...].firstIndex(of: 0x7D) else { return nil } // }
        let s = JavaText.trim(String(decoding: units[(a + 1)..<b], as: UTF16.self))
        return s.isEmpty ? nil : s
    }

    /// Java
    /// `tok.replace("=", "").replaceAll("\\(.*?\\)", "").replaceAll("\\[.*?]", "")
    ///  .replaceAll("\\{.*?}", "").replaceAll("<.*?>", "").replaceAll("~.*?~", "").trim()`
    /// -- in this order.
    ///
    /// Instead of Swift `Regex` this is a hand-written scanner over UTF-16 units, because
    /// Swift `.` works by graphemes and its set of line terminators is not Java's.
    /// Measured that this matters: the token `J(` (without a closing parenthesis) is **not
    /// cleaned** in Java and its key stays `J(`, hence unresolvable.
    private static func cleanKey(_ units: [UInt16]) -> Key {
        var out = units.filter { $0 != 0x3D } // replace("=", "") -- all occurrences
        out = removeReluctant(out, open: 0x28, close: 0x29) // ( )
        out = removeReluctant(out, open: 0x5B, close: 0x5D) // [ ]
        out = removeReluctant(out, open: 0x7B, close: 0x7D) // { }
        out = removeReluctant(out, open: 0x3C, close: 0x3E) // < >
        out = removeReluctant(out, open: 0x7E, close: 0x7E) // ~ ~
        return Array(JavaText.trim(String(decoding: out, as: UTF16.self)).utf16)
    }

    /// Equivalent of Java `replaceAll("<open>.*?<close>", "")`: from each
    /// `open` it looks for the **nearest** `close`, but does not cross a line end
    /// (the regex `.` does not match a line end). When `close` is missing, `open`
    /// stays in the string.
    ///
    /// **This is quadratic in the number of unpaired `open`s** -- and it is deliberately not
    /// fixed, because Java `Matcher.replaceAll` has the same complexity
    /// (it tries a match from every position). Measured, one token with N unpaired
    /// `(`, Java v1.1.1 / this port: 1,000 = 9 / 10 ms, 4,000 = 30 / 110 ms,
    /// 20,000 = 718 ms / 2.7 s -- both grow x4 when the input doubles.
    /// A linear version would be a divergence from the v1.1.1 behaviour; a corrupted `cty.dat`
    /// hangs both applications. Paired parentheses are linear, by contrast, because
    /// the whole span is dropped in one jump.
    private static func removeReluctant(_ units: [UInt16], open: UInt16, close: UInt16) -> [UInt16] {
        guard units.contains(open) else { return units }
        var out: [UInt16] = []
        out.reserveCapacity(units.count)
        var i = 0
        while i < units.count {
            if units[i] == open {
                var j = i + 1
                var found = -1
                while j < units.count {
                    let u = units[j]
                    if isJavaLineTerminator(u) {
                        break
                    }
                    if u == close {
                        found = j
                        break
                    }
                    j += 1
                }
                if found >= 0 {
                    i = found + 1
                    continue
                }
            }
            out.append(units[i])
            i += 1
        }
        return out
    }

    /// Line terminators of a Java regex without `UNIX_LINES`: `\n`, `\r`, U+0085, U+2028,
    /// U+2029. **Not** U+000B and U+000C -- `.` matches those.
    private static func isJavaLineTerminator(_ u: UInt16) -> Bool {
        u == 0x0A || u == 0x0D || u == 0x85 || u == 0x2028 || u == 0x2029
    }

    // MARK: - Java number parsing

    /// Equivalent of Java `Integer.parseInt(String)` -- returns `nil` where Java
    /// throws `NumberFormatException`.
    ///
    /// Swift `Int(String)` cannot be used here in either direction (measured on Java
    /// v1.1.1 and in Swift):
    /// - `Int` is 64-bit, so `"2147483648"` would be **accepted**, whereas Java rejects it;
    ///   in `cty.dat` that would mean that Java drops a record with such a CQ zone
    ///   (`cq` is missing), and we would load it;
    /// - Java, conversely, accepts **any Unicode decimal digits**
    ///   (`Character.digit`), so `"١٥"` is 15 -- Swift `Int` returns `nil`.
    ///
    /// Delegates to `JavaInteger.parseInt` (the only implementation in the project).
    static func javaParseInt(_ s: String) -> Int? {
        JavaInteger.parseInt(s).map(Int.init)
    }

    /// Equivalent of Java `Double.parseDouble(String)` -- returns `nil` where
    /// Java throws `NumberFormatException`.
    ///
    /// In `cty.dat`, `hasLatLon()` depends on this: whatever Java reads as a
    /// coordinate, we must read too, otherwise the azimuth disappears.
    ///
    /// Delegates to `JavaDouble.parseDouble` (the only implementation in the project).
    static func javaParseDouble(_ s: String) -> Double? {
        JavaDouble.parseDouble(s)
    }
}
