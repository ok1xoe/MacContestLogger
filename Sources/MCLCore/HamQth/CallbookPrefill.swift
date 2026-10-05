/// Pre-filling the exchange from the callbook (Java `hamqth.CallbookPrefill`, N1MM Callbook lookup): locator,
/// CQ and ITU zone and name from HamQTH / QRZ into the corresponding fields of the received exchange.
public enum CallbookPrefill {

    public typealias FieldType = ContestDefinition.FieldType

    /// Java `prefill(rec, received)` → `LinkedHashMap` field id → value `trim().toUpperCase()`.
    ///
    /// Type `nil` = `TEXT`; `LOCATOR` ← grid, `CQ_ZONE`/`ITU_ZONE` ← zones, `TEXT` with id `name` (case-
    /// insensitive, Java `equalsIgnoreCase`) ← name; others nothing. An `isBlank` value is
    /// not inserted; a later field with the same id overwrites the value at the original position; id `nil` is the Java key
    /// `null`. A `nil`/empty record or `received == nil` → empty map.
    public static func prefill(_ rec: HamQthRecord?,
                               _ received: [ContestDefinition.ExchangeField]?) -> JavaLinkedMap<String> {
        var out = JavaLinkedMap<String>()
        guard let rec, !rec.isEmpty, let received else {
            return out
        }
        for field in received {
            let value: String
            switch field.type ?? .TEXT {
            case .LOCATOR:
                value = rec.grid
            case .CQ_ZONE:
                value = rec.cqZone
            case .ITU_ZONE:
                value = rec.ituZone
            case .TEXT:
                value = isName(field.id) ? rec.name : ""
            default:
                value = ""
            }
            if !JavaText.isBlank(value) {
                out.put(field.id, JavaText.trim(value).uppercased())
            }
        }
        return out
    }

    /// One-line description for the entry window: `name · GRID · CQ n · ITU n` (empty `isBlank` parts
    /// omitted, grid `toUpperCase`).
    public static func describe(_ rec: HamQthRecord) -> String {
        var parts: [String] = []
        if !JavaText.isBlank(rec.name) {
            parts.append(rec.name)
        }
        if !JavaText.isBlank(rec.grid) {
            parts.append(rec.grid.uppercased())
        }
        if !JavaText.isBlank(rec.cqZone) {
            parts.append("CQ " + rec.cqZone)
        }
        if !JavaText.isBlank(rec.ituZone) {
            parts.append("ITU " + rec.ituZone)
        }
        // Parts are never empty (`isBlank` filters them out), so the Java "separator if `sb`
        // is non-empty" = joining by the separator.
        return parts.joined(separator: " \u{00B7} ")
    }

    /// Java `"name".equalsIgnoreCase(id)` (`null` → false).
    private static func isName(_ id: String?) -> Bool {
        guard let id else { return false }
        return id.utf16.count == 4 && JavaText.caseInsensitiveOrder("name", id) == 0
    }
}
