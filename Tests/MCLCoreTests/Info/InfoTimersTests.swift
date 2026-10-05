import Testing
@testable import MCLCore

/// `InfoTimers` against `ui/RateWindow.kt` (`:784-948`) of v1.1.1. The formatters `hm`, `hms`, `elapsed`, `suffix`
/// are the real Kotlin functions measured on the JVM; the timer rows come from the transcribed composable logic over
/// the real `ContestStats` (maintainer-only probe, see its README).
@Suite struct InfoTimersTests {

    // MARK: - Formatters (measured)

    @Test func hmAndHmsMatchTheJvm() throws {
        let hm = InfoProbeTable.area("hm")
        let hms = InfoProbeTable.area("hms")
        #expect(hm.count == 29)
        #expect(hms.count == 29)
        for row in hm {
            #expect(InfoTimers.hm(try #require(Int64(row.input))) == row.result, "hm \(row.input)")
        }
        for row in hms {
            #expect(InfoTimers.hms(try #require(Int64(row.input))) == row.result, "hms \(row.input)")
        }
    }

    @Test func elapsedMatchesTheJvm() throws {
        let rows = InfoProbeTable.area("elapsed")
        #expect(rows.count == 13)
        for row in rows {
            let parts = row.input.split(separator: " ").map { Int64($0)! }
            let since = try #require(JavaInstant.ofEpochSecond(parts[0]))
            let now = try #require(JavaInstant.ofEpochSecond(parts[1]))
            #expect(InfoTimers.elapsed(since: since, now: now) == row.result, "elapsed \(row.input)")
        }
    }

    @Test func suffixMatchesTheJvm() {
        let rows = InfoProbeTable.area("suffix")
        #expect(rows.count == 8)
        for row in rows {
            let minutes: Int? = row.input == "~" ? nil : Int(row.input)
            #expect("[" + InfoTimers.suffix(minutes) + "]" == row.result, "suffix \(row.input)")
        }
    }

    @Test func formattersByHand() {
        // RW:928, RW:931-938, RW:944-948.
        #expect(InfoTimers.hm(3_661) == "1:01")
        #expect(InfoTimers.hms(59) == "0:59")
        #expect(InfoTimers.hms(3_599) == "59:59")
        #expect(InfoTimers.hms(3_600) == "1:00:00")
        #expect(InfoTimers.hms(-5) == "0:00")
        let epoch = JavaInstant.epoch
        #expect(InfoTimers.elapsed(since: epoch, now: JavaInstant.ofEpochSecond(266_429)!) == "3 d 2:00")
        #expect(InfoTimers.elapsed(since: JavaInstant.ofEpochSecond(100)!, now: JavaInstant.ofEpochSecond(40)!) == "0:00")
    }

    // MARK: - Timers (transcribed glue over the real stats)

    private static func parse(_ input: String) -> (stats: ContestStats, now: JavaInstant, fields: [String]) {
        let fields = input.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        let stats = ContestStats.of(InfoProbeTable.logs[fields[0]] ?? [])
        return (stats, InfoProbeTable.instant(millis: Int64(fields[1])!), fields)
    }

    @Test func offTimeTimerMatchesTheJvm() {
        let rows = InfoProbeTable.area("offtime")
        #expect(rows.count == 2_736)
        for row in rows {
            let p = Self.parse(row.input)
            let start: JavaInstant? = p.fields[4] == "S" ? InfoProbeTable.contestStart : nil
            let cell = InfoTimers.offTime(mode: p.fields[2], stats: p.stats, now: p.now,
                                          rules: InfoProbeTable.operating(p.fields[3]), contestStart: start)
            let value: String = cell.value ?? "~"
            let text: String = "label=" + cell.label + ";value=" + value + ";ok=" + String(cell.state == .ok)
            #expect(text == row.result, "\(row.input)")
        }
    }

    @Test func timeOnBandMatchesTheJvm() {
        let rows = InfoProbeTable.area("onband")
        #expect(rows.count == 1_824)
        for row in rows {
            let p = Self.parse(row.input)
            let tuned: Band? = p.fields[2] == "-" ? nil : Band.from(adif: p.fields[2])
            let since = Int64(p.fields[3])!
            let tunedSince: JavaInstant? = since < 0
                ? nil : JavaInstant.ofEpochSecond(p.now.epochSecond - since)
            let cell = InfoTimers.onBand(band: tuned, stats: p.stats, tunedSince: tunedSince, now: p.now,
                                         rules: InfoProbeTable.operating(p.fields[4]))
            var text = "none"
            if let cell {
                text = "label=" + cell.label + ";value=" + (cell.value ?? "~") + ";ok=" + String(cell.state == .ok)
            }
            #expect(text == row.result, "\(row.input)")
        }
    }

    @Test func bandChangeCounterMatchesTheJvm() {
        let rows = InfoProbeTable.area("bandchg")
        #expect(rows.count == 190)
        for row in rows {
            let p = Self.parse(row.input)
            let cell = InfoTimers.bandChanges(stats: p.stats, now: p.now,
                                              rules: InfoProbeTable.operating(p.fields[2]))
            var text = "none"
            if let cell {
                let state: String
                switch cell.state {
                case .over: state = "over"
                case .warn: state = "warn"
                case .ok: state = "ok"
                case .none: state = "none"
                }
                text = "label=" + cell.label + ";value=" + (cell.value ?? "~") + ";state=" + state
            }
            #expect(text == row.result, "\(row.input)")
        }
    }

    /// The probe has to reach every branch, otherwise the rows above prove little.
    @Test func probeRowsReachEveryBranch() {
        let offtime = InfoProbeTable.area("offtime").map(\.result)
        #expect(offtime.contains { $0.hasSuffix("ok=true") })
        #expect(offtime.contains { $0.hasSuffix("ok=false") })
        #expect(offtime.contains { $0.contains("label=Interval ↓ (60);value=0:00") })
        #expect(offtime.contains { $0.contains("label=Off time celkem (720);value=~") })
        #expect(offtime.contains { $0.contains("Od posledního QSO;value=3 d ") })
        let onband = InfoProbeTable.area("onband").map(\.result)
        #expect(onband.contains("none") || onband.contains { $0 == "none" })
        #expect(onband.contains { $0.contains("(10);") && $0.hasSuffix("ok=true") })
        #expect(onband.contains { $0.contains("(10);") && $0.hasSuffix("ok=false") })
        let changes = InfoProbeTable.area("bandchg").map(\.result)
        #expect(changes.contains { $0.hasSuffix("state=over") })
        #expect(changes.contains { $0.hasSuffix("state=warn") })
        #expect(changes.contains { $0.hasSuffix("state=ok") })
    }

    // MARK: - Hand-written edges (RW lines in the comments)

    @Test func offTimeTimerEdgesByHand() {
        let stats = ContestStats.of([])
        let now = JavaInstant.epoch
        let rules = ContestDefinition.Operating(offTime: .init(minimumMinutes: 30, requiredMinutes: 60), bandChange: nil)
        // RW:857-860: an empty log has no pause, hence no value in any mode.
        for mode in InfoWindowConfig.offTimeModeOptions {
            let cell = InfoTimers.offTime(mode: mode, stats: stats, now: now, rules: rules, contestStart: nil)
            #expect(cell.value == nil, "\(mode)")
            #expect(cell.state == .none)
        }
        #expect(InfoTimers.offTime(mode: "countDown", stats: stats, now: now, rules: nil, contestStart: nil).label
            == "Interval ↓")
    }

    @Test func translatedLabels() {
        let english = SpotActionsTests.translator([
            "Od posledního QSO": "Since last QSO", "Na pásmu %s": "On band %s", "Změny pásma": "Band changes",
        ])
        let stats = ContestStats.of([])
        let now = JavaInstant.epoch
        #expect(InfoTimers.offTime(mode: "sinceLastQso", stats: stats, now: now, rules: nil, contestStart: nil,
                                   translate: english).label == "Since last QSO")
        let bandRules = ContestDefinition.Operating(offTime: nil, bandChange: .init(minimumMinutes: 10, perHour: 6))
        let onBand = InfoTimers.onBand(band: .m20, stats: stats, tunedSince: now, now: now, rules: bandRules,
                                       translate: english)
        #expect(onBand?.label == "On band 20m (10)")
        #expect(onBand?.value == "10:00")
        #expect(InfoTimers.bandChanges(stats: stats, now: now, rules: bandRules, translate: english)?.label
            == "Band changes")
        // RW:790-791: no definition, no rules (the resolution over real definitions is in `InfoViewsRuntimeTests`).
        #expect(InfoTimers.rules(definition: nil, category: nil) == nil)
    }
}
