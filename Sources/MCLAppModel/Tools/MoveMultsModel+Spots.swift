import Foundation
import MCLCore

/// N1MM's Move Multipliers window over the spot table: the spotted stations by band with the new multipliers, the
/// QSO points or the QSO count, the options (type, count range, bands and modes, saved in the settings), Refresh,
/// hiding a row and the clicks that tune to a spot. Tuning changes only the frequency and the mode; nothing transmits.
extension MoveMultsModel {

    // MARK: - options

    public var display: SpotMoveMults.Display {
        _ = optionsRevision
        return SpotMoveMults.Display(rawValue: deps.config?.config.moveMultsDisplay ?? "") ?? .multipliers
    }

    public func setDisplay(_ display: SpotMoveMults.Display) {
        deps.config?.config.moveMultsDisplay = display.rawValue
        optionsChanged()
    }

    /// The count range as typed.
    public var rangeText: String {
        _ = optionsRevision
        return deps.config?.config.moveMultsRange ?? "0-6"
    }

    public func setRangeText(_ text: String) {
        deps.config?.config.moveMultsRange = text
        optionsChanged()
    }

    public var modes: SpotMoveMults.ModeFilter {
        _ = optionsRevision
        return SpotMoveMults.ModeFilter(rawValue: deps.config?.config.moveMultsModes ?? "") ?? .contest
    }

    public func setModes(_ modes: SpotMoveMults.ModeFilter) {
        deps.config?.config.moveMultsModes = modes.rawValue
        optionsChanged()
    }

    /// The band columns: the saved ones, otherwise the contest's bands, otherwise 160–10 m.
    public var bands: [Band] {
        _ = optionsRevision
        let saved: String = deps.config?.config.moveMultsBands ?? ""
        if !saved.isEmpty {
            return MultGridExtras.bands(saved)
        }
        let contestBands: [Band] = (deps.contest.definition?.bands ?? []).compactMap { $0.flatMap(Band.from(adif:)) }
        return contestBands.isEmpty ? SpotAnalyzer.multGridBands : Band.allCases.filter { contestBands.contains($0) }
    }

    public func setBand(_ band: Band, shown: Bool) {
        var picked: [Band] = bands
        if shown {
            picked.append(band)
        } else {
            picked.removeAll { $0 == band }
        }
        guard !picked.isEmpty else { return }
        deps.config?.config.moveMultsBands = Band.allCases.filter { picked.contains($0) }.map(\.adif)
            .joined(separator: ",")
        optionsChanged()
    }

    private func optionsChanged() {
        deps.config?.saveSilently()
        optionsRevision += 1
        refreshSpots()
    }

    // MARK: - rows

    public func setShowSpots(_ on: Bool) {
        showSpots = on
        if on {
            refreshSpots()
        }
    }

    /// N1MM Refresh: rebuilds the list from the spots and the log, the hidden rows come back.
    public func refreshSpots() {
        hidden = []
        nextSpot = [:]
        guard deps.contest.isActive, let analysis = deps.analysis, let feed = deps.feed else {
            spotRows = []
            return
        }
        spotRows = analysis.current().moveMultRows(spots: feed.snapshot(), bands: bands, modes: modes,
                                                   qsos: deps.logbook.rows)
    }

    /// The rows shown: the display's filter, without the hidden ones.
    public var visibleSpotRows: [SpotMoveMults.Row] {
        SpotMoveMults.filter(spotRows, display: display, range: SpotMoveMults.range(rangeText))
            .filter { !hidden.contains($0.id) }
    }

    public func cellText(_ row: SpotMoveMults.Row, band: Band) -> String {
        SpotMoveMults.text(row, band: band, display: display)
    }

    /// N1MM's middle click: hides the row until the next refresh.
    public func hide(_ row: SpotMoveMults.Row) {
        hidden.insert(row.id)
    }

    // MARK: - clicks

    /// A click on a spotted band cell: VFO A (or, `otherVfo`, VFO B — N1MM's Shift+click in SO2V) to the spot.
    @discardableResult
    public func tune(_ row: SpotMoveMults.Row, band: Band, otherVfo: Bool = false) -> DxSpot? {
        guard let spot = row.cells[band.adif]?.spot else { return nil }
        if otherVfo {
            deps.rig.setOtherVfo(Int64(spot.freqHz))
        } else {
            deps.rig.tuneToSpot(spot, withMode: true)
        }
        return spot
    }

    /// A click on the call: the first spotted band, each further click the next one.
    @discardableResult
    public func tuneNext(_ row: SpotMoveMults.Row, otherVfo: Bool = false) -> DxSpot? {
        let spotted: [Band] = row.spottedBands(bands)
        guard !spotted.isEmpty else { return nil }
        let index: Int = (nextSpot[row.id] ?? 0) % spotted.count
        nextSpot[row.id] = index + 1
        return tune(row, band: spotted[index], otherVfo: otherVfo)
    }
}
