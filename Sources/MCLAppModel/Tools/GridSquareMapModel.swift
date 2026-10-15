import Foundation
import MCLCore
import Observation

/// N1MM „Grid Square Map" (Window → Multipliers, VHF and up, `gridmap`): the 4-character squares around the own
/// square coloured worked (blue) / spotted not worked (red) / expected not worked (brown), a band filter, and the
/// right-click menu of a square — calls worked and spots, turn the antenna, rover QTH, centre the map there, the
/// beam heading to its centre, the expected list and the export of the worked squares.
///
/// Worked squares come from the received locators of the log (not deleted, not X-QSO), spotted ones from the grid of
/// each contest-relevant spot (the comment, the grid database, the callbook — `SpotAnalyzer.gridForSpot`). One
/// observer of the shared `SpotFeed` while the window is open.
@Observable @MainActor
public final class GridSquareMapModel {

    /// The window id (`config.openWindows`) and the key of its expected list in `config.multExpected`.
    public static let windowId = "gridmap"

    public private(set) var isOpen = false
    public private(set) var spots: [DxSpot] = []
    /// The square in the middle; `nil` = the own square.
    public private(set) var centerOverride: String?
    /// The band filter; `nil` = all bands.
    public var band: Band?
    /// The open „calls worked and spots" or „beam heading" list.
    public var details: MultGridDetails?
    /// Bumped when the expected list changes (it lives in the settings).
    public private(set) var settingsRevision: Int = 0

    @ObservationIgnored private let contest: ContestModel
    @ObservationIgnored private let analysis: SpotAnalysisModel
    @ObservationIgnored private let feed: SpotFeed
    @ObservationIgnored private let rig: RigModel
    @ObservationIgnored public let language: LanguageModel
    @ObservationIgnored private let config: ConfigModel
    @ObservationIgnored private let logbook: LogbookModel
    @ObservationIgnored private var observer: SpotFeed.ObserverID?
    @ObservationIgnored private var spotCache: (key: String, squares: [GridSquareMap.SpotSquare])?
    /// Sets the rover QTH like the entry window's ROVERQTH command (with its status line).
    @ObservationIgnored var setRoverQth: ((String) -> Void)?

    struct Dependencies {
        let contest: ContestModel
        let analysis: SpotAnalysisModel
        let feed: SpotFeed
        let rig: RigModel
        let language: LanguageModel
        let config: ConfigModel
        let logbook: LogbookModel
    }

    init(_ dependencies: Dependencies) {
        contest = dependencies.contest
        analysis = dependencies.analysis
        feed = dependencies.feed
        rig = dependencies.rig
        language = dependencies.language
        config = dependencies.config
        logbook = dependencies.logbook
    }

    public func open() {
        guard !isOpen else { return }
        isOpen = true
        spots = feed.snapshot()
        observer = feed.addObserver { [weak self] in
            guard let self, self.isOpen else { return }
            self.spots = self.feed.snapshot()
        }
    }

    public func close() {
        guard isOpen else { return }
        isOpen = false
        if let observer {
            feed.removeObserver(observer)
        }
        observer = nil
    }

    var isSubscribed: Bool {
        observer != nil
    }

    // MARK: - the map

    /// The own locator (Settings → Station).
    public var myGrid: String {
        config.config.station.gridSquare
    }

    /// The square in the middle of the map, `nil` without an own locator and without a picked centre.
    public var center: String? {
        centerOverride ?? GridSquareMap.square(myGrid)
    }

    /// „Doplň lokátor stanice (Nastavení → Stanice)." while there is no centre.
    public var noGridText: String {
        language.tr("Doplň lokátor stanice (Nastavení → Stanice).")
    }

    /// The squares shown for a matrix size (north up, west left).
    public func matrix(columns: Int, rows: Int) -> [[String?]] {
        guard let center else { return [] }
        return GridSquareMap.matrix(center: center, columns: columns, rows: rows)
    }

    /// The spots reduced to their square and band, cached per feed and analysis revision.
    public var spotSquares: [GridSquareMap.SpotSquare] {
        let key: String = [String(feed.revision), String(analysis.revision), String(spots.count)]
            .joined(separator: ":")
        if let spotCache, spotCache.key == key {
            return spotCache.squares
        }
        let analyzer: SpotAnalyzer = analysis.current()
        var out: [GridSquareMap.SpotSquare] = []
        for spot in spots where analyzer.isColorRelevant(spot) {
            guard let square = GridSquareMap.square(analyzer.gridForSpot(spot)) else { continue }
            out.append(GridSquareMap.SpotSquare(square: square, band: Band.from(frequencyHz: spot.freqHz),
                                                call: spot.dxCall, freqHz: spot.freqHz, comment: spot.comment))
        }
        spotCache = (key, out)
        return out
    }

    /// The state of every square that is not empty.
    public var cells: [String: GridSquareMap.Cell] {
        GridSquareMap.cells(qsos: logbook.rows, spots: spotSquares, band: band, expected: expected)
    }

    /// The band filter's choices: the bands of the log's located QSOs and of the spots.
    public var bandChoices: [Band] {
        GridSquareMap.bands(qsos: logbook.rows, spots: spotSquares)
    }

    /// „Pracované čtverce: N" (the band in brackets when filtered).
    public var headline: String {
        let worked: Int = GridSquareMap.workedCount(cells)
        let text: String = language.tr("Pracované čtverce: %s", .int(worked))
        guard let band else { return text }
        return text + " (" + band.adif + ")"
    }

    /// The tooltip of a square: the square, the bearing and distance, the number of QSOs in it.
    public func tooltip(_ square: String) -> String {
        var parts: [String] = [square]
        if let heading = GridSquareMap.heading(from: myGrid, to: square) {
            parts.append("\(heading.bearing)° \(heading.km) km")
        }
        let count: Int = GridSquareMap.qsos(in: square, logbook.rows).count
        if count > 0 {
            parts.append(language.tr("QSO: %s", .int(count)))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - right-click menu

    /// N1MM „Show Calls Worked and Spots Available": the QSOs in the square (all bands) and its spots.
    public func showCallsWorked(_ square: String) {
        var lines: [String] = GridSquareMap.qsos(in: square, logbook.rows).map { qso in
            [LogTableColumns.timeText(qso.timestampUtc), qso.band?.adif ?? "?", qso.mode?.rawValue ?? "?", qso.call]
                .joined(separator: "  ")
        }
        if lines.isEmpty {
            lines.append(language.tr("Zatím nepracováno"))
        }
        let spotted: [GridSquareMap.SpotSquare] = spotSquares.filter { $0.square == square }
        if !spotted.isEmpty {
            lines.append("")
            lines.append(language.tr("Spoty:"))
            for spot in spotted {
                lines.append(spot.call + "  " + String(format: "%.1f", Double(spot.freqHz) / 1000) + "  "
                             + spot.comment)
            }
        }
        details = MultGridDetails(title: language.tr("Čtverec %s", .string(square)), lines: lines)
    }

    /// „Natočit anténu" applies (an own locator to turn from).
    public func canTurnAntenna(_ square: String) -> Bool {
        GridSquareMap.azimuth(from: myGrid, to: square) != nil
    }

    /// N1MM „Turn Antenna": the rotator to the short-path heading of the square's centre.
    public func turnAntenna(_ square: String) {
        guard let azimuth = GridSquareMap.azimuth(from: myGrid, to: square) else { return }
        rig.rotator.turnTo(azimuth)
    }

    /// N1MM „Set Grid Square Map Center".
    public func setCenter(_ square: String) {
        centerOverride = GridSquareMap.square(square)
    }

    /// Back to the own square.
    public func resetCenter() {
        centerOverride = nil
    }

    /// N1MM „Show Beam Heading to Grid Center": the bearing and distance from the own locator.
    public func showHeading(_ square: String) {
        let line: String
        if let heading = GridSquareMap.heading(from: myGrid, to: square) {
            line = language.tr("Azimut %s°, vzdálenost %s km (od %s)", .int(heading.bearing), .int(heading.km),
                               .string(myGrid.uppercased()))
        } else {
            line = noGridText
        }
        details = MultGridDetails(title: language.tr("Čtverec %s", .string(square)), lines: [line])
    }

    /// „Nastavit rover QTH" applies: a contest with a rover QTH.
    public var canSetRover: Bool {
        contest.usesRoverQth && setRoverQth != nil
    }

    /// N1MM „Set Rover QTH": the square becomes the rover's QTH.
    public func setRover(_ square: String) {
        setRoverQth?(square)
    }

    // MARK: - expected list and export

    /// The expected squares.
    public var expected: Set<String> {
        _ = settingsRevision
        return Set(MultGridExtras.expected(expectedText).compactMap { GridSquareMap.square($0) })
    }

    /// The expected list as edited (the saved text).
    public var expectedText: String {
        _ = settingsRevision
        return config.config.multExpected[Self.windowId] ?? ""
    }

    /// N1MM „Edit Expected Multipliers List": only the squares of the text are kept.
    public func setExpectedText(_ text: String) {
        let squares: Set<String> = Set(MultGridExtras.expected(text).compactMap { GridSquareMap.square($0) })
        config.config.multExpected[Self.windowId] = squares.isEmpty ? nil : MultGridExtras.expectedText(squares)
        saveSettings()
    }

    /// N1MM „Clear Expected Multiplier List".
    public func clearExpected() {
        config.config.multExpected[Self.windowId] = nil
        saveSettings()
    }

    /// N1MM „Export Mults & Bands from this Contest".
    public var workedExport: String {
        GridSquareMap.export(qsos: logbook.rows)
    }

    private func saveSettings() {
        config.saveSilently()
        settingsRevision += 1
    }
}
