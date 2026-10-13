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
    @ObservationIgnored private let status: StatusModel
    @ObservationIgnored private let language: LanguageModel
    @ObservationIgnored private let dialogs: DialogsModel
    @ObservationIgnored private let now: @Sendable () -> Date
    /// The spot actions of the entry windows (Remove spot of a call); wired by `AppModel`.
    @ObservationIgnored weak var spotNavigation: SpotNavigation?
    /// The entry window the spot keys act for (the active one); wired by `AppModel`.
    @ObservationIgnored var keyEntry: (@MainActor () -> EntryModel?)?
    /// Where the mouse last was over the map, in the canvas' coordinates; `nil` = outside.
    @ObservationIgnored private var pointer: Pointer?

    private struct Pointer {
        let x: Float
        let y: Float
        let height: Float
        let axisX: Float
        let rowH: Float
    }

    struct Dependencies {
        let feed: SpotFeed
        let analysis: SpotAnalysisModel
        let contest: ContestModel
        let config: ConfigModel
        let operating: OperatingModel
        let blacklist: BlacklistModel
        let callbook: CallbookModel
        let rig: RigModel
        let status: StatusModel
        let language: LanguageModel
        let dialogs: DialogsModel
        let now: @Sendable () -> Date
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
        status = dependencies.status
        language = dependencies.language
        dialogs = dependencies.dialogs
        now = dependencies.now
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

    /// The visible window: the stored one while the band is the same, otherwise the whole new band; drawn with the
    /// lowest frequency at the bottom when that option is on.
    public var viewport: BandmapViewport {
        _ = viewportRevision
        let current: Band? = band
        var window: BandmapViewport = storedBand == current
            ? storedViewport : BandmapViewport(band: current, tunedHz: tunedHz)
        window.lowestAtBottom = lowestAtBottom
        return window
    }

    // MARK: - the radio

    /// The header's radio (N1MM: the radio's name and VFO): „Rig 1"/„Rig 2" in SO2R, otherwise the active VFO
    /// („VFO A"/„VFO B"), then — while CAT is connected — the rig model of Settings without its hamlib number
    /// („1 — Hamlib Dummy" → „Hamlib Dummy").
    public func radioName(_ language: LanguageModel) -> String {
        let vfo: VfoState = rig.vfo
        let name: String
        if vfo.so2r {
            name = language.tr("Rig %s", .int(vfo.activeVfo + 1))
        } else {
            name = vfo.activeVfo == 0 ? "VFO A" : "VFO B"
        }
        guard rig.catConnected else { return name }
        return name + Self.modelSuffix(rig.rigConfig(vfo: vfo.activeVfo).modelLabel)
    }

    /// `" · <model>"` of a Settings model label (`"<hamlib id> — <name>"`), empty for a blank label.
    static func modelSuffix(_ label: String) -> String {
        var model: String = KotlinStrings.trim(label)
        if let dash = model.range(of: " — ") {
            model = KotlinStrings.trim(String(model[dash.upperBound...]))
        }
        return model.isEmpty ? "" : " · " + model
    }

    /// The transmit frequency while the active rig reports split (N1MM's red TX arrow); `nil` without split or
    /// with an unknown transmit frequency.
    public var splitTxHz: Int64? {
        guard let state = rig.activeState, state.split, state.txFreqHz > 0 else { return nil }
        return state.txFreqHz
    }

    /// The header's transmit frequency „TX 14027.00 kHz" while split, otherwise `nil`.
    public var txText: String? {
        splitTxHz.map { "TX " + FrequencyText.formatHz($0) + " kHz" }
    }

    /// The receiver's filter around the RX frequency from the rig's passband (N1MM draws it at the arrow);
    /// `nil` without CAT or with an unknown passband.
    public var passbandRange: ClosedRange<Int64>? {
        guard let state = rig.activeState else { return nil }
        return BandmapViewport.passband(rxHz: tunedHz, passbandHz: state.passband, rawMode: state.rawMode)
    }

    /// The arrow under the pointer (left of the axis): `true` = the TX arrow, `false` = the RX arrow, `nil` = none;
    /// when both are in reach the nearer one.
    func arrowAt(x: Float, y: Float, height: Float, axisX: Float) -> Bool? {
        guard band != nil else { return nil }
        let window: BandmapViewport = viewport
        let rx: Bool = window.hitsMarker(tunedHz, x: x, y: y, axisX: axisX, height: height)
        guard let tx = splitTxHz, window.hitsMarker(tx, x: x, y: y, axisX: axisX, height: height) else {
            return rx ? false : nil
        }
        guard rx else { return true }
        let toTx: Float = abs(window.yAt(tx, height: height) - y)
        let toRx: Float = abs(window.yAt(tunedHz, height: height) - y)
        return toTx < toRx
    }

    /// The tooltip of the arrow under the pointer (left of the axis): the exact RX or TX frequency.
    public func markerTooltip(x: Float, y: Float, height: Float, axisX: Float) -> String? {
        switch arrowAt(x: x, y: y, height: height, axisX: axisX) {
        case true?:
            return splitTxHz.map { "TX " + FrequencyText.formatHz($0) + " kHz" }
        case false?:
            return "RX " + FrequencyText.formatHz(tunedHz) + " kHz"
        case nil:
            return nil
        }
    }

    // MARK: - options

    /// N1MM „Show Lowest Freq at Bottom" (saved in the configuration).
    public var lowestAtBottom: Bool {
        config.config.dxCluster.bandmapLowestAtBottom
    }

    /// N1MM „Disable Mouse Wheel" (saved in the configuration).
    public var wheelDisabled: Bool {
        config.config.dxCluster.bandmapWheelDisabled
    }

    /// The context menu's „Nejnižší kmitočet dole": saved like the band plan option (the file only).
    public func toggleLowestAtBottom() {
        config.config.dxCluster.bandmapLowestAtBottom = !lowestAtBottom
        config.saveSilently()
        viewportRevision += 1
    }

    /// The context menu's „Vypnout kolečko myši".
    public func toggleWheelDisabled() {
        config.config.dxCluster.bandmapWheelDisabled = !wheelDisabled
        config.saveSilently()
    }

    /// N1MM „Go to Bottom Of Band": QSY to the lower edge of the band plan segment (CW, phone, digi) of the tuned
    /// frequency, else of the band.
    public func goToBottomOfBand() {
        guard let range = subBand() else { return }
        rig.qsy(range.lowerBound)
    }

    /// N1MM „Go to Top of Band": QSY to the upper edge of the segment, else of the band.
    public func goToTopOfBand() {
        guard let range = subBand() else { return }
        rig.qsy(range.upperBound)
    }

    private func subBand() -> ClosedRange<Int64>? {
        guard let band else { return nil }
        let bounds: ClosedRange<Int64> = BandmapViewport.bounds(band)
        let segments: [BandPlan.Segment] = analyzer().bandPlanSegments(lo: bounds.lowerBound, hi: bounds.upperBound)
        return BandmapViewport.subBand(tunedHz: tunedHz, segments: segments, bounds: bounds)
    }

    /// The spots of the buffer now (read when the feed's revision changes).
    public func spots() -> [DxSpot] {
        _ = feed.revision
        return feed.filteredSnapshot()
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

    /// The label as drawn (N1MM marks beyond `label`): the skimmer mark (`#`, `!` for one's own skimmer) and the
    /// gray-line `¤` after the call, the azimuth and skimmer count, `QSX 027` of a split comment, `NEW` for a spot
    /// younger than three minutes, and the QO-100 mark of a spot on that satellite's transponder (post-port).
    public func drawnLabel(_ spot: DxSpot) -> String {
        let spotted: SpotBuffer.Spotted? = feed.buffer.find(spot.dxCall)
        let base: String = BandmapSpotInfo.label(
            call: spot.dxCall, azimuth: azimuth(spot), skimmers: feed.buffer.skimmerCount(spot.dxCall),
            skimmerMark: BandmapSpotInfo.skimmerMark(spot, myCall: config.config.station.call),
            grayLine: onGrayLine(spot), qsxHz: BandmapSpotInfo.qsxHz(spot),
            isNew: BandmapSpotInfo.isNew(spottedAt: spotted?.spottedAt, now: now()))
        guard let mark = Qo100.label(freqHz: spot.freqHz) else { return base }
        return base + "  " + mark
    }

    /// N1MM's spot tooltip (the exact frequency, the spotter, the age, the comment, QSX, the counts, the azimuth, the
    /// gray line, a self-spot).
    public func tooltip(_ spot: DxSpot) -> String {
        let facts = BandmapSpotInfo.TooltipFacts(
            spottedAt: feed.buffer.find(spot.dxCall)?.spottedAt, now: now(),
            count: feed.buffer.spotCounts()[spot.dxCall.uppercased()] ?? 1,
            skimmers: feed.buffer.skimmerCount(spot.dxCall), azimuth: azimuth(spot), grayLine: onGrayLine(spot),
            qsxHz: BandmapSpotInfo.qsxHz(spot))
        var text: String = BandmapSpotInfo.tooltip(spot, facts: facts, translator: language.translator)
        if let satellite = Qo100.label(freqHz: spot.freqHz) {
            text += "\n" + satellite
        }
        return text
    }

    private func azimuth(_ spot: DxSpot) -> Int? {
        let myLatLon = Maidenhead.centerLatLon(config.config.station.gridSquare)
        return BandmapLayout.azimuthOf(call: spot.dxCall, myLatLon: myLatLon, dxcc: contest.runtime.dxccLookup)
    }

    /// The spotted station's entity is at its sunrise or sunset now (N1MM `¤`).
    private func onGrayLine(_ spot: DxSpot) -> Bool {
        guard let entity = contest.runtime.dxccLookup?.resolve(spot.dxCall), entity.hasLatLon else { return false }
        return BandmapSpotInfo.onGrayLine(lat: entity.lat, lon: entity.lon, now: now())
    }

    /// The tuning tolerance of the active entry window's mode (N1MM, drawn at the tuned frequency); `nil` with the
    /// call-frame off.
    public var tuningToleranceHz: Int? {
        let dx: DxClusterConfig = config.config.dxCluster
        guard dx.callFrame else { return nil }
        let mode: Mode = keyEntry?()?.form.mode ?? rig.activeState?.mode ?? .cw
        return dx.tuningToleranceHz(mode)
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
    /// the axis → `tuneToSpot`; otherwise `qsy` to the frequency under the cursor (also a click on the scale).
    ///
    /// N1MM: with the call-frame on, a single click on a spot only tunes (the call shows in the call-frame) and a
    /// double click also fills the call field; with it off every click fills the field (v1.1.1).
    public func click(x: Float, y: Float, height: Float, axisX: Float, rowH: Float) {
        tap(x: x, y: y, height: height, axisX: axisX, rowH: rowH, fillCall: !config.config.dxCluster.callFrame)
    }

    /// A double click: as a click, and a spot's call goes into the call field (replacing what was there).
    public func doubleClick(x: Float, y: Float, height: Float, axisX: Float, rowH: Float) {
        tap(x: x, y: y, height: height, axisX: axisX, rowH: rowH, fillCall: true)
    }

    private func tap(x: Float, y: Float, height: Float, axisX: Float, rowH: Float, fillCall: Bool) {
        guard let band else { return }
        // The red TX arrow: a click turns split off (the RX arrow and the CQ marker keep their meaning).
        if arrowAt(x: x, y: y, height: height, axisX: axisX) == true {
            rig.splitOff()
            return
        }
        let tap: BandmapTap = BandmapLayout.tap(x: x, y: y, viewport: viewport, height: height, axisX: axisX,
                                                rowH: rowH, spots: feed.filteredSnapshot(), cqHz: cqHz)
        switch tap {
        case .cqFrequency:
            // Kotlin `jumpToCqFrequency(band)`: `qsy(cq)` and Run.
            if let cq = operating.jumpToCqFrequency(band: band) {
                rig.qsy(cq)
            }
        case .spot(let spot):
            rig.tuneToSpot(spot, fillCall: fillCall)
        case .qsy(let hz):
            rig.qsy(hz)
        }
    }

    /// The wheel (`BM:236-257`, Compose's sign: `dy < 0` = up): Ctrl zooms, otherwise `qsy` by the step (Shift = the
    /// big one) within the band; the window follows the marker.
    public func wheel(dx: Float, dy: Float, ctrl: Bool, shift: Bool) {
        guard let band, !wheelDisabled else { return }
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

    // MARK: - keys

    /// The mouse moved over the map (the canvas' coordinates); the spot under it is the target of Alt+D.
    public func pointerMoved(x: Float, y: Float, height: Float, axisX: Float, rowH: Float) {
        pointer = Pointer(x: x, y: y, height: height, axisX: axisX, rowH: rowH)
    }

    /// The mouse left the map.
    public func pointerLeft() {
        pointer = nil
    }

    /// The spot label under the mouse (right of the axis), if any.
    public var hoveredSpot: DxSpot? {
        guard let pointer else { return nil }
        return menuSpot(x: pointer.x, y: pointer.y, height: pointer.height, axisX: pointer.axisX, rowH: pointer.rowH)
    }

    /// The zoom keys (keypad `+`/`-`, Cmd+= / Cmd+-, `BandmapZoomKey`) and the spot shortcuts while the Bandmap
    /// window is the key window: Mark (Alt+M), Remove spot (Alt+D) and Remove
    /// spot + blacklist (Alt+Shift+D) by the user's key bindings, the key translated like the entry's. Mark acts as
    /// the entry's (the active entry window's frequency); Remove takes the spot under the mouse, otherwise it acts as
    /// the entry's (the call field, or the spot nearest to the tuned frequency). `true` = consumed (press and
    /// release of a bound spot key); every other key is left to AppKit.
    public func handleKey(_ event: MacKeyEvent) -> Bool {
        if let zoom = BandmapZoomKey.decode(event) {
            if event.kind == .keyDown {
                if zoom > 0 {
                    zoomIn()
                } else {
                    zoomOut()
                }
            }
            return true
        }
        guard event.kind != .flagsChanged, let stroke = AwtKeyCodes.translateForLayout(event) else { return false }
        let combo = KeyCombo(ctrl: stroke.isControlDown, alt: stroke.isAltDown, shift: stroke.isShiftDown,
                             meta: stroke.isMetaDown, keyCode: stroke.vk)
        guard let action = KeyBindings(config.config.keyBindings).resolve(combo),
              action == .mark || action == .removeSpot || action == .removeSpotBlacklist else { return false }
        guard (stroke.phase == .pressed) != action.onKeyUp, !event.isARepeat else { return true }
        guard let entry = keyEntry?(), entry.acceptsInput else { return true }
        if action != .mark, let spot = hoveredSpot, let spots = spotNavigation {
            spots.removeSpotOf(call: spot.dxCall, blacklist: action == .removeSpotBlacklist)
        } else {
            entry.runShortcut(action)
        }
        return true
    }

    // MARK: - context menu

    /// The spot under a right click (right of the axis); `nil` = the menu without the spot items.
    public func menuSpot(x: Float, y: Float, height: Float, axisX: Float, rowH: Float) -> DxSpot? {
        guard band != nil else { return nil }
        return BandmapLayout.menuSpot(x: x, y: y, viewport: viewport, height: height, axisX: axisX, rowH: rowH,
                                      spots: feed.filteredSnapshot())
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

    /// `tr("Smazat všechny spoty")` (N1MM "Remove Spots, ALL BANDS").
    public func clearSpots() {
        feed.buffer.clear()
    }

    /// N1MM "Remove Spots, This Band Only[, Leave Self Spots]" and "Remove Spots, ALL Bands, Leave Self Spots": the
    /// spots of the band map's band (`thisBand`) or of every band; `keepSelf` leaves the self spots (Mark, Store, the
    /// spots of calls tuned away from). Without a tuned band "this band" removes nothing.
    public func removeSpots(thisBand: Bool, keepSelf: Bool) {
        let band: Band? = self.band
        if thisBand && band == nil { return }
        feed.buffer.removeAll { spot in
            if keepSelf && spot.selfSpotted { return false }
            return !thisBand || spot.band == band
        }
    }

    // MARK: - band plan and licence lines

    /// The US licence class edges in the window when the option is on (N1MM's red lines on the scale).
    public var licenseLines: [Int64] {
        guard showLicenseLines else { return [] }
        let window: BandmapViewport = viewport
        return UsLicenseLines.edges(lo: window.loHz, hi: window.hiHz)
    }

    /// `dxCluster.showUsLicenseLines` (read live, so Settings and the menu both apply at once).
    public var showLicenseLines: Bool {
        config.config.dxCluster.showUsLicenseLines
    }

    /// „Zobrazit/Skrýt čáry licenčních tříd USA": written into the configuration and saved like the band plan option.
    public func toggleLicenseLines() {
        config.config.dxCluster.showUsLicenseLines = !showLicenseLines
        config.saveSilently()
    }

    /// The band plan edited at `freqHz` from the context menu (N1MM: a right click on the frequency sets a CW,
    /// digital or phone sub-band edge there or removes the sub-band): the station region's rows of
    /// `bandplan.yaml` change (`BandPlanEdit`), the file is written and the band data reloaded as after Settings →
    /// Band plan, so the band map redraws with the new plan. A refused edit or a failed write says why in the status
    /// line. Returns whether the plan changed.
    @discardableResult
    public func editBandPlan(_ action: BandPlanEdit.Action, atHz freqHz: Int64) async -> Bool {
        guard let root = contest.bandDataRoot else { return false }
        let region: String = analyzer().stationRegion.rawValue
        let band: Band? = Band.from(frequencyHz: Int(clamping: freqHz))
        let khz: Double = (Double(freqHz) / 100.0).rounded() / 10.0
        let outcome: BandPlanEdit.Outcome? = try? await BlockingQueue.run {
            let rows: [BandPlanFile.Segment] = BandPlanEdit.seeded(BandPlanFile.read(root), region: region)
            let outcome: BandPlanEdit.Outcome = BandPlanEdit.apply(action, atKhz: khz, band: band, region: region,
                                                                   segments: rows)
            if case .edited(let edited) = outcome {
                try BandPlanFile.write(root, edited)
            }
            return outcome
        }
        switch outcome {
        case .edited?:
            await contest.reloadBandData()
            status.show(ContestMessage("Bandplán upraven na %s kHz", .string(FrequencyText.formatHz(freqHz))))
            return true
        case .refused(let refusal)?:
            switch refusal {
            case .outsideBand: status.show(ContestMessage("Bandplán: kmitočet není v pásmu"))
            case .noSegment: status.show(ContestMessage("Bandplán: na tomto pásmu takový úsek není"))
            case .empty: status.show(ContestMessage("Bandplán: úsek by byl prázdný"))
            }
            return false
        case nil:
            status.show(ContestMessage("Bandplán se nepodařilo uložit"))
            return false
        }
    }

    /// N1MM „Find a Callsign": a prompt for the call (or a part of it); the next spot above the tuned frequency that
    /// matches is tuned to like a click (Alt+F8 returns).
    public func promptFind() {
        dialogs.prompt(title: ContestMessage("Najít volačku v bandmapě"),
                       hint: ContestMessage("Volačka nebo její část; hledá se od naladěné frekvence nahoru"),
                       initial: "") { [weak self] text in
            self?.find(text)
        }
    }

    /// Tunes to the next spot whose call contains `query` (see `BandmapSpotInfo.find`).
    public func find(_ query: String) {
        guard !KotlinStrings.isBlank(query) else { return }
        guard let spot = BandmapSpotInfo.find(query, in: feed.filteredSnapshot(), fromHz: tunedHz) else {
            status.show(ContestMessage("%s v bandmapě není", .string(KotlinStrings.trim(query).uppercased())))
            return
        }
        rig.tuneToSpot(spot, fillCall: !config.config.dxCluster.callFrame)
    }

    /// „Zobrazit/Skrýt bandplán": the option is written into the configuration and saved — the file only, without
    /// the side effects of Kotlin's `saveConfig()`; a failure is swallowed (`runCatching`).
    public func toggleBandPlan() {
        config.config.dxCluster.showBandPlan = !showPlan
        config.saveSilently()
    }
}
