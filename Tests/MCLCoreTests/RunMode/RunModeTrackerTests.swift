import Testing
@testable import MCLCore

/// Port of the Java `runmode/RunModeTrackerTest` (9 tests).
@Suite struct RunModeTrackerTests {

    private let t = RunModeTracker()

    @Test func cqRemembersFrequencyPerBand() {
        #expect(t.onCq(14_025_000) == .run)
        t.onCq(7_012_000)

        #expect(t.cqFrequency(.m20) == 14_025_000)
        #expect(t.cqFrequency(.m40) == 7_012_000)
        #expect(t.cqFrequency(.m15) == nil)
    }

    @Test func qsyAwayFromCqSwitchesToSearchAndPounce() {
        t.onCq(14_025_000)

        #expect(t.onTuned(14_025_200, mode: .cw, current: .run, autoSwitch: true, runOnCqFreq: true) == nil,
                "Run stays within the tolerance")
        #expect(t.onTuned(14_031_000, mode: .cw, current: .run, autoSwitch: true, runOnCqFreq: true)
                == .searchAndPounce)
    }

    @Test func returningToCqFrequencySwitchesBackToRun() {
        t.onCq(14_025_000)

        #expect(t.onTuned(14_025_100, mode: .cw, current: .searchAndPounce, autoSwitch: true, runOnCqFreq: true)
                == .run)
        #expect(t.onTuned(14_040_000, mode: .cw, current: .searchAndPounce, autoSwitch: true, runOnCqFreq: true)
                == nil)
    }

    @Test func cqFrequencyOnOtherBandIsRemembered() {
        t.onCq(14_025_000)
        t.onCq(7_012_000) // the last CQ is on 40 m

        // QSY to the 20 m CQ frequency in S&P → Run (the CQ frequency of every band counts)
        #expect(t.onTuned(14_025_000, mode: .cw, current: .searchAndPounce, autoSwitch: true, runOnCqFreq: true)
                == .run)
        // and now "home" is 20 m: a shift away from it switches to S&P
        #expect(t.onTuned(14_030_000, mode: .cw, current: .run, autoSwitch: true, runOnCqFreq: true)
                == .searchAndPounce)
    }

    @Test func phoneHasWiderTolerance() {
        t.onCq(14_250_000)

        #expect(t.onTuned(14_250_800, mode: .ssb, current: .run, autoSwitch: true, runOnCqFreq: true) == nil)
        #expect(t.onTuned(14_250_800, mode: .cw, current: .run, autoSwitch: true, runOnCqFreq: true)
                == .searchAndPounce)
    }

    @Test func autoSwitchOffKeepsMode() {
        t.onCq(14_025_000)

        #expect(t.onTuned(14_031_000, mode: .cw, current: .run, autoSwitch: false, runOnCqFreq: true) == nil)
        #expect(t.onTuned(14_025_000, mode: .cw, current: .searchAndPounce, autoSwitch: false, runOnCqFreq: true)
                == nil)
    }

    @Test func sprintOptionDoesNotSwitchToRunOnCqFrequency() {
        t.onCq(14_025_000)

        #expect(t.onTuned(14_025_000, mode: .cw, current: .searchAndPounce, autoSwitch: true, runOnCqFreq: false)
                == nil)
        // QSY away from Run but into S&P switches further
        #expect(t.onTuned(14_031_000, mode: .cw, current: .run, autoSwitch: true, runOnCqFreq: false)
                == .searchAndPounce)
    }

    @Test func runWithoutAnyCqNeverSwitches() {
        #expect(t.onTuned(14_031_000, mode: .cw, current: .run, autoSwitch: true, runOnCqFreq: true) == nil)
    }

    @Test func toggleSetsCqFrequencyWhenEnteringRun() {
        #expect(t.toggle(.searchAndPounce, 21_020_000) == .run)
        #expect(t.cqFrequency(.m15) == 21_020_000)
        #expect(t.toggle(.run, 21_020_000) == .searchAndPounce)
    }
}

/// `RunModeTracker` against Java v1.1.1: 1,500 random events (`onCq`, `toggle`, `onTuned`,
/// `cqFrequency`) from `java.util.Random(20261002)` replayed by the Swift `JavaRandom` — frequencies at band
/// edges, outside bands, zero, negative, `Long.MAX_VALUE`, all modes and `null` (probe
/// a maintainer-only probe, table `RunModeMeasured`).
@Suite struct RunModeMeasuredTests {

    private static let bases: [Int] = [0, -5, 14_025_000, 7_012_000, 21_020_000, 3_500_200, 50_000,
                                       14_250_000, 14_000_400, 14_349_800, Int.max, 50_000_000]

    private static func name(_ band: Band?) -> String {
        guard let band else { return "null" }
        return String(describing: band).uppercased()
    }

    private static func name(_ mode: RunMode) -> String {
        mode.rawValue
    }

    /// Probe rows replayed in Swift (the same order of `Random` calls as the probe).
    static func replay(seed: Int64, count: Int) -> [String] {
        var random = JavaRandom(seed: seed)
        let tracker = RunModeTracker()
        let modes: [Mode] = Mode.allCases
        let bands: [Band] = Band.javaV111Cases
        var lines: [String] = []
        for index in 0..<count {
            let op = Int(random.nextInt(bound: 4))
            let base: Int = bases[Int(random.nextInt(bound: Int32(bases.count)))]
            // Java: `base > 0 && base != Long.MAX_VALUE ? base + r.nextInt(2601) - 1300 : base` — spelled out into
            // typed steps (a short expression for the Swift 6.1 type-checker); `nextInt` only in the branch as in Java.
            let shifted: Bool = base > 0 && base != Int.max
            var freq: Int = base
            if shifted {
                let offset: Int = Int(random.nextInt(bound: 2601)) - 1300
                freq = base + offset
            }
            let line: String
            switch op {
            case 0:
                line = "cq \(freq) -> \(name(tracker.onCq(freq)))"
            case 1:
                let current: RunMode = random.nextInt(bound: 2) == 0 ? .run : .searchAndPounce
                line = "toggle \(name(current)) \(freq) -> \(name(tracker.toggle(current, freq)))"
            case 2:
                let modeIndex = Int(random.nextInt(bound: Int32(modes.count + 1)))
                let mode: Mode? = modeIndex == modes.count ? nil : modes[modeIndex]
                let current: RunMode = random.nextInt(bound: 2) == 0 ? .run : .searchAndPounce
                let auto: Bool = random.nextInt(bound: 4) != 0
                let runOnCq: Bool = random.nextInt(bound: 3) != 0
                let result: String = tracker.onTuned(freq, mode: mode, current: current, autoSwitch: auto,
                                                     runOnCqFreq: runOnCq).map(name) ?? "-"
                let args = "\(freq) \(mode?.rawValue ?? "null") \(name(current)) \(auto) \(runOnCq)"
                line = "tuned \(args) -> \(result)"
            default:
                let bandIndex = Int(random.nextInt(bound: Int32(bands.count + 1)))
                let band: Band? = bandIndex == bands.count ? nil : bands[bandIndex]
                line = "cqFreq \(name(band)) -> \(tracker.cqFrequency(band).map(String.init) ?? "-")"
            }
            lines.append("\(index) \(line)")
        }
        let edge = RunModeTracker()
        edge.onCq(14_025_000)
        let deltas: [Int] = [-1001, -1000, -301, -300, 0, 300, 301, 1000, 1001]
        let edgeModes: [Mode?] = [.cw, .ssb, nil]
        for mode in edgeModes {
            for delta in deltas {
                for current in [RunMode.run, RunMode.searchAndPounce] {
                    let result: RunMode? = edge.onTuned(14_025_000 + delta, mode: mode, current: current,
                                                        autoSwitch: true, runOnCqFreq: true)
                    let head = "edge \(delta) \(mode?.rawValue ?? "null") \(name(current))"
                    lines.append("\(head) -> \(result.map(name) ?? "-")")
                }
            }
        }
        for mode in modes {
            lines.append("tol \(mode.rawValue) \(RunModeTracker.toleranceHz(mode))")
        }
        lines.append("tol null \(RunModeTracker.toleranceHz(nil))")
        return lines
    }

    @Test func fuzzedEventsMatchJava() {
        JavaV111Gate.run {
            let expected: [String] = RunModeMeasured.rows.split(separator: "\n").map(String.init)
            let actual: [String] = Self.replay(seed: 20_261_002, count: 1_500)
            #expect(actual.count == expected.count)
            var mismatches = 0
            for (got, want) in zip(actual, expected) where got != want {
                mismatches += 1
                if mismatches <= 10 {
                    Issue.record("Swift \(got) ≠ Java \(want)")
                }
            }
            #expect(mismatches == 0)
        }
    }
}
