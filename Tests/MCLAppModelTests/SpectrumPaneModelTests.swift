import CoreGraphics
import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// The spectrum pane of the waterfall window (N1MM+ Spectrum Display): a tone of the synthetic receiver audio becomes
/// a signal on the band, a click snaps to it, Cmd+click sets the split on a fake rigctld (loopback), the wheel moves
/// the saved levels and tunes, the zoom and the vertical layout. Nothing transmits; no audio device is opened.
@MainActor @Suite struct SpectrumPaneModelTests {

    /// A tone with a faint deterministic noise floor.
    static func noisyTone(_ hz: Double, _ n: Int, amp: Double = 0.3) -> [Double] {
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        return (0..<n).map { i in
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let noise: Double = (Double(seed >> 11) / Double(1 << 53) - 0.5) * 0.004
            return amp * sin(2 * Double.pi * hz * Double(i) / RadioSignals.sampleRate) + noise
        }
    }

    private static func refreshed(_ app: KeyingApp, _ model: WaterfallModel) async {
        app.radioClock.advance(by: 100)
        await model.settle()
        await runMainQueue()
    }

    @Test func aToneIsASignalAndAClickSnapsToItsCentre() async throws {
        let app = try await KeyingApp.make()
        let model: WaterfallModel = app.model.makeWaterfall()
        app.model.rig.tuneTo(14_025_000)
        await model.open()
        try RadioSignals.feed(app, Self.noisyTone(1_000, 4_096 * 3))
        await Self.refreshed(app, model)
        let picture: SpectrumPicture = try #require(model.picture)
        #expect(picture.count == 512)
        #expect(picture.window == 0..<512)
        let signal: SpectrumSignal = try #require(picture.signals.first { abs($0.centerHz - 14_026_000) < 30 })
        #expect(model.statsLine != nil)
        // A click 300 Hz above the signal in the spectrum lands on its centre.
        let off: Double = try #require(model.fraction(ofHz: signal.centerHz + 300))
        model.press(fraction: off, command: false, inSpectrum: true)
        #expect(abs(app.model.rig.tuning.tunedFreqHz - Int64(signal.centerHz.rounded())) <= 10)
        // The waterfall does not snap.
        let dial: Int64 = app.model.rig.tuning.tunedFreqHz
        let there: Double = try #require(model.fraction(ofHz: Double(dial) + 1_200))
        model.press(fraction: there, command: false, inSpectrum: false)
        #expect(abs(app.model.rig.tuning.tunedFreqHz - (dial + 1_200)) <= 10)
        // Snap off: the click tunes where it is.
        model.updateSetup { $0.set(.snapToSignal, flag: false) }
        #expect(app.model.config.config.spectrumSetup == ["snapToSignal": "false"])
        let dial2: Int64 = app.model.rig.tuning.tunedFreqHz
        let near: Double = try #require(model.fraction(ofHz: Double(dial2) + 700))
        model.press(fraction: near, command: false, inSpectrum: true)
        #expect(abs(app.model.rig.tuning.tunedFreqHz - (dial2 + 700)) <= 10)
        model.close()
        await app.settle()
    }

    @Test func theWheelMovesTheSavedLevelsAndTunes() async throws {
        let app = try await KeyingApp.make()
        let model: WaterfallModel = app.model.makeWaterfall()
        model.wheelLevels(3, target: .threshold)
        model.wheelLevels(2, target: .reference)
        model.wheelLevels(1, target: .range)
        #expect(app.model.config.config.spectrum.scale == SpectrumScale(thresholdDb: 13, refDb: 2, rangeDb: 55))
        #expect(model.setup.scale.thresholdDb == 13)
        // Without a frequency the wheel does not tune.
        model.wheelTune(1, large: false)
        #expect(app.model.rig.tuning.tunedFreqHz == 0)
        app.model.rig.tuneTo(7_010_000)
        let step: Int64 = app.model.rig.tuneStepHz(.cw)
        model.wheelTune(2, large: false)
        #expect(app.model.rig.tuning.tunedFreqHz == 7_010_000 + 2 * step)
        model.wheelTune(-1, large: true)
        #expect(app.model.rig.tuning.tunedFreqHz == 7_010_000 + 2 * step - 10 * step)
    }

    @Test func theZoomAndTheVerticalLayout() async throws {
        let app = try await KeyingApp.make()
        let model: WaterfallModel = app.model.makeWaterfall()
        app.model.rig.tuneTo(14_025_000)
        await model.open()
        try RadioSignals.feed(app, Self.noisyTone(1_000, 4_096 * 3))
        model.zoom(by: 1)
        #expect(model.zoom == 2)
        await Self.refreshed(app, model)
        let zoomed: SpectrumPicture = try #require(model.picture)
        #expect(zoomed.window.count == 256)
        let image: CGImage = try #require(model.image)
        #expect(image.width == 256)
        #expect(image.height == 300)
        // Mode "?" is upper sideband: the dial is the left edge, the zoom stays at the start of the audio.
        #expect(zoomed.window == 0..<256)
        model.zoom(by: -1)
        model.zoom(by: -1)
        #expect(model.zoom == 1)
        await model.settle()
        await runMainQueue()
        // A tall window turns the panes: the waterfall runs right to left, the frequency up.
        model.layout(width: 300, height: 800)
        #expect(!model.isHorizontal)
        await Self.refreshed(app, model)
        let turned: CGImage = try #require(model.image)
        #expect(turned.width == 300)
        #expect(turned.height == 512)
        model.updateSetup { $0.orientation = .horizontal }
        model.layout(width: 300, height: 800)
        #expect(model.isHorizontal)
        model.close()
        await app.settle()
    }

    @Test func commandClickSetsTheSplitAndTheTxLineFollowsTheRig() async throws {
        let fake = try FakeRigctld(freqHz: 14_025_000, mode: "CW")
        fake.setSplit(true, txHz: 14_025_500)
        let rigApp = try await RigApp.make { config, _ in
            config.rig = fakeRigConfig(fake.port)
            config.cwPitchHz = 600
        }
        await rigApp.connect()
        await rigApp.settle()
        let model: WaterfallModel = rigApp.model.makeWaterfall()
        #expect(model.txHz == 14_025_500)
        // CW: the audio covers 14024.4 … 14027.4 kHz, the RX line is the CW pitch.
        let rx: Double = try #require(model.pitchLine)
        #expect(abs(rx - 0.2) < 1e-9)
        let tx: Double = try #require(model.txLine)
        #expect(abs(tx - 1_100.0 / 3_000) < 1e-9)
        model.press(fraction: 0.5, command: true, inSpectrum: true)
        await rigApp.settle()
        #expect(fake.writes.contains("I 14025900"))
        // The RX frequency stayed.
        #expect(!fake.writes.contains("F 14025900"))
    }
}
