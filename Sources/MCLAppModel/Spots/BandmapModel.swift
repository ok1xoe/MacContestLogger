import Foundation
import MCLCore
import Observation

/// The Bandmap window (`BandmapWindow.kt`, `BM:79-131, 154-360`): the visible window of the tuned band
/// (reset when the band changes, Kotlin `remember(band)`), the spot labels, their colours, the azimuths and skimmer
/// counts, the CQ marker, the band notes and the band plan, and what a click, the wheel, a drag and the context menu
/// do. The geometry is the core's (`BandmapViewport`, `BandmapLayout`); the view measures its fonts and passes the
/// axis position and the row height.
///
/// Tuning goes through the rig model only (`tuneToSpot`, `qsy`; CAT frequency and split) — nothing transmits.
@Observable @MainActor
public final class BandmapModel {

    /// The spot font (Kotlin `fontText`, 8…28, default 11; not saved).
    public private(set) var spotFont: Int = BandmapViewport.defaultSpotFont
    /// Rises when the window was zoomed, panned or reset (the view redraws).
    public private(set) var viewportRevision: Int = 0

    @ObservationIgnored private var storedViewport = BandmapViewport(band: nil)
    @ObservationIgnored private var storedBand: Band?
    @ObservationIgnored private let feed: SpotFeed
    @ObservationIgnored private let analysis: SpotAnalysisModel
    @ObservationIgnored private let contest: ContestModel
    @ObservationIgnored private let config: ConfigModel
    @ObservationIgnored private let operating: OperatingModel
    @ObservationIgnored private let blacklist: BlacklistModel
    @ObservationIgnored private let callbook: CallbookModel
    @ObservationIgnored private let rig: RigModel

    struct Dependencies {
        let feed: SpotFeed
        let analysis: SpotAnalysisModel
        let contest: ContestModel
        let config: ConfigModel
        let operating: OperatingModel
        let blacklist: BlacklistModel
        let callbook: CallbookModel
        let rig: RigModel
    }

    init(_ dependencies: Dependencies) {
        feed = dependencies.feed
        analysis = dependencies.analysis
        contest = dependencies.contest
        config = dependencies.config
        operating = dependencies.operating
        blacklist = dependencies.blacklist
        callbook = dependencies.callbook
        rig = dependencies.rig
        storedBand = rig.currentBand
        storedViewport = BandmapViewport(band: storedBand, tunedHz: rig.tuning.tunedFreqHz)
        observeBand()
    }

    /// Kotlin `remember(band)`: every change of the tuned band starts the window over on the whole band (also a
    /// change back to a band zoomed before).
    private func observeBand() {
        withObservationTracking {
            _ = rig.currentBand
        } onChange: { [weak self] in
            MainHop.post {
                guard let self else { return }
                let current: Band? = self.rig.currentBand
                if current != self.storedBand {
                    self.store(BandmapViewport(band: current, tunedHz: self.tunedHz), band: current)
                }
                self.observeBand()
            }
        }
    }

    /// The window opened: Kotlin's `remember` state starts over (the whole band, the spot font 11).
    public func windowOpened() {
        store(BandmapViewport(band: band, tunedHz: tunedHz), band: band)
        spotFont = BandmapViewport.defaultSpotFont
    }

    // MARK: - what is shown

    /// Kotlin `state.currentBand`; `nil` = „Bandmapa — nalaď pásmo".
    public var band: Band? {
        rig.currentBand
    }

    /// Kotlin `state.tunedFreqHz` (the VFO marker and the header).
    public var tunedHz: Int64 {
        rig.tuning.tunedFreqHz
    }

    /// The header `String.format(Locale.US, "%.2f kHz", tuned / 1000.0)`.
    public var tunedText: String {
        FrequencyText.formatHz(tunedHz) + " kHz"
    }

    /// The visible window: the stored one while the band is the same, otherwise the whole new band.
    public var viewport: BandmapViewport {
        _ = viewportRevision
        let current: Band? = band
        return storedBand == current ? storedViewport : BandmapViewport(band: current, tunedHz: tunedHz)
    }

    /// The spots of the buffer now (read when the feed's revision changes).
    public func spots() -> [DxSpot] {
        _ = feed.revision
        return feed.snapshot()
    }

    /// The spot labels in the window (`layoutSpots`).
    public func placements(spots: [DxSpot], height: Float, rowH: Float) -> [SpotPlacement] {
        BandmapLayout.place(spots: spots, viewport: viewport, height: height, rowH: rowH)
    }

    /// Kotlin `spotColorOf(spot)`: outside a contest always „good", otherwise by dupe and new multipliers.
    public func colorKey(_ spot: DxSpot, analyzer: SpotAnalyzer) -> SpotColorClassifier.SpotColorKey {
        guard contest.isActive else { return .good }
        let state: SpotStatus = analyzer.spotStatus(spot)
        return SpotColorClassifier.classify(dupe: state.dupe, newMultCount: state.newMultCount)
    }

    /// The analysis to colour a frame with (one per redraw).
    public func analyzer() -> SpotAnalyzer {
        _ = analysis.revision
        return analysis.current()
    }

    /// The label text: the call, the azimuth from my grid (`azimuthOf`) and the skimmer count.
    public func label(_ spot: DxSpot) -> String {
        let myLatLon = Maidenhead.centerLatLon(config.config.station.gridSquare)
        let azimuth: Int? = BandmapLayout.azimuthOf(call: spot.dxCall, myLatLon: myLatLon,
                                                    dxcc: contest.runtime.dxccLookup)
        return BandmapLayout.labelText(call: spot.dxCall, azimuth: azimuth,
                                       skimmers: feed.buffer.skimmerCount(spot.dxCall))
    }

    /// The label as drawn: `label` plus the QO-100 mark of a spot on that satellite's transponder (post-port).
    public func drawnLabel(_ spot: DxSpot) -> String {
        let base: String = label(spot)
        guard let mark = Qo100.label(freqHz: spot.freqHz) else { return base }
        return base + "  " + mark
    }

    /// Kotlin `state.cqFrequencyHz(band)` (the CQ marker).
    public var cqHz: Int64? {
        operating.cqFrequency(band: band)
    }

    /// Kotlin `BandNotes.forBand(config.bandNotes, band)`.
    public var notes: [BandNote] {
        guard let band else { return [] }
        return BandNotes.forBand(config.config.bandNotes, band: band)
    }

    /// Kotlin `dxCluster.isShowBandPlan` (read live, so Settings and the menu both apply at once).
    public var showPlan: Bool {
        config.config.dxCluster.showBandPlan
    }

    /// The band plan of the window when shown (`contest.bandPlanSegments(visLo, visHi)`, after `reloadBandData`).
    public func planSegments(analyzer: SpotAnalyzer) -> [BandPlan.Segment] {
        guard showPlan else { return [] }
        let window: BandmapViewport = viewport
        return analyzer.bandPlanSegments(lo: window.loHz, hi: window.hiHz)
    }

    // MARK: - the spot font

    /// The font field's value, clamped to 8…28 (`setFont`).
    public func setSpotFont(_ size: Int) {
        spotFont = Swift.min(Swift.max(size, BandmapViewport.spotFontRange.lowerBound),
                             BandmapViewport.spotFontRange.upperBound)
    }

    // MARK: - pointer

    /// A click (`detectTapGestures`, `BM:284-306`): the CQ marker → back to the CQ frequency (Run); a spot right of
    /// the axis → `tuneToSpot`; otherwise `qsy` to the frequency under the cursor.
    public func click(x: Float, y: Float, height: Float, axisX: Float, rowH: Float) {
        guard let band else { return }
        let tap: BandmapTap = BandmapLayout.tap(x: x, y: y, viewport: viewport, height: height, axisX: axisX,
                                                rowH: rowH, spots: feed.snapshot(), cqHz: cqHz)
        switch tap {
        case .cqFrequency:
            // Kotlin `jumpToCqFrequency(band)`: `qsy(cq)` and Run.
            if let cq = operating.jumpToCqFrequency(band: band) {
                rig.qsy(cq)
            }
        case .spot(let spot):
            rig.tuneToSpot(spot)
        case .qsy(let hz):
            rig.qsy(hz)
        }
    }

    /// The wheel (`BM:236-257`, Compose's sign: `dy < 0` = up): Ctrl zooms, otherwise `qsy` by the step (Shift = the
    /// big one) within the band; the window follows the marker.
    public func wheel(dx: Float, dy: Float, ctrl: Bool, shift: Bool) {
        guard let band else { return }
        var window: BandmapViewport = viewport
        let target: Int64? = window.wheel(
            dx: dx, dy: dy, ctrl: ctrl, shift: shift, tunedHz: tunedHz, bounds: BandmapViewport.bounds(band),
            stepHz: Int64(config.config.dxCluster.wheelStepHz),
            stepShiftHz: Int64(config.config.dxCluster.wheelStepShiftHz))
        store(window, band: band)
        if let target {
            rig.qsy(target)
        }
    }

    /// A drag (`BM:258-283`): longer than 6 px shows the frequencies under its ends.
    public func drag(from startY: Float, to endY: Float, height: Float) {
        guard let band else { return }
        var window: BandmapViewport = viewport
        if window.dragZoom(from: startY, to: endY, height: height, bounds: BandmapViewport.bounds(band)) {
            store(window, band: band)
        }
    }

    /// „Přiblížit" (half the span, centred on the tuned frequency).
    public func zoomIn() {
        guard let band else { return }
        var window: BandmapViewport = viewport
        window.zoomIn(tunedHz: tunedHz, bounds: BandmapViewport.bounds(band))
        store(window, band: band)
    }

    /// „Oddálit" (twice the span).
    public func zoomOut() {
        guard let band else { return }
        var window: BandmapViewport = viewport
        window.zoomOut(tunedHz: tunedHz, bounds: BandmapViewport.bounds(band))
        store(window, band: band)
    }

    /// „Reset zobrazení": the whole band (a microwave band: the default window around the tuned frequency).
    public func resetView() {
        guard let band else { return }
        store(BandmapViewport(band: band, tunedHz: tunedHz), band: band)
    }

    private func store(_ window: BandmapViewport, band: Band?) {
        storedViewport = window
        storedBand = band
        viewportRevision += 1
    }

    // MARK: - context menu

    /// The spot under a right click (right of the axis); `nil` = the menu without the spot items.
    public func menuSpot(x: Float, y: Float, height: Float, axisX: Float, rowH: Float) -> DxSpot? {
        guard band != nil else { return nil }
        return BandmapLayout.menuSpot(x: x, y: y, viewport: viewport, height: height, axisX: axisX, rowH: rowH,
                                      spots: feed.snapshot())
    }

    /// `tr("Blacklist volačky %s")`.
    public func blacklistCall(_ spot: DxSpot) {
        blacklist.blacklistCall(spot.dxCall)
    }

    /// „Blacklist spottera …".
    public func blacklistSpotter(_ spot: DxSpot) {
        blacklist.blacklistSpotter(spot.spotter)
    }

    /// „Odebrat spot" (every spot of the call).
    public func remove(_ spot: DxSpot) {
        feed.buffer.remove(spot.dxCall)
    }

    /// „QRZ.com".
    public func openQrz(_ spot: DxSpot) {
        callbook.openQrz(spot.dxCall)
    }

    /// „HamQTH".
    public func openHamQth(_ spot: DxSpot) {
        callbook.openHamQth(spot.dxCall)
    }

    /// „Dohledat na HamQTH" / „Dohledat na QRZ.com": opens the spot call's page on the service in the browser.
    public func lookup(_ spot: DxSpot, on service: CallbookService) {
        callbook.openPage(spot.dxCall, on: service)
    }

    /// The menu items need a call (no credentials: it is a web page).
    public func canLookup(_ spot: DxSpot) -> Bool {
        !CallbookPolicy.key(spot.dxCall).isEmpty
    }

    /// `tr("Smazat všechny spoty")`.
    public func clearSpots() {
        feed.buffer.clear()
    }

    /// „Zobrazit/Skrýt bandplán": the option is written into the configuration and saved — the file only, without
    /// the side effects of Kotlin's `saveConfig()`; a failure is swallowed (`runCatching`).
    public func toggleBandPlan() {
        config.config.dxCluster.showBandPlan = !showPlan
        config.saveSilently()
    }
}
