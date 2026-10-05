import Foundation

/// The logic of the map window (Kotlin `WorldMapWindow.kt`, `WM:75-402`): projection centred on the station's longitude,
/// the Maidenhead field under a point, the strongest cell per field, the classification and outlines of the land rings,
/// DXCC dots, the night side as pixel columns and the click-to-spot rule. Colours and drawing stay in the app; every
/// pixel value is a `Float` computed exactly like the Kotlin `Float`/`Double` mix.
public struct WorldMapModel: Sendable, Equatable {

    /// Top and bottom of the shown latitude range (Antarctica is cut at −75°) and its span.
    public static let latTop: Double = 90
    public static let latBottom: Double = -75
    public static let latSpan: Double = 165

    /// Longitude at the horizontal centre of the map.
    public let centerLon: Double

    public init(centerLon: Double) {
        self.centerLon = centerLon
    }

    /// The station position: latitude and longitude from the settings when both parse, otherwise the centre of the
    /// locator; `nil` when neither works.
    public static func stationPosition(latitude: String, longitude: String, gridSquare: String)
        -> (lat: Double, lon: Double)? {
        if let lat = JavaDouble.parseDouble(latitude), let lon = JavaDouble.parseDouble(longitude) {
            return (lat, lon)
        }
        return Maidenhead.centerLatLon(gridSquare)
    }

    /// A model centred on the station (longitude 0 without a position).
    public init(station: (lat: Double, lon: Double)?) {
        self.init(centerLon: station?.lon ?? 0)
    }

    /// The window opens in DXCC mode when asked to or when no contest is active.
    public static func initialDxccMode(startDxcc: Bool, contestActive: Bool) -> Bool {
        startDxcc || !contestActive
    }

    // MARK: - projection

    /// Horizontal pixel of a longitude on a map `width` pixels wide (wraps around the date line).
    public func px(lon: Double, width: Float) -> Float {
        var t: Double = (lon - centerLon) / 360.0 + 0.5
        t = (t.truncatingRemainder(dividingBy: 1.0) + 1.0).truncatingRemainder(dividingBy: 1.0)
        return Float(t * Double(width))
    }

    /// Vertical pixel of a latitude on a map `height` pixels high.
    public static func py(lat: Double, height: Float) -> Float {
        Float((latTop - lat) / latSpan * Double(height))
    }

    public func py(lat: Double, height: Float) -> Float {
        Self.py(lat: lat, height: height)
    }

    /// Longitude and latitude under a point of the canvas (the tap handler). The ratios are `Float` divisions like
    /// Kotlin (`pos.x / size.width`), only then widened.
    public func coordinates(x: Float, y: Float, width: Int, height: Int) -> (lon: Double, lat: Double) {
        let xRatio: Float = x / Float(width)
        let yRatio: Float = y / Float(height)
        let lon: Double = centerLon + (Double(xRatio) - 0.5) * 360.0
        let lat: Double = Self.latTop - Double(yRatio) * Self.latSpan
        return (lon, lat)
    }

    /// The Maidenhead field (two letters) of a position.
    public static func fieldAt(lon: Double, lat: Double) -> String? {
        let lo: Double = ((lon + 180).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let la: Double = coerce(lat + 90, 0.0, 179.999)
        if la < 0 || la >= 180 { return nil }
        let col: Int = Swift.min(17, Swift.max(0, Int(JavaMath.d2i(lo / 20))))
        let row: Int = Swift.min(17, Swift.max(0, Int(JavaMath.d2i(la / 10))))
        return fieldName(col: col, row: row)
    }

    static func fieldName(col: Int, row: Int) -> String {
        let a = UInt16(0x41)
        return JavaChar.string([a + UInt16(col), a + UInt16(row)])
    }

    /// Kotlin `coerceIn`: `NaN` passes through, like Kotlin's comparisons.
    private static func coerce(_ value: Double, _ low: Double, _ high: Double) -> Double {
        if value < low { return low }
        if value > high { return high }
        return value
    }

    // MARK: - field states

    /// Strength of a cell (`dbl` > `spotted` > `worked` > empty).
    public static func rank(_ cell: MultCell) -> Int {
        switch cell {
        case .spottedDbl: return 3
        case .spotted: return 2
        case .worked: return 1
        case .empty: return 0
        }
    }

    /// The strongest cell over the bands for every field of the grid (rows keyed by the field); empty ones are left out.
    /// Kotlin `maxByOrNull`: the first of equal strength wins (the order of `cells` is the band order, so a plain
    /// maximum over the values is the same).
    public static func fieldStates(grid: MultGridView) -> [String: MultCell] {
        var out: [String: MultCell] = [:]
        for row in grid.rows {
            var strongest: MultCell = .empty
            for band in SpotAnalyzer.multGridBands {
                guard let cell = row.cells[band.adif] else { continue }
                if rank(cell) > rank(strongest) { strongest = cell }
            }
            if strongest != .empty {
                out[row.key] = strongest
            }
        }
        return out
    }

    // MARK: - land rings

    /// How a land ring is drawn.
    public enum RingKind: Equatable, Sendable {
        /// Reaches below −78°: drawn as a flat band down to the bottom edge, segment by segment.
        case antarctic
        /// A sparse envelope of scattered islands: drawn as dots, not as a filled blob.
        case archipelago
        /// An ordinary filled outline with a coast line.
        case land
    }

    /// Classification of a ring `[lon0, lat0, lon1, lat1, …]` (Antarctica first, then the sparse archipelagos).
    public static func classify(ring: [Float]) -> RingKind {
        var minLat: Double = 90
        var maxLat: Double = -90
        var minLon: Double = 180
        var maxLon: Double = -180
        var k = 0
        while k + 1 < ring.count {
            let lo = Double(ring[k])
            let la = Double(ring[k + 1])
            if la < minLat { minLat = la }
            if la > maxLat { maxLat = la }
            if lo < minLon { minLon = lo }
            if lo > maxLon { maxLon = lo }
            k += 2
        }
        if minLat < -78.0 {
            return .antarctic
        }
        let points: Int = ring.count / 2
        let lonSpanRaw: Double = maxLon - minLon
        let lonSpan: Double = JavaMath.min(lonSpanRaw, 360.0 - lonSpanRaw)
        let maxSpan: Double = JavaMath.max(lonSpan, maxLat - minLat)
        if maxSpan > 12.0 && points < 26 && Double(points) / maxSpan < 1.4 {
            return .archipelago
        }
        return .land
    }

    /// A segment of the Antarctic band: the quad `(x0,y0) (x1,y1) (x1,height) (x0,height)` and its coast line.
    public struct BandSegment: Equatable, Sendable {
        public let x0: Float, y0: Float, x1: Float, y1: Float
    }

    /// The segments of an Antarctic ring; a jump of 180° or more in longitude (the date line) is not joined.
    public func antarcticSegments(ring: [Float], width: Float, height: Float) -> [BandSegment] {
        guard ring.count >= 2 else { return [] }
        var out: [BandSegment] = []
        var prevX: Float = px(lon: Double(ring[0]), width: width)
        var prevY: Float = py(lat: Double(ring[1]), height: height)
        var prevLon: Double = Double(ring[0])
        var i = 2
        while i + 1 < ring.count {
            let lon: Double = Double(ring[i])
            let x: Float = px(lon: lon, width: width)
            let y: Float = py(lat: Double(ring[i + 1]), height: height)
            if abs(lon - prevLon) < 180.0 {
                out.append(BandSegment(x0: prevX, y0: prevY, x1: x, y1: y))
            }
            prevX = x
            prevY = y
            prevLon = lon
            i += 2
        }
        return out
    }

    /// The dots of an archipelago ring (one per point).
    public func archipelagoDots(ring: [Float], width: Float, height: Float) -> [(x: Float, y: Float)] {
        var out: [(x: Float, y: Float)] = []
        var j = 0
        while j + 1 < ring.count {
            out.append((px(lon: Double(ring[j]), width: width), py(lat: Double(ring[j + 1]), height: height)))
            j += 2
        }
        return out
    }

    /// One vertex of a land outline; `move` starts a new sub-path (the first point and every wrap over the date line).
    public struct PathPoint: Equatable, Sendable {
        public let x: Float
        public let y: Float
        public let move: Bool
    }

    /// The outline of a land ring: a jump of more than half the width between neighbours starts a new sub-path.
    public func landPath(ring: [Float], width: Float, height: Float) -> [PathPoint] {
        var out: [PathPoint] = []
        let wrapLimit: Float = width * 0.5
        var prevX: Float = .nan
        var i = 0
        while i + 1 < ring.count {
            let x: Float = px(lon: Double(ring[i]), width: width)
            let y: Float = py(lat: Double(ring[i + 1]), height: height)
            out.append(PathPoint(x: x, y: y, move: prevX.isNaN || abs(x - prevX) > wrapLimit))
            prevX = x
            i += 2
        }
        return out
    }

    // MARK: - night side

    /// One pixel column of the night side: from `y0` to `y1`.
    public struct NightColumn: Equatable, Sendable {
        public let x: Int
        public let y0: Float
        public let y1: Float
    }

    /// The night side as 1-pixel columns: the terminator latitude from the Sun's declination, the night above or below
    /// it depending on the sign of the elevation at the top edge. Columns with no night are left out.
    public func terminatorColumns(width: Float, height: Float, epochMillis: Int64) -> [NightColumn] {
        let sun = SolarTerminator.subsolar(epochMillis: epochMillis)
        let tanDec: Double = tan(JavaMath.toRadians(sun.lat))
        var out: [NightColumn] = []
        let count: Int = Int(JavaMath.d2i(Double(width)))
        var xp = 0
        while xp < count {
            let ratio: Float = Float(xp) / width
            let lon: Double = centerLon + (Double(ratio) - 0.5) * 360.0
            let hRad: Double = JavaMath.toRadians(lon - sun.lon)
            let latTerm: Double
            if abs(tanDec) < 1e-6 {
                latTerm = cos(hRad) > 0 ? Self.latBottom : Self.latTop
            } else {
                latTerm = JavaMath.toDegrees(atan(-cos(hRad) / tanDec))
            }
            let termY: Float = Self.coerce(py(lat: latTerm, height: height), 0, height)
            let topNight: Bool = SolarTerminator.elevation(Self.latTop, lon, sun) < 0
            let y0: Float = topNight ? 0 : termY
            let y1: Float = topNight ? termY : height
            if y1 > y0 {
                out.append(NightColumn(x: xp, y0: y0, y1: y1))
            }
            xp += 1
        }
        return out
    }

    private static func coerce(_ value: Float, _ low: Float, _ high: Float) -> Float {
        if value < low { return low }
        if value > high { return high }
        return value
    }

    /// The Sun marker position (the subsolar point), or `nil` when it is below the shown range.
    public func sunMarker(width: Float, height: Float, epochMillis: Int64) -> (x: Float, y: Float)? {
        let sun = SolarTerminator.subsolar(epochMillis: epochMillis)
        guard sun.lat >= Self.latBottom else { return nil }
        return (px(lon: sun.lon, width: width), py(lat: sun.lat, height: height))
    }

    // MARK: - fields, grid lines, labels

    /// A coloured Maidenhead field rectangle.
    public struct FieldRect: Equatable, Sendable {
        public let key: String
        public let cell: MultCell
        public let x: Float
        public let y: Float
        public let width: Float
        public let height: Float
    }

    /// The rectangles of the coloured fields in column-major order (20° × 10° each).
    public func fieldRects(fieldStates: [String: MultCell], width: Float, height: Float) -> [FieldRect] {
        var out: [FieldRect] = []
        for col in 0..<18 {
            for row in 0..<18 {
                let key: String = Self.fieldName(col: col, row: row)
                guard let cell = fieldStates[key], cell != .empty else { continue }
                let x0: Float = px(lon: -180.0 + Double(col * 20), width: width)
                let yTop: Float = py(lat: -90.0 + Double(row + 1) * 10.0, height: height)
                let yBottom: Float = py(lat: -90.0 + Double(row) * 10.0, height: height)
                out.append(FieldRect(key: key, cell: cell, x: x0, y: yTop, width: width / 18, height: yBottom - yTop))
            }
        }
        return out
    }

    /// X positions of the 19 vertical field lines.
    public func verticalGridLines(width: Float) -> [Float] {
        (0...18).map { px(lon: -180.0 + Double($0 * 20), width: width) }
    }

    /// Y positions of the 19 horizontal field lines.
    public func horizontalGridLines(height: Float) -> [Float] {
        (0...18).map { py(lat: -90.0 + Double($0 * 10), height: height) }
    }

    /// A field label drawn at the top-left corner of a coloured field.
    public struct FieldLabel: Equatable, Sendable {
        public let key: String
        public let x: Float
        public let y: Float
    }

    /// Labels of the coloured fields, ordered by key.
    public func fieldLabels(fieldStates: [String: MultCell], width: Float, height: Float) -> [FieldLabel] {
        var out: [FieldLabel] = []
        for key in fieldStates.keys.sorted() {
            let units: [UInt16] = Array(key.utf16)
            guard units.count >= 2 else { continue }
            let col = Int(units[0]) - 0x41
            let row = Int(units[1]) - 0x41
            guard (0...17).contains(col), (0...17).contains(row) else { continue }
            let x: Float = px(lon: -180.0 + Double(col * 20) + 2, width: width)
            let y: Float = py(lat: -90.0 + Double(row + 1) * 10.0 - 1, height: height)
            out.append(FieldLabel(key: key, x: x, y: y))
        }
        return out
    }

    // MARK: - DXCC dots

    /// Marker state of a DXCC entity.
    public enum DotState: Equatable, Sendable {
        case worked
        case spotted
        case none
    }

    public struct Dot: Equatable, Sendable {
        public let lat: Double
        public let lon: Double
        public let state: DotState
    }

    /// One dot per entity with a position: worked (from the log, the QSO's stored entity or the resolved callsign),
    /// spotted (a spot's callsign resolves to it) or neither; worked wins.
    public static func dxccDots(qsos: [Qso], spots: [DxSpot], lookup: (any DxccLookup)?) -> [Dot] {
        guard let lookup else { return [] }
        var worked: Set<Int> = []
        for q in qsos where !q.deleted {
            if let entity = q.dxccEntity {
                worked.insert(entity)
            } else if let resolved = lookup.resolve(q.call) {
                worked.insert(resolved.entityCode)
            }
        }
        var spotted: Set<Int> = []
        for s in spots {
            if let resolved = lookup.resolve(s.dxCall) {
                spotted.insert(resolved.entityCode)
            }
        }
        var out: [Dot] = []
        for e in lookup.entities() where e.hasLatLon {
            let state: DotState = worked.contains(e.entityCode) ? .worked
                : (spotted.contains(e.entityCode) ? .spotted : .none)
            out.append(Dot(lat: e.lat, lon: e.lon, state: state))
        }
        return out
    }

    /// Radius of a dot (grey ones are small).
    public static func dotRadius(_ state: DotState) -> Float {
        state == .none ? 2 : 4
    }

    // MARK: - texts

    /// Title above the DXCC map: worked and spotted counts and the time of the terminator (`HH:mm'Z'`).
    public static func dxccTitle(dots: [Dot], epochMillis: Int64, translate: Translator) -> String {
        let worked: Int = dots.filter { $0.state == .worked }.count
        let spotted: Int = dots.filter { $0.state == .spotted }.count
        let seconds: Int64 = JavaMath.floorDiv(epochMillis, 1_000)
        let stamp: String = ToolsFormat.hhColonMmZ(epochSecond: seconds)
        return translate.translate("DXCC — pracováno %s zemí · %s spotovaných nových · šedá linie %s",
                                   [.int(worked), .int(spotted), .string(stamp)])
    }

    /// Title above the squares map.
    public static func squaresTitle(worked: Int, translate: Translator) -> String {
        translate.translate("Čtverce v mapě — %s mults worked", [.int(worked)])
    }

    /// Message of the squares mode without a contest.
    public static func noContestText(_ translator: Translator) -> String {
        translator.translate("Čtverce jsou násobiče gridového závodu — žádný aktivní závod.")
    }

    // MARK: - click

    /// Click on the map: the first spot whose grid begins with the clicked field (the grid comes from `gridOf`, the
    /// offline table or the callbook). `nil` without a DXCC lookup, outside the map or without a match.
    public static func tap(lon: Double, lat: Double, spots: [DxSpot], hasLookup: Bool,
                           gridOf: (String) -> String?) -> DxSpot? {
        guard let field = fieldAt(lon: lon, lat: lat), hasLookup else { return nil }
        for spot in spots {
            guard let grid = gridOf(spot.dxCall) else { continue }
            let units: [UInt16] = Array(grid.utf16)
            guard units.count >= 2 else { continue }
            if JavaText.toUpperCase(JavaChar.string(Array(units[0..<2]))) == field {
                return spot
            }
        }
        return nil
    }
}
