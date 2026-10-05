import CoreGraphics
import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// The waterfall window (`WaterfallWindow.kt`): the audio queue feeds the FFT rows, every 100 ms the
/// image is rendered off the main actor into a `CGImage` with the same pixels as `WaterfallPixels`; the info line,
/// the hover, the click and the receiver audio held only while the window is open. The audio is synthetic PCM.
@MainActor @Suite struct WaterfallModelTests {

    /// Renders and reads back one pixel of `image` as 0x00RRGGBB (drawn 1:1 into an sRGB RGBA bitmap).
    private static func pixel(_ image: CGImage, x: Int, y: Int) throws -> UInt32 {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let drawn: Bool = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                                          bitsPerComponent: 8, bytesPerRow: image.width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        try #require(drawn)
        // The bitmap's first row in memory is the image's top row.
        let base: Int = (y * image.width + x) * 4
        return UInt32(bytes[base]) << 16 | UInt32(bytes[base + 1]) << 8 | UInt32(bytes[base + 2])
    }

    /// A 1 kHz tone: after the 100 ms refresh the image is the rendering of the model's rows (one pixel per bin,
    /// 300 rows, the newest on top) and its brightest top pixel sits at the tone's bin.
    @Test func pixelsFromBlocks() async throws {
        let app = try await KeyingApp.make()
        let waterfall: WaterfallModel = app.model.makeWaterfall()
        await waterfall.open()
        #expect(app.model.audio.userNames == ["waterfall"])
        try RadioSignals.feed(app, RadioSignals.tone(1_000, 4_096 * 3, 0.5))
        app.radioClock.advance(by: 100)
        await waterfall.settle()
        await runMainQueue()
        let image: CGImage = try #require(waterfall.image)
        let expected = try #require(WaterfallPixels.render(rows: waterfall.waterfall.normalizedRows()))
        #expect(image.width == expected.width)
        #expect(image.height == 300)
        let bin: Int = Int((1_000 / waterfall.waterfall.maxHz * Double(expected.width)).rounded())
        let row: ArraySlice<UInt32> = expected.pixels[0..<expected.width]
        let brightest: UInt32 = try #require(row.max())
        #expect(row[bin] == brightest)
        #expect(try #require(row.min()) < brightest)
        for x in [0, bin, expected.width / 2, expected.width - 1] {
            #expect(try Self.pixel(image, x: x, y: 0) == expected.pixels[x])
        }
        // An unfilled row is black.
        #expect(try Self.pixel(image, x: bin, y: 299) == 0)
        waterfall.close()
        await app.settle()
        #expect(app.model.audio.userNames.isEmpty)
        #expect(!app.model.audio.capture.isRunning)
        #expect(app.radioClock.pendingCount == 0)
    }

    /// `0x00RRGGBB` → `CGImage` keeps every channel (red, green, blue in their bytes).
    @Test func cgImageChannels() throws {
        let pixels: [UInt32] = [0x00FF_0000, 0x0000_FF00, 0x0000_00FF, 0x0012_3456]
        let image = try #require(WaterfallModel.cgImage(WaterfallPixels.Image(width: 2, height: 2, pixels: pixels)))
        #expect(try Self.pixel(image, x: 0, y: 0) == 0xFF_0000)
        #expect(try Self.pixel(image, x: 1, y: 0) == 0x00_FF00)
        #expect(try Self.pixel(image, x: 0, y: 1) == 0x00_00FF)
        #expect(try Self.pixel(image, x: 1, y: 1) == 0x12_3456)
    }

    /// A render still on the lane when the window closes does not set the image.
    @Test func renderAfterCloseIsDropped() async throws {
        let app = try await KeyingApp.make()
        let waterfall: WaterfallModel = app.model.makeWaterfall()
        await waterfall.open()
        try RadioSignals.feed(app, RadioSignals.tone(1_000, 4_096 * 3, 0.5))
        waterfall.refresh()
        waterfall.close()
        await waterfall.settle()
        await runMainQueue()
        #expect(waterfall.image == nil)
    }

    /// The info line: mode „?" and the pitch; the hover shows the frequency on the band from the tuned frequency
    /// (no rig state); a press tunes only with a known dial frequency.
    @Test func infoHoverAndClick() async throws {
        let app = try await KeyingApp.make(configure: { config, _ in config.cwPitchHz = 550 })
        let waterfall: WaterfallModel = app.model.makeWaterfall()
        #expect(waterfall.infoLine.text.czech == "0–3 kHz audia přijímače · mód ? · CW tón 550 Hz")
        #expect(!waterfall.infoLine.isError)
        #expect(waterfall.pitchLine == nil)
        #expect(waterfall.pitchLineX(width: 300) == nil)
        waterfall.click(x: 100, width: 300)
        #expect(app.model.rig.tuning.tunedFreqHz == 0)
        app.model.rig.tuneTo(14_025_000)
        waterfall.hover(x: 150, width: 300)
        #expect(waterfall.hoverHz == 1_500)
        let rf: Int64 = AudioToRf.rfHz(dialHz: 14_025_000, rawMode: "", audioHz: 1_500, cwPitch: 550)
        #expect(waterfall.infoLine.text.czech == RadioWindowTexts.waterfallHover(audioHz: 1_500, rfHz: rf))
        #expect(waterfall.infoLine.text.czech == "audio 1500 Hz → 14026.50 kHz")
        waterfall.click(x: 150, width: 300)
        #expect(app.model.rig.tuning.tunedFreqHz == rf)
        waterfall.hoverEnded()
        #expect(waterfall.infoLine.text.czech == "0–3 kHz audia přijímače · mód ? · CW tón 550 Hz")
    }

    /// A failed input replaces the info line with the error.
    @Test func audioError() async throws {
        let app = try await KeyingApp.make()
        app.keying.failAudio("busy")
        let waterfall: WaterfallModel = app.model.makeWaterfall()
        await waterfall.open()
        #expect(waterfall.infoLine.isError)
        #expect(waterfall.infoLine.text.czech
            == "Zvukový vstup: Zvukový vstup není dostupný: busy (Nastavení → Audio → Vstup přijímače)")
        #expect(app.model.audio.userNames.isEmpty)
        waterfall.close()
    }

    /// The window went before its opening task ran: the cancelled `open()` holds nothing (no listener, no input, no
    /// refresh).
    @Test func cancelledOpenHoldsNothing() async throws {
        let app = try await KeyingApp.make()
        let model = app.model.makeWaterfall()
        let opening = Task { await model.open() }
        opening.cancel()
        await opening.value
        model.close()
        await app.settle()
        #expect(app.model.audio.userNames.isEmpty)
        #expect(app.keying.events.isEmpty)
        #expect(app.radioClock.pendingCount == 0)
    }

    /// The opening is cancelled while the input is starting (and no close follows): the model gives back the input
    /// and the listener itself.
    @Test func openCancelledDuringTheStartReleases() async throws {
        let app = try await KeyingApp.make()
        let model = app.model.makeWaterfall()
        app.keying.holdAudioStart()
        let opening = Task { await model.open() }
        await eventually("start in flight") { app.keying.events.count == 1 }
        opening.cancel()
        app.keying.releaseAudioStart()
        await opening.value
        await app.settle()
        #expect(app.model.audio.userNames.isEmpty)
        #expect(!app.model.audio.capture.isRunning)
        #expect(app.radioClock.pendingCount == 0)
    }

    /// A model that goes away open (its window never closed it) gives the input back as a last resort.
    @Test func modelGoneWithoutCloseReleases() async throws {
        let app = try await KeyingApp.make()
        do {
            let model = app.model.makeWaterfall()
            await model.open()
            #expect(app.model.audio.userNames == ["waterfall"])
        }
        await eventually("released") { app.model.audio.userNames.isEmpty }
        await app.settle()
        #expect(!app.model.audio.capture.isRunning)
    }
}
