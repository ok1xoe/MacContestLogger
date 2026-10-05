import Foundation
import os

/// Performance intervals of the app: an `os_signpost` interval for Instruments and a `Logger` line with
/// the duration for `log stream`, both under subsystem `cz.ok1xoe.maccontestlogger`, category `perf`:
///
/// ```
/// log stream --level info --predicate 'subsystem == "cz.ok1xoe.maccontestlogger" AND category == "perf"'
/// ```
///
/// A line reads `<name> <ms> ms main|off <detail>`; `main` = the interval ended on the main thread. Intervals cost
/// two clock reads and one log call, so they stay in release builds.
public enum Perf {

    public static let subsystem = "cz.ok1xoe.maccontestlogger"

    private static let signposter = OSSignposter(subsystem: subsystem, category: "perf")
    private static let logger = Logger(subsystem: subsystem, category: "perf")

    /// A started interval.
    public struct Interval: Sendable {
        fileprivate let name: StaticString
        fileprivate let state: OSSignpostIntervalState
        fileprivate let startNanoseconds: UInt64
    }

    public static func begin(_ name: StaticString) -> Interval {
        Interval(name: name, state: signposter.beginInterval(name),
                 startNanoseconds: DispatchTime.now().uptimeNanoseconds)
    }

    /// Ends the interval and logs its duration; `detail` (e.g. a row count) is appended to the line.
    public static func end(_ interval: Interval, _ detail: String = "") {
        signposter.endInterval(interval.name, interval.state)
        let elapsed: UInt64 = DispatchTime.now().uptimeNanoseconds &- interval.startNanoseconds
        let milliseconds = Double(elapsed) / 1_000_000
        let name = String(describing: interval.name)
        let thread: String = Thread.isMainThread ? "main" : "off"
        let duration: String = String(format: "%.2f", milliseconds)
        var text: String = name
        text += " " + duration
        text += " ms " + thread
        if !detail.isEmpty {
            text += " " + detail
        }
        logger.info("\(text, privacy: .public)")
    }

    /// Measures `body` as one interval.
    public static func measure<T>(_ name: StaticString, _ detail: String = "", _ body: () throws -> T) rethrows -> T {
        let interval: Interval = begin(name)
        defer { end(interval, detail) }
        return try body()
    }

    /// A plain log line in the same category (e.g. a main-thread stall).
    public static func note(_ text: String) {
        logger.info("\(text, privacy: .public)")
    }
}
