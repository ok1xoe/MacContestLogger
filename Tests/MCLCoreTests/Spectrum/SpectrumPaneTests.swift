import Foundation
import Testing
@testable import MCLCore

/// The spectrum display's core (N1MM+ Spectrum Display): the options map, the frame axis of the receiver audio, the
/// wheel scale, the zoom window, the decaying trace with static rejection, signal detection and snapping, the
/// waterfall crop and vertical image, and the shared pipeline. Synthetic levels only.
@Suite struct SpectrumPaneTests {

    /// A flat noise floor at `floor` dB with Gaussian-like bumps (centre bin, height dB, half width in bins).
    static func levels(_ count: Int, floor: Double = -100, bumps: [(Int, Double, Int)] = []) -> [Double] {
        var out = [Double](repeating: floor, count: count)
        for (center, height, half) in bumps {
            for i in Swift.max(0, center - half)...Swift.min(count - 1, center + half) {
                let d: Double = Double(i - center) / Double(Swift.max(1, half))
                out[i] = Swift.max(out[i], floor + height * (1 - d * d))
            }
        }
        return out
    }

    // MARK: - setup

    @Test func defaultsAreNotStoredAndNumbersAreClamped() {
        var setup = SpectrumSetup(["orientation": "auto", "unknown": "x", "noiseAsLine": "true"])
        #expect(setup.values == ["noiseAsLine": "true"])
        #expect(setup.orientation == .auto)
        #expect(setup.flag(.snapToSignal))
        #expect(setup.flag(.showWaterfall))
        #expect(!setup.flag(.reduceSmearing))
        #expect(setup.decaySpeed == .medium)
        #expect(setup.background == .black)
        #expect(setup.sizeFactor == 40)
        setup.sizeFactor = 95
        #expect(setup.sizeFactor == 80)
        setup.set(.sizeFactor, "abc")
        #expect(setup.sizeFactor == 40)
        setup.set(.thresholdDb, "500")
        #expect(setup.scale.thresholdDb == 60)
        setup.orientation = .vertical
        setup.decaySpeed = .fast
        setup.background = .white
        #expect(setup.values["orientation"] == "vertical")
        #expect(setup.decaySpeed.dbPerSecond == 40)
        setup.orientation = .auto
        #expect(setup.values["orientation"] == nil)
        setup.set(.orientation, "sideways")
        #expect(setup.orientation == .auto)
    }

    @Test func theSetupIsKeptInTheConfigurationAndOldConfigsLoad() throws {
        var config = AppConfig()
        var setup: SpectrumSetup = config.spectrum
        setup.scale = SpectrumScale(thresholdDb: 14, refDb: -5, rangeDb: 80)
        config.spectrum = setup
        #expect(config.spectrumSetup == ["thresholdDb": "14", "refDb": "-5", "rangeDb": "80"])
        let data: Data = try JSONEncoder().encode(config)
        let decoded: AppConfig = try JSONDecoder().decode(AppConfig.self, from: data)
        #expect(decoded.spectrum.scale == SpectrumScale(thresholdDb: 14, refDb: -5, rangeDb: 80))
        let old: AppConfig = try JSONDecoder().decode(AppConfig.self, from: Data("{}".utf8))
        #expect(old.spectrumSetup.isEmpty)
        #expect(old.spectrum.scale == SpectrumScale())
    }

    @Test func orientationFollowsTheShapeOnAuto() {
        #expect(SpectrumOrientation.auto.isHorizontal(width: 800, height: 300))
        #expect(!SpectrumOrientation.auto.isHorizontal(width: 300, height: 800))
        #expect(SpectrumOrientation.horizontal.isHorizontal(width: 300, height: 800))
        #expect(!SpectrumOrientation.vertical.isHorizontal(width: 800, height: 300))
    }

    // MARK: - the frame axis

    @Test func audioBinsGoOnTheBandByMode() {
        let row = [Double](repeating: -90, count: 512)
        let usb = SpectrumFrame.audio(levelsDb: row, maxHz: 3_000, dialHz: 14_200_000, rawMode: "USB", cwPitch: 600)
        #expect(usb.startHz == 14_200_000)
        #expect(usb.stepHz == 3_000.0 / 512)
        #expect(usb.hz(atBin: 256) == 14_201_500)
        let cw = SpectrumFrame.audio(levelsDb: row, maxHz: 3_000, dialHz: 14_025_000, rawMode: "CW", cwPitch: 600)
        // The CW pitch sits on the dial frequency.
        #expect(Swift.abs(cw.hz(atBin: 600 / cw.stepHz) - 14_025_000) < 1e-6)
        let lsb = SpectrumFrame.audio(levelsDb: row, maxHz: 3_000, dialHz: 7_100_000, rawMode: "LSB", cwPitch: 600)
        #expect(lsb.stepHz < 0)
        #expect(lsb.hz(atBin: 512) == 7_097_000)
        let lowest: Double = 7_100_000 - 3_000.0 * 511 / 512
        #expect(lsb.lowHz == lowest)
        #expect(lsb.highHz == 7_100_000)
        let cwr = SpectrumFrame.audio(levelsDb: row, maxHz: 3_000, dialHz: 14_025_000, rawMode: "CWR", cwPitch: 600)
        #expect(cwr.stepHz < 0)
        #expect(Swift.abs(cwr.hz(atBin: 600 / cwr.binWidthHz) - 14_025_000) < 1e-6)
        let none = SpectrumFrame.audio(levelsDb: row, maxHz: 3_000, dialHz: 0, rawMode: "", cwPitch: 600)
        #expect(none.startHz == 0)
        #expect(none.hz(atBin: 512) == 3_000)
        #expect(usb.bin(ofHz: 14_201_500) == 256)
        #expect(usb.binInside(14_199_000) == nil)
        #expect(usb.binInside(14_201_500) == 256)
    }

    // MARK: - the scale and the zoom

    @Test func theWheelMovesTheThresholdReferenceAndRange() {
        let scale = SpectrumScale()
        #expect(scale.wheel(3, .threshold).thresholdDb == 13)
        #expect(scale.wheel(-100, .threshold).thresholdDb == 1)
        #expect(scale.wheel(2, .reference).refDb == 2)
        #expect(scale.wheel(-100, .reference).refDb == -60)
        #expect(scale.wheel(1, .range).rangeDb == 55)
        #expect(scale.wheel(-100, .range).rangeDb == 120)
        #expect(scale.thresholdLevel(floorDb: -100) == -90)
        #expect(scale.fraction(-110, floorDb: -100) == 0)
        #expect(scale.fraction(-80, floorDb: -100) == 0.5)
        #expect(scale.fraction(0, floorDb: -100) == 1)
        let shifted: SpectrumScale = scale.wheel(10, .reference)
        #expect(shifted.fraction(-80, floorDb: -100) > 0.5)
    }

    @Test func theZoomWindowCentresOnTheReceiveFrequencyAndStaysInside() {
        #expect(SpectrumZoom.window(count: 512, zoom: 1, centerBin: 100) == 0..<512)
        #expect(SpectrumZoom.window(count: 512, zoom: 2, centerBin: 256) == 128..<384)
        #expect(SpectrumZoom.window(count: 512, zoom: 4, centerBin: 10) == 0..<128)
        #expect(SpectrumZoom.window(count: 512, zoom: 4, centerBin: 510) == 384..<512)
        #expect(SpectrumZoom.window(count: 512, zoom: 4, centerBin: nil) == 192..<320)
        #expect(SpectrumZoom.window(count: 512, zoom: 4, centerBin: -40) == 192..<320)
        #expect(SpectrumZoom.window(count: 0, zoom: 4, centerBin: nil).isEmpty)
        #expect(SpectrumZoom.step(1, by: -1) == 1)
        #expect(SpectrumZoom.step(1, by: 1) == 2)
        #expect(SpectrumZoom.step(16, by: 1) == 16)
        #expect(SpectrumZoom.bin(atFraction: 0.5, window: 128..<384) == 256)
        #expect(SpectrumZoom.fraction(ofBin: 256, window: 128..<384) == 0.5)
        #expect(SpectrumZoom.fraction(ofBin: 400, window: 128..<384) == nil)
    }

    // MARK: - the trace

    @Test func theDecayingLineFallsAtItsSpeedAndJumpsUp() {
        var trace = SpectrumTrace()
        let axis = SpectrumFrame(startHz: 14_000_000, stepHz: 50, levelsDb: Self.levels(64, bumps: [(20, 40, 2)]))
        let quiet = SpectrumFrame(startHz: 14_000_000, stepHz: 50, levelsDb: Self.levels(64))
        trace.add(quiet, seconds: 0.1, decayDbPerSecond: 15, staticSensitivity: 50, resetOnRetune: false)
        #expect(trace.floorDb == -100)
        trace.add(axis, seconds: 0.1, decayDbPerSecond: 15, staticSensitivity: 50, resetOnRetune: false)
        #expect(trace.decayed[20] == -60)
        trace.add(quiet, seconds: 1, decayDbPerSecond: 15, staticSensitivity: 50, resetOnRetune: false)
        #expect(trace.decayed[20] == -75)
        #expect(trace.instant[20] == -100)
        trace.add(quiet, seconds: 10, decayDbPerSecond: 15, staticSensitivity: 50, resetOnRetune: false)
        #expect(trace.decayed[20] == -100)
        trace.add(axis, seconds: 0.1, decayDbPerSecond: 15, staticSensitivity: 50, resetOnRetune: false)
        #expect(trace.decayed[20] == -60)
        // The 60 s average moved only a little towards the signal.
        #expect(trace.average[20] < -99)
        #expect(trace.average[20] > -100)
    }

    @Test func aStaticCrashIsShownButNotTakenIn() {
        var trace = SpectrumTrace()
        let quiet = SpectrumFrame(startHz: 7_000_000, stepHz: 50, levelsDb: Self.levels(64))
        trace.add(quiet, seconds: 0.1, decayDbPerSecond: 15, staticSensitivity: 50, resetOnRetune: false)
        let crash = SpectrumFrame(startHz: 7_000_000, stepHz: 50, levelsDb: Self.levels(64, floor: -70))
        trace.add(crash, seconds: 0.1, decayDbPerSecond: 15, staticSensitivity: 50, resetOnRetune: false)
        #expect(trace.isStatic)
        #expect(trace.instant[5] == -70)
        #expect(trace.decayed[5] == -100)
        #expect(trace.floorDb == -100)
        trace.add(quiet, seconds: 0.1, decayDbPerSecond: 15, staticSensitivity: 50, resetOnRetune: false)
        #expect(!trace.isStatic)
        // Sensitivity 0 turns the rejection off.
        trace.add(crash, seconds: 0.1, decayDbPerSecond: 15, staticSensitivity: 0, resetOnRetune: false)
        #expect(!trace.isStatic)
        #expect(trace.decayed[5] == -70)
        // A lasting change (another band) is accepted after a dozen frames and the floor follows it.
        var lasting = SpectrumTrace()
        lasting.add(quiet, seconds: 0.1, decayDbPerSecond: 15, staticSensitivity: 100, resetOnRetune: false)
        for _ in 0..<SpectrumTrace.maxStaticFrames {
            lasting.add(crash, seconds: 0.1, decayDbPerSecond: 15, staticSensitivity: 100, resetOnRetune: false)
            #expect(lasting.isStatic)
        }
        lasting.add(crash, seconds: 0.1, decayDbPerSecond: 15, staticSensitivity: 100, resetOnRetune: false)
        #expect(!lasting.isStatic)
        #expect(lasting.floorDb == -70)
        #expect(SpectrumTrace.staticLimitDb(sensitivity: 0) == nil)
        #expect(SpectrumTrace.staticLimitDb(sensitivity: 1) == 40)
        #expect(SpectrumTrace.staticLimitDb(sensitivity: 100) == 3)
    }

    @Test func anotherAxisStartsTheTraceOrTheAverageOver() {
        var trace = SpectrumTrace()
        let strong = SpectrumFrame(startHz: 14_000_000, stepHz: 50, levelsDb: Self.levels(64, bumps: [(20, 40, 2)]))
        trace.add(strong, seconds: 0.1, decayDbPerSecond: 15, staticSensitivity: 50, resetOnRetune: false)
        let moved = SpectrumFrame(startHz: 14_001_000, stepHz: 50, levelsDb: Self.levels(64))
        trace.add(moved, seconds: 0.1, decayDbPerSecond: 15, staticSensitivity: 50, resetOnRetune: false)
        // Smearing kept: the old peak still decays where it was drawn, the average starts over.
        #expect(trace.decayed[20] > -100)
        #expect(trace.average[20] == -100)
        trace.add(strong, seconds: 0.1, decayDbPerSecond: 15, staticSensitivity: 50, resetOnRetune: true)
        #expect(trace.decayed == strong.levelsDb)
        #expect(trace.frames == 1)
        let wider = SpectrumFrame(startHz: 14_000_000, stepHz: 50, levelsDb: Self.levels(128))
        trace.add(wider, seconds: 0.1, decayDbPerSecond: 15, staticSensitivity: 50, resetOnRetune: false)
        #expect(trace.decayed.count == 128)
        #expect(trace.axisCount == 128)
    }

    // MARK: - signals

    @Test func signalsAreRunsAboveTheThresholdWithWeightedCentres() {
        let axis = SpectrumFrame(startHz: 14_000_000, stepHz: 10, levelsDb: [])
        var levels: [Double] = Self.levels(100, bumps: [(20, 30, 3), (60, 20, 4)])
        // A one-bin dip inside the second signal does not split it.
        levels[61] = -100
        let signals: [SpectrumSignal] = SignalDetector.detect(levels: levels, axis: axis, thresholdDb: -90)
        #expect(signals.count == 2)
        #expect(Swift.abs(signals[0].centerHz - 14_000_200) < 1e-6)
        #expect(signals[0].peakDb == -70)
        #expect(Swift.abs(signals[1].centerHz - 14_000_600) < 10)
        #expect(signals[1].lowHz <= 14_000_590)
        #expect(signals[1].highHz >= 14_000_610)
        // Downward axis: still sorted by frequency.
        let down = SpectrumFrame(startHz: 7_003_000, stepHz: -10, levelsDb: [])
        let reversed: [SpectrumSignal] = SignalDetector.detect(levels: levels, axis: down, thresholdDb: -90)
        #expect(reversed.map(\.centerHz) == reversed.map(\.centerHz).sorted())
        #expect(SignalDetector.detect(levels: Self.levels(10), axis: axis, thresholdDb: -90).isEmpty)
    }

    @Test func snapTakesTheNearestSignalWithinTwoKilohertz() {
        let signals: [SpectrumSignal] = [
            SpectrumSignal(centerHz: 14_010_000, lowHz: 14_009_950, highHz: 14_010_050, peakDb: -60),
            SpectrumSignal(centerHz: 14_012_500, lowHz: 14_012_450, highHz: 14_012_550, peakDb: -60),
        ]
        #expect(SignalDetector.snap(14_011_000, signals: signals) == 14_010_000)
        #expect(SignalDetector.snap(14_011_900, signals: signals) == 14_012_500)
        #expect(SignalDetector.snap(14_015_000, signals: signals) == nil)
        #expect(SignalDetector.snap(14_011_000, signals: []) == nil)
    }

    // MARK: - pixels

    @Test func theWaterfallIsCroppedAndTurnedForTheBarChart() {
        let rows: [[Float]] = [[0, 0.5, 1, 0.25], [1, 1, 0, 0]]
        #expect(SpectrumPixels.crop(rows, window: 0..<4) == rows)
        #expect(SpectrumPixels.crop(rows, window: 1..<3) == [[0.5, 1], [1, 0]])
        let image = WaterfallPixels.Image(width: 3, height: 2, pixels: [1, 2, 3, 4, 5, 6])
        // Newest row (1 2 3) on the right, bin 0 at the bottom.
        let up: WaterfallPixels.Image = SpectrumPixels.vertical(image, binZeroAtBottom: true)
        #expect(up.width == 2)
        #expect(up.height == 3)
        #expect(up.pixels == [6, 3, 5, 2, 4, 1])
        let down: WaterfallPixels.Image = SpectrumPixels.vertical(image, binZeroAtBottom: false)
        #expect(down.pixels == [4, 1, 5, 2, 6, 3])
    }

    // MARK: - the pipeline

    final class FakeSource: SpectrumSource, @unchecked Sendable {
        var frame: SpectrumFrame?
        var serial = 0
        func latestFrame(tuning: SpectrumTuning) -> (frame: SpectrumFrame, serial: Int)? {
            frame.map { ($0, serial) }
        }
        func waterfallRows() -> [[Float]] { [] }
        var secondsPerFrame: Double { 0.25 }
    }

    @Test func thePipelineTakesEachLineOnceAndDetects() throws {
        let source = FakeSource()
        let pipeline = SpectrumPipeline()
        let tuning = SpectrumTuning(dialHz: 14_025_000, rawMode: "CW", cwPitch: 600)
        var settings = SpectrumPipeline.Settings(scale: SpectrumScale(thresholdDb: 10), decay: .fast)
        #expect(pipeline.step(source, tuning: tuning, settings: settings) == nil)
        source.frame = SpectrumFrame(startHz: 14_020_000, stepHz: 25, levelsDb: Self.levels(400, bumps: [(200, 30, 2)]))
        source.serial = 1
        let first = try #require(pipeline.step(source, tuning: tuning, settings: settings))
        #expect(first.signals.count == 1)
        #expect(Swift.abs(first.signals[0].centerHz - 14_025_000) < 1e-6)
        #expect(first.window == 0..<400)
        #expect(first.thresholdLevelDb == -90)
        // The same serial again: not taken in a second time (the decay does not run).
        source.frame = SpectrumFrame(startHz: 14_020_000, stepHz: 25, levelsDb: Self.levels(400))
        let same = try #require(pipeline.step(source, tuning: tuning, settings: settings))
        #expect(same.decayed[200] == -70)
        source.serial = 3
        let next = try #require(pipeline.step(source, tuning: tuning, settings: settings))
        // Two lines' time at 40 dB/s: 0.5 s → 20 dB.
        #expect(next.decayed[200] == -90)
        settings.zoom = 4
        settings.rxHz = 14_025_000
        let zoomed = try #require(pipeline.step(source, tuning: tuning, settings: settings))
        #expect(zoomed.window == 150..<250)
        #expect(zoomed.instant.count == 100)
        #expect(zoomed.hz(atFraction: 0.5) == 14_025_000)
        #expect(zoomed.fraction(ofHz: 14_025_000) == 0.5)
        #expect(zoomed.fraction(ofHz: 14_020_000) == nil)
        // Another source starts over.
        let other = FakeSource()
        #expect(pipeline.step(other, tuning: tuning, settings: settings) == nil)
    }
}
