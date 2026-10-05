import Foundation
import Testing
@testable import MCLCore

/// A port of the Kotlin `BroadcastServiceTest.kt` (4 tests)
/// + the radio and score loops over manual clocks (without wall-clock time).
@Suite(.ioSafetyNet) struct BroadcastServiceTests {

    final class FakeBroadcaster: Broadcaster, @unchecked Sendable {
        private let condition = NSCondition()
        private var items: [(String, [Target])] = []
        private var closedFlag = false

        func send(_ xml: String, _ targets: [Target]) {
            condition.lock()
            items.append((xml, targets))
            condition.broadcast()
            condition.unlock()
        }

        func send(_ data: [UInt8], _ targets: [Target]) {
            // The N1MM tests do not use the binary path.
        }

        func close() {
            condition.lock()
            closedFlag = true
            condition.unlock()
        }

        var sent: [(String, [Target])] {
            condition.lock()
            defer { condition.unlock() }
            return items
        }

        var closed: Bool {
            condition.lock()
            defer { condition.unlock() }
            return closedFlag
        }

        /// Blocking (own thread): waits for at least `count` sends; `false` after the guard `ioWait`.
        func waitFor(_ count: Int) -> Bool {
            let deadline = Date(timeIntervalSinceNow: ioWait)
            condition.lock()
            defer { condition.unlock() }
            while items.count < count {
                if !condition.wait(until: deadline) { return items.count >= count }
            }
            return true
        }
    }

    /// A manual clock: every `sleep` is recorded and waits for `release(ms)` (one permit for the loop with that
    /// period) or for cancellation.
    final class ManualClock: BroadcastClock, @unchecked Sendable {
        private let condition = NSCondition()
        private var requests: [Int64] = []
        private var permits: [Int64: Int] = [:]
        private var cancelledReturns = 0

        func sleep(milliseconds: Int64, _ cancellation: BroadcastCancellation) -> Bool {
            condition.lock()
            defer { condition.unlock() }
            requests.append(milliseconds)
            condition.broadcast()
            while true {
                if cancellation.isCancelled {
                    cancelledReturns += 1
                    condition.broadcast()
                    return false
                }
                if let n = permits[milliseconds], n > 0 {
                    permits[milliseconds] = n - 1
                    return true
                }
                condition.wait()
            }
        }

        func release(_ milliseconds: Int64) {
            condition.lock()
            permits[milliseconds, default: 0] += 1
            condition.broadcast()
            condition.unlock()
        }

        /// Wakes the waiters so they read the cancellation.
        func interrupt() {
            condition.lock()
            condition.broadcast()
            condition.unlock()
        }

        /// `false` after the guard `ioWait`.
        func waitForRequests(_ count: Int, of milliseconds: Int64) -> Bool {
            let deadline = Date(timeIntervalSinceNow: ioWait)
            condition.lock()
            defer { condition.unlock() }
            while requests.filter({ $0 == milliseconds }).count < count {
                if !condition.wait(until: deadline) { return requests.filter({ $0 == milliseconds }).count >= count }
            }
            return true
        }

        /// `false` after the guard `ioWait`.
        func waitForCancelledReturns(_ count: Int) -> Bool {
            let deadline = Date(timeIntervalSinceNow: ioWait)
            condition.lock()
            defer { condition.unlock() }
            while cancelledReturns < count {
                if !condition.wait(until: deadline) { return cancelledReturns >= count }
            }
            return true
        }
    }

    private static func contact() -> BroadcastXml.ContactData {
        BroadcastXml.ContactData(
            contestName: "", contestNr: 1, timestamp: Date(timeIntervalSince1970: 1_782_999_900), myCall: "OK1XOE",
            rxFreqHz: 3_525_190, txFreqHz: 3_525_190, mode: "CW", call: "A51AS", continent: "AS", snt: "599", sntNr: 1,
            rcv: "599", rcvNr: 28, points: 3, isMultiplier: true, id: "id", stationName: "OK1XOE")
    }

    private static func appInfo() -> BroadcastXml.AppInfoData {
        BroadcastXml.AppInfoData(dbName: "db", contestNr: 1, contestName: "", stationName: "S", myCall: "OK1XOE")
    }

    private static func service(_ cfg: BroadcastConfig, _ fake: FakeBroadcaster) -> BroadcastService {
        BroadcastService(config: cfg, broadcaster: fake, radioProvider: { nil }, scoreProvider: { nil },
                         appInfoProvider: { appInfo() })
    }

    @Test func sendsContactInfoWhenEnabled() {
        var cfg = BroadcastConfig()
        cfg.contactsEnabled = true
        cfg.contactsTargets = "127.0.0.1:12060"
        let fake = FakeBroadcaster()
        let s = Self.service(cfg, fake)
        s.sendContactInfo(Self.contact())
        #expect(fake.sent.count == 1)
        #expect(fake.sent[0].0.hasPrefix("<contactinfo>"))
        #expect(fake.sent[0].1.count == 1)
    }

    @Test func skipsWhenDisabled() {
        var cfg = BroadcastConfig()
        cfg.contactsEnabled = false
        cfg.contactsTargets = "127.0.0.1:12060"
        let fake = FakeBroadcaster()
        Self.service(cfg, fake).sendContactInfo(Self.contact())
        #expect(fake.sent.isEmpty)
    }

    @Test func skipsWhenNoTargets() {
        var cfg = BroadcastConfig()
        cfg.contactsEnabled = true
        cfg.contactsTargets = ""
        let fake = FakeBroadcaster()
        Self.service(cfg, fake).sendContactInfo(Self.contact())
        #expect(fake.sent.isEmpty)
    }

    @Test func radioSendUsesRadioTargets() {
        var cfg = BroadcastConfig()
        cfg.radioEnabled = true
        cfg.radioTargets = "127.0.0.1:1 127.0.0.1:2"
        let fake = FakeBroadcaster()
        let s = Self.service(cfg, fake)
        s.sendRadio(BroadcastXml.RadioData(stationName: "S", freqHz: 14_025_400, mode: "CW", opCall: "OP", isRunning: true))
        #expect(fake.sent.count == 1)
        #expect(fake.sent[0].0.hasPrefix("<RadioInfo>"))
        #expect(fake.sent[0].1.count == 2)
    }

    // MARK: - Loops (Kotlin `radioLoop`/`scoreLoop`, over manual clocks)

    final class RadioScript: @unchecked Sendable {
        private let lock = NSLock()
        private var value: BroadcastXml.RadioData?
        var current: BroadcastXml.RadioData? {
            get { lock.lock(); defer { lock.unlock() }; return value }
            set { lock.lock(); value = newValue; lock.unlock() }
        }
    }

    private static func radio(_ freq: Int64, _ mode: String?) -> BroadcastXml.RadioData {
        BroadcastXml.RadioData(stationName: "S", freqHz: freq, mode: mode, opCall: "OP", isRunning: false)
    }

    /// The key `freq/mode`: sent on a change or every 10th tick (the first always); without data nothing is sent.
    @Test func radioStepSendsOnChangeAndEveryTenthTick() {
        var cfg = BroadcastConfig()
        cfg.radioEnabled = true
        cfg.radioTargets = "127.0.0.1:12060"
        let fake = FakeBroadcaster()
        let script = RadioScript()
        let s = BroadcastService(config: cfg, broadcaster: fake, radioProvider: { script.current },
                                 scoreProvider: { nil }, appInfoProvider: { Self.appInfo() })
        script.current = Self.radio(14_025_000, "CW")
        let plan: [(Int32, BroadcastXml.RadioData?, Int)] = [
            (0, Self.radio(14_025_000, "CW"), 1),   // first tick
            (1, Self.radio(14_025_000, "CW"), 1),   // unchanged
            (2, Self.radio(14_025_010, "CW"), 2),   // frequency change
            (3, Self.radio(14_025_010, nil), 3),    // mode change (nil → "null")
            (4, Self.radio(14_025_010, nil), 3),
            (5, nil, 3),                            // without data
            (10, Self.radio(14_025_010, nil), 4),   // every 10th tick
            (11, Self.radio(14_025_010, nil), 4),
            (-10, Self.radio(14_025_010, nil), 5),  // Kotlin `Int` after overflow: -10 % 10 == 0
        ]
        for (ticks, data, expected) in plan {
            script.current = data
            s.radioStep(ticks: ticks)
            #expect(fake.sent.count == expected, "tick \(ticks)")
        }
    }

    /// `start()`: app info once, radio with a period of 1 s, score 10 s; `close()` cancels the loops and closes the broadcaster.
    @Test func loopsUseClockAndStopOnClose() async {
        var cfg = BroadcastConfig()
        cfg.radioEnabled = true
        cfg.radioTargets = "127.0.0.1:1"
        cfg.scoreEnabled = true
        cfg.scoreTargets = "127.0.0.1:2"
        cfg.appInfoEnabled = true
        cfg.appInfoTargets = "127.0.0.1:3"
        let fake = FakeBroadcaster()
        let clock = ManualClock()
        let score = BroadcastXml.ScoreData(contest: "C", call: "OK1XOE", ops: "", score: 10, timestamp: nil)
        let s = BroadcastService(config: cfg, broadcaster: fake, radioProvider: { Self.radio(7_000_000, "CW") },
                                 scoreProvider: { score }, appInfoProvider: { Self.appInfo() }, clock: clock)
        s.start()
        let started: Bool = await onOwnThread {
            clock.waitForRequests(1, of: 1_000) && clock.waitForRequests(1, of: 10_000) && fake.waitFor(3)
        }
        #expect(started)
        let first: [String] = fake.sent.map { item in String(item.0.prefix { $0 != ">" }) }.sorted()
        #expect(first == ["<AppInfo", "<RadioInfo", "<dynamicresults"])

        // the next radio tick without a change sends nothing, a score tick does
        clock.release(1_000)
        clock.release(10_000)
        let ticked: Bool = await onOwnThread {
            clock.waitForRequests(2, of: 1_000) && clock.waitForRequests(2, of: 10_000)
        }
        #expect(ticked)
        #expect(fake.sent.count == 4)
        #expect(fake.sent[3].0.hasPrefix("<dynamicresult"))

        s.close()
        clock.interrupt()
        #expect(await onOwnThread { clock.waitForCancelledReturns(2) })
        #expect(fake.closed)
        #expect(fake.sent.count == 4)
    }

    /// `SystemBroadcastClock` waits on a monotonic clock (`DispatchTime`): a short wait finishes (`true`),
    /// cancellation also wakes a wait for the clock (`false`, without a wall-clock bound — the only guard is `ioSafetyNet`), after cancellation
    /// it no longer waits.
    @Test func systemClockSleepsMonotonicallyAndWakesOnCancel() async {
        let clock = SystemBroadcastClock()
        let job = BroadcastCancellation()
        #expect(await onOwnThread { clock.sleep(milliseconds: 1, job) })
        let sleeper = Inbox<Bool>()
        let thread = Thread { sleeper.offer(clock.sleep(milliseconds: 3_600_000, job)) }
        thread.start()
        let waiting: Bool = await onOwnThread {
            let deadline = Date(timeIntervalSinceNow: ioWait)
            while job.waitingCount == 0 && Date() < deadline {
                usleep(1_000)
            }
            return job.waitingCount == 1
        }
        #expect(waiting)
        job.cancel()
        #expect(await onOwnThread { sleeper.take() } == false)
        #expect(await onOwnThread { clock.sleep(milliseconds: 3_600_000, job) } == false)
    }
}
