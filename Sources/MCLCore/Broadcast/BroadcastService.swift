import Foundation

/// Clock of the `BroadcastService` loops (Kotlin `delay`): a wait that `close()` interrupts.
public protocol BroadcastClock: Sendable {
    /// Waits `milliseconds` on the caller's thread; `false` if `cancellation` cancelled the loop in the meantime.
    func sleep(milliseconds: Int64, _ cancellation: BroadcastCancellation) -> Bool
}

/// Cancellation of the loops of one `start()` (Kotlin `Job.cancel`).
public final class BroadcastCancellation: @unchecked Sendable {
    private let condition = NSCondition()
    private var cancelled = false
    /// Monotonic wait (`wait(milliseconds:)`): a semaphore with `DispatchTime`, `cancel` wakes all waiters.
    private let wakeup = DispatchSemaphore(value: 0)
    private var sleepers = 0

    public init() {}

    public var isCancelled: Bool {
        condition.lock()
        defer { condition.unlock() }
        return cancelled
    }

    /// Number of threads currently in `wait(milliseconds:)` (tests).
    var waitingCount: Int {
        condition.lock()
        defer { condition.unlock() }
        return sleepers
    }

    func cancel() {
        condition.lock()
        cancelled = true
        let waiting: Int = sleepers
        condition.broadcast()
        condition.unlock()
        for _ in 0..<waiting {
            wakeup.signal()
        }
    }

    /// Waits `milliseconds` on a **monotonic** clock (`DispatchTime`, like Kotlin `delay` over `System.nanoTime`)
    /// or until cancelled; `false` = cancelled. A wall-clock shift (NTP, manual adjustment — common with FT8) neither
    /// lengthens nor shortens the wait.
    public func wait(milliseconds: Int64) -> Bool {
        condition.lock()
        if cancelled {
            condition.unlock()
            return false
        }
        sleepers += 1
        condition.unlock()
        let (nanos, overflow) = max(0, milliseconds).multipliedReportingOverflow(by: 1_000_000)
        let deadline: DispatchTime = overflow ? .distantFuture : DispatchTime.now() + .nanoseconds(Int(nanos))
        _ = wakeup.wait(timeout: deadline)
        condition.lock()
        sleepers -= 1
        let result: Bool = !cancelled
        condition.unlock()
        return result
    }

    /// Waits until `deadline` or cancellation; `false` = cancelled.
    public func wait(until deadline: Date) -> Bool {
        condition.lock()
        defer { condition.unlock() }
        while !cancelled {
            if !condition.wait(until: deadline) {
                return !cancelled
            }
        }
        return false
    }
}

/// Real time — monotonic (`DispatchTime`), not the wall-clock `Date`.
public struct SystemBroadcastClock: BroadcastClock {
    public init() {}

    public func sleep(milliseconds: Int64, _ cancellation: BroadcastCancellation) -> Bool {
        cancellation.wait(milliseconds: milliseconds)
    }
}

/// UDP broadcast coordinator — the non-UI core of Kotlin `broadcast/BroadcastService.kt` (v1.1.1).
/// Contacts are sent "push" (from the app hooks), radio and score by "pull" loops; everything
/// fire-and-forget, `close()` cancels the loops and closes the broadcaster.
///
/// As in Kotlin:
/// - targets are parsed once in the constructor (`Target.parseAll`); it sends only when the type is enabled **and**
///   there is at least one target;
/// - `start()`: app info once (only when enabled and it has targets), the radio loop and the score loop **always**
///   (a disabled type is filtered out by `sendRadio`/`sendScore`);
/// - radio loop: provider → key `"<freqHz>/<mode>"` (`null` as `"null"`); sends when the key
///   changed **or** `ticks % 10 == 0` (the first pass always), `ticks` grows even without data; then 1 s;
/// - score loop: provider → send, then 10 s;
/// - providers return `nil` when there is no data (CAT not running / no contest).
///
/// Kotlin coroutines on `Dispatchers.IO` are own threads here (`broadcast-radio`, `broadcast-score`,
/// `broadcast-appinfo`) — `UdpBroadcaster` blocks (DNS). Waiting goes through an injected clock
/// (`BroadcastClock`), so that the loop tests do not need wall-clock time. Providers are called on the threads
/// of the loops (the UI prepares its data itself, as in Kotlin).
public final class BroadcastService: @unchecked Sendable {

    public typealias RadioProvider = @Sendable () -> BroadcastXml.RadioData?
    public typealias ScoreProvider = @Sendable () -> BroadcastXml.ScoreData?
    public typealias AppInfoProvider = @Sendable () -> BroadcastXml.AppInfoData

    private let config: BroadcastConfig
    private let broadcaster: any Broadcaster
    private let radioProvider: RadioProvider
    private let scoreProvider: ScoreProvider
    private let appInfoProvider: AppInfoProvider
    private let clock: any BroadcastClock

    private let contactsTargets: [Target]
    private let radioTargets: [Target]
    private let scoreTargets: [Target]
    private let appInfoTargets: [Target]

    private let lock = NSLock()
    private var jobs: [BroadcastCancellation] = []
    private var lastRadioKey: String?

    public init(config: BroadcastConfig, broadcaster: any Broadcaster,
                radioProvider: @escaping RadioProvider, scoreProvider: @escaping ScoreProvider,
                appInfoProvider: @escaping AppInfoProvider, clock: any BroadcastClock = SystemBroadcastClock()) {
        self.config = config
        self.broadcaster = broadcaster
        self.radioProvider = radioProvider
        self.scoreProvider = scoreProvider
        self.appInfoProvider = appInfoProvider
        self.clock = clock
        self.contactsTargets = Target.parseAll(config.contactsTargets)
        self.radioTargets = Target.parseAll(config.radioTargets)
        self.scoreTargets = Target.parseAll(config.scoreTargets)
        self.appInfoTargets = Target.parseAll(config.appInfoTargets)
    }

    public func sendContactInfo(_ c: BroadcastXml.ContactData) {
        maybe(config.contactsEnabled, contactsTargets) { BroadcastXml.contactInfo(c) }
    }

    public func sendContactReplace(_ c: BroadcastXml.ContactData, oldCall: String, oldTs: Date?) {
        maybe(config.contactsEnabled, contactsTargets) { BroadcastXml.contactReplace(c, oldCall: oldCall, oldTs: oldTs) }
    }

    public func sendContactDelete(_ c: BroadcastXml.ContactData) {
        maybe(config.contactsEnabled, contactsTargets) { BroadcastXml.contactDelete(c) }
    }

    public func sendRadio(_ r: BroadcastXml.RadioData) {
        maybe(config.radioEnabled, radioTargets) { BroadcastXml.radioInfo(r) }
    }

    public func sendScore(_ s: BroadcastXml.ScoreData) {
        maybe(config.scoreEnabled, scoreTargets) { BroadcastXml.dynamicResults(s) }
    }

    public func sendAppInfo(_ a: BroadcastXml.AppInfoData) {
        maybe(config.appInfoEnabled, appInfoTargets) { BroadcastXml.appInfo(a) }
    }

    private func maybe(_ enabled: Bool, _ targets: [Target], _ xml: () -> String) {
        if enabled && !targets.isEmpty {
            broadcaster.send(xml(), targets)
        }
    }

    /// Starts app info and the loops; each call starts new ones (like Kotlin `launch`).
    public func start() {
        let job = BroadcastCancellation()
        lock.lock()
        jobs.append(job)
        lock.unlock()
        if config.appInfoEnabled && !appInfoTargets.isEmpty {
            spawn("broadcast-appinfo") { [self] in
                if !job.isCancelled {
                    sendAppInfo(appInfoProvider())
                }
            }
        }
        spawn("broadcast-radio") { [self] in radioLoop(job) }
        spawn("broadcast-score") { [self] in scoreLoop(job) }
    }

    private func spawn(_ name: String, _ body: @escaping @Sendable () -> Void) {
        let thread = Thread(block: body)
        thread.name = name
        thread.start()
    }

    private func radioLoop(_ job: BroadcastCancellation) {
        var ticks: Int32 = 0
        while !job.isCancelled {
            radioStep(ticks: ticks)
            ticks = ticks &+ 1
            if !clock.sleep(milliseconds: 1_000, job) { return }
        }
    }

    /// One pass of the radio loop (Kotlin `radioLoop` without `delay`).
    func radioStep(ticks: Int32) {
        guard let r = radioProvider() else { return }
        let key: String = String(r.freqHz) + "/" + (r.mode ?? "null")
        lock.lock()
        let send: Bool = key != lastRadioKey || ticks % 10 == 0
        if send {
            lastRadioKey = key
        }
        lock.unlock()
        if send {
            sendRadio(r)
        }
    }

    private func scoreLoop(_ job: BroadcastCancellation) {
        while !job.isCancelled {
            if let s = scoreProvider() {
                sendScore(s)
            }
            if !clock.sleep(milliseconds: 10_000, job) { return }
        }
    }

    /// Cancels the loops and closes the broadcaster (Kotlin `runCatching { broadcaster.close() }`).
    public func close() {
        lock.lock()
        let running = jobs
        jobs.removeAll()
        lock.unlock()
        for job in running {
            job.cancel()
        }
        broadcaster.close()
    }
}
