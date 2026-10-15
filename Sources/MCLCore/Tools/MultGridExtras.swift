import Foundation

/// N1MM Multipliers window features beyond the Java grid: the mouse-over information of a prefix, the right-click
/// menu (calls worked and spots, countries in a zone, turn the antenna, rover QTH), the bands displayed and the
/// expected multiplier list with „show all possible". Pure.
public enum MultGridExtras {

    // MARK: - bands displayed

    /// The bands offered by „Pásma v mřížce" (160 m – 70 cm and the microwave bands).
    public static let bandChoices: [Band] = Band.allCases

    /// The saved band list (`"160m,40m"`) as bands in band order; an empty or unreadable list = the default.
    public static func bands(_ saved: String?) -> [Band] {
        let picked: Set<Band> = Set((saved ?? "").split(separator: ",").compactMap {
            Band.from(adif: $0.trimmingCharacters(in: .whitespaces))
        })
        let out: [Band] = Band.allCases.filter { picked.contains($0) }
        return out.isEmpty ? SpotAnalyzer.multGridBands : out
    }

    /// The bands as saved (`nil` = the default, nothing to save).
    public static func savedBands(_ bands: [Band]) -> String? {
        let ordered: [Band] = Band.allCases.filter { bands.contains($0) }
        return ordered.isEmpty || ordered == SpotAnalyzer.multGridBands ? nil
            : ordered.map(\.adif).joined(separator: ",")
    }

    /// The `multGridBands` key of a kind's modes shown (`dxcc/modes`).
    public static func modesKey(_ kind: String) -> String {
        kind + "/modes"
    }

    /// The modes shown (`CW,SSB`), only those of the contest, in its order; `nil` = none saved or none left (the
    /// default: the contest's first mode).
    public static func modes(_ saved: String?, of contestModes: [String]) -> [String]? {
        let picked: Set<String> = Set((saved ?? "").split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces).uppercased()
        })
        let out: [String] = contestModes.filter { picked.contains($0.uppercased()) }
        return out.isEmpty ? nil : out
    }

    /// The modes as saved (`nil` = the default, the contest's first mode alone).
    public static func savedModes(_ modes: [String], of contestModes: [String]) -> String? {
        let ordered: [String] = contestModes.filter { modes.contains($0) }
        return ordered.isEmpty || ordered == Array(contestModes.prefix(1)) ? nil : ordered.joined(separator: ",")
    }

    /// The header of a band column (`160`, `70cm` → `70c`): the ADIF name without the `m`.
    public static func header(_ band: Band) -> String {
        String(band.adif.dropLast())
    }

    // MARK: - expected multipliers

    /// N1MM „Edit Expected Multiplier List": one multiplier per line as the window shows it (prefix or key), upper
    /// case; anything after the first word (N1MM's band in MHz) is ignored, `#` starts a comment.
    public static func expected(_ text: String) -> Set<String> {
        var out: Set<String> = []
        for line in text.split(whereSeparator: \.isNewline) {
            let content: Substring = line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
                .first ?? ""
            guard let word = content.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "," }).first else {
                continue
            }
            out.insert(word.uppercased())
        }
        return out
    }

    /// The list as text, one per line, sorted.
    public static func expectedText(_ keys: Set<String>) -> String {
        keys.sorted().map { $0 + "\n" }.joined()
    }

    /// N1MM „Export Mults & Bands from this Contest": the worked multipliers with their worked bands
    /// (`DL 14 7`, bands in MHz), readable back as an expected list.
    public static func workedExport(_ rows: [MultGridRow], bands: [Band]) -> String {
        var lines: [String] = []
        for row in rows {
            let worked: [String] = bands.filter { row.cells[$0.adif] == .worked }.map { mhz($0) }
            guard !worked.isEmpty else { continue }
            lines.append(([MultGridLayout.label(row).uppercased()] + worked).joined(separator: " "))
        }
        return lines.map { $0 + "\n" }.joined()
    }

    private static func mhz(_ band: Band) -> String {
        let value: Double = Double(band.lowHz) / 1_000_000
        return value >= 1 ? String(Int(value)) : String(value)
    }

    /// Whether a row is on the expected list (its label, prefix or key).
    public static func isExpected(_ row: MultGridRow, _ expected: Set<String>) -> Bool {
        guard !expected.isEmpty else { return false }
        return [MultGridLayout.label(row), row.prefix, row.key, row.label].contains { expected.contains($0.uppercased()) }
    }

    /// The rows shown: by default the worked and spotted ones and the expected ones (N1MM „Show only worked &
    /// expected"); `showAll` every possible multiplier. The continent filter applies in both.
    public static func visibleRows(_ rows: [MultGridRow], bands: [Band], continents: Set<String>,
                                   expected: Set<String>, showAll: Bool) -> [MultGridRow] {
        rows.filter { row in
            guard KotlinText.isBlank(row.continent) || continents.contains(row.continent) else { return false }
            if showAll {
                return true
            }
            return bands.contains { (row.cells[$0.adif] ?? .empty) != .empty } || isExpected(row, expected)
        }
    }

    // MARK: - prefix information and the right-click menu

    /// The DXCC entity of a `dxcc` row (its key is the entity code).
    public static func entity(kind: String, row: MultGridRow, lookup: (any DxccLookup)?) -> DxccEntity? {
        guard kind == "dxcc", let code = Int(row.key) else { return nil }
        return lookup?.entities().first { $0.entityCode == code }
    }

    /// The position of a row: the entity's for `dxcc`, the centre of the field for `grid`.
    public static func position(kind: String, row: MultGridRow, lookup: (any DxccLookup)?)
        -> (lat: Double, lon: Double)? {
        if let entity = entity(kind: kind, row: row, lookup: lookup) {
            return entity.hasLatLon ? (entity.lat, entity.lon) : nil
        }
        if kind == "grid" {
            return fieldCenter(row.key) ?? Maidenhead.centerLatLon(row.key)
        }
        return nil
    }

    /// The centre of a two-letter Maidenhead field (`JO` → 55° N, 10° E).
    static func fieldCenter(_ field: String) -> (lat: Double, lon: Double)? {
        let letters: [UInt8] = Array(field.uppercased().utf8)
        guard letters.count == 2, letters.allSatisfy({ $0 >= 65 && $0 <= 82 }) else { return nil }
        return (Double(Int(letters[1]) - 65) * 10 - 90 + 5, Double(Int(letters[0]) - 65) * 20 - 180 + 10)
    }

    /// The short-path azimuth to a row from my position (Turn Antenna); `nil` without both positions.
    public static func azimuth(kind: String, row: MultGridRow, lookup: (any DxccLookup)?, myLat: Double,
                               myLon: Double) -> Double? {
        guard !myLat.isNaN, !myLon.isNaN, let target = position(kind: kind, row: row, lookup: lookup) else {
            return nil
        }
        return GreatCircle.bearingDeg(myLat, myLon, target.lat, target.lon)
    }

    /// N1MM's mouse-over of a prefix: `DL Germany · EU · CQ 14 · ITU 28 · SP 51° LP 231° · 1234 km` (the parts that
    /// are known); a field gives its bearing and distance; `nil` for other kinds.
    public static func prefixInfo(kind: String, row: MultGridRow, lookup: (any DxccLookup)?, myLat: Double,
                                  myLon: Double) -> String? {
        var parts: [String] = []
        if let entity = entity(kind: kind, row: row, lookup: lookup) {
            parts.append([entity.primaryPrefix, entity.name].compactMap { $0 }.joined(separator: " "))
            if let continent = entity.primaryContinent {
                parts.append(continent)
            }
            if let zones = zoneText(entity.cq) {
                parts.append("CQ " + zones)
            }
            if let zones = zoneText(entity.itu) {
                parts.append("ITU " + zones)
            }
        } else if kind == "grid" {
            parts.append(row.key)
        } else {
            return nil
        }
        if let target = position(kind: kind, row: row, lookup: lookup), !myLat.isNaN, !myLon.isNaN {
            let bearing: Int = Int(GreatCircle.bearingDeg(myLat, myLon, target.lat, target.lon).rounded()) % 360
            let km: Int = Int(GreatCircle.distanceKm(myLat, myLon, target.lat, target.lon).rounded())
            parts.append("SP \(bearing)° LP \((bearing + 180) % 360)° · \(km) km")
        }
        return parts.joined(separator: " · ")
    }

    private static func zoneText(_ zones: [Int?]?) -> String? {
        let known: [Int] = (zones ?? []).compactMap { $0 }
        return known.isEmpty ? nil : known.map(String.init).joined(separator: ",")
    }

    /// N1MM „Show Countries" of a zone chart (`cq` / `itu`): the entities of the zone as `prefix name`, sorted by
    /// prefix; empty for other kinds.
    public static func countriesInZone(kind: String, zone: String, lookup: (any DxccLookup)?) -> [String] {
        guard kind == "cq" || kind == "itu", let number = Int(zone), let lookup else { return [] }
        let entities: [DxccEntity] = lookup.entities().filter { entity in
            let zones: [Int?]? = kind == "cq" ? entity.cq : entity.itu
            return (zones ?? []).contains(number)
        }
        return entities
            .map { [$0.primaryPrefix, $0.name].compactMap { $0 }.joined(separator: " ") }
            .sorted()
    }

    /// Whether „Set Rover QTH" applies to a kind: the districts (counties) and the grid fields.
    public static func roverKind(_ kind: String) -> Bool {
        kind == "districts" || kind == "grid"
    }

    /// N1MM „Show Calls Worked": the QSOs that counted the multiplier `key` of the binding, from a replay of the log
    /// into a fresh session (in log order).
    public static func workedQsos(_ fresh: ContestSession, _ qsos: [Qso], bindingId: String, key: String,
                                  now: () -> Date = Date.init) -> [Qso] {
        var out: [Qso] = []
        _ = ContestReplay.replay(fresh, qsos, now: now) { qso, result in
            if result.multipliers.contains(where: { ($0.bindingId ?? $0.setId) == bindingId && $0.key == key }) {
                out.append(qso)
            }
        }
        return out
    }
}
