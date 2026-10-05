import Foundation

/// A cancellable scheduled action of a `RescoreClock`.
@MainActor
public protocol RescoreTimer: AnyObject {
    func cancel()
}

/// Time source of `RescoreScheduler`: runs `fire` on the main actor after a delay. Tests inject a fake clock and
/// advance it by hand.
@MainActor
public protocol RescoreClock: AnyObject {
    func schedule(afterMilliseconds delay: Int, _ fire: @escaping @MainActor @Sendable () -> Void) -> any RescoreTimer
}

/// Production clock: the main dispatch queue (`asyncAfter`).
@MainActor
public final class MainQueueRescoreClock: RescoreClock {

    public init() {}

    public func schedule(afterMilliseconds delay: Int,
                         _ fire: @escaping @MainActor @Sendable () -> Void) -> any RescoreTimer {
        let item = DispatchWorkItem {
            MainActor.assumeIsolated {
                fire()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delay), execute: item)
        return WorkItemTimer(item)
    }

    private final class WorkItemTimer: RescoreTimer {
        private let item: DispatchWorkItem

        init(_ item: DispatchWorkItem) {
            self.item = item
        }

        func cancel() {
            item.cancel()
        }
    }
}

/// Score recount scheduling (N1MM Rescore) from the Kotlin `AppState.requestRescore` (v1.1.1).
///
/// The scheduler decides **when** to recount and what to do with a finished result; the replay itself
/// (`ContestRuntime.freshSession` + `ContestReplay`, off the main actor), `adopt` and the DXCC backfill are run by the
/// owner. Flow:
/// 0. **Before** calling `request` the owner captures what Kotlin captures at request time (KA:1229-1232): the active
///    contest id, the log snapshot (of `revision`) and the score total before (`score?.total`). A manual request runs
///    `onRun` synchronously inside `request`, so capturing afterwards would be too late.
/// 1. `request(manual:isActive:revision:)` — outside a contest a manual request returns
///    „Přepočet skóre: není aktivní závod", an automatic one nothing; otherwise the previous pending job is cancelled
///    and a new `Job` is due: automatic after 300 ms (a burst of requests collapses into the last one), manual at
///    once. A due job is delivered to `onRun` („replay the log of revision N").
/// 2. When the replay finishes the owner calls `finish(_:currentRevision:)`: a job that was superseded or cancelled
///    meanwhile → `.discard`; the log changed since the request → `.rerun` (the owner requests again with the same
///    `manual`, as Kotlin calls `requestRescore(manual)`); otherwise `.adopt`.
/// 3. After a successful `adopt` (with the captured contest id) of a manual job the owner backfills DXCC
///    (`backfillDxcc` over the captured snapshot, off the main thread), bumps the log revision when
///    `filled > 0` (KA:1243 `logRevision++`, the table shows the filled countries) and shows `summary` with the
///    captured score before and the adopted score after.
@MainActor
public final class RescoreScheduler {

    /// Kotlin `RESCORE_DEBOUNCE_MS`.
    public static let debounceMilliseconds = 300

    /// One recount: the log revision it was requested for and whether it is manual.
    public struct Job: Equatable, Sendable {
        public let generation: Int
        public let revision: Int64
        public let manual: Bool
    }

    public enum Completion: Equatable, Sendable {
        /// Superseded or cancelled — drop the result.
        case discard
        /// The log changed during the replay — request again (`manual` as before).
        case rerun(manual: Bool)
        /// Take the result over (`ContestRuntime.adopt`).
        case adopt
    }

    private let clock: any RescoreClock
    private var pending: (any RescoreTimer)?
    private var generation = 0
    private var running: Job?

    /// Receives a due job; the owner starts the replay.
    public var onRun: ((Job) -> Void)?

    public init(clock: any RescoreClock) {
        self.clock = clock
    }

    /// Requests a recount of the log at `revision`. Returns the status text to show at once (only a manual request
    /// outside a contest has one).
    @discardableResult
    public func request(manual: Bool = false, isActive: Bool, revision: Int64) -> ContestMessage? {
        if !isActive {
            return manual ? ContestMessage("Přepočet skóre: není aktivní závod") : nil
        }
        cancel()
        generation += 1
        let job = Job(generation: generation, revision: revision, manual: manual)
        if manual {
            start(job)
        } else {
            pending = clock.schedule(afterMilliseconds: Self.debounceMilliseconds) { [weak self] in
                self?.start(job)
            }
        }
        return nil
    }

    /// Cancels the pending and the running job (its result will be discarded).
    public func cancel() {
        pending?.cancel()
        pending = nil
        running = nil
    }

    /// Is a job pending or running?
    public var isBusy: Bool {
        pending != nil || running != nil
    }

    private func start(_ job: Job) {
        guard job.generation == generation else { return }
        pending = nil
        running = job
        onRun?(job)
    }

    /// What to do with the replay of `job` when the log is now at `currentRevision`.
    public func finish(_ job: Job, currentRevision: Int64) -> Completion {
        guard let running, running == job else { return .discard }
        self.running = nil
        if job.revision != currentRevision {
            return .rerun(manual: job.manual)
        }
        return .adopt
    }

    // MARK: - manual recount extras

    /// DXCC backfill of the manual recount (Kotlin `backfillDxcc` inside `runCatching { … }.getOrDefault(0)`): fills
    /// missing countries, saves every changed QSO through `update` and returns their count; **any** error → 0 (even
    /// when some QSOs were already saved). Blocking — run off the main thread.
    nonisolated public static func backfillDxcc(_ snapshot: [Qso], dxcc: (any DxccLookup)?,
                                                update: (Qso) throws -> Void) -> Int {
        guard let dxcc else { return 0 }
        var qsos: [Qso] = snapshot
        let changed: [Qso] = DxccFiller.fillAll(&qsos, dxcc)
        do {
            for qso in changed {
                try update(qso)
            }
        } catch {
            return 0
        }
        return changed.count
    }

    /// Status parts of a manual recount, joined by `" · "` (`summaryText`): „Skóre přepočteno: …" with „předtím %s"
    /// when the total changed from a known one, otherwise „beze změny"; skipped QSOs and filled countries when
    /// non-zero. `after` is the adopted score total (`0` without a score).
    nonisolated public static func summary(replayed: Int, skipped: Int, before: Int64?, after: Int64,
                                           filled: Int) -> [ContestMessage] {
        let change: ContestMessage
        if let before, before != after {
            change = ContestMessage("předtím %s", .string(String(before)))
        } else {
            change = ContestMessage("beze změny")
        }
        let head = ContestMessage("Skóre přepočteno: %s QSO, celkem %s (%s)",
                                  parts: [.value(.int(replayed)), .value(.string(String(after))), .message(change)])
        var parts: [ContestMessage] = [head]
        if skipped > 0 {
            parts.append(ContestMessage("%s QSO nešlo započítat", .int(skipped)))
        }
        if filled > 0 {
            parts.append(ContestMessage("doplněna země u %s QSO", .int(filled)))
        }
        return parts
    }

    /// `summary` translated and joined like Kotlin `buildString`.
    nonisolated public static func summaryText(_ parts: [ContestMessage], translator: Translator,
                                               decimalSeparator: String = ".") -> String {
        parts.map { $0.text(translator, decimalSeparator: decimalSeparator) }.joined(separator: " · ")
    }
}
