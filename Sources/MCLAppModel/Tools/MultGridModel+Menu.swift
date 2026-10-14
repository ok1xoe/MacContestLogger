import Foundation
import MCLCore

/// A list the Multipliers window shows in a sheet (N1MM „Show Calls Worked and Spots Available", „Show Countries").
public struct MultGridDetails: Equatable, Identifiable, Sendable {
    public let title: String
    public let lines: [String]

    public var id: String { title }
}

/// N1MM Multipliers window: the bands displayed, the expected multiplier list, „show all possible", the mouse-over of a
/// prefix and the right-click menu.
extension MultGridModel {

    // MARK: - settings

    /// The band columns (`multGridBands` of the kind; 160–10 m by default).
    public var bands: [Band] {
        _ = settingsRevision
        return MultGridExtras.bands(config?.config.multGridBands[kind])
    }

    public var bandHeaders: [String] {
        bands.map(MultGridExtras.header)
    }

    public func setBand(_ band: Band, shown: Bool) {
        var picked: [Band] = bands
        if shown {
            picked.append(band)
        } else {
            picked.removeAll { $0 == band }
        }
        guard !picked.isEmpty, let config else { return }
        config.config.multGridBands[kind] = MultGridExtras.savedBands(picked)
        saveSettings()
    }

    /// The expected multipliers of the kind.
    public var expected: Set<String> {
        _ = settingsRevision
        return MultGridExtras.expected(config?.config.multExpected[kind] ?? "")
    }

    /// The expected list as edited (the saved text).
    public var expectedText: String {
        _ = settingsRevision
        return config?.config.multExpected[kind] ?? ""
    }

    public func setExpectedText(_ text: String) {
        guard let config else { return }
        let keys: Set<String> = MultGridExtras.expected(text)
        config.config.multExpected[kind] = keys.isEmpty ? nil : MultGridExtras.expectedText(keys)
        saveSettings()
    }

    /// N1MM „Export Mults & Bands from this Contest".
    public var workedExport: String {
        MultGridExtras.workedExport(grid.rows, bands: bands)
    }

    /// Every possible multiplier instead of only the worked, spotted and expected ones.
    public var showAll: Bool {
        _ = settingsRevision
        return config?.config.multGridShowAll.contains(kind) ?? false
    }

    public func setShowAll(_ on: Bool) {
        guard let config else { return }
        config.config.multGridShowAll.removeAll { $0 == kind }
        if on {
            config.config.multGridShowAll.append(kind)
        }
        saveSettings()
    }

    private func saveSettings() {
        config?.saveSilently()
        settingsRevision += 1
    }

    // MARK: - prefix information

    private var myPosition: (lat: Double, lon: Double) {
        guard let station = config?.config.station else { return (.nan, .nan) }
        return InfoLines.position(latitude: station.latitude, longitude: station.longitude)
    }

    /// Whether a row is on the expected list (drawn emphasized).
    public func isExpected(_ row: MultGridRow) -> Bool {
        MultGridExtras.isExpected(row, expected)
    }

    /// N1MM's mouse-over of a prefix: country, continent, zones, bearings and distance.
    public func prefixInfo(_ row: MultGridRow) -> String? {
        let position = myPosition
        return MultGridExtras.prefixInfo(kind: kind, row: row, lookup: contest.runtime.dxccLookup,
                                         myLat: position.lat, myLon: position.lon)
    }

    // MARK: - right-click menu

    /// „Natočit anténu" applies (a position to turn to and my own).
    public func canTurnAntenna(_ row: MultGridRow) -> Bool {
        azimuth(row) != nil
    }

    private func azimuth(_ row: MultGridRow) -> Double? {
        let position = myPosition
        return MultGridExtras.azimuth(kind: kind, row: row, lookup: contest.runtime.dxccLookup,
                                      myLat: position.lat, myLon: position.lon)
    }

    /// N1MM „Turn Antenna": the rotator to the multiplier's short-path heading.
    public func turnAntenna(_ row: MultGridRow) {
        guard let azimuth = azimuth(row) else { return }
        rig.rotator.turnTo(azimuth)
    }

    /// „Země v zóně" applies (a zone chart).
    public var isZoneKind: Bool {
        kind == "cq" || kind == "itu"
    }

    /// N1MM „Show Countries" of a zone.
    public func showCountries(_ row: MultGridRow) {
        let lines: [String] = MultGridExtras.countriesInZone(kind: kind, zone: row.key,
                                                             lookup: contest.runtime.dxccLookup)
        details = MultGridDetails(title: language.tr("Země v zóně %s", .string(row.key)),
                                  lines: lines.isEmpty ? [language.tr("Žádné země")] : lines)
    }

    /// „Nastavit rover QTH" applies: a contest with a rover QTH and a county or grid chart.
    public var canSetRover: Bool {
        MultGridExtras.roverKind(kind) && contest.usesRoverQth && setRoverQth != nil
    }

    /// N1MM „Set Rover QTH": the rover's county or grid square.
    public func setRover(_ row: MultGridRow) {
        setRoverQth?(MultGridLayout.label(row))
    }

    /// N1MM „Show Calls Worked and Spots Available": the QSOs that counted the multiplier (all bands) and its spots.
    public func showCallsWorked(_ row: MultGridRow) {
        let analyzer: SpotAnalyzer = analysis.current()
        var lines: [String] = []
        if let bindingId = analyzer.gridBindingId(kind: kind), let fresh = contest.runtime.freshSession(),
           let qsos = logbook?.rows {
            for qso in MultGridExtras.workedQsos(fresh, qsos, bindingId: bindingId, key: row.key) {
                lines.append([LogTableColumns.timeText(qso.timestampUtc), qso.band?.adif ?? "?",
                              qso.mode?.rawValue ?? "?", qso.call].joined(separator: "  "))
            }
        }
        if lines.isEmpty {
            lines.append(language.tr("Zatím nepracováno"))
        }
        let spotted: [DxSpot] = analyzer.gridSpots(kind: kind, key: row.key, spots: spots)
        if !spotted.isEmpty {
            lines.append("")
            lines.append(language.tr("Spoty:"))
            for spot in spotted {
                lines.append(spot.dxCall + "  " + String(format: "%.1f", Double(spot.freqHz) / 1000)
                             + "  " + spot.comment)
            }
        }
        details = MultGridDetails(title: language.tr("Násobič %s", .string(MultGridLayout.label(row))),
                                  lines: lines)
    }
}

extension MultGridModel {
    /// The language of the window's menus.
    public var languageModel: LanguageModel {
        language
    }
}
