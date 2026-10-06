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
    let spotFont: Int
    let viewport: BandmapViewport

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
        spotFont = model.spotFont
        viewport = model.viewport
    }
}

/// The band map (an AppKit island, Kotlin `Canvas` of `BandmapWindow.kt:213-360, 440-620`): a
/// flipped `NSView` that draws the band plan strip, the axis with its ticks, the spread spot labels with their leader
/// lines, the band notes, the CQ line and the VFO triangle, and takes the pointer — a click, a drag that zooms, the
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
final class BandmapCanvas: NSView {

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
        drawSpots(model: model, state: state, axisX: axisX, height: height, metrics: metrics)
        drawNotes(state: state, viewport: viewport, axisX: axisX, width: width, yAt: yAt)
        drawCq(state: state, viewport: viewport, axisX: axisX, width: width, yAt: yAt, metrics: metrics)
        drawVfo(state: state, viewport: viewport, axisX: axisX, width: width, yAt: yAt)
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

    /// The tuned frequency: a translucent line across and a triangle pointing at the axis.
    private func drawVfo(state: BandmapDrawState, viewport: BandmapViewport, axisX: CGFloat, width: CGFloat,
                         yAt: (Int64) -> CGFloat) {
        guard state.tunedHz >= viewport.loHz, state.tunedHz <= viewport.hiHz else { return }
        let y: CGFloat = yAt(state.tunedHz)
        line(from: NSPoint(x: axisX, y: y), to: NSPoint(x: width, y: y),
             color: DomainColors.dupe.withAlphaComponent(0.5), width: 2)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: axisX - Self.markerWidth, y: y - Self.markerHeight))
        path.line(to: NSPoint(x: axisX, y: y))
        path.line(to: NSPoint(x: axisX - Self.markerWidth, y: y + Self.markerHeight))
        path.close()
        DomainColors.dupe.setFill()
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

    // MARK: - pointer

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
            addItem(menu, "QRZ.com") { model.openQrz(spot) }
            addItem(menu, "HamQTH") { model.openHamQth(spot) }
            menu.addItem(.separator())
        }
        addItem(menu, language.tr("Smazat všechny spoty")) { model.clearSpots() }
        addItem(menu, state.showPlan ? language.tr("Skrýt bandplán") : language.tr("Zobrazit bandplán")) {
            model.toggleBandPlan()
        }
        menu.popUp(positioning: nil, at: point, in: self)
    }

    private func addItem(_ menu: NSMenu, _ title: String, enabled: Bool = true,
                         _ run: @escaping @MainActor () -> Void) {
        let action = MenuItemAction(run)
        menuActions.append(action)
        let item = NSMenuItem(title: title, action: #selector(MenuItemAction.fire), keyEquivalent: "")
        item.target = action
        item.isEnabled = enabled
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
