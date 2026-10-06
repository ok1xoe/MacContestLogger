import Foundation

/// DXCC resolver over Club Log's `cty.xml` (`ClubLogCtyData`), with Club Log's lookup order:
///
/// 1. **Exception** — the whole callsign (as written, upper-case) with an exception record valid at the QSO date;
/// 2. **Invalid operation** — the whole callsign listed as an invalid operation at that date → no entity;
/// 3. `/MM` (maritime mobile) and `/AM` (aeronautical mobile) → no entity; the modifiers `/P`, `/M`, `/QRP`, `/A`,
///    `/R`, `/LH`, `/B`, `/J` are dropped;
/// 4. **Prefix** — the prefix-bearing part of the call (the shorter part of `DL/OK1XOE` or `OK1XOE/DL`, the call
///    itself otherwise; a single-digit suffix moves the call area, `UA1ABC/9` → `UA9ABC`) matched against the
///    prefix records by the longest prefix valid at the QSO date;
/// 5. **Zone exception** — the whole callsign with its own CQ zone at that date overrides the zone of the result.
///
/// A record with ADIF number 0 (Club Log's "no DXCC") resolves to no entity.
///
/// The entity: `entityCode` and `adifDxcc` are the DXCC (ADIF) number, `countryCode` and `primaryPrefix` the entity's
/// primary prefix (as with `cty.dat`), `continents`/`cq`/coordinates from the matched record (falling back to the
/// entity). `cty.xml` has no ITU zones and spells names in capitals: both come from `localNames` (the other DXCC
/// source, matched by ADIF number) when it knows the entity.
///
/// All data are immutable after the build, so the type is `Sendable` without a lock; every lookup is local.
public final class ClubLogCtyResolver: DxccLookup {

    /// What the other DXCC source knows about an ADIF number (name and ITU zones).
    public struct LocalEntity: Sendable, Equatable {
        public let name: String?
        public let itu: [Int?]?

        public init(name: String?, itu: [Int?]?) {
            self.name = name
            self.itu = itu
        }
    }

    private static let droppedSuffixes: Set<String> = ["P", "M", "QRP", "A", "R", "LH", "B", "J"]
    private static let noDxccSuffixes: Set<String> = ["MM", "AM"]

    private let entitiesByAdif: [Int: ClubLogCtyData.Entity]
    private let exceptions: [String: [ClubLogCtyData.Mapping]]
    private let prefixes: [String: [ClubLogCtyData.Mapping]]
    private let invalid: [String: [ClubLogCtyData.InvalidOperation]]
    private let zones: [String: [ClubLogCtyData.ZoneException]]
    private let maxPrefixLength: Int
    private let local: [Int: LocalEntity]
    private let all: [DxccEntity]
    private let now: @Sendable () -> Date

    /// - Parameters:
    ///   - localNames: names and ITU zones by ADIF number from the other DXCC source (`nil`/empty = Club Log's own).
    ///   - now: the date of a lookup without a QSO date (`resolve(_:)`: live logging, spots, the info lines).
    public init(_ data: ClubLogCtyData, localNames: [Int: LocalEntity] = [:],
                now: @escaping @Sendable () -> Date = Date.init) {
        var byAdif: [Int: ClubLogCtyData.Entity] = [:]
        for entity in data.entities where byAdif[entity.adif] == nil {
            byAdif[entity.adif] = entity
        }
        entitiesByAdif = byAdif
        exceptions = Dictionary(grouping: data.exceptions, by: \.call)
        prefixes = Dictionary(grouping: data.prefixes, by: \.call)
        invalid = Dictionary(grouping: data.invalidOperations, by: \.call)
        zones = Dictionary(grouping: data.zoneExceptions, by: \.call)
        maxPrefixLength = data.prefixes.map(\.call.count).max() ?? 0
        local = localNames
        self.now = now
        var listed: [DxccEntity] = []
        var seen: Set<Int> = []
        for entity in data.entities.sorted(by: { $0.adif < $1.adif })
        where !entity.deleted && entity.adif > 0 && seen.insert(entity.adif).inserted {
            listed.append(Self.makeEntity(entity, record: nil, cqz: nil, local: localNames[entity.adif]))
        }
        all = listed
    }

    /// The names and ITU zones of another source, by ADIF number (entities without a number are skipped; the first
    /// one of a number wins).
    public static func localNames(from lookup: (any DxccLookup)?) -> [Int: LocalEntity] {
        var out: [Int: LocalEntity] = [:]
        for entity in lookup?.entities() ?? [] {
            guard let adif = entity.adifDxcc, out[adif] == nil else { continue }
            out[adif] = LocalEntity(name: entity.name, itu: entity.itu)
        }
        return out
    }

    public func entities() -> [DxccEntity] {
        all
    }

    public func resolve(_ callsign: String?) -> DxccEntity? {
        resolve(callsign, at: nil)
    }

    public func resolve(_ callsign: String?, at date: Date?) -> DxccEntity? {
        guard let callsign else { return nil }
        let call = JavaText.trim(callsign).uppercased()
        guard !call.isEmpty else { return nil }
        let when: Date = date ?? now()
        if let exception = Self.valid(exceptions[call], at: when) {
            return entity(for: exception, call: call, at: when)
        }
        if invalid[call]?.contains(where: { ClubLogCtyData.isValid(at: when, start: $0.start, end: $0.end) }) == true {
            return nil
        }
        guard let prefixPart = Self.prefixPart(call) else { return nil }
        var length = min(prefixPart.count, maxPrefixLength)
        while length > 0 {
            let candidate = String(prefixPart.prefix(length))
            if let mapping = Self.valid(prefixes[candidate], at: when) {
                return entity(for: mapping, call: call, at: when)
            }
            length -= 1
        }
        return nil
    }

    /// The part of the call that carries the prefix, or `nil` for `/MM` and `/AM`.
    static func prefixPart(_ call: String) -> String? {
        guard call.contains("/") else { return call }
        let parts = call.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        if parts.count > 1, let last = parts.last, noDxccSuffixes.contains(last) {
            return nil
        }
        var tokens: [String] = []
        var areaDigit: Character?
        for (index, part) in parts.enumerated() {
            if index > 0 && droppedSuffixes.contains(part) {
                continue
            }
            if index > 0, part.count == 1, let char = part.first, char.isASCII, char.isNumber {
                areaDigit = char
                continue
            }
            tokens.append(part)
        }
        guard var chosen = tokens.first else {
            return call.replacingOccurrences(of: "/", with: "")
        }
        for token in tokens.dropFirst() where token.count < chosen.count {
            chosen = token
        }
        if let areaDigit, tokens.count == 1 {
            chosen = moveCallArea(chosen, to: areaDigit)
        }
        return chosen
    }

    /// `UA1ABC` + `9` → `UA9ABC`: the first run of digits is replaced by the area digit.
    private static func moveCallArea(_ call: String, to digit: Character) -> String {
        let chars = Array(call)
        guard let first = chars.firstIndex(where: { $0.isASCII && $0.isNumber }) else { return call }
        var end = first
        while end < chars.count, chars[end].isASCII, chars[end].isNumber { end += 1 }
        return String(chars[..<first]) + String(digit) + String(chars[end...])
    }

    private static func valid(_ records: [ClubLogCtyData.Mapping]?, at date: Date) -> ClubLogCtyData.Mapping? {
        records?.first { ClubLogCtyData.isValid(at: date, start: $0.start, end: $0.end) }
    }

    private func entity(for mapping: ClubLogCtyData.Mapping, call: String, at date: Date) -> DxccEntity? {
        guard mapping.adif > 0 else { return nil }
        let base = entitiesByAdif[mapping.adif]
            ?? ClubLogCtyData.Entity(adif: mapping.adif, name: mapping.entity ?? "", prefix: mapping.call)
        let zone: Int? = zones[call]?.first { ClubLogCtyData.isValid(at: date, start: $0.start, end: $0.end) }?.zone
        return Self.makeEntity(base, record: mapping, cqz: zone, local: local[mapping.adif])
    }

    private static func makeEntity(_ entity: ClubLogCtyData.Entity, record: ClubLogCtyData.Mapping?, cqz: Int?,
                                   local: LocalEntity?) -> DxccEntity {
        let continent: String? = record?.cont ?? entity.cont
        let zone: Int? = cqz ?? record?.cqz ?? entity.cqz
        let lat: Double = record?.lat ?? entity.lat ?? .nan
        let lon: Double = record?.lon ?? entity.lon ?? .nan
        let name: String? = local?.name ?? (entity.name.isEmpty ? nil : entity.name)
        let prefix: String? = entity.prefix.isEmpty ? nil : entity.prefix
        return DxccEntity(entityCode: entity.adif, name: name, countryCode: prefix,
                          continents: continent.map { [$0] }, cq: zone.map { [$0] }, itu: local?.itu,
                          lat: lat, lon: lon, primaryPrefix: prefix, adifDxcc: entity.adif)
    }
}
