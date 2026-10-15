// Adapted from RYRY's SoftFSKKeyer (https://github.com/ok1xoe/RYRY). Copyright 2026 OK1XOE, GNU LGPL v3
// (third-party/MMTTY/NOTICE.md).
import Darwin
import Foundation

/// The clock of the FSK keyer: monotonic nanoseconds and a sleep until a deadline.
public protocol FskClock: Sendable {
    func now() -> UInt64
    func sleep(untilNanos deadline: UInt64)
}

/// The real clock: `CLOCK_UPTIME_RAW`, a sleep to just before the deadline and a short spin for the edge.
public struct HostFskClock: FskClock {
    public init() {}

    public func now() -> UInt64 {
        clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
    }

    public func sleep(untilNanos deadline: UInt64) {
        while true {
            let current: UInt64 = now()
            guard current < deadline else { return }
            let remaining: UInt64 = deadline - current
            if remaining > 300_000 {
                var request = timespec(tv_sec: 0, tv_nsec: Int(remaining - 200_000))
                if remaining - 200_000 >= 1_000_000_000 {
                    request = timespec(tv_sec: Int((remaining - 200_000) / 1_000_000_000),
                                       tv_nsec: Int((remaining - 200_000) % 1_000_000_000))
                }
                nanosleep(&request, nil)
            }
        }
    }
}

/// Software-timed FSK on a serial port's DTR or RTS line (MMTTY's EXTFSK without a plugin): the key line of
/// `CwKeyLines`, active = space, idle = mark (`invert` swaps them). The built-in modem's Baudot codes (MMTTY bit
/// order) are pulled from `source` as the keyer needs them; each character's edges are timed from its own start, so
/// the error does not add up. Runs on its own thread with real-time priority; `onEnd` is called once the modulator
/// has finished and the last character is out (not after `stop`).
public final class SoftFskKeyer: @unchecked Sendable {

    /// What the keyer asks the modulator for: the next codes and whether the transmission has ended.
    public typealias Source = @Sendable () -> (codes: [UInt8], finished: Bool)

    private let lines: any CwKeyLines
    private let bitNs: Double
    private let stopBits: Double
    private let invert: Bool
    private let clock: any FskClock
    private let source: Source
    private let onEnd: @Sendable () -> Void
    private let condition = NSCondition()
    private var running = false
    private var exited: DispatchSemaphore?
    private var failure: (any Error)?
    private var sent: Int = 0

    public init(lines: any CwKeyLines, baud: Double = 45.45, stopBits: Double = 1.5, invert: Bool = false,
                clock: any FskClock = HostFskClock(), source: @escaping Source,
                onEnd: @escaping @Sendable () -> Void) {
        self.lines = lines
        bitNs = 1e9 / max(baud, 1)
        self.stopBits = stopBits
        self.invert = invert
        self.clock = clock
        self.source = source
        self.onEnd = onEnd
    }

    /// The last error of the line (the keyer stops at it).
    public var lastError: (any Error)? {
        condition.withLock { failure }
    }

    /// Characters sent so far (tests).
    public var charactersSent: Int {
        condition.withLock { sent }
    }

    /// MMTTY code → ITA2 (the LSB goes out first).
    public static func reverse5(_ code: UInt8) -> UInt8 {
        var out: UInt8 = 0
        for bit in 0..<5 where code & (1 << bit) != 0 {
            out |= 1 << (4 - bit)
        }
        return out
    }

    private func setLevel(mark: Bool) -> Bool {
        do {
            try lines.setKey(mark == invert)
            return true
        } catch {
            condition.withLock { failure = error }
            return false
        }
    }

    /// The line to mark and the keying thread started.
    public func start() throws {
        guard setLevel(mark: true) else {
            throw lastError ?? CancellationError()
        }
        let done = DispatchSemaphore(value: 0)
        condition.withLock {
            running = true
            exited = done
        }
        let thread = Thread { [self] in
            run()
            done.signal()
        }
        thread.qualityOfService = .userInteractive
        thread.name = "SoftFskKeyer"
        thread.start()
    }

    /// Stops at once (the character in progress is cut), the line back to mark; waits for the thread (≤ one bit).
    public func stop() {
        let done: DispatchSemaphore? = condition.withLock {
            running = false
            let semaphore = exited
            exited = nil
            return semaphore
        }
        _ = done?.wait(timeout: .now() + .milliseconds(300))
        _ = setLevel(mark: true)
    }

    private var isRunning: Bool {
        condition.withLock { running }
    }

    /// Real-time thread priority (best effort): edges within tens of microseconds.
    private static func makeRealtime() {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        func ticks(_ ns: Double) -> UInt32 {
            UInt32(ns * Double(timebase.denom) / Double(timebase.numer))
        }
        var policy = thread_time_constraint_policy_data_t(period: ticks(22_000_000), computation: ticks(500_000),
                                                          constraint: ticks(2_000_000), preemptible: 1)
        let count = mach_msg_type_number_t(MemoryLayout<thread_time_constraint_policy_data_t>.size
            / MemoryLayout<integer_t>.size)
        _ = withUnsafeMutablePointer(to: &policy) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                thread_policy_set(pthread_mach_thread_np(pthread_self()),
                                  thread_policy_flavor_t(THREAD_TIME_CONSTRAINT_POLICY), $0, count)
            }
        }
    }

    private func run() {
        if clock is HostFskClock {
            Self.makeRealtime()
        }
        var queue: [UInt8] = []
        var head = 0
        var finished = false
        var nextStart: UInt64 = 0
        var ended = false
        while isRunning {
            if head >= queue.count {
                if finished {
                    ended = true
                    break
                }
                let next = source()
                queue = next.codes
                head = 0
                finished = next.finished
                continue
            }
            let code: UInt8 = Self.reverse5(queue[head])
            head += 1
            let start: UInt64 = max(clock.now(), nextStart)
            var last: Bool?
            var broken = false
            for bit in 0..<6 {
                let mark: Bool = bit == 0 ? false : code & (1 << (bit - 1)) != 0
                clock.sleep(untilNanos: start + UInt64((Double(bit) * bitNs).rounded()))
                guard isRunning else { break }
                if mark != last {
                    guard setLevel(mark: mark) else {
                        broken = true
                        break
                    }
                    last = mark
                }
            }
            guard isRunning, !broken else { break }
            clock.sleep(untilNanos: start + UInt64((6 * bitNs).rounded()))
            if last != true {
                guard setLevel(mark: true) else { break }
            }
            nextStart = start + UInt64(((6 + stopBits) * bitNs).rounded())
            clock.sleep(untilNanos: nextStart)
            condition.withLock { sent += 1 }
        }
        _ = setLevel(mark: true)
        let failed: Bool = lastError != nil
        if (ended || failed) && isRunning {
            onEnd()
        }
    }
}
