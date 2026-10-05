import Foundation
import Testing
@testable import MCLCore

/// `RescoreScheduler` against the Kotlin `AppState.requestRescore` (v1.1.1, read from the source): debounce 300 ms,
/// cancellation of the previous job, recount again when the log changed during the replay, the manual summary.
/// Time is a fake clock advanced by hand.
@MainActor
@Suite struct RescoreSchedulerTests {

    @MainActor
    final class FakeClock: RescoreClock {
        final class Timer: RescoreTimer {
            let due: Int
            let fire: @MainActor @Sendable () -> Void
            var cancelled = false

            init(due: Int, fire: @escaping @MainActor @Sendable () -> Void) {
                self.due = due
                self.fire = fire
            }

            func cancel() {
                cancelled = true
            }
        }

        var now = 0
        var timers: [Timer] = []

        func schedule(afterMilliseconds delay: Int,
                      _ fire: @escaping @MainActor @Sendable () -> Void) -> any RescoreTimer {
            let timer = Timer(due: now + delay, fire: fire)
            timers.append(timer)
            return timer
        }

        func advance(_ milliseconds: Int) {
            now += milliseconds
            let due = timers.filter { !$0.cancelled && $0.due <= now }
            timers.removeAll { $0.cancelled || $0.due <= now }
            for timer in due {
                timer.fire()
            }
        }
    }

    final class Recorder {
        var jobs: [RescoreScheduler.Job] = []
    }

    static func scheduler() -> (RescoreScheduler, FakeClock, Recorder) {
        let clock = FakeClock()
        let scheduler = RescoreScheduler(clock: clock)
        let recorder = Recorder()
        scheduler.onRun = { recorder.jobs.append($0) }
        return (scheduler, clock, recorder)
    }

    @Test func notActive() {
        let (scheduler, clock, recorder) = Self.scheduler()
        #expect(scheduler.request(manual: true, isActive: false, revision: 1)?.czech
                == "Přepočet skóre: není aktivní závod")
        #expect(scheduler.request(manual: false, isActive: false, revision: 1) == nil)
        clock.advance(1_000)
        #expect(recorder.jobs.isEmpty)
        #expect(!scheduler.isBusy)
    }

    @Test func automaticRequestWaits300Ms() {
        let (scheduler, clock, recorder) = Self.scheduler()
        #expect(scheduler.request(isActive: true, revision: 7) == nil)
        clock.advance(299)
        #expect(recorder.jobs.isEmpty)
        clock.advance(1)
        #expect(recorder.jobs.map(\.revision) == [7])
        #expect(recorder.jobs.first?.manual == false)
    }

    @Test func burstCollapsesIntoLastRequest() {
        let (scheduler, clock, recorder) = Self.scheduler()
        scheduler.request(isActive: true, revision: 1)
        clock.advance(200)
        scheduler.request(isActive: true, revision: 2)
        clock.advance(200)
        scheduler.request(isActive: true, revision: 3)
        clock.advance(299)
        #expect(recorder.jobs.isEmpty)
        clock.advance(1)
        #expect(recorder.jobs.map(\.revision) == [3])
    }

    @Test func manualRunsAtOnceAndCancelsPending() {
        let (scheduler, clock, recorder) = Self.scheduler()
        scheduler.request(isActive: true, revision: 1)
        scheduler.request(manual: true, isActive: true, revision: 2)
        #expect(recorder.jobs.map(\.revision) == [2])
        #expect(recorder.jobs.first?.manual == true)
        clock.advance(1_000)
        #expect(recorder.jobs.count == 1, "the automatic job was cancelled")
    }

    @Test func finishAdoptsWhenTheLogDidNotChange() throws {
        let (scheduler, clock, recorder) = Self.scheduler()
        scheduler.request(isActive: true, revision: 5)
        clock.advance(300)
        let job = try #require(recorder.jobs.first)
        #expect(scheduler.isBusy)
        #expect(scheduler.finish(job, currentRevision: 5) == .adopt)
        #expect(!scheduler.isBusy)
        #expect(scheduler.finish(job, currentRevision: 5) == .discard, "finished once")
    }

    @Test func finishRerunsWhenTheLogChanged() throws {
        let (scheduler, _, recorder) = Self.scheduler()
        scheduler.request(manual: true, isActive: true, revision: 5)
        let job = try #require(recorder.jobs.first)
        #expect(scheduler.finish(job, currentRevision: 6) == .rerun(manual: true))
    }

    @Test func supersededOrCancelledJobIsDiscarded() throws {
        let (scheduler, clock, recorder) = Self.scheduler()
        scheduler.request(manual: true, isActive: true, revision: 1)
        let first = try #require(recorder.jobs.first)
        scheduler.request(isActive: true, revision: 2)
        #expect(scheduler.finish(first, currentRevision: 1) == .discard)
        clock.advance(300)
        let second = try #require(recorder.jobs.last)
        scheduler.cancel()
        #expect(scheduler.finish(second, currentRevision: 2) == .discard)
    }

    @Test func cancelStopsPendingJob() {
        let (scheduler, clock, recorder) = Self.scheduler()
        scheduler.request(isActive: true, revision: 1)
        scheduler.cancel()
        clock.advance(1_000)
        #expect(recorder.jobs.isEmpty)
        #expect(!scheduler.isBusy)
    }

    // MARK: - manual summary and backfill

    @Test func summaryTexts() {
        let source = Translator.source
        let unchanged = RescoreScheduler.summary(replayed: 12, skipped: 0, before: 340, after: 340, filled: 0)
        #expect(RescoreScheduler.summaryText(unchanged, translator: source)
                == "Skóre přepočteno: 12 QSO, celkem 340 (beze změny)")
        let firstScore = RescoreScheduler.summary(replayed: 1, skipped: 0, before: nil, after: 3, filled: 0)
        #expect(RescoreScheduler.summaryText(firstScore, translator: source)
                == "Skóre přepočteno: 1 QSO, celkem 3 (beze změny)")
        let all = RescoreScheduler.summary(replayed: 1234, skipped: 2, before: 1_000_000, after: 2_500_000, filled: 3)
        #expect(RescoreScheduler.summaryText(all, translator: source)
                == "Skóre přepočteno: 1234 QSO, celkem 2500000 (předtím 1000000) · 2 QSO nešlo započítat"
                + " · doplněna země u 3 QSO")
    }

    @Test func summaryTranslates() {
        let english = Translator(language: "en", translations: LanguageCatalog.Translations([
            JavaStringKey("Skóre přepočteno: %s QSO, celkem %s (%s)"): "Score recalculated: %s QSOs, %s in total (%s)",
            JavaStringKey("beze změny"): "no change",
        ]))
        let parts = RescoreScheduler.summary(replayed: 2, skipped: 0, before: 4, after: 4, filled: 0)
        #expect(RescoreScheduler.summaryText(parts, translator: english)
                == "Score recalculated: 2 QSOs, 4 in total (no change)")
    }

    @Test func backfillCountsChangedAndZeroOnError() throws {
        let dxcc = try SessionFixture.dxcc()
        var known = Qso()
        known.call = "OK1ABC"
        var filled = Qso()
        filled.call = "W1AW"
        filled.dxccEntity = 291
        filled.dxccName = "United States"
        filled.continent = "NA"
        var unknown = Qso()
        unknown.call = "ZZ9ZZ"
        var saved: [String] = []
        let count = RescoreScheduler.backfillDxcc([known, filled, unknown], dxcc: dxcc) { saved.append($0.call) }
        #expect(count == 1)
        #expect(saved == ["OK1ABC"])

        struct Boom: Error {}
        let failed = RescoreScheduler.backfillDxcc([known], dxcc: dxcc) { _ in throw Boom() }
        #expect(failed == 0)
        #expect(RescoreScheduler.backfillDxcc([known], dxcc: nil) { _ in } == 0)
    }

    @Test func mainQueueClockFires() async {
        let clock = MainQueueRescoreClock()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            _ = clock.schedule(afterMilliseconds: 0) {
                continuation.resume()
            }
        }
    }
}
