import Foundation
import Testing
@testable import MCLCore

/// `WaterfallPalette.heat` against the real `WaterfallWindowKt.heat(float)` (probe `rig-keying`, `heat` — 1 021 values
/// incl. NaN, ±∞, −0 and the thresholds) and `WaterfallPixels.render` against `render` (`WaterfallWindow.kt:118-128`).
@Suite struct WaterfallPixelsTests {

    @Test func heatMatchesTheJvmBitForBit() throws {
        let rows = RigKeyingProbeTable.area("heat")
        #expect(rows.count == 1_021)
        for row in rows {
            let bits = try #require(UInt32(row.input, radix: 16))
            let expected = try #require(UInt32(row.result, radix: 16))
            #expect(WaterfallPalette.heat(Float(bitPattern: bits)) == expected, "\(row.input)")
        }
    }

    @Test func noiseIsDarkBlueAndStrongSignalWhite() {
        #expect(WaterfallPalette.heat(0) == 0x00003F)
        #expect(WaterfallPalette.heat(1) == 0xFFFFFF)
        #expect(WaterfallPalette.heat(.nan) == 0)
    }

    @Test func emptyModelRendersNothing() {
        #expect(WaterfallPixels.render(rows: []) == nil)
        #expect(WaterfallPixels.render(rows: [[]]) == nil)
    }

    /// The newest row (first) is on top; rows not yet filled stay black; the width is the bin count.
    @Test func newestRowOnTopAndTheRestBlack() throws {
        let image = try #require(WaterfallPixels.render(rows: [[1, 0, 0.5], [0, 0, 0]]))
        #expect(image.width == 3)
        #expect(image.height == 300)
        #expect(image.pixels.count == 900)
        #expect(Array(image.pixels[0..<3]) == [0xFFFFFF, 0x00003F, WaterfallPalette.heat(0.5)])
        #expect(Array(image.pixels[3..<6]) == [0x00003F, 0x00003F, 0x00003F])
        #expect(image.pixels[6...].allSatisfy { $0 == 0 })
    }

    @Test func rowsBeyondTheHeightAreNotDrawn() throws {
        let rows: [[Float]] = Array(repeating: [1], count: 5)
        let image = try #require(WaterfallPixels.render(rows: rows, height: 3))
        #expect(image.pixels == [0xFFFFFF, 0xFFFFFF, 0xFFFFFF])
    }

    /// The real model: 3 kHz at 12 kHz = 512 bins, newest first.
    @Test func realModelRendersAtTheBinWidth() throws {
        let model = Waterfall(sampleRate: 12_000, maxHz: WaterfallPixels.maxHz, rows: Int32(WaterfallPixels.rows))
        let tone: [Double] = (0..<4_096).map { sin(Double($0) * 2 * .pi * 1_000 / 12_000) * 0.5 }
        model.add(tone)
        let image = try #require(WaterfallPixels.render(rows: model.normalizedRows()))
        #expect(image.width == 512)
        #expect(image.height == 300)
    }

    @Test func hoverAndPitchLineScaleWithTheWidth() {
        #expect(WaterfallPixels.audioHz(x: 380, width: 760, maxHz: 3_000) == 1_500)
        #expect(WaterfallPixels.pitchLineX(pitchHz: 600, maxHz: 3_000, width: 760) == 152)
    }
}
