import CoreGraphics
import Foundation
@testable import MCLCore
import Testing

/// N1MM „Snap windows to edges" (the geometry) and „Grab Focus From Other Apps When Radio Is Tuned" (telling the
/// operator's tuning from the app's), and their stored options.
@MainActor @Suite struct WindowBehaviourTests {

    private let screen = CGRect(x: 0, y: 0, width: 1_440, height: 875)

    @Test func snapsToTheNearestScreenEdge() {
        let frame = CGRect(x: 8, y: 300, width: 400, height: 300)
        #expect(WindowSnap.snappedOrigin(frame, screens: [screen], others: [], distance: 12)
            == CGPoint(x: 0, y: 300))
        let topRight = CGRect(x: 1_030, y: 570, width: 400, height: 300)
        #expect(WindowSnap.snappedOrigin(topRight, screens: [screen], others: [], distance: 12)
            == CGPoint(x: 1_040, y: 575))
        // Too far from every edge: nothing moves; already on an edge: nothing to do.
        let middle = CGRect(x: 200, y: 300, width: 400, height: 300)
        #expect(WindowSnap.snappedOrigin(middle, screens: [screen], others: [], distance: 12) == nil)
        let onEdge = CGRect(x: 0, y: 300, width: 400, height: 300)
        #expect(WindowSnap.snappedOrigin(onEdge, screens: [screen], others: [], distance: 12) == nil)
    }

    @Test func snapsToAnotherWindow() {
        let other = CGRect(x: 500, y: 300, width: 400, height: 300)
        // Side by side, its top aligned.
        let frame = CGRect(x: 905, y: 296, width: 300, height: 300)
        #expect(WindowSnap.snappedOrigin(frame, screens: [screen], others: [other], distance: 12)
            == CGPoint(x: 900, y: 300))
        // Below it, left edges aligned.
        let below = CGRect(x: 507, y: 100, width: 300, height: 195)
        #expect(WindowSnap.snappedOrigin(below, screens: [screen], others: [other], distance: 12)
            == CGPoint(x: 500, y: 105))
        // A window far away on the other axis does not count.
        let away = CGRect(x: 905, y: 20, width: 300, height: 100)
        #expect(WindowSnap.snappedOrigin(away, screens: [], others: [other], distance: 12) == nil)
    }

    @Test func theScreenWithMostOfTheWindowCounts() {
        let right = CGRect(x: 1_440, y: 0, width: 1_920, height: 1_080)
        let frame = CGRect(x: 1_450, y: 500, width: 400, height: 300)
        #expect(WindowSnap.snappedOrigin(frame, screens: [screen, right], others: [], distance: 12)
            == CGPoint(x: 1_440, y: 500))
    }

    @Test func operatorTuningIsToldFromTheApps() {
        var detector = RadioTuneDetector()
        func polled(_ rig: Int, _ previous: Int64?, _ now: Int64) -> Bool {
            detector.polled(rig: rig, previousHz: previous, nowHz: now)
        }
        // The first state (a connect) and an unchanged frequency are no tune.
        #expect(!polled(0, nil, 14_025_000))
        #expect(!polled(0, 14_025_000, 14_025_000))
        // The knob.
        #expect(polled(0, 14_025_000, 14_025_500))
        // A QSY of the app, reached in one poll (also with the rig's own rounding or CW offset).
        detector.appTuned(rig: 0, freqHz: 7_010_000)
        #expect(!polled(0, 14_025_500, 7_010_000))
        #expect(!polled(0, 7_010_000, 7_010_600))
        // The announcement is used up: the knob again.
        #expect(polled(0, 7_010_600, 7_011_000))
        // A change far from the announced frequency is the operator's.
        detector.appTuned(rig: 1, freqHz: 21_010_000)
        #expect(!polled(0, 7_011_000, 7_011_000))
        #expect(polled(1, 14_000_000, 14_100_000))
        #expect(polled(1, 14_100_000, 21_010_000))
        // A VFO swap or a CAT macro: any next change is the app's.
        detector.appChanged(rig: 0)
        #expect(!polled(0, 7_011_000, 3_510_000))
    }

    @Test func optionsAreOffByDefaultAndStoredSparsely() {
        var setup = WindowSetup()
        #expect(!setup.flag(.grabFocusOnTune))
        #expect(!setup.flag(.snapWindows))
        #expect(setup.snapDistance == 12)
        setup.set(.snapWindows, flag: true)
        setup.set(.snapDistance, "99")
        #expect(setup.values == ["snapWindows": "true", "snapDistance": "99"])
        #expect(setup.snapDistance == WindowSetup.distanceRange.upperBound)
        setup.set(.snapWindows, flag: false)
        #expect(setup.values == ["snapDistance": "99"])
        #expect(WindowSetup(["grabFocusOnTune": "false", "unknown": "x"]).values.isEmpty)
        var config = AppConfig()
        config.window = WindowSetup(["grabFocusOnTune": "true"])
        let data: Data = (try? JSONEncoder().encode(config)) ?? Data()
        let back: AppConfig? = try? JSONDecoder().decode(AppConfig.self, from: data)
        #expect(back?.window.flag(.grabFocusOnTune) == true)
    }
}
