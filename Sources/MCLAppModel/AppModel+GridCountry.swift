import Foundation
import MCLCore

/// N1MM's VHF locator helpers in the entry window: the big grid of a one-field country and a warning when the typed
/// locator does not fit the station's country.
extension AppModel {

    /// The only grid field of the call's country (`nil` = more fields, no data yet, or no DXCC).
    public func bigGrid(call: String) -> String? {
        guard let entity = contest.runtime.dxccLookup?.resolve(call) else { return nil }
        return GridCountry.bigGrid(entity: entity, fieldMap: callbook.gridData?.fieldMap)
    }

    /// „JN79 nesedí k zemi DL" for a typed locator that does not fit the country of the typed call; `nil` = fits or
    /// nothing to check.
    public func gridWarning(_ entry: EntryModel) -> String? {
        guard contest.isActive, KotlinStrings.trim(entry.form.call).utf16.count >= 3,
              let id = entry.fields.first(where: { $0.type == .LOCATOR })?.id,
              let grid = entry.form.contestExchange[id].map({ KotlinStrings.trim($0).uppercased() }),
              QsoSearch.isLocator(grid),
              let entity = contest.runtime.dxccLookup?.resolve(entry.form.call) else { return nil }
        guard !GridCountry.plausible(grid, entity: entity, fieldMap: callbook.gridData?.fieldMap) else { return nil }
        return language.tr("%s nesedí k zemi %s", .string(grid), .string(entity.primaryPrefix ?? entity.name ?? ""))
    }
}
