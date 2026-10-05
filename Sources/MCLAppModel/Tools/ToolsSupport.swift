import Foundation
import MCLCore
import Observation

/// A repeating timer on an injected clock (the ticks of the Info window, the sked and TOUR watchers, the map's night
/// layer). Stopping cancels the pending timer; a tick in flight never reschedules after `stop`.
@MainActor
final class RepeatingTick {
    private let clock: any RescoreClock
    private let milliseconds: Int
    private let body: @MainActor () -> Void
    private var timer: (any RescoreTimer)?
    private var running = false

    init(clock: any RescoreClock, milliseconds: Int, _ body: @escaping @MainActor () -> Void) {
        self.clock = clock
        self.milliseconds = milliseconds
        self.body = body
    }

    var isRunning: Bool {
        running
    }

    /// Schedules the first tick after one period (the caller runs an immediate pass itself when it needs one).
    func start() {
        guard !running else { return }
        running = true
        schedule()
    }

    func stop() {
        running = false
        timer?.cancel()
        timer = nil
    }

    private func schedule() {
        timer = clock.schedule(afterMilliseconds: milliseconds) { [weak self] in
            guard let self, self.running else { return }
            self.body()
            if self.running {
                self.schedule()
            }
        }
    }
}

extension SerialLane {

    /// Runs `body` on the lane and returns its result without blocking a cooperative thread.
    func run<T: Sendable>(_ body: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { (continuation: CheckedContinuation<T, Never>) in
            submit {
                continuation.resume(returning: body())
            }
        }
    }
}

/// What a window's snapshot is computed from: the log of the active contest, recomputed off the main thread whenever
/// the log's revision (or anything the window reads besides it) changes. Every run takes a generation; a result whose
/// generation is no longer the current one — a QSO arrived while it was computed, the window closed — is dropped.
@MainActor
final class LogDerived<Value: Sendable> {

    /// The pure computation over a copy of the rows (runs off the main thread).
    typealias Job = @Sendable ([Qso]) -> Value

    /// Prepares a job on the main actor (reads what the job needs besides the rows); tests replace it.
    var source: @MainActor () -> Job
    /// A log of at most this many rows is computed inline on the main actor (small windows redraw at once); a
    /// negative limit computes every log off the main thread.
    var inlineLimit = -1

    private let logbook: LogbookModel
    private let tracked: @MainActor () -> Void
    private let apply: @MainActor (Value) -> Void
    private let debounce: (clock: any RescoreClock, milliseconds: Int)?
    private(set) var generation = 0
    private var running = false
    private var timer: (any RescoreTimer)?
    private var tasks: [Task<Void, Never>] = []

    /// - Parameters:
    ///   - tracked: reads the observable state besides `logbook.revision` that makes the snapshot stale.
    ///   - debounce: a change schedules the run after this delay; a newer change replaces the pending run.
    init(logbook: LogbookModel, debounce: (clock: any RescoreClock, milliseconds: Int)? = nil,
         tracked: @escaping @MainActor () -> Void = {}, source: @escaping @MainActor () -> Job,
         apply: @escaping @MainActor (Value) -> Void) {
        self.logbook = logbook
        self.debounce = debounce
        self.tracked = tracked
        self.source = source
        self.apply = apply
    }

    var isRunning: Bool {
        running
    }

    /// Starts observing and computes once.
    func start() {
        guard !running else { return }
        running = true
        observe()
        refresh()
    }

    /// Stops observing; a result still in flight is dropped.
    func stop() {
        running = false
        generation += 1
        timer?.cancel()
        timer = nil
    }

    /// Asks for a new snapshot (debounced when configured).
    func refresh() {
        guard running else { return }
        if let debounce {
            timer?.cancel()
            timer = debounce.clock.schedule(afterMilliseconds: debounce.milliseconds) { [weak self] in
                self?.run()
            }
        } else {
            run()
        }
    }

    /// Waits for the computations started so far.
    func settle() async {
        let pending: [Task<Void, Never>] = tasks
        for task in pending {
            await task.value
        }
        tasks.removeFirst(min(pending.count, tasks.count))
    }

    private func run() {
        guard running else { return }
        timer = nil
        generation += 1
        let mine: Int = generation
        let rows: [Qso] = logbook.rows
        let job: Job = source()
        if inlineLimit >= 0, rows.count <= inlineLimit {
            apply(job(rows))
            return
        }
        let task = Task { [weak self] in
            let value: Value? = try? await BlockingQueue.run {
                job(rows)
            }
            guard let self, self.running, mine == self.generation, let value else { return }
            self.apply(value)
        }
        tasks.append(task)
        if tasks.count > 8 {
            tasks.removeFirst(tasks.count - 8)
        }
    }

    private func observe() {
        withObservationTracking {
            _ = logbook.revision
            tracked()
        } onChange: { [weak self] in
            MainHop.post {
                guard let self, self.running else { return }
                self.refresh()
                self.observe()
            }
        }
    }
}
