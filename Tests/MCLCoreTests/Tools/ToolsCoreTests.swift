import Foundation
import Testing
@testable import MCLCore

/// Unit tests of the tool-window core that the JVM probe cannot reach (the safety gate of the simulator, the edges of the
/// watches, the row selection of the move window).
@Suite struct ToolsCoreTests {

    typealias P = ToolsParity

    // MARK: - simulator gate

    private func session(spread: Int32 = 300, activity: Int32 = 3) -> SimulatorSession {
        SimulatorSession(settings: PileupSimulator.Settings(activity: activity, minWpm: 22, maxWpm: 32, pitchSpreadHz: spread),
                         scp: ScpDatabase.of(["OK1ABC", "DL1XYZ"]), random: JavaPileupRandom(seed: 7))
    }

    @Test func runningSimulatorBlocksKeyingAndOutwardEffects() {
        let running = session()
        #expect(running.isRunning)
        #expect(!running.allowsRigKeying)
        #expect(!running.allowsOutwardEffects)
        running.stop()
        #expect(!running.isRunning)
        #expect(running.allowsRigKeying)
        #expect(running.allowsOutwardEffects)
    }

    @Test func stoppedSimulatorIgnoresInput() {
        let s = session()
        _ = s.onSent("CQ TEST")
        _ = s.onLogged(call: "OK1ABC", exchangeRcvd: "5NN 1", serialRcvd: nil)
        let checks: Int = s.checks.count
        let qsos: Int = s.qsos
        s.stop()
        #expect(s.onSent("CQ TEST").isEmpty)
        #expect(s.onLogged(call: "OK1ABC", exchangeRcvd: "5NN 1", serialRcvd: nil) == nil)
        #expect(s.checks.count == checks)
        #expect(s.qsos == qsos)
    }

    @Test func checksAreNewestFirst() throws {
        let s = session()
        _ = s.onLogged(call: "AAA", exchangeRcvd: "1", serialRcvd: nil)
        _ = s.onLogged(call: "BBB", exchangeRcvd: "2", serialRcvd: nil)
        #expect(s.checks.map(\.loggedCall) == ["BBB", "AAA"])
        #expect(s.errors == 2)
    }

    @Test func absurdToneSpreadIsSwallowed() {
        // 2 * spread + 1 overflows `int` when a caller arrives: Kotlin's `IllegalArgumentException` would crash the
        // caller of `onSent`; the session reports no replies instead (`try?`).
        let s = session(spread: 1 << 30, activity: 6)
        #expect(s.onSent("CQ TEST").isEmpty)
    }

    @Test func exchangeJoinsTheSerialNumber() {
        #expect(SimulatorSession.exchange("5NN", 12) == "5NN 12")
        #expect(SimulatorSession.exchange("5NN", nil) == "5NN")
        #expect(SimulatorSession.exchange("", 3) == " 3")
    }

    @Test func formParsingHandlesKotlinNumberSyntax() {
        #expect(SimulatorSession.toIntOrNull("+7") == 7)
        #expect(SimulatorSession.toIntOrNull("-") == nil)
        #expect(SimulatorSession.toIntOrNull("") == nil)
        #expect(SimulatorSession.toIntOrNull("2147483647") == 2_147_483_647)
        #expect(SimulatorSession.toIntOrNull("-2147483648") == -2_147_483_648)
        #expect(SimulatorSession.toIntOrNull("2147483648") == nil)
        #expect(SimulatorSession.toIntOrNull("1 2") == nil)
    }

    // MARK: - sked edges

    @Test func skedTimeAtTheEdgeOfTheInstantRangeIsInvalid() throws {
        let edge = try #require(JavaInstant.ofEpochSecond(JavaInstant.maxSecond))
        let result = SkedEditing.add(call: "OK1ABC", freqHz: 14_025_000, mode: "CW", timeText: "0930", note: "", now: edge)
        #expect(result == .failure(.invalidTime("0930")))
        // An absolute time does not look at `now`.
        let absolute = SkedEditing.add(call: "OK1ABC", freqHz: 14_025_000, mode: "CW", timeText: "2026-11-28 1430",
                                       note: "", now: edge)
        #expect((try? absolute.get().atUtc) == "2026-11-28T14:30:00Z")
    }

    @Test func skedDueWindowIsInclusive() throws {
        let now: JavaInstant = P.t0Instant
        func sked(_ offset: Int64) -> SkedEntry {
            SkedEntry(call: "K1AAA", freqHz: 14_025_000, mode: "CW", atUtc: now.plus(seconds: offset)!.toString(), note: "")
        }
        func fresh(_ offset: Int64) -> [String] {
            var watch = SkedWatch()
            return watch.due(skeds: [sked(offset)], now: now)
        }
        #expect(fresh(60).count == 1)
        #expect(fresh(61).isEmpty)
        #expect(fresh(-300).count == 1)
        #expect(fresh(-301).isEmpty)
        var watch = SkedWatch()
        // Each sked is announced once, even when it stays due.
        let one: SkedEntry = sked(0)
        #expect(watch.due(skeds: [one], now: now).count == 1)
        #expect(watch.due(skeds: [one], now: now).isEmpty)
        #expect(watch.reminded.contains(one.id))
    }

    @Test func skedAtTheEdgeOfTheRangeIsNotDueInsteadOfCrashing() throws {
        let edge = SkedEntry(call: "K1AAA", freqHz: 14_025_000, mode: "CW",
                             atUtc: JavaInstant(uncheckedSecond: JavaInstant.minSecond, nano: 0).toString(), note: "")
        var watch = SkedWatch()
        #expect(watch.due(skeds: [edge], now: P.t0Instant).isEmpty)
    }

    // MARK: - TOUR edges

    @Test func firstTourTickOnlyRemembers() throws {
        let a = try Tour(startMinute: 0, durationMinutes: 100_000_000)
        let b = try Tour(startMinute: 0, durationMinutes: 20_000_000)
        var watch = TourWatch()
        #expect(watch.tick(tour: a, now: P.t0, active: true, translate: P.cs) == nil)
        #expect(watch.lastSession == a.session(at: P.t0))
        #expect(watch.tick(tour: b, now: P.t0, active: true, translate: P.cs) != nil)
        // An inactive contest does not report but the session is remembered, so activating does not announce later.
        var quiet = TourWatch()
        _ = quiet.tick(tour: a, now: P.t0, active: false, translate: P.cs)
        #expect(quiet.tick(tour: b, now: P.t0, active: false, translate: P.cs) == nil)
        #expect(quiet.tick(tour: b, now: P.t0, active: true, translate: P.cs) == nil)
        // Without a TOUR the memory is cleared.
        _ = quiet.tick(tour: nil, now: P.t0, active: true, translate: P.cs)
        #expect(quiet.lastSession == nil)
    }

    // MARK: - move window rows

    @Test func moveRowsTakeTheLatestOnesAndSkipDeleted() {
        var qsos: [Qso] = (0..<40).map { P.qso("K\($0)AA", "20m", .cw, "") }
        qsos[39].deleted = true
        qsos[38].xqso = true
        var asked: [String] = []
        let rows = MoveRequest.rows(qsos: qsos) { qso in
            asked.append(qso.call)
            return qso.call == "K36AA" ? [MoveMultipliers.Candidate(band: "15m", newMults: ["zones"], points: 3)] : []
        }
        // Newest first; the deleted and the X-QSO are skipped and do not count against the limit of 25.
        #expect(asked.count == MoveRequest.recentLimit)
        #expect(asked.first == "K37AA")
        #expect(asked.last == "K13AA")
        #expect(rows.map(\.qso.call) == ["K36AA"])
        #expect(MoveRequest.buttonLabel(rows[0].candidates[0]) == "15m +1 QSY?")
        #expect(MoveRequest.bandModeText(qsos[0]) == "20m CW")
        #expect(MoveRequest.bandModeText(Qso()) == " ")
    }

    @Test func moveTextsAreCzechOriginals() {
        #expect(MoveRequest.hint(translate: P.cs).hasPrefix("Stanice z posledních 25 QSO"))
        #expect(MoveRequest.noFrequencyText(band: "15m", translate: P.cs)
            == "Na 15m ještě nemám frekvenci — přelaď ručně (Ctrl+PgUp/PgDn)")
    }

    // MARK: - map, propagation, notes

    @Test func mapStartsInDxccModeOutsideAContest() {
        #expect(WorldMapModel.initialDxccMode(startDxcc: false, contestActive: false))
        #expect(WorldMapModel.initialDxccMode(startDxcc: true, contestActive: true))
        #expect(!WorldMapModel.initialDxccMode(startDxcc: false, contestActive: true))
    }

    @Test func fieldStatesTakeTheStrongestCell() {
        let rows: [MultGridRow] = [
            MultGridRow(key: "JN", label: "", prefix: "", continent: "", cells: ["20m": .worked, "40m": .spottedDbl, "10m": .spotted]),
            MultGridRow(key: "FN", label: "", prefix: "", continent: "", cells: ["20m": .empty]),
            MultGridRow(key: "PM", label: "", prefix: "", continent: "", cells: ["20m": .spotted, "15m": .worked]),
        ]
        let grid = MultGridView(available: true, worked: 2, possible: -1, rows: rows)
        #expect(WorldMapModel.fieldStates(grid: grid) == ["JN": .spottedDbl, "PM": .spotted])
    }

    @Test func propagationRowsStartAtTheHighestBand() {
        let rows = PropagationRows.rows(from: (50, 15), to: (51, 10), sfi: 120, now: P.t0)
        #expect(rows.map { $0.band.adif } == ["10m", "15m", "20m", "40m", "80m", "160m"])
        #expect(rows.allSatisfy { $0.levels.count == 24 })
        #expect(PropagationRows.defaultSfiText(wwv: nil) == "120")
        #expect(PropagationRows.color(.open) == 0xFF43_A047)
    }

    @Test func removingANoteDropsOnlyOneOfEqualDuplicates() {
        let a = BandNote(band: "20m", freqKHz: 0, text: "x")
        let b = BandNote(band: "40m", freqKHz: 0, text: "y")
        #expect(BandNotesEditing.removing(a, from: [a, b, a]) == [b, a])
        #expect(BandNotesEditing.removing(BandNote(band: "10m", freqKHz: 0, text: "z"), from: [a, b]) == [a, b])
    }
}
