/// The callbook rules of v1.1.1 (`ui/AppState.kt`: `lookupCallbook` `:311-334`, `sourceAllows` `:415-425`,
/// `fetchMerged` `:427-443`, `prefetchGridsForSpots` `:449-470`, `hamQthRecordFor` `:298-299`) without the clients
/// and the cache — the app model owns those and asks here what to query and how to merge.
///
/// Kotlin quirk kept: the typed-call lookup is gated by `configured()` of either client **without** `isEnabled`.
/// A source that is enabled without credentials is never asked; one with credentials but disabled lets the lookup
/// through to the lane, which then queries nothing and caches `EMPTY`.
public enum CallbookPolicy {

    /// The two callbooks, in the order they are asked.
    public enum Source: Equatable, Sendable {
        case hamQth
        case qrz
    }

    /// The cache key: Kotlin `call.trim().uppercase()`.
    public static func key(_ call: String) -> String {
        JavaText.toUpperCase(KotlinText.trim(call))
    }

    /// `lookupCallbook` gate: the key when it has at least 3 UTF-16 units and either client is configured, otherwise
    /// `nil` (the entry window then clears its callbook record).
    public static func lookupKey(call: String, hamQthConfigured: Bool, qrzConfigured: Bool) -> String? {
        let key: String = key(call)
        if key.utf16.count < 3 || (!hamQthConfigured && !qrzConfigured) {
            return nil
        }
        return key
    }

    /// The sources the typed-call lookup queries: each only when enabled **and** configured (no mode or field filter).
    public static func lookupSources(hamQthEnabled: Bool, hamQthConfigured: Bool, qrzEnabled: Bool,
                                     qrzConfigured: Bool) -> [Source] {
        var out: [Source] = []
        if hamQthEnabled && hamQthConfigured { out.append(.hamQth) }
        if qrzEnabled && qrzConfigured { out.append(.qrz) }
        return out
    }

    /// `sourceAllows`: enabled, configured, and the spot category (`nil` = unknown) in the source's modes; empty modes
    /// or an unknown category allow. Modes and the category compare after Kotlin `uppercase()`.
    public static func sourceAllows(enabled: Bool, configured: Bool, modes: [String], category: String?) -> Bool {
        if !enabled || !configured { return false }
        let set = Set(modes.map { JavaText.toUpperCase($0) })
        guard let category else { return true }
        return set.isEmpty || set.contains(JavaText.toUpperCase(category))
    }

    /// The merge of `lookupCallbook` (`fields == nil`: every field) and `fetchMerged` (`fields` = the source's
    /// `fetchFields`, matched exactly): per field the first value that is not Kotlin-blank wins — a blank value is kept
    /// only until a later source has a better one.
    public static func merge(_ records: [(record: HamQthRecord, fields: [String]?)]) -> HamQthRecord {
        var grid = ""
        var name = ""
        var cq = ""
        var itu = ""
        for (record, fields) in records {
            if allows(fields, "grid") && KotlinText.isBlank(grid) { grid = record.grid }
            if allows(fields, "name") && KotlinText.isBlank(name) { name = record.name }
            if allows(fields, "cqZone") && KotlinText.isBlank(cq) { cq = record.cqZone }
            if allows(fields, "ituZone") && KotlinText.isBlank(itu) { itu = record.ituZone }
        }
        return HamQthRecord(grid: grid, name: name, cqZone: cq, ituZone: itu)
    }

    private static func allows(_ fields: [String]?, _ field: String) -> Bool {
        guard let fields else { return true }
        return fields.contains(field)
    }

    /// The prefetch gate: only for a contest that needs callbook data and with either client configured.
    public static func prefetchAllowed(needsLookup: Bool, hamQthConfigured: Bool, qrzConfigured: Bool) -> Bool {
        needsLookup && (hamQthConfigured || qrzConfigured)
    }

    /// `prefetchGridsForSpots` selection: spots with a non-empty key, not cached, without an offline grid and allowed
    /// by a source; one spot per key (the first in buffer order).
    public static func prefetchSelection(spots: [DxSpot], cached: (String) -> Bool, hasOfflineGrid: (String) -> Bool,
                                         allows: (DxSpot) -> Bool) -> [DxSpot] {
        var seen = Set<String>()
        var out: [DxSpot] = []
        for spot in spots {
            let key: String = key(spot.dxCall)
            if key.isEmpty || cached(key) || hasOfflineGrid(key) || !allows(spot) { continue }
            if seen.insert(key).inserted {
                out.append(spot)
            }
        }
        return out
    }

    /// `hamQthRecordFor` / the cache hit of `lookupCallbook`: a cached `EMPTY` counts as nothing.
    public static func usable(_ record: HamQthRecord?) -> HamQthRecord? {
        guard let record, !record.isEmpty else { return nil }
        return record
    }
}
