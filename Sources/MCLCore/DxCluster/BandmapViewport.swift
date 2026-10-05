/// The visible frequency window of the Bandmap and its geometry (Kotlin `ui/BandmapWindow.kt` of v1.1.1: `visLo`/`visHi`,
/// `zoomTo` `:154-163`, the wheel `:236-257`, the drag zoom `:258-283`, the tap `:284-306`, `yAt` `:507-511`, the
/// ticks `:526-536`, `niceStepHz` `:622-631`). The view only draws; every coordinate comes from here.
///
/// Arithmetic is Kotlin's step by step: frequencies are `Long` (`Int64`), screen positions `Float` — `freqAt` adds a
/// `Long` to a `Float` (so above 16.7 MHz it is only as precise as `Float`, measured), `Float.toLong()` truncates.
/// The wheel sign is Compose's: a negative `dy` is "up" (higher frequency, zoom in).
public struct BandmapViewport: Equatable, Sendable {

    /// `PAD_TOP` / `PAD_BOT`: the axis starts and ends this far from the edges.
    public static let padTop: Float = 24
    public static let padBottom: Float = 24
    /// `CQ_HIT_PX`: the tolerance of a click on the CQ marker (left of the axis).
    public static let cqHitPx: Float = 10
    /// A drag shorter than this (or equal) is not a zoom.
    public static let dragThresholdPx: Float = 6
    /// The narrowest zoom (`newSpan.coerceIn(1000L, bandSpan)`).
    public static let minSpanHz: Int64 = 1_000
    /// The spot font (`fontText.toIntOrNull()?.coerceIn(8, 28) ?: 11`); the axis uses one point less, at least 7.
    public static let spotFontRange: ClosedRange<Int> = 8...28
    public static let defaultSpotFont = 11

    public private(set) var loHz: Int64
    public private(set) var hiHz: Int64

    /// `remember(band) { band?.lowHz() ?: 0L }` / `band?.highHz() ?: 1L`.
    public init(band: Band?) {
        loHz = band.map { Int64($0.lowHz) } ?? 0
        hiHz = band.map { Int64($0.highHz) } ?? 1
    }

    /// The default window of a microwave band (post-port): the whole band is hundreds of MHz wide (3 cm: 500 MHz),
    /// so the spots would be unreadable; it opens this wide around the tuned frequency and zooms out to the band.
    public static let microwaveWindowHz: Int64 = 2_000_000

    /// The window a band opens with: the whole band like Kotlin, but for a microwave band `microwaveWindowHz`
    /// centred on `tunedHz` and pushed inside the band (a tuned frequency outside the band: its lower edge).
    public init(band: Band?, tunedHz: Int64) {
        guard let band, band.isMicrowave else {
            self.init(band: band)
            return
        }
        let bounds: ClosedRange<Int64> = Self.bounds(band)
        let span: Int64 = Self.microwaveWindowHz
        var lo: Int64 = bounds.lowerBound
        if bounds.contains(tunedHz) {
            lo = Swift.max(tunedHz - span / 2, bounds.lowerBound)
            lo = Swift.min(lo, bounds.upperBound - span)
        }
        self.init(loHz: lo, hiHz: lo + span)
    }

    /// An explicit window (tests and restoring a state).
    public init(loHz: Int64, hiHz: Int64) {
        self.loHz = loHz
        self.hiHz = hiHz
    }

    /// The band limits as the Kotlin code reads them (`band.lowHz()..band.highHz()`).
    public static func bounds(_ band: Band) -> ClosedRange<Int64> {
        Int64(band.lowHz)...Int64(band.highHz)
    }

    /// „Reset zobrazení" and a band change (`remember(band)`): the whole band.
    public mutating func reset(band: Band?) {
        self = BandmapViewport(band: band)
    }

    /// The same for the microwave bands, which open on a narrow window around the tuned frequency.
    public mutating func reset(band: Band?, tunedHz: Int64) {
        self = BandmapViewport(band: band, tunedHz: tunedHz)
    }

    /// The visible span `visHi - visLo`.
    public var spanHz: Int64 {
        hiHz &- loHz
    }

    // MARK: - zoom and wheel

    /// `zoomTo(newSpan)`: the window centred on the tuned frequency, at least 1 kHz and at most the band, pushed back
    /// inside the band. Kotlin's `coerceIn` throws for a band narrower than 1 kHz (none exists); here nothing happens.
    public mutating func zoom(to newSpan: Int64, tunedHz: Int64, bounds: ClosedRange<Int64>) {
        let bandSpan: Int64 = bounds.upperBound - bounds.lowerBound
        guard bandSpan >= Self.minSpanHz else { return }
        let span: Int64 = Swift.min(Swift.max(newSpan, Self.minSpanHz), bandSpan)
        var lo: Int64 = tunedHz - span / 2
        var hi: Int64 = lo + span
        if lo < bounds.lowerBound {
            lo = bounds.lowerBound
            hi = lo + span
        }
        if hi > bounds.upperBound {
            hi = bounds.upperBound
            lo = hi - span
        }
        loHz = Swift.max(lo, bounds.lowerBound)
        hiHz = Swift.min(hi, bounds.upperBound)
    }

    /// The „+" button and Ctrl+wheel up: half the visible span.
    public mutating func zoomIn(tunedHz: Int64, bounds: ClosedRange<Int64>) {
        zoom(to: spanHz / 2, tunedHz: tunedHz, bounds: bounds)
    }

    /// The „−" button and Ctrl+wheel down: twice the visible span.
    public mutating func zoomOut(tunedHz: Int64, bounds: ClosedRange<Int64>) {
        zoom(to: spanHz &* 2, tunedHz: tunedHz, bounds: bounds)
    }

    /// The wheel. The dominant axis counts (macOS turns Shift+wheel into a horizontal scroll). With Ctrl it zooms
    /// (`dy < 0` in, otherwise — also `0` — out) and returns `nil`. Otherwise the tuned frequency moves by the step
    /// (Shift = the big step; `dy < 0` up, otherwise down) clamped to the band; when it leaves the window the window
    /// follows it with the same span. Returns the frequency to QSY to.
    public mutating func wheel(dx: Float, dy: Float, ctrl: Bool, shift: Bool, tunedHz: Int64,
                               bounds: ClosedRange<Int64>, stepHz: Int64, stepShiftHz: Int64) -> Int64? {
        let delta: Float = Swift.abs(dy) >= Swift.abs(dx) ? dy : dx
        if ctrl {
            if delta < 0 {
                zoomIn(tunedHz: tunedHz, bounds: bounds)
            } else {
                zoomOut(tunedHz: tunedHz, bounds: bounds)
            }
            return nil
        }
        let chosen: Int64 = shift ? stepShiftHz : stepHz
        let move: Int64 = delta < 0 ? chosen : -chosen
        let target: Int64 = Swift.min(Swift.max(tunedHz &+ move, bounds.lowerBound), bounds.upperBound)
        let span: Int64 = spanHz
        if target > hiHz {
            hiHz = target
            loHz = hiHz - span
        } else if target < loHz {
            loHz = target
            hiHz = loHz + span
        }
        return target
    }

    /// The drag zoom: a drag longer than 6 px shows the frequencies under its ends, clamped to the band. Returns
    /// whether it zoomed.
    @discardableResult
    public mutating func dragZoom(from startY: Float, to endY: Float, height: Float,
                                  bounds: ClosedRange<Int64>) -> Bool {
        guard Swift.abs(startY - endY) > Self.dragThresholdPx else { return false }
        let first: Int64 = freqAt(Swift.min(startY, endY), height: height)
        let second: Int64 = freqAt(Swift.max(startY, endY), height: height)
        loHz = Swift.max(first, bounds.lowerBound)
        hiHz = Swift.min(second, bounds.upperBound)
        return true
    }

    // MARK: - geometry

    /// `height - PAD_TOP - PAD_BOT`.
    public static func usable(_ height: Float) -> Float {
        let inner: Float = height - padTop
        return inner - padBottom
    }

    /// `yAt(hz)`: `PAD_TOP + (hz - loHz) / span * usable`, span at least 1.
    public func yAt(_ hz: Int64, height: Float) -> Float {
        let span = Float(Swift.max(spanHz, 1))
        let ratio: Float = Float(hz &- loHz) / span
        let offset: Float = ratio * Self.usable(height)
        return Self.padTop + offset
    }

    /// `freqAt(y)`: `(visLo + ((y - PAD_TOP) / usable) * (visHi - visLo)).toLong()` — a `Float` sum, truncated.
    ///
    /// Above 70 cm (post-port microwaves, never reachable in Java) the sum is done in `Double`: a `Float` has a
    /// resolution of 1 kHz at 10 GHz, so a click would land on whole kilohertz only.
    public func freqAt(_ y: Float, height: Float) -> Int64 {
        let ratio: Float = (y - Self.padTop) / Self.usable(height)
        if loHz > Int64(Band.cm70.highHz) {
            return JavaMath.d2l(Double(loHz) + Double(ratio) * Double(spanHz))
        }
        let offset: Float = ratio * Float(spanHz)
        let sum: Float = Float(loHz) + offset
        return JavaMath.d2l(Double(sum))
    }

    /// The click on the CQ marker: a CQ frequency inside the window, left of the axis, at most 10 px from it.
    public func hitsCqMarker(cqHz: Int64?, x: Float, y: Float, axisX: Float, height: Float) -> Bool {
        guard let cqHz, cqHz >= loHz, cqHz <= hiHz, x < axisX else { return false }
        return Swift.abs(y - yAt(cqHz, height: height)) <= Self.cqHitPx
    }

    // MARK: - ticks

    /// `niceStepHz(rough)`: 1/2/5 × 10ⁿ Hz, at least 1. (Kotlin's loop overflows above 10¹⁸, unreachable for a band;
    /// here it stops at the largest power of ten.)
    public static func niceStepHz(_ rough: Int64) -> Int64 {
        let r: Int64 = Swift.max(rough, 1)
        var mag: Int64 = 1
        while true {
            let (next, overflow) = mag.multipliedReportingOverflow(by: 10)
            if overflow || next > r { break }
            mag = next
        }
        if r / mag >= 5 { return mag * 5 }
        if r / mag >= 2 { return mag * 2 }
        return mag
    }

    /// The tick frequencies: the step for about ten ticks, from the first multiple at or above `loHz` to `hiHz`.
    public var ticks: [Int64] {
        let step: Int64 = Self.niceStepHz(spanHz / 10)
        var f: Int64 = (loHz / step) * step
        if f < loHz { f += step }
        var out: [Int64] = []
        while f <= hiHz {
            out.append(f)
            f += step
        }
        return out
    }

    /// The tick label `"%d".format(f / 1000)`: whole kHz, truncated toward zero.
    public static func tickLabel(_ hz: Int64) -> String {
        String(hz / 1000)
    }

    // MARK: - fonts

    /// `coerceIn(8, 28)` of the spot font steppers.
    public static func spotFont(_ size: Int) -> Int {
        Swift.min(Swift.max(size, spotFontRange.lowerBound), spotFontRange.upperBound)
    }

    /// `(spotFontSp - 1).coerceAtLeast(7)`.
    public static func axisFont(spotFont: Int) -> Int {
        Swift.max(spotFont - 1, 7)
    }
}

/// A spot with its frequency anchor on the axis and its spread label position (Kotlin `SpotPlacement`).
public struct SpotPlacement: Equatable, Sendable {
    public let spot: DxSpot
    public let trueY: Float
    public let labelY: Float

    public init(spot: DxSpot, trueY: Float, labelY: Float) {
        self.spot = spot
        self.trueY = trueY
        self.labelY = labelY
    }
}

/// What a click in the Bandmap does (`BM:284-306`).
public enum BandmapTap: Equatable, Sendable {
    /// Back to the CQ frequency (`jumpToCqFrequency`).
    case cqFrequency
    /// Tune to the spot (`tuneToSpot`).
    case spot(DxSpot)
    /// QSY to the clicked frequency (`qsy(tapHz)`).
    case qsy(Int64)
}

/// The spot labels of the Bandmap (Kotlin `layoutSpots` `BM:463-478`, `hitSpot` `BM:486-492`, `azimuthOf`
/// `BM:120-126`, the label text `BM:546-550`). Deterministic from the inputs — drawing and hit-testing share it.
public enum BandmapLayout {

    /// `layoutSpots`: the spots inside the window (inclusive), sorted by frequency (stable), spread by
    /// `SpotLabelLayout.place` between `PAD_TOP` and `height - PAD_BOT`; the order is that of `place` (by `labelY`).
    public static func place(spots: [DxSpot], viewport: BandmapViewport, height: Float,
                             rowH: Float) -> [SpotPlacement] {
        let inWindow: [DxSpot] = spots.filter { spot in
            let hz = Int64(spot.freqHz)
            return hz >= viewport.loHz && hz <= viewport.hiHz
        }
        // Kotlin `sortedBy` is stable.
        let visible: [DxSpot] = inWindow.enumerated().sorted { left, right in
            if left.element.freqHz != right.element.freqHz {
                return left.element.freqHz < right.element.freqHz
            }
            return left.offset < right.offset
        }.map(\.element)
        if visible.isEmpty { return [] }
        let rows: [SpotLabelLayout.Row] = visible.enumerated().map { index, spot in
            SpotLabelLayout.Row(index: index, trueY: viewport.yAt(Int64(spot.freqHz), height: height))
        }
        let maxY: Float = height - BandmapViewport.padBottom
        return SpotLabelLayout.place(rows, rowH: rowH, minY: BandmapViewport.padTop, maxY: maxY).map {
            SpotPlacement(spot: visible[$0.index], trueY: $0.trueY, labelY: $0.labelY)
        }
    }

    /// `hitSpot`: the label nearest to `y` (the first on a tie) when it is within half the distance to its nearest
    /// neighbour, at most a row and at least 6 px.
    public static func hitSpot(_ placements: [SpotPlacement], y: Float, rowH: Float) -> SpotPlacement? {
        guard var nearestIndex = placements.indices.first else { return nil }
        for index in placements.indices.dropFirst()
        where Swift.abs(placements[index].labelY - y) < Swift.abs(placements[nearestIndex].labelY - y) {
            nearestIndex = index
        }
        let nearest: SpotPlacement = placements[nearestIndex]
        var gap: Float = .greatestFiniteMagnitude
        for index in placements.indices where index != nearestIndex {
            gap = Swift.min(gap, Swift.abs(placements[index].labelY - nearest.labelY))
        }
        let tolerance: Float = Swift.max(Swift.min(rowH, gap / 2), 6)
        return Swift.abs(nearest.labelY - y) <= tolerance ? nearest : nil
    }

    /// The click (`detectTapGestures`): the CQ marker first, then a spot right of the axis, otherwise a QSY to the
    /// frequency under the cursor.
    public static func tap(x: Float, y: Float, viewport: BandmapViewport, height: Float, axisX: Float, rowH: Float,
                           spots: [DxSpot], cqHz: Int64?) -> BandmapTap {
        if viewport.hitsCqMarker(cqHz: cqHz, x: x, y: y, axisX: axisX, height: height) {
            return .cqFrequency
        }
        let placements: [SpotPlacement] = place(spots: spots, viewport: viewport, height: height, rowH: rowH)
        if let nearest = hitSpot(placements, y: y, rowH: rowH), x > axisX {
            return .spot(nearest.spot)
        }
        return .qsy(viewport.freqAt(y, height: height))
    }

    /// The spot under a right click (right of the axis), `nil` = the menu without the spot items.
    public static func menuSpot(x: Float, y: Float, viewport: BandmapViewport, height: Float, axisX: Float,
                                rowH: Float, spots: [DxSpot]) -> DxSpot? {
        guard x > axisX else { return nil }
        let placements: [SpotPlacement] = place(spots: spots, viewport: viewport, height: height, rowH: rowH)
        return hitSpot(placements, y: y, rowH: rowH)?.spot
    }

    /// `azimuthOf(call)`: the station grid centre → the entity coordinates → `Math.round(bearing).toInt()`; `nil`
    /// without a grid centre, an entity or its coordinates.
    public static func azimuthOf(call: String, myLatLon: (lat: Double, lon: Double)?,
                                 dxcc: (any DxccLookup)?) -> Int? {
        GreatCircle.azimuth(from: myLatLon, toCall: call, dxcc: dxcc)
    }

    /// The label text: the call, `" <az>°"` when known and `" ×<n>"` for two or more skimmers.
    public static func labelText(call: String, azimuth: Int?, skimmers: Int) -> String {
        let az: String = azimuth.map { " " + String($0) + "°" } ?? ""
        let sk: String = skimmers >= 2 ? " ×" + String(skimmers) : ""
        return call + az + sk
    }
}
