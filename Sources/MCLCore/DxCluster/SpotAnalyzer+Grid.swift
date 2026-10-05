import Foundation

extension SpotAnalyzer {

    /// Kotlin `multiplierGrid(kind, spots)` (`ContestController.kt:615-697`): the grid of one multiplier kind (key ×
    /// band of `multGridBands`) with the spotted layer from the spots.
    ///
    /// Kinds: `dxcc` (a DXCC set; spot key = entity code), `grid` (set `grid_fields`; key = the first two characters
    /// of the spot's grid, upper case, exactly two), `itu` / `cq` (sets `itu_zones` / `cq_zones`; key = the first
    /// zone of the entity), `districts` / `sections` / `other` (by `MultiplierKind.classify`; no key from a spot).
    /// Another kind, no contest, or no matching binding → `MultGridView.unavailable`.
    ///
    /// A cell is `worked` (worked on the band), `spottedDbl` (a spot of that key and band brings more than one new
    /// multiplier), `spotted`, or `empty`. Spots of a determined non-contest mode are ignored. `spotAt` keeps the
    /// first spot of a cell. A non-enumerable set gets extra rows for spotted keys not yet worked, sorted by
    /// UTF-16 (Kotlin `sorted()`), with the key as label and empty prefix/continent.
    public func multiplierGrid(kind: String, spots: [DxSpot]) -> MultGridView {
        guard let session else { return .unavailable }
        guard let selector = selector(kind: kind, definition: session.definition) else { return .unavailable }
        let bands: [Band] = Self.multGridBands
        guard let grid = try? session.multiplierGrid(bands: bands, matching: selector.matches),
              grid.available else {
            return .unavailable
        }

        // Spotted layer: (key, band) → double multiplier? + the spot for tuning by a click.
        var spotted: [MultGridView.CellKey: Bool] = [:]
        var spotAt: [MultGridView.CellKey: DxSpot] = [:]
        for spot in spots {
            if !isColorRelevant(spot) {
                continue
            }
            guard let key = selector.spotKey(spot), let band = Band.from(frequencyHz: spot.freqHz) else { continue }
            let cell = MultGridView.CellKey(key: key, band: band.adif)
            // Kotlin `(spotted[k] ?: false) || (spotStatus(spot).newMultCount > 1)` — short-circuit.
            let already: Bool = spotted[cell] ?? false
            spotted[cell] = already || spotStatus(spot).newMultCount > 1
            if spotAt[cell] == nil {
                spotAt[cell] = spot
            }
        }

        func cellsFor(_ key: String, _ workedBands: [String]) -> [String: MultCell] {
            var cells: [String: MultCell] = [:]
            for band in bands {
                let adif: String = band.adif
                let cell = MultGridView.CellKey(key: key, band: adif)
                if workedBands.contains(where: { JavaText.equals($0, adif) }) {
                    cells[adif] = .worked
                } else if let double = spotted[cell] {
                    cells[adif] = double ? .spottedDbl : .spotted
                } else {
                    cells[adif] = .empty
                }
            }
            return cells
        }

        var rows: [MultGridRow] = []
        var existing: Set<String> = []
        for row in grid.rows {
            // A `nil` key or label (Kotlin NPE in the non-null `MultGridRow`) is shown as an empty text.
            let key: String = row.key ?? ""
            existing.insert(key)
            rows.append(MultGridRow(key: key, label: row.label ?? "", prefix: row.prefix, continent: row.continent,
                                    cells: cellsFor(key, row.workedBands)))
        }
        var extraKeys: Set<String> = []
        for cell in spotted.keys where !existing.contains(cell.key) {
            extraKeys.insert(cell.key)
        }
        let extra: [String] = extraKeys.sorted { JavaText.compare($0, $1) < 0 }
        for key in extra {
            rows.append(MultGridRow(key: key, label: key, prefix: "", continent: "", cells: cellsFor(key, [])))
        }
        return MultGridView(available: true, worked: Int(grid.worked), possible: Int(grid.possible), rows: rows,
                            spotAt: spotAt)
    }

    /// The binding predicate and the spot key of a grid kind (Kotlin `when (kind)`, `:624-655`).
    private struct GridSelector {
        let matches: (ContestDefinition.MultiplierBinding, any MultiplierSet) -> Bool
        let spotKey: (DxSpot) -> String?
    }

    private func selector(kind: String, definition: ContestDefinition) -> GridSelector? {
        let dxcc = self.dxcc
        switch kind {
        case "dxcc":
            return GridSelector(matches: { _, set in set is DxccMultiplierSet },
                                spotKey: { spot in dxcc?.resolve(spot.dxCall).map { String($0.entityCode) } })
        case "grid":
            return GridSelector(matches: { _, set in Self.hasId(set, "grid_fields") },
                                spotKey: { spot in Self.gridField(self.gridForSpot(spot)) })
        case "itu":
            return GridSelector(matches: { _, set in Self.hasId(set, "itu_zones") },
                                spotKey: { spot in Self.firstZone(dxcc?.resolve(spot.dxCall)?.itu) })
        case "cq":
            return GridSelector(matches: { _, set in Self.hasId(set, "cq_zones") },
                                spotKey: { spot in Self.firstZone(dxcc?.resolve(spot.dxCall)?.cq) })
        case "districts", "sections", "other":
            return GridSelector(matches: { binding, set in
                JavaText.equals(MultiplierKind.classify(definition, binding, set).key, kind)
            }, spotKey: { _ in nil })
        default:
            return nil
        }
    }

    /// Kotlin `set.id() == id` (a `nil` id never matches).
    private static func hasId(_ set: any MultiplierSet, _ id: String) -> Bool {
        guard let setId = set.id else { return false }
        return JavaText.equals(id, setId)
    }

    /// Kotlin `firstOrNull()?.toString()`: a missing list, an empty list or a `null` first zone → `nil`.
    private static func firstZone(_ zones: [Int?]?) -> String? {
        guard let zones, let first = zones.first, let zone = first else { return nil }
        return String(zone)
    }

    /// Kotlin `grid?.take(2)?.uppercase()?.takeIf { it.length == 2 }` (UTF-16 units).
    static func gridField(_ grid: String?) -> String? {
        guard let grid else { return nil }
        let head: [UInt16] = Array(grid.utf16.prefix(2))
        let field: String = JavaText.toUpperCase(JavaChar.string(head))
        return field.utf16.count == 2 ? field : nil
    }
}
