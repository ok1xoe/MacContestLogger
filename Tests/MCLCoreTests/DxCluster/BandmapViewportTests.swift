import Foundation
import Testing
@testable import MCLCore

/// The probe table a maintainer-only probe, read from the repository.
/// Inputs and results escape control characters, NBSP and the backslash as `\uXXXX`.
enum SpotsCoreProbeTable {

    struct Row: Equatable {
        let area: String
        let input: String
        let result: String
    }

    static let rows: [Row] = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/jvm-probes/spots-core-probe.tsv")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").map { line in
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            return Row(area: parts[0], input: unescape(parts[1]), result: parts.count > 2 ? unescape(parts[2]) : "")
        }
    }()

    static func area(_ name: String) -> [Row] {
        rows.filter { $0.area == name }
    }

    /// `\uXXXX` → the UTF-16 unit.
    static func unescape(_ text: String) -> String {
        var units: [UInt16] = []
        let source = Array(text.utf16)
        var index = 0
        while index < source.count {
            if source[index] == 0x5C, index + 5 < source.count, source[index + 1] == 0x75,
               let value = UInt16(String(utf16CodeUnits: Array(source[(index + 2)..<(index + 6)]), count: 4),
                                  radix: 16) {
                units.append(value)
                index += 6
            } else {
                units.append(source[index])
                index += 1
            }
        }
        return String(utf16CodeUnits: units, count: units.count)
    }

    /// The raw bits of a probe float `1.5/3fc00000`.
    static func bits(_ text: Substring) -> UInt32? {
        guard let slash = text.lastIndex(of: "/") else { return nil }
        return UInt32(text[text.index(after: slash)...], radix: 16)
    }
}

/// `BandmapViewport` and `BandmapLayout` against the Kotlin band map (`ui/BandmapWindow.kt` of v1.1.1) measured on the
/// JVM (maintainer-only probe): the real private `niceStepHz`, `layoutSpots`, `hitSpot` and `azimuthOf`
/// through reflection, the inlined `zoomTo`, wheel, `freqAt`, drag, CQ hit, `yAt` and tick expressions.
@Suite struct BandmapViewportTests {

    static let twenty: ClosedRange<Int64> = 14_000_000...14_350_000

    @Test func probeTableIsPresent() {
        #expect(SpotsCoreProbeTable.rows.count > 350)
    }

    @Test func niceStepMatchesTheJvm() throws {
        let rows = SpotsCoreProbeTable.area("nice")
        #expect(rows.count == 39)
        for row in rows {
            let rough = try #require(Int64(row.input))
            #expect(String(BandmapViewport.niceStepHz(rough)) == row.result, "\(row.input)")
        }
    }

    @Test func ticksAndLabelsMatchTheJvm() throws {
        let rows = SpotsCoreProbeTable.area("ticks")
        #expect(rows.count == 11)
        for row in rows {
            let parts = row.input.split(separator: " ").compactMap { Int64($0) }
            let viewport = BandmapViewport(loHz: parts[0], hiHz: parts[1])
            let step = BandmapViewport.niceStepHz(viewport.spanHz / 10)
            var text = String(step) + ":"
            for tick in viewport.ticks {
                text += " " + String(tick) + "=" + BandmapViewport.tickLabel(tick)
            }
            #expect(text == row.result, "\(row.input)")
        }
    }

    @Test func yAtMatchesTheJvmBitForBit() throws {
        let rows = SpotsCoreProbeTable.area("yAt")
        #expect(rows.count == 28)
        for row in rows {
            let parts = row.input.split(separator: " ")
            let hz = try #require(Int64(parts[0]))
            let viewport = BandmapViewport(loHz: try #require(Int64(parts[1])), hiHz: try #require(Int64(parts[2])))
            let height = try #require(Float(parts[3]))
            let expected = try #require(SpotsCoreProbeTable.bits(row.result[...]))
            #expect(viewport.yAt(hz, height: height).bitPattern == expected, "\(row.input)")
        }
    }

    // MARK: - layout and hit

    struct LayoutCase {
        let name: String
        let spots: [DxSpot]
        let lo: Int64
        let hi: Int64
        let height: Float
        let rowH: Float
    }

    static func spots(_ data: [(String, Int)]) -> [DxSpot] {
        data.map { DxSpot(spotter: "S", freqHz: $0.1, dxCall: $0.0, comment: "") }
    }

    /// The same cases as `SpotsCoreProbe.layoutCases`.
    static let layoutCases: [LayoutCase] = [
        LayoutCase(name: "sparse", spots: spots([("A", 14_010_000), ("B", 14_100_000), ("C", 14_300_000)]),
                   lo: 14_000_000, hi: 14_350_000, height: 640, rowH: 15),
        LayoutCase(name: "dense",
                   spots: spots([("A", 14_025_000), ("B", 14_025_100), ("C", 14_025_200), ("D", 14_025_300)]),
                   lo: 14_000_000, hi: 14_350_000, height: 640, rowH: 15),
        LayoutCase(name: "outside",
                   spots: spots([("X", 13_999_999), ("A", 14_000_000), ("Z", 14_350_001), ("B", 14_350_000)]),
                   lo: 14_000_000, hi: 14_350_000, height: 400, rowH: 17),
        LayoutCase(name: "unsorted", spots: spots([("C", 14_200_000), ("A", 14_001_000), ("B", 14_001_000)]),
                   lo: 14_000_000, hi: 14_350_000, height: 300, rowH: 14),
        LayoutCase(name: "edgeTop", spots: spots([("A", 14_000_000), ("B", 14_000_010), ("C", 14_000_020)]),
                   lo: 14_000_000, hi: 14_350_000, height: 640, rowH: 16),
        LayoutCase(name: "edgeBottom", spots: spots([("A", 14_349_980), ("B", 14_349_990), ("C", 14_350_000)]),
                   lo: 14_000_000, hi: 14_350_000, height: 640, rowH: 16),
        LayoutCase(name: "overflow",
                   spots: spots([("A", 14_100_000), ("B", 14_100_001), ("C", 14_100_002), ("D", 14_100_003)]),
                   lo: 14_000_000, hi: 14_350_000, height: 80, rowH: 15),
        LayoutCase(name: "zero", spots: spots([("A", 5)]), lo: 5, hi: 5, height: 100, rowH: 10),
        LayoutCase(name: "empty", spots: [], lo: 14_000_000, hi: 14_350_000, height: 640, rowH: 15),
        LayoutCase(name: "tight", spots: spots([("A", 14_100_000), ("B", 14_100_000), ("C", 14_100_000)]),
                   lo: 14_000_000, hi: 14_350_000, height: 640, rowH: 8),
        LayoutCase(name: "vhf", spots: spots([("A", 144_050_000), ("B", 144_050_016), ("C", 144_300_000)]),
                   lo: 144_000_000, hi: 146_000_000, height: 777, rowH: 13.5),
    ]

    static func placements(_ layout: LayoutCase) -> [SpotPlacement] {
        BandmapLayout.place(spots: layout.spots, viewport: BandmapViewport(loHz: layout.lo, hiHz: layout.hi),
                            height: layout.height, rowH: layout.rowH)
    }

    @Test func layoutMatchesTheJvmBitForBit() throws {
        let rows = SpotsCoreProbeTable.area("layout")
        #expect(rows.count == Self.layoutCases.count)
        for layout in Self.layoutCases {
            let row = try #require(rows.first { $0.input == layout.name })
            let expected: [(String, UInt32, UInt32)] = try row.result.split(separator: " ").map { token in
                let at = try #require(token.firstIndex(of: "@"))
                let arrow = try #require(token.firstIndex(of: ">"))
                let trueY = try #require(SpotsCoreProbeTable.bits(token[token.index(after: at)..<arrow]))
                let labelY = try #require(SpotsCoreProbeTable.bits(token[token.index(after: arrow)...]))
                return (String(token[..<at]), trueY, labelY)
            }
            let actual = Self.placements(layout)
            #expect(actual.count == expected.count, "\(layout.name)")
            for (placed, want) in zip(actual, expected) {
                #expect(placed.spot.dxCall == want.0, "\(layout.name)")
                #expect(placed.trueY.bitPattern == want.1, "\(layout.name) \(want.0) trueY")
                #expect(placed.labelY.bitPattern == want.2, "\(layout.name) \(want.0) labelY")
            }
        }
    }

    @Test func hitSpotMatchesTheJvm() throws {
        let rows = SpotsCoreProbeTable.area("hit")
        #expect(rows.count == Self.layoutCases.count)
        for layout in Self.layoutCases {
            let row = try #require(rows.first { $0.input == layout.name })
            let placements = Self.placements(layout)
            for token in row.result.split(separator: " ") {
                let pair = token.split(separator: "=")
                let y = try #require(Float(pair[0]))
                let hit = BandmapLayout.hitSpot(placements, y: y, rowH: layout.rowH)
                #expect((hit?.spot.dxCall ?? "-") == String(pair[1]), "\(layout.name) y=\(y)")
            }
        }
    }

    // MARK: - zoom, wheel, drag

    static func viewportFrom(_ parts: [Int64]) -> (tuned: Int64, viewport: BandmapViewport) {
        (parts[0], BandmapViewport(loHz: parts[1], hiHz: parts[2]))
    }

    @Test func zoomButtonsMatchTheJvm() throws {
        for area in ["zoomIn", "zoomOut"] {
            let rows = SpotsCoreProbeTable.area(area)
            #expect(rows.count == 9)
            for row in rows {
                let parts = row.input.split(separator: " ").compactMap { Int64($0) }
                let start = Self.viewportFrom(parts)
                let tuned = start.tuned
                var viewport = start.viewport
                let bounds = parts[3]...parts[4]
                if area == "zoomIn" {
                    viewport.zoomIn(tunedHz: tuned, bounds: bounds)
                } else {
                    viewport.zoomOut(tunedHz: tuned, bounds: bounds)
                }
                #expect("\(viewport.loHz) \(viewport.hiHz)" == row.result, "\(area) \(row.input)")
            }
        }
    }

    @Test func wheelMatchesTheJvm() throws {
        let rows = SpotsCoreProbeTable.area("wheel")
        #expect(rows.count == 144)
        for row in rows {
            let parts = row.input.split(separator: " ")
            let numbers = parts.prefix(3).compactMap { Int64($0) }
            let start = Self.viewportFrom(numbers)
            var viewport = start.viewport
            let dx = try #require(Float(parts[3].dropFirst(3)))
            let dy = try #require(Float(parts[4].dropFirst(3)))
            let modifier = parts.count > 5 ? String(parts[5]) : ""
            let qsy = viewport.wheel(dx: dx, dy: dy, ctrl: modifier == "ctrl", shift: modifier == "shift",
                                     tunedHz: start.tuned, bounds: Self.twenty, stepHz: 100, stepShiftHz: 1000)
            let text = qsy.map { "qsy \($0) \(viewport.loHz) \(viewport.hiHz)" } ?? "zoom \(viewport.loHz) \(viewport.hiHz)"
            #expect(text == row.result, "\(row.input)")
        }
    }

    @Test func freqAtMatchesTheJvm() throws {
        let rows = SpotsCoreProbeTable.area("freqAt")
        #expect(rows.count == 10)
        for row in rows {
            let parts = row.input.split(separator: " ")
            let viewport = BandmapViewport(loHz: try #require(Int64(parts[0])), hiHz: try #require(Int64(parts[1])))
            let height = try #require(Float(parts[2]))
            for token in row.result.split(separator: " ") {
                let pair = token.split(separator: "=")
                let y = try #require(Float(pair[0]))
                #expect(String(viewport.freqAt(y, height: height)) == String(pair[1]), "\(row.input) y=\(y)")
            }
        }
    }

    @Test func dragZoomMatchesTheJvm() throws {
        let rows = SpotsCoreProbeTable.area("drag")
        #expect(rows.count == 30)
        for row in rows {
            let parts = row.input.split(separator: " ")
            let lo = try #require(Int64(parts[0]))
            let hi = try #require(Int64(parts[1]))
            var viewport = BandmapViewport(loHz: lo, hiHz: hi)
            let zoomed = viewport.dragZoom(from: try #require(Float(parts[2])), to: try #require(Float(parts[3])),
                                           height: 640, bounds: lo...hi)
            let text = zoomed ? "\(viewport.loHz) \(viewport.hiHz)" : "none"
            #expect(text == row.result, "\(row.input)")
        }
    }

    @Test func cqMarkerHitMatchesTheJvm() throws {
        let rows = SpotsCoreProbeTable.area("cq")
        #expect(rows.count == 4)
        for row in rows {
            let parts = row.input.split(separator: " ").compactMap { Int64($0) }
            let viewport = BandmapViewport(loHz: parts[1], hiHz: parts[2])
            let tokens = row.result.split(separator: " ")
            let cqY = try #require(SpotsCoreProbeTable.bits(tokens[0]))
            #expect(viewport.yAt(parts[0], height: 640).bitPattern == cqY, "\(row.input)")
            for token in tokens.dropFirst() {
                let pair = token.split(separator: "=")
                let y = try #require(Float(pair[0]))
                let hit = viewport.hitsCqMarker(cqHz: parts[0], x: 0, y: y, axisX: 1, height: 640)
                #expect(String(hit) == String(pair[1]), "\(row.input) y=\(y)")
            }
        }
    }

    /// `BM:290`: the CQ marker counts only left of the axis, inside the window and when a CQ frequency exists.
    @Test func cqMarkerNeedsTheLeftSideAndTheWindow() {
        let viewport = BandmapViewport(loHz: 14_000_000, hiHz: 14_350_000)
        #expect(viewport.hitsCqMarker(cqHz: 14_000_000, x: 10, y: 24, axisX: 50, height: 640))
        #expect(!viewport.hitsCqMarker(cqHz: 14_000_000, x: 50, y: 24, axisX: 50, height: 640))
        #expect(!viewport.hitsCqMarker(cqHz: 13_999_999, x: 10, y: 24, axisX: 50, height: 640))
        #expect(!viewport.hitsCqMarker(cqHz: nil, x: 10, y: 24, axisX: 50, height: 640))
    }

    // MARK: - azimuth

    struct FakeLookup: DxccLookup {
        let lat: Double
        let lon: Double

        func resolve(_ callsign: String?) -> DxccEntity? {
            guard let callsign, callsign.hasPrefix("K") else { return nil }
            let lat: Double = callsign == "KNAN" ? .nan : self.lat
            return DxccEntity(entityCode: 291, name: "USA", countryCode: "K", continents: ["NA"], cq: [5], itu: [8],
                              lat: lat, lon: lon, primaryPrefix: "K")
        }

        func entities() -> [DxccEntity] { [] }
    }

    @Test func azimuthMatchesTheJvm() throws {
        let rows = SpotsCoreProbeTable.area("azimuth")
        #expect(rows.count == 48)
        for row in rows {
            let parts = row.input.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
            let lookup = FakeLookup(lat: try #require(Double(parts[1])), lon: try #require(Double(parts[2])))
            let latLon = Maidenhead.centerLatLon(parts[0])
            let azimuth = BandmapLayout.azimuthOf(call: parts[3], myLatLon: latLon, dxcc: lookup)
            #expect((azimuth.map(String.init) ?? "null") == row.result, "\(row.input)")
        }
    }

    // MARK: - from the source

    /// `remember(band)`: the whole band; no band = `0..1`.
    @Test func resetShowsTheWholeBand() {
        var viewport = BandmapViewport(loHz: 14_020_000, hiHz: 14_021_000)
        viewport.reset(band: .m40)
        #expect(viewport == BandmapViewport(loHz: 7_000_000, hiHz: 7_300_000))
        viewport.reset(band: nil)
        #expect(viewport == BandmapViewport(loHz: 0, hiHz: 1))
        #expect(BandmapViewport.bounds(.m2) == 144_000_000...148_000_000)
    }

    /// A click (`BM:284-306`): the CQ marker wins, then a spot right of the axis, otherwise a QSY under the cursor.
    @Test func tapPicksCqThenSpotThenQsy() {
        let viewport = BandmapViewport(loHz: 14_000_000, hiHz: 14_350_000)
        let spots = Self.spots([("A", 14_010_000), ("B", 14_100_000)])
        let onA: Float = viewport.yAt(14_010_000, height: 640)
        #expect(BandmapLayout.tap(x: 200, y: onA, viewport: viewport, height: 640, axisX: 60, rowH: 15, spots: spots,
                                  cqHz: nil) == .spot(spots[0]))
        // Left of the axis the spot is not hit; the click QSYs.
        #expect(BandmapLayout.tap(x: 30, y: onA, viewport: viewport, height: 640, axisX: 60, rowH: 15, spots: spots,
                                  cqHz: nil) == .qsy(viewport.freqAt(onA, height: 640)))
        #expect(BandmapLayout.tap(x: 30, y: onA, viewport: viewport, height: 640, axisX: 60, rowH: 15, spots: spots,
                                  cqHz: 14_010_000) == .cqFrequency)
        #expect(BandmapLayout.tap(x: 200, y: 300, viewport: viewport, height: 640, axisX: 60, rowH: 15, spots: spots,
                                  cqHz: nil) == .qsy(14_163_176))
        #expect(BandmapLayout.menuSpot(x: 200, y: onA, viewport: viewport, height: 640, axisX: 60, rowH: 15,
                                       spots: spots) == spots[0])
        #expect(BandmapLayout.menuSpot(x: 60, y: onA, viewport: viewport, height: 640, axisX: 60, rowH: 15,
                                       spots: spots) == nil)
    }

    /// The label (`BM:546-550`): azimuth when known, skimmer count from two.
    @Test func labelText() {
        #expect(BandmapLayout.labelText(call: "OK1ABC", azimuth: nil, skimmers: 0) == "OK1ABC")
        #expect(BandmapLayout.labelText(call: "OK1ABC", azimuth: 0, skimmers: 1) == "OK1ABC 0°")
        #expect(BandmapLayout.labelText(call: "K1ABC", azimuth: 298, skimmers: 3) == "K1ABC 298° ×3")
        #expect(BandmapLayout.labelText(call: "K1ABC", azimuth: nil, skimmers: 2) == "K1ABC ×2")
    }

    @Test func fontsAreClamped() {
        #expect(BandmapViewport.spotFont(7) == 8)
        #expect(BandmapViewport.spotFont(29) == 28)
        #expect(BandmapViewport.spotFont(BandmapViewport.defaultSpotFont) == 11)
        #expect(BandmapViewport.axisFont(spotFont: 11) == 10)
        #expect(BandmapViewport.axisFont(spotFont: 8) == 7)
        #expect(BandmapViewport.axisFont(spotFont: 2) == 7)
    }

    /// Every real band is at least 1 kHz wide, so Kotlin's `coerceIn(1000L, bandSpan)` never throws.
    @Test func everyBandIsWiderThanTheMinimumZoom() {
        for band in Band.allCases {
            #expect(Int64(band.highHz - band.lowHz) >= BandmapViewport.minSpanHz, "\(band)")
        }
    }
}

/// The microwave bands (post-port): the default window is 2 MHz around the tuned frequency, not the whole band.
@Suite struct MicrowaveBandmapViewportTests {

    private static let mhz: Int64 = 1_000_000

    @Test func aMicrowaveBandOpensOnATwoMegahertzWindowAroundTheTunedFrequency() {
        let viewport = BandmapViewport(band: .cm3, tunedHz: 10_489_750_000)
        #expect(viewport.loHz == 10_488_750_000 && viewport.hiHz == 10_490_750_000)
        #expect(viewport.spanHz == 2 * Self.mhz)
    }

    @Test func theWindowIsPushedInsideTheBand() {
        let low = BandmapViewport(band: .cm3, tunedHz: 10_000_100_000)
        #expect(low.loHz == 10_000_000_000 && low.hiHz == 10_002_000_000)
        let high = BandmapViewport(band: .cm23, tunedHz: 1_299_900_000)
        #expect(high.loHz == 1_298_000_000 && high.hiHz == 1_300_000_000)
    }

    @Test func aTunedFrequencyOutsideTheBandOpensAtTheLowerEdge() {
        let viewport = BandmapViewport(band: .cm13, tunedHz: 144_300_000)
        #expect(viewport.loHz == 2_300_000_000 && viewport.hiHz == 2_302_000_000)
    }

    @Test func oldBandsKeepTheWholeBand() {
        for band in Band.javaV111Cases {
            #expect(BandmapViewport(band: band, tunedHz: Int64(band.lowHz + 1_000)) == BandmapViewport(band: band))
        }
        #expect(BandmapViewport(band: .m2, tunedHz: 144_300_000).spanHz == 4 * Self.mhz)
        #expect(BandmapViewport(band: nil, tunedHz: 0) == BandmapViewport(band: nil))
    }

    @Test func zoomingOutReachesTheWholeBand() {
        var viewport = BandmapViewport(band: .cm3, tunedHz: 10_368_100_000)
        let bounds = BandmapViewport.bounds(.cm3)
        for _ in 0..<12 { viewport.zoomOut(tunedHz: 10_368_100_000, bounds: bounds) }
        #expect(viewport.loHz == 10_000_000_000 && viewport.hiHz == 10_500_000_000)
    }

    @Test func aClickOnA3cmWindowIsNotQuantisedToKilohertz() {
        let viewport = BandmapViewport(band: .cm3, tunedHz: 10_489_750_000)
        let height: Float = 600
        let y: Float = BandmapViewport.padTop + BandmapViewport.usable(height) / 2
        // The middle of the window is the tuned frequency; a Float sum would give 10 489 749 ~ 10 489 750 kHz steps.
        #expect(viewport.freqAt(y, height: height) == 10_489_750_000)
        let y2: Float = y + 1
        let step: Int64 = viewport.freqAt(y2, height: height) - viewport.freqAt(y, height: height)
        #expect(step > 3_000 && step < 3_700, "one pixel is about 3.4 kHz of a 2 MHz window: \(step)")
    }
}
