import Foundation
import Testing
@testable import MCLCore

/// The spectrum display's signal logic (N1MM+ Spectrum Display): marker filters, Shift+Up/Down targets, the spots
/// over the spectrum, `@frequency` spots of unknown signals and the CQ frequency finder. Synthetic data only.
@Suite struct SpectrumSignalsTests {

    static func signal(_ hz: Double, peak: Double = -60) -> SpectrumSignal {
        SpectrumSignal(centerHz: hz, lowHz: hz - 40, highHz: hz + 40, peakDb: peak)
    }

    static let signals: [SpectrumSignal] = [signal(14_010_000), signal(14_012_000), signal(14_014_000),
                                            signal(14_016_000, peak: -50)]
    static let spots: [SpectrumSpot] = [
        SpectrumSpot(call: "OK1AA", freqHz: 14_010_050, dupe: true),
        SpectrumSpot(call: "*14012.0", freqHz: 14_012_000, nonWorkable: true),
        SpectrumSpot(call: "DL1MM", freqHz: 14_013_900, mult: true),
        SpectrumSpot(call: "@14016.0", freqHz: 14_016_000, generated: true),
        SpectrumSpot(call: "G4XX", freqHz: 14_020_000),
    ]

    @Test func markerFiltersPickTheirSignals() {
        let centers: (SpectrumMarkerFilter) -> [Double] = { filter in
            SpectrumSignals.markers(Self.signals, spots: Self.spots, filter: filter, toleranceHz: 150).map(\.centerHz)
        }
        #expect(centers(.all) == [14_010_000, 14_012_000, 14_014_000, 14_016_000])
        #expect(centers(.nonDupes) == [14_014_000, 14_016_000])
        // The display's own @frequency spot does not make a signal known.
        #expect(centers(.unknown) == [14_016_000])
        #expect(centers(.mults) == [14_014_000])
        // A narrow tolerance: the dupe spot 50 Hz off is no longer on the signal (its extent is ±40 Hz).
        #expect(SpectrumSignals.isSkipped(Self.signals[0], spots: Self.spots, toleranceHz: 60))
        #expect(!SpectrumSignals.isSkipped(Self.signals[0], spots: Self.spots, toleranceHz: 10))
        #expect(SpectrumSignals.isUnknown(Self.signals[0], spots: Self.spots, toleranceHz: 10))
    }

    @Test func shiftArrowsJumpOverDupesAndStopAtTheEdge() {
        let targets: [Double] = SpectrumSignals.jumpTargets(Self.signals, spots: Self.spots, filter: .all,
                                                            toleranceHz: 150)
        #expect(targets == [14_014_000, 14_016_000])
        #expect(SpectrumSignals.next(from: 14_009_000, direction: 1, targets: targets, minStepHz: 75) == 14_014_000)
        #expect(SpectrumSignals.next(from: 14_014_000, direction: 1, targets: targets, minStepHz: 75) == 14_016_000)
        #expect(SpectrumSignals.next(from: 14_014_050, direction: -1, targets: targets, minStepHz: 75) == nil)
        #expect(SpectrumSignals.next(from: 14_016_000, direction: 1, targets: targets, minStepHz: 75) == nil)
        #expect(SpectrumSignals.next(from: 14_016_000, direction: -1, targets: targets, minStepHz: 75) == 14_014_000)
        // Only unknown signals: the jump follows the filter too.
        #expect(SpectrumSignals.jumpTargets(Self.signals, spots: Self.spots, filter: .unknown, toleranceHz: 150)
            == [14_016_000])
    }

    @Test func theSpotsOverTheSpectrum() {
        let all: [SpectrumOverlaySpot] = SpectrumSignals.overlay(Self.spots, signals: Self.signals, lowHz: 14_009_000,
                                                                 highHz: 14_021_000, onlyHeard: false,
                                                                 toleranceHz: 150, tunedHz: 14_013_950)
        #expect(all.map(\.spot.call) == ["OK1AA", "*14012.0", "DL1MM", "G4XX"])
        #expect(all.map(\.heard) == [true, true, true, false])
        #expect(all.map(\.tuned) == [false, false, true, false])
        let heard: [SpectrumOverlaySpot] = SpectrumSignals.overlay(Self.spots, signals: Self.signals,
                                                                   lowHz: 14_009_000, highHz: 14_013_000,
                                                                   onlyHeard: true, toleranceHz: 150, tunedHz: 0)
        #expect(heard.map(\.spot.call) == ["OK1AA", "*14012.0"])
        let anyTuned: Bool = heard.contains { $0.tuned }
        #expect(!anyTuned)
    }

    @Test func unknownSignalsBecomeAtFrequencySpots() {
        #expect(SpectrumSignals.unknownCall(14_025_340) == "@14025.3")
        #expect(SpectrumSignals.unknownCall(7_001_950) == "@7002.0")
        let spots = SpectrumSignals.unknownSpots(Self.signals, spots: Self.spots, toleranceHz: 150)
        #expect(spots.map(\.call) == ["@14016.0"])
        #expect(spots.map(\.freqHz) == [14_016_000])
        // Two signals on the same 100 Hz give one spot; at most `maxUnknownSpots`, the strongest.
        let many: [SpectrumSignal] = (0..<60).map { Self.signal(7_000_000 + Double($0) * 500, peak: Double(-$0)) }
            + [Self.signal(7_000_020, peak: -1)]
        let capped = SpectrumSignals.unknownSpots(many, spots: [], toleranceHz: 100)
        #expect(capped.count == SpectrumSignals.maxUnknownSpots - 1)
        #expect(capped.first?.call == "@7000.0")
        #expect(!capped.contains { $0.call == "@7029.5" })
    }

    @Test func theCqFinderTakesTheQuietestWindows() {
        // 100 bins of 50 Hz (5 kHz); busy around bins 10, 45 and 80, quiet elsewhere with a slope.
        let axis = SpectrumFrame(startHz: 14_000_000, stepHz: 50, levelsDb: [])
        var average: [Double] = (0..<100).map { -100 + Double($0) * 0.01 }
        for busy in [10, 45, 80] {
            for i in (busy - 3)...(busy + 3) {
                average[i] = -60
            }
        }
        let found: [Double] = CqFrequencyFinder.find(average: average, axis: axis, window: 0..<100,
                                                     thresholdDb: -90, widthHz: 500)
        #expect(found.count == 5)
        // Best first: the quietest (lowest) windows with no signal, at least one CQ width apart.
        let bins: [Double] = found.map { ($0 - 14_000_000) / 50 }
        for (i, a) in bins.enumerated() {
            for b in bins[(i + 1)...] {
                #expect(abs(a - b) >= 10)
            }
            for busy in [10.0, 45, 80] {
                #expect(abs(a - busy) > 7)
            }
        }
        #expect(bins[0] < bins[1] || bins[0] < 40)
        // Too narrow a view, or nothing averaged yet: nothing.
        #expect(CqFrequencyFinder.find(average: average, axis: axis, window: 0..<5, thresholdDb: -90,
                                       widthHz: 500).isEmpty)
        #expect(CqFrequencyFinder.find(average: [], axis: axis, window: 0..<100, thresholdDb: -90,
                                       widthHz: 500).isEmpty)
        #expect(CqFrequencyFinder.widthHz(cw: true, phone: false) == 500)
        #expect(CqFrequencyFinder.widthHz(cw: false, phone: true) == 3_000)
    }

    @Test func theNewOptionsAndTheirDefaults() {
        var setup = SpectrumSetup()
        #expect(setup.flag(.showMarkers))
        #expect(setup.flag(.showSpots))
        #expect(!setup.flag(.onlyHeardSpots))
        #expect(!setup.flag(.unknownAsSpots))
        #expect(setup.markerFilter == .all)
        #expect(setup.staticSensitivity == 50)
        setup.markerFilter = .unknown
        setup.staticSensitivity = 140
        #expect(setup.values == ["markerFilter": "unknown", "staticSensitivity": "100"])
    }
}
