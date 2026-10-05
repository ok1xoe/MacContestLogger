import Foundation

/// Map of large squares (2-character Maidenhead field) → DXCC entities (Java `hamqth.GridFieldMap`),
/// derived from the callsign database (`ww_digi_grid.csv`) via the DXCC resolver: for each callsign we know the grid
/// field and the DXCC, so we know from which fields which country really transmits. `GridComment` uses it
/// via the protocol `GridFieldLookup`.
///
/// Construction (for the file format see `CallsignGridCsv`): a line with an empty callsign or a locator shorter
/// than 2 UTF-16 units is skipped; field = first 2 units of the locator `toUpperCase()` (port
/// convention `uppercased()`); a callsign the resolver does not know is skipped (the field is not even created).
/// A locator starting with a non-BMP character + another character: Java takes a field with a lone half of a pair,
/// here U+FFFD (the same class as `FixedMultiplierSet` `keyLength`) — a key
/// that a valid field never asks for.
public struct GridFieldMap: GridFieldLookup {

    private let entitiesByField: [JavaStringKey: Set<Int>]

    private init(_ entitiesByField: [JavaStringKey: Set<Int>]) {
        self.entitiesByField = entitiesByField
    }

    public static let empty = GridFieldMap([:])

    /// Is the field in the map (do we have data for it)? Field `trim().toUpperCase()`; `nil` → false.
    public func known(_ field: String?) -> Bool {
        guard let field else { return false }
        return entitiesByField[GridFieldMap.key(field)] != nil
    }

    /// Does the given DXCC entity transmit from this field (per historical data)?
    public func matches(_ field: String?, entityCode: Int) -> Bool {
        guard let field, let set = entitiesByField[GridFieldMap.key(field)] else { return false }
        return set.contains(entityCode)
    }

    /// Loads from `<contestDataDir>/multipliers/ww_digi_grid.csv`, otherwise an empty map (also without a resolver
    /// or on a read error).
    public static func fromDir(_ contestDataDir: URL?, _ dxcc: (any DxccLookup)?) -> GridFieldMap {
        guard let contestDataDir, let dxcc else { return empty }
        let file = CallsignGridCsv.file(in: contestDataDir)
        guard BandPlan.isRegularFile(file), let data = try? Data(contentsOf: file) else {
            return empty
        }
        return build(data, dxcc)
    }

    /// Java `build(InputStream, DxccLookup)` over the whole CSV content.
    public static func build(_ csv: Data, _ dxcc: any DxccLookup) -> GridFieldMap {
        var map: [JavaStringKey: Set<Int>] = [:]
        for row in CallsignGridCsv.rows(csv) {
            let gridUnits: [UInt16] = Array(row.grid.utf16)
            if row.call.isEmpty || gridUnits.count < 2 {
                continue
            }
            let field = String(decoding: gridUnits[0..<2], as: UTF16.self).uppercased()
            if let entity = dxcc.resolve(row.call) {
                map[JavaStringKey(field), default: []].insert(entity.entityCode)
            }
        }
        return GridFieldMap(map)
    }

    private static func key(_ field: String) -> JavaStringKey {
        JavaStringKey(JavaText.trim(field).uppercased())
    }
}
