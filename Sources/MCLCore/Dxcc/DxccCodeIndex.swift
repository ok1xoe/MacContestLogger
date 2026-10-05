import Foundation

/// DXCC entity numbers from `dxcc.json` for data that does not contain them -- mainly
/// `cty.dat`, which has only a name and prefixes.
///
/// Port of the Java `dxcc/DxccCodeIndex.java`. Matching is done first by name (after
/// folding diacritics and unifying the spelling), then by any prefix of the
/// entity. **An ambiguous match is discarded**: under `3Y` there are both Bouvet and Peter I
/// Island, and a wrong DXCC number is worse than none -- the ADIF field `DXCC` is then
/// rather omitted. Deleted entities are ignored, otherwise the defunct Czechoslovakia
/// would invalidate the prefix `OM`.
///
/// **No paths.** The Java version takes an `InputStream`, the port takes `Data` -- the external
/// set `~/dxcc-json/` is not copied into the repo and the caller handles the path.
///
/// Unlike `DxccResolver`, this is a `struct`: the index is immutable once built
/// (the Java version holds `Map.copyOf`) and memoizes nothing. Both maps are `HashMap`s,
/// so **order is not behaviour** -- lookups are by key only.
public struct DxccCodeIndex: Sendable {

    /// Error message of the Java version
    /// (`DxccException("Nelze načíst čísla DXCC z dxcc.json", e)`).
    private static let parseMessage = "Nelze načíst čísla DXCC z dxcc.json"

    /// Names from `cty.dat` that are written differently in `dxcc.json` by more than just
    /// spelling (key and value are already after `normalize`).
    ///
    /// The second half are entities that DXCC does not know at all -- `cty.dat` lists them because of
    /// WAE (Sicily, Shetland, European Turkey...). For DXCC they belong under the parent
    /// country, so they are mapped to it.
    private static let aliases: [String: String] = [
        "bouvet": "bouvet is",
        "peter 1 is": "peter i is",
        "san felix and san ambrosio": "desventuradas is",
        "minami torishima": "minami tori shima",
        "ogasawara": "ogasawara is",
        "heard is": "heard is and mcdonald is",
        "itu headquarters": "international telecommunication union headquarters",
        "vienna intl ctr": "austria",
        "shetland is": "scotland",
        "african italy": "italy",
        "sicily": "italy",
        "bear is": "svalbard",
        "european turkey": "turkey",
    ]

    private let byName: [String: Int]
    private let byPrefix: [String: Int]

    private init(byName: [String: Int], byPrefix: [String: Int]) {
        self.byName = byName
        self.byPrefix = byPrefix
    }

    /// Record from the file after mapping -- the Java `RawEntity`. It has **only** these four
    /// fields; `cq`, `continent`, `prefixRegex` and the others are not in its DTO, so they are
    /// ignored entirely, even when wrongly typed (measured -- `DxccResolver` fails
    /// on the same input).
    private struct Raw {
        var entityCode = 0
        var name: String?
        var prefix: String?
        var deleted = false
    }

    /// The four creator properties of the Java `RawEntity`. The count is part of the behaviour:
    /// once all four appear in one object, any further occurrence of them is
    /// an error of the whole file -- and it is **a different count than for the resolver** (9), so
    /// the same file may pass for one type and not for the other.
    private static let creatorKeys: Set<String> = ["entityCode", "name", "prefix", "deleted"]

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
            case "prefix":
                raw.prefix = try DxccJson.string(value, key: key, message: parseMessage)
            default:
                raw.deleted = try DxccJson.bool(value, key: key, message: parseMessage)
            }
        }
        return raw
    }

    /// Builds the index from the contents of `dxcc.json`.
    ///
    /// - Throws: `DxccError` (`kind == .parse`) when the input cannot be parsed,
    ///   or (`kind == .nullPointer`) on a `null` element in the `dxcc` array. A missing
    ///   or `null` `dxcc` **field** is not an error -- an empty index results (the Java
    ///   version handles that `null` itself, `DxccResolver` does not).
    public static func fromData(_ data: Data) throws -> DxccCodeIndex {
        let root = try DxccJson.parse(data, message: parseMessage)
        let values = try DxccJson.entityValues(root, message: parseMessage) ?? []
        // 1st phase = mapping of the whole file (a type error fails the file even in a record
        // that would be skipped later), 2nd phase = building the index.
        var raws: [Raw?] = []
        raws.reserveCapacity(values.count)
        for value in values {
            guard case .object(let object) = value else {
                raws.append(nil)
                continue
            }
            raws.append(try map(object))
        }
        var names: [String: Int] = [:]
        var prefixes: [String: Int] = [:]
        var nameClash: Set<String> = []
        var prefixClash: Set<String> = []
        for raw in raws {
            guard let raw else {
                // Java `e.deleted()` on a `null` element -> NullPointerException.
                throw DxccError(kind: .nullPointer, message: parseMessage,
                                cause: "prvek pole dxcc je null")
            }
            guard !raw.deleted, let name = raw.name else { continue }
            put(&names, &nameClash, normalize(name), raw.entityCode)
            if let prefix = raw.prefix {
                for part in prefix.components(separatedBy: ",") {
                    // Java `p.trim()` leaves a non-breaking space in the key.
                    put(&prefixes, &prefixClash, JavaText.trim(part).uppercased(), raw.entityCode)
                }
            }
        }
        for key in nameClash { names.removeValue(forKey: key) }
        for key in prefixClash { prefixes.removeValue(forKey: key) }
        return DxccCodeIndex(byName: names, byPrefix: prefixes)
    }

    /// Java `put`: the first write wins, but as soon as the same key appears
    /// with a **different** number, the key is noted in `clash` and at the end it disappears
    /// from the map entirely. An empty key is not stored.
    private static func put(_ map: inout [String: Int], _ clash: inout Set<String>,
                            _ key: String, _ code: Int) {
        if key.isEmpty { return }
        if let previous = map[key] {
            if previous != code { clash.insert(key) }
            return
        }
        map[key] = code
    }

    /// DXCC entity number, or `nil` when it cannot be determined unambiguously.
    ///
    /// - Parameters:
    ///   - name: entity name as written by the source (`cty.dat`).
    ///   - primaryPrefix: primary prefix of the entity (`OM`, `3Y/p`...).
    public func code(_ name: String?, _ primaryPrefix: String?) -> Int? {
        let normalized = Self.normalize(name)
        // The alias is tried **before** a direct name match, so a WAE entity is
        // translated to the parent country even when the source has its own record
        // (measured: "Sicily" -> Italy, not the Sicilian record).
        if let byAlias = byName[Self.aliases[normalized] ?? normalized] {
            return byAlias
        }
        if let primaryPrefix {
            // Java `primaryPrefix.trim().toUpperCase()` -- `trim()` drops only
            // characters <= U+0020, so a non-breaking space in the query remains.
            let key = JavaText.trim(primaryPrefix).uppercased()
            if let byPrefixCode = byPrefix[key] {
                return byPrefixCode
            }
        }
        return nil
    }

    /// Unifies the spelling of a name: folds diacritics, drops punctuation and normalizes
    /// the usual differences between `cty.dat` and `dxcc.json` ("Islands"/"Is",
    /// "Republic"/"Rep").
    ///
    /// The chain of transformations is **order-sensitive** (`of` is deleted only after
    /// unifying "islands"->"is") -- it copies the Java `normalize` step by step.
    /// In Java the method is package-private and tests call it too, hence here it is
    /// `internal`.
    static func normalize(_ s: String?) -> String {
        guard let s else { return "" }
        // 1. NFD + dropping combining marks (Java `\p{Mn}+`).
        let withoutDiacritics = String(String.UnicodeScalarView(
            s.decomposedStringWithCanonicalMapping.unicodeScalars.filter {
                $0.properties.generalCategory != .nonspacingMark
            }))
        // 2. lowercase and `&` -> "and".
        var t = withoutDiacritics.lowercased().replacingOccurrences(of: "&", with: " and ")
        // 3. anything outside [a-z0-9] is a space.
        t = JavaText.trim(t.replacing(/[^a-z0-9]+/, with: " "))
        // 4. unifying the usual words -- in this order.
        t = t.replacing(/\b(islands|island|isl|is)\b/, with: "is")
        t = t.replacing(/\b(republic|rep)\b/, with: "rep")
        t = t.replacing(/\bof\b/, with: " ")
        t = t.replacing(/\b(federal|federation|fed)\b/, with: "fed")
        t = t.replacing(/\b(saint|st)\b/, with: "st")
        t = t.replacing(/\bhq\b/, with: "headquarters")
        // 5. a single space between words.
        return JavaText.trim(t.replacing(/\s+/, with: " "))
    }
}
