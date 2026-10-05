import Foundation

/// Quit trace of debug builds only, for the end-to-end quit check (`scripts/quit-e2e.py`): with
/// `MCL_QUIT_TRACE=<file>` the app appends one line per quit event (`ready`, `terminate`, `should terminate …`,
/// `deadline armed <s> s`, `milestone transmitReleased=<bool>`, `shutdown finished`, `will terminate`,
/// `force exit <code>`, `cleanup done`, …). Without the variable, and in release builds, nothing is written.
///
/// `MCL_DEBUG_STALL_QUIT=1` (debug builds only) holds the quit sequence before it starts, as a quit wedged before the
/// transmit release would be, so the check can see the deadline of a deferred exit end the process.
enum QuitTrace {

    #if DEBUG
    private static let path: String? = {
        guard let value = ProcessInfo.processInfo.environment["MCL_QUIT_TRACE"], !value.isEmpty else { return nil }
        return value
    }()

    static var stallsQuit: Bool {
        ProcessInfo.processInfo.environment["MCL_DEBUG_STALL_QUIT"] == "1"
    }
    #else
    static var stallsQuit: Bool {
        false
    }
    #endif

    static func write(_ line: @autoclosure () -> String) {
        #if DEBUG
        guard let path else { return }
        let data = Data((line() + "\n").utf8)
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        guard let handle = FileHandle(forWritingAtPath: path) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
        #endif
    }
}
