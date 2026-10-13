import AppKit
import MCLAppModel
import MCLCore
import SwiftUI

/// What the band map draws, read from the model while the SwiftUI body runs, so that every change of the spots, the
/// analysis, the tuned frequency, the window or the font redraws it (`updateNSView`).
struct BandmapDrawState {
    let band: Band
    let tunedHz: Int64
    let spots: [DxSpot]
    let analyzer: SpotAnalyzer
    let cqHz: Int64?
    let notes: [BandNote]
    let showPlan: Bool
    let licenseLines: [Int64]
    let spotFont: Int
    let viewport: BandmapViewport
    let toleranceHz: Int?
    let txHz: Int64?
    let passband: ClosedRange<Int64>?

    /// `nil` without a tuned band (the window shows its hint instead).
    @MainActor
    init?(_ model: BandmapModel) {
        guard let band = model.band else { return nil }
        self.band = band
        tunedHz = model.tunedHz
        spots = model.spots()
        analyzer = model.analyzer()
        cqHz = model.cqHz
        notes = model.notes
        showPlan = model.showPlan
        licenseLines = model.licenseLines
        spotFont = model.spotFont
        viewport = model.viewport
        toleranceHz = model.tuningToleranceHz
        txHz = model.splitTxHz
        passband = model.passbandRange
    }
}

/// The band map (an AppKit island, Kotlin `Canvas` of `BandmapWindow.kt:213-360, 440-620`): a
/// flipped `NSView` that draws the band plan strip, the axis with its ticks, the spread spot labels with their leader
/// lines, the band notes, the CQ line, the receiver's filter and the RX/TX arrows, and takes the pointer — a click, a drag that zooms, the
/// wheel and the context menu. Every coordinate and every decision is the models' (`BandmapModel`, the core's
/// `BandmapViewport`/`BandmapLayout`); the view only measures its fonts and passes the positions on.
///
/// Units are points. Kotlin's constants (24 px padding, 90 px leader) are pixels of the Compose canvas; the points
/// give the same proportions at the default font on a 1× display.
struct BandmapView: NSViewRepresentable {
    let model: BandmapModel
    let language: LanguageModel
    let state: BandmapDrawState

    func makeNSView(context: Context) -> BandmapCanvas {
        let view = BandmapCanvas()
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.group)
        return view
    }

    func updateNSView(_ view: BandmapCanvas, context: Context) {
        view.model = model
        view.language = language
        view.state = state
        view.setAccessibilityLabel(language.tr("Bandmapa"))
        view.refreshAccessibilityValue()
        view.refreshToolTips()
        view.needsDisplay = true
    }
}

/// One spot of the band map for assistive technologies; the press tunes to it, like a click on its label.
final class BandmapSpotElement: NSAccessibilityElement {
    /// Set on the main actor; the accessibility press arrives on the main thread.
    nonisolated(unsafe) var onPress: (@MainActor () -> Void)?

    override func accessibilityPerformPress() -> Bool {
        guard let onPress else { return false }
        MainActor.assumeIsolated { onPress() }
        return true
    }
}

@MainActor
final class BandmapCanvas: NSView, NSViewToolTipOwner {

    var model: BandmapModel?
    var language: LanguageModel?
    var state: BandmapDrawState?

    private var wheel = BandmapWheel()
    private var pressStart: NSPoint?
    private var dragCurrentY: CGFloat?
    private var menuActions: [MenuItemAction] = []

    /// Vertical positions grow downwards, as in Compose.
    override var isFlipped: Bool {
        true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    // MARK: - metrics

    private struct Metrics {
        let axisX: Float
        let rowH: Float
        let spotFont: NSFont
        let axisFont: NSFont
    }

    /// `axisLabelW + 18` and the row height of the measured "X" + 2 (`BM:180-195`).
    private func metrics(_ state: BandmapDrawState) -> Metrics {
        let spotFont = NSFont.monospacedSystemFont(ofSize: CGFloat(state.spotFont), weight: .regular)
        let axisSize: Int = BandmapViewport.axisFont(spotFont: state.spotFont)
        let axisFont = NSFont.monospacedSystemFont(ofSize: CGFloat(axisSize), weight: .regular)
        let widest: String = BandmapViewport.tickLabel(Int64(state.band.highHz))
        let labelW: CGFloat = (widest as NSString).size(withAttributes: [.font: axisFont]).width.rounded(.up)
        let rowH: CGFloat = ("X" as NSString).size(withAttributes: [.font: spotFont]).height.rounded(.up)
        return Metrics(axisX: Float(labelW) + 18, rowH: Float(rowH) + 2, spotFont: spotFont, axisFont: axisFont)
    }

    // MARK: - drawing

    private static let leaderWidth: CGFloat = 90
    private static let planWidth: CGFloat = 13
    private static let markerWidth: CGFloat = 18
    private static let markerHeight: CGFloat = 8
    private static let passbandWidth: CGFloat = 5

    override func draw(_ dirtyRect: NSRect) {
        guard let state, let model, let context = NSGraphicsContext.current?.cgContext else { return }
        let metrics: Metrics = metrics(state)
        let axisX = CGFloat(metrics.axisX)
        let height = Float(bounds.height)
        let width: CGFloat = bounds.width
        let viewport: BandmapViewport = state.viewport
        func yAt(_ hz: Int64) -> CGFloat {
            CGFloat(viewport.yAt(hz, height: height))
        }
        drawPlan(model: model, state: state, axisX: axisX, yAt: yAt, metrics: metrics, context: context)
        drawAxis(viewport: viewport, axisX: axisX, yAt: yAt, metrics: metrics)
        drawLicenseLines(state: state, axisX: axisX, yAt: yAt)
        drawSpots(model: model, state: state, axisX: axisX, height: height, metrics: metrics)
        drawNotes(state: state, viewport: viewport, axisX: axisX, width: width, yAt: yAt)
        drawCq(state: state, viewport: viewport, axisX: axisX, width: width, yAt: yAt, metrics: metrics)
        drawPassband(state: state, viewport: viewport, axisX: axisX, yAt: yAt)
        drawTolerance(state: state, viewport: viewport, axisX: axisX, yAt: yAt)
        if let tx = state.txHz {
            drawArrow(at: tx, color: .systemRed, viewport: viewport, axisX: axisX, width: width, yAt: yAt)
        }
        drawArrow(at: state.tunedHz, color: .systemBlue, viewport: viewport, axisX: axisX, width: width, yAt: yAt)
        if let start = pressStart, let current = dragCurrentY {
            DomainColors.primary.withAlphaComponent(0.15).setFill()
            let top: CGFloat = Swift.min(start.y, current)
            NSRect(x: axisX, y: top, width: width - axisX, height: abs(start.y - current)).fill()
        }
    }

    private func line(from: NSPoint, to: NSPoint, color: NSColor, width: CGFloat, dash: [CGFloat] = []) {
        let path = NSBezierPath()
        path.move(to: from)
        path.line(to: to)
        path.lineWidth = width
        if !dash.isEmpty {
            path.setLineDash(dash, count: dash.count, phase: 0)
        }
        color.setStroke()
        path.stroke()
    }

    private func text(_ string: String, at point: NSPoint, font: NSFont, color: NSColor) {
        (string as NSString).draw(at: point, withAttributes: [.font: font, .foregroundColor: color])
    }

    private func size(_ string: String, font: NSFont) -> NSSize {
        (string as NSString).size(withAttributes: [.font: font])
    }

    /// The band plan strip right of the axis, drawn first so it stays under the spots, notes and the marker.
    private func drawPlan(model: BandmapModel, state: BandmapDrawState, axisX: CGFloat,
                          yAt: (Int64) -> CGFloat, metrics: Metrics, context: CGContext) {
        guard state.showPlan else { return }
        let labelFont = NSFont.monospacedSystemFont(
            ofSize: CGFloat(Swift.max(BandmapViewport.axisFont(spotFont: state.spotFont) - 1, 7)), weight: .regular)
        for segment in model.planSegments(analyzer: state.analyzer) {
            let top: CGFloat = yAt(segment.lowHz)
            let bottom: CGFloat = yAt(segment.highHz)
            let segmentHeight: CGFloat = Swift.max(bottom - top, 1)
            let color: NSColor = SpotColors.plan(segment.category)
            color.withAlphaComponent(0.30).setFill()
            NSRect(x: axisX + 1, y: top, width: Self.planWidth, height: segmentHeight).fill()
            let label: String = SpotColors.planLabel(segment.category)
            let measured: NSSize = size(label, font: labelFont)
            guard measured.width + 6 <= segmentHeight else { continue }
            let centerX: CGFloat = axisX + 1 + Self.planWidth / 2
            let centerY: CGFloat = top + segmentHeight / 2
            context.saveGState()
            context.translateBy(x: centerX, y: centerY)
            context.rotate(by: -CGFloat.pi / 2)
            text(label, at: NSPoint(x: -measured.width / 2, y: -measured.height / 2), font: labelFont, color: color)
            context.restoreGState()
        }
    }

    private func drawAxis(viewport: BandmapViewport, axisX: CGFloat, yAt: (Int64) -> CGFloat, metrics: Metrics) {
        let top = CGFloat(BandmapViewport.padTop)
        let bottom: CGFloat = bounds.height - CGFloat(BandmapViewport.padBottom)
        let axisColor: NSColor = .secondaryLabelColor
        line(from: NSPoint(x: axisX, y: top), to: NSPoint(x: axisX, y: bottom), color: axisColor, width: 1.5)
        for tick in viewport.ticks {
            let y: CGFloat = yAt(tick)
            line(from: NSPoint(x: axisX - 4, y: y), to: NSPoint(x: axisX, y: y), color: axisColor, width: 1)
            let label: String = BandmapViewport.tickLabel(tick)
            let measured: NSSize = size(label, font: metrics.axisFont)
            text(label, at: NSPoint(x: axisX - 8 - measured.width, y: y - measured.height / 2),
                 font: metrics.axisFont, color: .labelColor)
        }
    }

    /// The US licence class edges (N1MM's red lines): a short red line across the scale at each edge.
    private func drawLicenseLines(state: BandmapDrawState, axisX: CGFloat, yAt: (Int64) -> CGFloat) {
        for hz in state.licenseLines {
            let y: CGFloat = yAt(hz)
            line(from: NSPoint(x: axisX - 10, y: y), to: NSPoint(x: axisX + 1 + Self.planWidth, y: y),
                 color: .systemRed, width: 1.5)
        }
    }

    /// The spots spread over free rows, each with a leader line from its frequency on the axis to its label.
    private func drawSpots(model: BandmapModel, state: BandmapDrawState, axisX: CGFloat, height: Float,
                           metrics: Metrics) {
        let placements: [SpotPlacement] = model.placements(spots: state.spots, height: height, rowH: metrics.rowH)
        let boldFont: NSFont = NSFont.monospacedSystemFont(ofSize: CGFloat(state.spotFont), weight: .bold)
        for placement in placements {
            let spot: DxSpot = placement.spot
            let color: NSColor = SpotColors.color(model.colorKey(spot, analyzer: state.analyzer))
            line(from: NSPoint(x: axisX, y: CGFloat(placement.trueY)),
                 to: NSPoint(x: axisX + Self.leaderWidth - 4, y: CGFloat(placement.labelY)), color: color, width: 1)
            let font: NSFont = spot.selfSpotted ? boldFont : metrics.spotFont
            let label: String = model.drawnLabel(spot)
            let measured: NSSize = size(label, font: font)
            text(label, at: NSPoint(x: axisX + Self.leaderWidth, y: CGFloat(placement.labelY) - measured.height / 2),
                 font: font, color: color)
        }
    }

    /// The band notes: a dotted line and the text at the frequency.
    private func drawNotes(state: BandmapDrawState, viewport: BandmapViewport, axisX: CGFloat, width: CGFloat,
                           yAt: (Int64) -> CGFloat) {
        let font = NSFont.systemFont(ofSize: CGFloat(state.spotFont - 1))
        for note in state.notes {
            guard let hz = BandNotes.markHz(note), hz >= viewport.loHz, hz <= viewport.hiHz else { continue }
            let y: CGFloat = yAt(hz)
            line(from: NSPoint(x: axisX - 4, y: y), to: NSPoint(x: width, y: y),
                 color: SpotColors.note.withAlphaComponent(0.6), width: 1, dash: [2, 3])
            let measured: NSSize = size(note.text, font: font)
            text(note.text, at: NSPoint(x: width - measured.width - 4, y: y - measured.height - 1), font: font,
                 color: SpotColors.note)
        }
    }

    /// The CQ frequency (N1MM „CQ-Frequency"): a dashed line across and „CQ" at the axis.
    private func drawCq(state: BandmapDrawState, viewport: BandmapViewport, axisX: CGFloat, width: CGFloat,
                        yAt: (Int64) -> CGFloat, metrics: Metrics) {
        guard let cq = state.cqHz, cq >= viewport.loHz, cq <= viewport.hiHz else { return }
        let y: CGFloat = yAt(cq)
        line(from: NSPoint(x: axisX - 4, y: y), to: NSPoint(x: width, y: y),
             color: DomainColors.primary.withAlphaComponent(0.7), width: 1.5, dash: [6, 4])
        let font = NSFont.monospacedSystemFont(
            ofSize: CGFloat(BandmapViewport.axisFont(spotFont: state.spotFont)), weight: .bold)
        let measured: NSSize = size("CQ", font: font)
        text("CQ", at: NSPoint(x: axisX - Self.markerWidth - 4 - measured.width, y: y - measured.height - 2),
             font: font, color: DomainColors.primary)
    }

    /// N1MM's tuning tolerance: a light blue band on the scale around the tuned frequency (the call-frame's reach).
    private func drawTolerance(state: BandmapDrawState, viewport: BandmapViewport, axisX: CGFloat,
                               yAt: (Int64) -> CGFloat) {
        guard let tolerance = state.toleranceHz, tolerance > 0, state.tunedHz >= viewport.loHz,
              state.tunedHz <= viewport.hiHz else { return }
        let first: CGFloat = yAt(state.tunedHz - Int64(tolerance))
        let second: CGFloat = yAt(state.tunedHz + Int64(tolerance))
        let top: CGFloat = Swift.min(first, second)
        let height: CGFloat = Swift.max(abs(second - first), 2)
        NSColor.systemTeal.withAlphaComponent(0.35).setFill()
        NSRect(x: axisX - 6, y: top, width: 6, height: height).fill()
    }

    /// The receiver's filter (N1MM draws the filter width at the arrow): a bar right of the band plan strip.
    private func drawPassband(state: BandmapDrawState, viewport: BandmapViewport, axisX: CGFloat,
                              yAt: (Int64) -> CGFloat) {
        guard let range = state.passband, range.upperBound >= viewport.loHz,
              range.lowerBound <= viewport.hiHz else { return }
        let first: CGFloat = yAt(Swift.max(range.lowerBound, viewport.loHz))
        let second: CGFloat = yAt(Swift.min(range.upperBound, viewport.hiHz))
        NSColor.systemBlue.withAlphaComponent(0.45).setFill()
        NSRect(x: axisX + Self.planWidth + 2, y: Swift.min(first, second), width: Self.passbandWidth,
               height: Swift.max(abs(second - first), 2)).fill()
    }

    /// An arrow of the radio (N1MM: blue = the receive frequency, red = the transmit frequency while split): a
    /// translucent line across and a triangle pointing at the axis.
    private func drawArrow(at hz: Int64, color: NSColor, viewport: BandmapViewport, axisX: CGFloat, width: CGFloat,
                           yAt: (Int64) -> CGFloat) {
        guard hz >= viewport.loHz, hz <= viewport.hiHz else { return }
        let y: CGFloat = yAt(hz)
        line(from: NSPoint(x: axisX, y: y), to: NSPoint(x: width, y: y), color: color.withAlphaComponent(0.5),
             width: 2)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: axisX - Self.markerWidth, y: y - Self.markerHeight))
        path.line(to: NSPoint(x: axisX, y: y))
        path.line(to: NSPoint(x: axisX - Self.markerWidth, y: y + Self.markerHeight))
        path.close()
        color.setFill()
        path.fill()
        path.lineWidth = 1
        NSColor.labelColor.setStroke()
        path.stroke()
    }

    // MARK: - accessibility

    /// The spots as a list of children (callsign, kHz and the state as text), each pressable like a click on its
    /// label; the band, the tuned frequency and the count are the map's own value.
    override func accessibilityChildren() -> [Any]? {
        guard let state, let model, let language else { return [] }
        let metrics: Metrics = metrics(state)
        let placements: [SpotPlacement] = model.placements(spots: state.spots, height: Float(bounds.height),
                                                           rowH: metrics.rowH)
        let rowHeight = CGFloat(metrics.rowH)
        var children: [NSAccessibilityElement] = []
        for placement in placements {
            let spot: DxSpot = placement.spot
            let key: SpotColorClassifier.SpotColorKey = model.colorKey(spot, analyzer: state.analyzer)
            let element = BandmapSpotElement()
            element.setAccessibilityParent(self)
            element.setAccessibilityRole(.button)
            element.setAccessibilityLabel(AccessibilityText.bandmapSpot(
                call: spot.dxCall, freqHz: spot.freqHz, color: key, translator: language.translator))
            element.setAccessibilityHelp(model.tooltip(spot))
            let origin = NSPoint(x: CGFloat(metrics.axisX) + Self.leaderWidth,
                                 y: CGFloat(placement.labelY) - rowHeight / 2)
            let frame = NSRect(origin: origin, size: NSSize(width: Swift.max(bounds.width - origin.x, 1),
                                                            height: rowHeight))
            element.setAccessibilityFrameInParentSpace(frame)
            let axisX: Float = metrics.axisX
            let rowH: Float = metrics.rowH
            let height = Float(bounds.height)
            let labelY: Float = placement.labelY
            element.onPress = { [weak model] in
                model?.click(x: axisX + Float(Self.leaderWidth) + 1, y: labelY, height: height, axisX: axisX,
                             rowH: rowH)
            }
            children.append(element)
        }
        return children
    }

    /// The summary the view exposes as its value (refreshed with every update).
    func refreshAccessibilityValue() {
        guard let state, let language else {
            setAccessibilityValue(nil)
            return
        }
        setAccessibilityValue(AccessibilityText.bandmapValue(
            band: state.band.adif, tunedHz: state.tunedHz, spots: state.spots.count, translator: language.translator))
    }

    // MARK: - tooltips

    /// One tooltip area per spot label (N1MM's spot tooltip), rebuilt with every update and resize.
    func refreshToolTips() {
        removeAllToolTips()
        guard let state, let model else { return }
        let metrics: Metrics = metrics(state)
        let rowHeight = CGFloat(metrics.rowH)
        let left = CGFloat(metrics.axisX) + Self.leaderWidth
        for placement in model.placements(spots: state.spots, height: Float(bounds.height), rowH: metrics.rowH) {
            let rect = NSRect(x: left, y: CGFloat(placement.labelY) - rowHeight / 2,
                              width: Swift.max(bounds.width - left, 1), height: rowHeight)
            addToolTip(rect, owner: self, userData: nil)
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        refreshToolTips()
    }

    nonisolated func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint,
                          userData data: UnsafeMutableRawPointer?) -> String {
        MainActor.assumeIsolated {
            guard let model, let state else { return "" }
            let metrics: Metrics = metrics(state)
            guard let spot = model.menuSpot(x: Float(point.x), y: Float(point.y), height: Float(bounds.height),
                                            axisX: metrics.axisX, rowH: metrics.rowH) else { return "" }
            return model.tooltip(spot)
        }
    }

    // MARK: - pointer

    /// The mouse position over the map: the spot under it is the target of Alt+D (`BandmapModel.handleKey`).
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow,
                                                              .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        guard let model, let state else { return }
        let point: NSPoint = convert(event.locationInWindow, from: nil)
        let metrics: Metrics = metrics(state)
        model.pointerMoved(x: Float(point.x), y: Float(point.y), height: Float(bounds.height), axisX: metrics.axisX,
                           rowH: metrics.rowH)
        let tip: String? = model.markerTooltip(x: Float(point.x), y: Float(point.y), height: Float(bounds.height),
                                               axisX: metrics.axisX)
        if toolTip != tip {
            toolTip = tip
        }
    }

    override func mouseExited(with event: NSEvent) {
        model?.pointerLeft()
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            rightMouseDown(with: event)
            return
        }
        pressStart = convert(event.locationInWindow, from: nil)
        dragCurrentY = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard pressStart != nil else { return }
        dragCurrentY = convert(event.locationInWindow, from: nil).y
        needsDisplay = true
    }

    /// A drag longer than the model's threshold zooms; anything else is a click at the press position.
    override func mouseUp(with event: NSEvent) {
        defer {
            pressStart = nil
            dragCurrentY = nil
            needsDisplay = true
        }
        guard let start = pressStart, let model, let state else { return }
        let metrics: Metrics = metrics(state)
        let height = Float(bounds.height)
        if let current = dragCurrentY, abs(start.y - current) > CGFloat(BandmapViewport.dragThresholdPx) {
            model.drag(from: Float(start.y), to: Float(current), height: height)
        } else if event.clickCount >= 2 {
            model.doubleClick(x: Float(start.x), y: Float(start.y), height: height, axisX: metrics.axisX,
                              rowH: metrics.rowH)
        } else {
            model.click(x: Float(start.x), y: Float(start.y), height: height, axisX: metrics.axisX,
                        rowH: metrics.rowH)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        guard let model else { return }
        if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
            wheel.reset()
        }
        let flags: NSEvent.ModifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let momentum: Bool = !event.momentumPhase.isEmpty
        let steps = wheel.feed(deltaX: Double(event.scrollingDeltaX), deltaY: Double(event.scrollingDeltaY),
                               precise: event.hasPreciseScrollingDeltas, momentum: momentum)
        for step in steps {
            model.wheel(dx: step.dx, dy: step.dy, ctrl: flags.contains(.control), shift: flags.contains(.shift))
        }
    }

    // MARK: - context menu

    override func rightMouseDown(with event: NSEvent) {
        guard let model, let state, let language else { return }
        let point: NSPoint = convert(event.locationInWindow, from: nil)
        let metrics: Metrics = metrics(state)
        let spot: DxSpot? = model.menuSpot(x: Float(point.x), y: Float(point.y), height: Float(bounds.height),
                                           axisX: metrics.axisX, rowH: metrics.rowH)
        let menu = NSMenu()
        menuActions = []
        if let spot {
            addItem(menu, language.tr("Blacklist volačky %s", .string(spot.dxCall))) { model.blacklistCall(spot) }
            addItem(menu, "Blacklist spottera " + spot.spotter) { model.blacklistSpotter(spot) }
            addItem(menu, "Odebrat spot") { model.remove(spot) }
            // Same items and order as the log window's row menu (both open the call's page in the browser).
            addItem(menu, language.tr("Dohledat na %s", .string(CallbookService.hamQth.displayName))) {
                model.openHamQth(spot)
            }
            addItem(menu, language.tr("Dohledat na %s", .string(CallbookService.qrz.displayName))) {
                model.openQrz(spot)
            }
            // N1MM's cluster queries about the station (View menu) and its Telnet history.
            menu.addItem(queryItem(model: model, language: language, call: spot.dxCall))
            addItem(menu, language.tr("Historie spotů %s", .string(spot.dxCall))) { model.showHistory(of: spot.dxCall) }
            menu.addItem(.separator())
        }
        // N1MM's order: Zoom In, Zoom Out, Disable Mouse Wheel, Go to Bottom / Top Of Band.
        addItem(menu, language.tr("Přiblížit")) { model.zoomIn() }
        addItem(menu, language.tr("Oddálit")) { model.zoomOut() }
        addItem(menu, language.tr("Vypnout kolečko myši"), checked: model.wheelDisabled) {
            model.toggleWheelDisabled()
        }
        addItem(menu, language.tr("Na spodní okraj úseku pásma")) { model.goToBottomOfBand() }
        addItem(menu, language.tr("Na horní okraj úseku pásma")) { model.goToTopOfBand() }
        menu.addItem(.separator())
        addItem(menu, language.tr("Smazat spoty, jen toto pásmo, ponechat vlastní")) {
            model.removeSpots(thisBand: true, keepSelf: true)
        }
        addItem(menu, language.tr("Smazat spoty, jen toto pásmo")) { model.removeSpots(thisBand: true, keepSelf: false) }
        addItem(menu, language.tr("Smazat spoty, všechna pásma, ponechat vlastní")) {
            model.removeSpots(thisBand: false, keepSelf: true)
        }
        addItem(menu, language.tr("Smazat všechny spoty")) { model.clearSpots() }
        menu.addItem(.separator())
        addItem(menu, state.showPlan ? language.tr("Skrýt bandplán") : language.tr("Zobrazit bandplán")) {
            model.toggleBandPlan()
        }
        let freqHz: Int64 = state.viewport.freqAt(Float(point.y), height: Float(bounds.height))
        menu.addItem(bandPlanItem(model: model, language: language, freqHz: freqHz))
        addItem(menu, !model.showLicenseLines
                    ? language.tr("Zobrazit čáry licenčních tříd USA")
                    : language.tr("Skrýt čáry licenčních tříd USA")) {
            model.toggleLicenseLines()
        }
        addItem(menu, language.tr("Najít volačku…")) { model.promptFind() }
        addItem(menu, language.tr("Historie spotů mé značky")) { model.showMyHistory() }
        menu.addItem(.separator())
        // N1MM „Telnet Bands/Modes" and „Telnet Filters": one sheet holds both parts of the spot filter.
        addItem(menu, language.tr("Telnet pásma/módy…")) { model.openSpotFilter() }
        addItem(menu, language.tr("Telnet filtry…")) { model.openSpotFilter() }
        addItem(menu, language.tr("Uživatelská tlačítka…")) { model.editButtons() }
        addItem(menu, language.tr("Nejnižší kmitočet dole"), checked: model.lowestAtBottom) {
            model.toggleLowestAtBottom()
        }
        menu.popUp(positioning: nil, at: point, in: self)
    }

    /// „Bandplán zde (… kHz)": the sub-band edges set at the clicked frequency, or the sub-band under it removed
    /// (N1MM's band plan adjustment by a right click on the frequency).
    private func bandPlanItem(model: BandmapModel, language: LanguageModel, freqHz: Int64) -> NSMenuItem {
        let item = NSMenuItem(title: language.tr("Bandplán zde (%s kHz)", .string(FrequencyText.formatHz(freqHz))),
                              action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let edits: [(String, BandPlanEdit.Action)] = [
            ("Začátek CW zde", .setLow(mode: "CW")), ("Konec CW zde", .setHigh(mode: "CW")),
            ("Začátek Digi zde", .setLow(mode: "DIGI")), ("Konec Digi zde", .setHigh(mode: "DIGI")),
            ("Začátek fonie zde", .setLow(mode: "PHONE")), ("Konec fonie zde", .setHigh(mode: "PHONE")),
            ("Odebrat úsek zde", .remove),
        ]
        for (index, edit) in edits.enumerated() {
            if index == edits.count - 1 {
                submenu.addItem(.separator())
            }
            let action: BandPlanEdit.Action = edit.1
            addItem(submenu, language.tr(edit.0)) {
                Task { await model.editBandPlan(action, atHz: freqHz) }
            }
        }
        item.submenu = submenu
        return item
    }

    /// „Dotaz na DX cluster": the N1MM queries about `call` (last 10 spots, station, QSL, sunrise/sunset, callbook).
    private func queryItem(model: BandmapModel, language: LanguageModel, call: String) -> NSMenuItem {
        let item = NSMenuItem(title: language.tr("Dotaz na DX cluster"), action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for query in ClusterCallQuery.allCases {
            addItem(submenu, language.tr(query.titleKey)) { model.query(query, call: call) }
        }
        item.submenu = submenu
        return item
    }

    private func addItem(_ menu: NSMenu, _ title: String, enabled: Bool = true, checked: Bool = false,
                         _ run: @escaping @MainActor () -> Void) {
        let action = MenuItemAction(run)
        menuActions.append(action)
        let item = NSMenuItem(title: title, action: #selector(MenuItemAction.fire), keyEquivalent: "")
        item.target = action
        item.isEnabled = enabled
        item.state = checked ? .on : .off
        menu.addItem(item)
    }
}

/// The target of a context menu item.
@MainActor
private final class MenuItemAction: NSObject {
    private let run: @MainActor () -> Void

    init(_ run: @escaping @MainActor () -> Void) {
        self.run = run
    }

    @objc func fire() {
        run()
    }
}
