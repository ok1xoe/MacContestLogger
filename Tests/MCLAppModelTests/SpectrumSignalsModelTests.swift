import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// The spectrum display's signals in the waterfall window (N1MM+ Spectrum Display): two synthetic tones are two
/// signals; Shift+Up/Down jumps between them skipping a dupe spot, the markers follow the filter, the CQ button finds
/// quiet frequencies, unknown signals become `@frequency` spots (only when switched on) and go with the window.
/// The audio is synthetic PCM; nothing transmits.
@MainActor @Suite struct SpectrumSignalsModelTests {

    static func twoTones(_ n: Int) -> [Double] {
        let a: [Double] = SpectrumPaneModelTests.noisyTone(1_000, n, amp: 0.2)
        return a.enumerated().map { i, v in
            v + 0.2 * sin(2 * Double.pi * 2_000 * Double(i) / RadioSignals.sampleRate)
        }
    }

    private static func opened() async throws -> (KeyingApp, WaterfallModel) {
        let app = try await KeyingApp.make()
        let model: WaterfallModel = app.model.makeWaterfall()
        app.model.rig.tuneTo(14_025_000)
        await model.open()
        try RadioSignals.feed(app, twoTones(4_096 * 3))
        app.radioClock.advance(by: 100)
        await model.settle()
        await runMainQueue()
        return (app, model)
    }

    @Test func shiftArrowsJumpBetweenSignalsAndSkipDupes() async throws {
        let (app, model) = try await Self.opened()
        let picture: SpectrumPicture = try #require(model.picture)
        let centers: [Double] = picture.signals.map(\.centerHz)
        let first: Double = try #require(centers.first { abs($0 - 14_026_000) < 30 })
        let second: Double = try #require(centers.first { abs($0 - 14_027_000) < 30 })
        #expect(model.markers.count == picture.signals.count)
        #expect(model.jump(direction: 1, fromHz: 14_025_000))
        #expect(abs(app.model.rig.tuning.tunedFreqHz - Int64(first.rounded())) <= 10)
        #expect(model.jump(direction: 1, fromHz: Int64(first.rounded())))
        #expect(abs(app.model.rig.tuning.tunedFreqHz - Int64(second.rounded())) <= 10)
        // The top edge: the jump stays (N1MM stops there) but the key is used.
        let top: Double = try #require(centers.last)
        app.model.rig.tuneTo(Int64(top.rounded()))
        #expect(model.jump(direction: 1, fromHz: Int64(top.rounded())))
        #expect(abs(app.model.rig.tuning.tunedFreqHz - Int64(top.rounded())) <= 10)
        // A dupe spot on the second signal: Shift+Up from the first skips it, the markers without dupes drop it.
        model.spotsProvider = { _, _ in [SpectrumSpot(call: "OK1AA", freqHz: 14_027_000, dupe: true)] }
        model.updateSetup { $0.markerFilter = .nonDupes }
        #expect(!model.markers.contains { abs($0.centerHz - second) < 1 })
        app.model.rig.tuneTo(Int64(first.rounded()))
        #expect(model.jump(direction: 1, fromHz: Int64(first.rounded())))
        #expect(abs(app.model.rig.tuning.tunedFreqHz - Int64(second.rounded())) > 10)
        // The spot label is drawn over its signal and a click goes there.
        let labels: [SpectrumOverlaySpot] = model.overlaySpots
        #expect(labels.map(\.spot.call) == ["OK1AA"])
        #expect(labels.first?.heard == true)
        let label: SpectrumSpot = try #require(labels.first?.spot)
        model.tuneToSpot(label)
        #expect(abs(app.model.rig.tuning.tunedFreqHz - 14_027_000) <= 10)
        // Shift+↓ in the entry window goes through the same jump.
        model.spotsProvider = { _, _ in [] }
        app.model.rig.tuneTo(14_025_000)
        await runMainQueue()
        #expect(app.model.entry.handle(.spectrumJump(1)))
        #expect(abs(app.model.rig.tuning.tunedFreqHz - Int64(first.rounded())) <= 10)
        model.close()
        // A closed window does not take the keys: they tune as plain arrows.
        #expect(!model.jump(direction: 1, fromHz: 14_025_000))
        #expect(app.model.entry.spectrumJump?(1, 14_025_000) == false)
        await app.settle()
    }

    @Test func theCqButtonFindsQuietFrequenciesAndTheArrowsFollowThem() async throws {
        let (app, model) = try await Self.opened()
        model.toggleCqFrequencies()
        let found: [Double] = model.cqFrequencies
        #expect(!found.isEmpty)
        #expect(found.count <= 5)
        #expect(model.cqMarkers.map(\.rank) == Array(1...found.count))
        for hz in found {
            // Away from both tones.
            #expect(abs(hz - 14_026_000) > 200)
            #expect(abs(hz - 14_027_000) > 200)
        }
        let sorted: [Double] = found.sorted()
        app.model.rig.tuneTo(14_024_000)
        #expect(model.jump(direction: 1, fromHz: 14_024_000))
        #expect(abs(app.model.rig.tuning.tunedFreqHz - Int64(sorted[0].rounded())) <= 10)
        model.toggleCqFrequencies()
        #expect(model.cqFrequencies.isEmpty)
        model.close()
        await app.settle()
    }

    @Test func unknownSignalsBecomeAtFrequencySpotsOnlyWhenSwitchedOn() async throws {
        let (app, model) = try await Self.opened()
        let buffer: SpotBuffer = app.model.dxCluster.spots
        #expect(!buffer.snapshot().contains { $0.spotter == SpectrumSignals.unknownSpotter })
        model.updateSetup { $0.set(.unknownAsSpots, flag: true) }
        try RadioSignals.feed(app, Self.twoTones(2_048))
        app.radioClock.advance(by: 100)
        await model.settle()
        await runMainQueue()
        let made: [DxSpot] = buffer.snapshot().filter { $0.spotter == SpectrumSignals.unknownSpotter }
        #expect(made.contains { $0.dxCall == "@14026.0" })
        #expect(made.contains { $0.dxCall == "@14027.0" })
        // The bandmap's spots now cover the signals, but the display's own do not make them known.
        #expect(model.markers.count >= 2)
        model.updateSetup { $0.markerFilter = .unknown }
        #expect(model.markers.count >= 2)
        // The window goes: its spots go with it.
        model.close()
        #expect(!buffer.snapshot().contains { $0.spotter == SpectrumSignals.unknownSpotter })
        await app.settle()
    }
}
