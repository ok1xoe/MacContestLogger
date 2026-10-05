/// Map of large squares (2-character Maidenhead field) → DXCC entities, as `GridComment` uses it
/// to verify a grid (Java `hamqth.GridFieldMap` — it is ported in the `hamqth/` package, which
/// conforms to this protocol).
public protocol GridFieldLookup: Sendable {
    /// Is the field in the map (do we have data for it)? Java `known(field)`.
    func known(_ field: String?) -> Bool
    /// Does the given DXCC entity transmit from this field? Java `matches(field, entityCode)`.
    func matches(_ field: String?, entityCode: Int) -> Bool
}

/// Maidenhead locator from the body of a DX spot (Java `dxcluster.GridComment`), but only if the grid's position
/// roughly matches the callsign's DXCC entity — so that the spotter's grid or a random string is not mistaken for it.
///
/// The pattern `\b([A-R]{2}[0-9]{2}(?:[A-X]{2})?)\b` runs over `comment.toUpperCase()` (port convention:
/// `uppercased()`), candidates in order of occurrence, the first that passes wins. Verification: first via the
/// field → DXCC map (`GridFieldLookup`), otherwise by the distance of the grid centre from the entity's coordinates
/// (`GreatCircle`, threshold 3,500 km), rejected if neither applies. The decision log has Java texts
/// (`String.format("%.0f km od %s", …)` via `JavaFormat`, a `null` prefix as "null").
public enum GridComment {

    private static let gridPattern: JavaRegex = DxClusterRegex.compile("\\b([A-R]{2}[0-9]{2}(?:[A-X]{2})?)\\b")
    private static let maxKm: Double = 3500.0

    /// - Parameters:
    ///   - fieldMap: field → DXCC map, or `nil` for distance-only verification
    ///   - log: optional decision logger (candidates), or `nil`
    public static func extractGrid(_ comment: String?, _ entity: DxccEntity?,
                                   fieldMap: (any GridFieldLookup)? = nil,
                                   log: ((String) -> Void)? = nil) -> String? {
        guard let comment, let entity else { return nil }
        for match in gridPattern.allMatches(in: comment.uppercased()) {
            let grid = match.group(1) ?? ""
            let field = String(grid.prefix(2))
            let decision = check(grid: grid, field: field, entity: entity, fieldMap: fieldMap)
            if let log {
                let verdict = decision.ok ? "PŘIJAT" : "zamítnut"
                log(JavaFormat.format("  kandidát %s: %s → %s", .string(grid), .string(decision.why), .string(verdict)))
            }
            if decision.ok {
                return grid
            }
        }
        return nil
    }

    private static func check(grid: String, field: String, entity: DxccEntity,
                              fieldMap: (any GridFieldLookup)?) -> (ok: Bool, why: String) {
        let prefix: String = entity.primaryPrefix ?? "null"
        if let fieldMap, fieldMap.known(field) {
            let ok = fieldMap.matches(field, entityCode: entity.entityCode)
            var why = "pole " + field
            why += ok ? " patří " : " nepatří "
            why += prefix + " (dle dat)"
            return (ok, why)
        }
        if entity.hasLatLon {
            var dist: Double = -1
            if let center = Maidenhead.centerLatLon(grid) {
                dist = GreatCircle.distanceKm(center.lat, center.lon, entity.lat, entity.lon)
            }
            let ok = dist >= 0 && dist <= maxKm
            return (ok, JavaFormat.format("%.0f km od %s", .double(dist), .string(entity.primaryPrefix)))
        }
        return (false, "nelze ověřit (bez dat i souřadnic)")
    }
}
