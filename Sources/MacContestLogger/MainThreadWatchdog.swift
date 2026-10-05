import Foundation
import MCLAppModel

/// Development measurement ("the main thread never blocks for more than 100 ms"): with
/// `MCL_PERF_WATCHDOG=1` a timer on its own queue posts a ping to the main queue every 50 ms and logs
/// `main-stall <ms> ms` (category `perf`) when the main thread answered more than 100 ms late.
final class MainThreadWatchdog: @unchecked Sendable {

    static let shared = MainThreadWatchdog()

    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["MCL_PERF_WATCHDOG"] == "1"
    }

    private let queue = DispatchQueue(label: "cz.ok1xoe.maccontestlogger.watchdog", qos: .utility)
    private var timer: DispatchSourceTimer?
    private let thresholdNanoseconds: UInt64 = 100_000_000

    func start() {
        queue.async {
            guard self.timer == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(50))
            timer.setEventHandler {
                self.ping()
            }
            self.timer = timer
            timer.resume()
        }
    }

    private func ping() {
        let sent: UInt64 = DispatchTime.now().uptimeNanoseconds
        let threshold: UInt64 = thresholdNanoseconds
        DispatchQueue.main.async {
            let late: UInt64 = DispatchTime.now().uptimeNanoseconds &- sent
            if late > threshold {
                Perf.note("main-stall " + String(format: "%.1f", Double(late) / 1_000_000) + " ms")
            }
        }
    }
}
