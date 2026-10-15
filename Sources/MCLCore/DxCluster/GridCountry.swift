import Foundation

/// N1MM's VHF locator helpers: does a typed locator fit the station's country, and the big grid (2-character field)
/// of a country that has only one.
public enum GridCountry {

    /// Is the locator plausible for the entity? By the field → country data when the field is known, otherwise by the
    /// distance from the entity's coordinates (3,500 km, like the spot grid check). Without data `true`.
    public static func plausible(_ grid: String, entity: DxccEntity, fieldMap: GridFieldMap?) -> Bool {
        let upper: String = grid.uppercased()
        guard upper.count >= 4 else { return true }
        let field = String(upper.prefix(2))
        if fieldMap?.known(field) != true && !entity.hasLatLon {
            return true
        }
        return GridComment.check(grid: upper, field: field, entity: entity, fieldMap: fieldMap).ok
    }

    /// The only field the entity transmits from (`OK` → `JN`?), `nil` when it has more or no data.
    public static func bigGrid(entity: DxccEntity, fieldMap: GridFieldMap?) -> String? {
        guard let fields = fieldMap?.fields(entityCode: entity.entityCode), fields.count == 1 else { return nil }
        return fields[0]
    }
}
