import Darwin
import Foundation

/// Plugins (like DXLog scripts / N1MM external apps): executable files in the directory
/// `plugins/<event>/` are called on an event; they receive the event data as JSON on stdin (`PluginEventJson`)
/// and the event name in the environment variable `MCL_EVENT`. What a plugin prints to stdout and stderr is shown in the
/// messages window. A slow plugin is terminated after a time limit. Java `scripting.PluginRunner` v1.1.1 over `ProcessRunner`.
///
/// Measured by the maintainer-only probe: the output is read **only after exit** (just what is in the pipe;
/// a plugin with output above ~64 KiB blocks and hits the limit; output of a background child after exit is lost),
/// decoded like Java `new String(bytes, UTF_8)`, split by `\n`/`\r`/`\r\n` and at most 50 lines are taken; termination
/// by a signal = `128 + signal`; a script without `#!` runs via `/bin/sh`; a start error = `nelze spustit: Cannot run
/// program "<path>": error=<errno>, <strerror>`.
public struct PluginRunner: Sendable {

    /// Events that plugins can be attached to (subdirectory name), in Java order.
    public enum Event: String, CaseIterable, Sendable {
        case qsoLogged = "QSO_LOGGED"
        case contestOpened = "CONTEST_OPENED"
        case spotReceived = "SPOT_RECEIVED"
    }

    /// Result of one plugin (Java record `Result`).
    public struct Result: Equatable, Sendable {
        public let plugin: String
        public let exitCode: Int32
        public let output: [String]

        public init(plugin: String, exitCode: Int32, output: [String]) {
            self.plugin = plugin
            self.exitCode = exitCode
            self.output = output
        }
    }

    public let root: String
    public let timeoutMs: Int64

    public init(root: String, timeoutMs: Int64) {
        self.root = root
        self.timeoutMs = timeoutMs
    }

    /// `QSO_LOGGED` → `qso-logged`.
    public static func dirName(_ event: Event) -> String {
        String(JavaText.toLowerCase(event.rawValue).map { $0 == "_" ? "-" : $0 })
    }

    /// Executable plugins for an event (paths), sorted by name by bytes (Java `Path.compareTo`):
    /// regular files, also through a symbolic link (`Files.isRegularFile`), executable (`Files.isExecutable`),
    /// the name does not start with a dot. A missing or unreadable directory → empty.
    public func plugins(_ event: Event) -> [String] {
        let dir: String = RawFileSystem.resolve(root, Self.dirName(event))
        guard RawFileSystem.isDirectory(dir), let names = RawFileSystem.listDirectory(dir) else {
            return []
        }
        let prefix: [UInt8] = Array(dir.utf8) + [0x2F]
        // Broken into typed steps (short expressions for the Swift 6.1 type checker).
        let visible: [[UInt8]] = names.filter { $0.first != 0x2E }
        let ordered: [[UInt8]] = visible.sorted { $0.lexicographicallyPrecedes($1) }
        // A name that is not valid UTF-8 is decoded here with U+FFFD and `stat` then does not find it — such a plugin
        // is not listed (a deliberate divergence from Java v1.1.1).
        let paths: [String] = ordered.map { String(decoding: prefix + $0, as: UTF8.self) }
        return paths.filter(Self.isExecutableFile)
    }

    /// Runs all plugins of the event one after another. **Blocks** (process, waiting up to `timeoutMs` for each plugin) —
    /// call from your own thread, never from the main one or Swift's shared pool.
    public func fire(_ event: Event, json: String) -> [Result] {
        plugins(event).map { run($0, event, json) }
    }

    /// `fire` with an overall limit: before each plugin `deadline()` is asked; the plugin gets at most the time left
    /// (never more than `timeoutMs`) and a plugin that would start after the deadline is not started — it is reported
    /// as ended by the time limit. `nil` = no overall limit (the quit sets one).
    public func fire(_ event: Event, json: String, deadline: @Sendable () -> Date?) -> [Result] {
        var results: [Result] = []
        for plugin in plugins(event) {
            var limitMs: Int64 = timeoutMs
            if let end = deadline() {
                let left = Int64(end.timeIntervalSinceNow * 1000)
                if left <= 0 {
                    let name: String = Self.fileName(plugin)
                    results.append(Result(plugin: name, exitCode: -1,
                                          output: ["plugin překročil časový limit \(timeoutMs) ms — ukončen"]))
                    continue
                }
                limitMs = min(limitMs, left)
            }
            results.append(PluginRunner(root: root, timeoutMs: limitMs).run(plugin, event, json))
        }
        return results
    }

    func run(_ plugin: String, _ event: Event, _ json: String) -> Result {
        let name: String = Self.fileName(plugin)
        let runner = ProcessRunner(executable: plugin, arguments: [], environment: ["MCL_EVENT": Self.dirName(event)],
                                   pipesInput: true)
        do {
            try runner.start()
        } catch let error as ProcessRunnerError {
            return Result(plugin: name, exitCode: -1, output: ["nelze spustit: " + error.message])
        } catch {
            return Result(plugin: name, exitCode: -1, output: ["nelze spustit: \(error)"])
        }
        runner.writeInputAndClose(Array(json.utf8)) // the plugin does not read stdin — no problem
        guard runner.waitForExit(timeoutMs: Int(clamping: timeoutMs)) else {
            runner.destroyForcibly()
            return Result(plugin: name, exitCode: -1, output: ["plugin překročil časový limit \(timeoutMs) ms — ukončen"])
        }
        let lines: [String] = JavaLines.split(JavaUtf8.decode(runner.drainOutputAtExit()))
        return Result(plugin: name, exitCode: runner.javaExitValue ?? -1, output: Array(lines.prefix(50)))
    }

    /// Java `Path.getFileName().toString()` of a path from `plugins` (the last component).
    static func fileName(_ path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else {
            return path
        }
        return String(path[path.index(after: slash)...])
    }

    private static func isExecutableFile(_ path: String) -> Bool {
        var info = stat()
        guard stat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else {
            return false
        }
        return access(path, X_OK) == 0
    }
}
