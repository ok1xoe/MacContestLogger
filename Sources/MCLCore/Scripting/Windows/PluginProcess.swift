import Darwin
import Foundation

/// The process of a window plugin: JSON lines both ways, read **while it runs** (unlike `PluginRunner`, which reads
/// after the exit). Stdout is framed and decoded on a GCD reader (never the main thread), stderr is passed on line by
/// line, stdin is written by a serial writer queue. A plugin that stops reading stdin shows as backpressure:
/// `send` refuses once `maxPendingInputBytes` wait unwritten.
///
/// `exited` is called once, after the process ended and its output was read (or at most `outputGraceMs` after the
/// end, when a child of the plugin still holds the pipe), with the exit code (`128 + signal` for a signal).
public final class PluginProcess: @unchecked Sendable {

    public struct Handlers: Sendable {
        public var message: @Sendable (PluginInbound) -> Void
        public var protocolError: @Sendable (String) -> Void
        public var stderr: @Sendable (String) -> Void
        public var exited: @Sendable (Int32) -> Void

        public init(message: @escaping @Sendable (PluginInbound) -> Void,
                    protocolError: @escaping @Sendable (String) -> Void,
                    stderr: @escaping @Sendable (String) -> Void,
                    exited: @escaping @Sendable (Int32) -> Void) {
            self.message = message
            self.protocolError = protocolError
            self.stderr = stderr
            self.exited = exited
        }
    }

    /// Unwritten stdin beyond which `send` refuses (the plugin does not read).
    public static let maxPendingInputBytes = 1 << 20
    /// A stderr line is cut to this many characters.
    public static let maxStderrLine = 500
    /// How long the output may stay open after the process ended.
    static let outputGraceMs = 500

    public let executable: String
    public let directory: String
    private let environment: [String: String]
    private let handlers: Handlers
    private var process = Process()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private let stdinPipe = Pipe()
    private let writeQueue = DispatchQueue(label: "cz.ok1xoe.maccontestlogger.plugin.stdin")
    private let lock = NSLock()
    private var state = State()

    private struct State {
        var started = false
        var terminated = false
        var stdoutDone = false
        var stderrDone = false
        var finished = false
        var inputClosed = false
        var pendingInput = 0
        var code: Int32 = 0
        var waiters: [CheckedContinuation<Void, Never>] = []
        var framer = PluginLineFramer()
        var stderrSplitter = JavaLineSplitter()
    }

    public init(executable: String, directory: String, environment: [String: String], handlers: Handlers) {
        self.executable = executable
        self.directory = directory
        self.environment = environment
        self.handlers = handlers
    }

    /// Starts the process (a script without `#!` runs through `/bin/sh`, as for the event plugins). Throws with
    /// the text of `ProcessRunnerError` when it cannot start.
    public func start() throws(ProcessRunnerError) {
        guard access(executable, F_OK) == 0 else {
            throw ProcessRunnerError("Cannot run program \"\(executable)\": error=2, No such file or directory")
        }
        guard access(executable, X_OK) == 0 else {
            throw ProcessRunnerError("Cannot run program \"\(executable)\": error=13, Permission denied")
        }
        _ = fcntl(stdinPipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data: Data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            }
            self?.stdout(data)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data: Data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            }
            self?.stderr(data)
        }
        var code: Int32? = launch(executable, [])
        if code == ENOEXEC {
            code = launch("/bin/sh", [executable])
        }
        if let code {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            throw ProcessRunnerError("Cannot run program \"\(executable)\": error=\(code), "
                + String(cString: strerror(code)))
        }
        lock.withLock { state.started = true }
    }

    /// One attempt; `nil` = running, else `errno`. Every attempt gets a fresh `Process`.
    private func launch(_ path: String, _ arguments: [String]) -> Int32? {
        process = Process()
        process.currentDirectoryURL = URL(fileURLWithPath: directory, isDirectory: true)
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, added in added }
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.terminationHandler = { [weak self] finished in
            self?.terminated(finished)
        }
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        do {
            try process.run()
            return nil
        } catch {
            let ns = error as NSError
            if ns.domain == NSPOSIXErrorDomain {
                return Int32(ns.code)
            }
            if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError, underlying.domain == NSPOSIXErrorDomain {
                return Int32(underlying.code)
            }
            return EIO
        }
    }

    public var pid: Int32 {
        process.processIdentifier
    }

    /// Started and not yet ended.
    public var isRunning: Bool {
        lock.withLock { state.started && !state.terminated }
    }

    /// Unwritten stdin bytes.
    public var pendingInputBytes: Int {
        lock.withLock { state.pendingInput }
    }

    /// Queues one line for stdin. `false` = not sent: the process ended, its stdin is closed, or it has not read
    /// `maxPendingInputBytes` (backpressure).
    @discardableResult
    public func send(_ line: String) -> Bool {
        let bytes: [UInt8] = Array(line.utf8) + [0x0A]
        let count: Int = bytes.count
        let admitted: Bool = lock.withLock {
            guard state.started, !state.terminated, !state.inputClosed else { return false }
            guard state.pendingInput + count <= Self.maxPendingInputBytes else { return false }
            state.pendingInput += count
            return true
        }
        guard admitted else { return false }
        let fd: Int32 = stdinPipe.fileHandleForWriting.fileDescriptor
        writeQueue.async { [self] in
            let closed: Bool = lock.withLock { state.inputClosed }
            var ok = !closed
            var offset = 0
            while ok && offset < bytes.count {
                let written: Int = bytes[offset...].withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
                if written < 0 {
                    if errno == EINTR { continue }
                    ok = false
                } else {
                    offset += written
                }
            }
            lock.withLock {
                state.pendingInput -= count
                if !ok {
                    state.inputClosed = true
                }
            }
        }
        return true
    }

    /// Closes stdin after the lines queued so far (the plugin reads the end of its input and may exit on its own).
    public func closeInput() {
        writeQueue.async { [self] in
            let close: Bool = lock.withLock {
                guard state.started, !state.inputClosed else { return false }
                state.inputClosed = true
                return true
            }
            if close {
                try? stdinPipe.fileHandleForWriting.close()
            }
        }
    }

    /// The regular stop: stdin is closed (after the queued lines), `SIGTERM`, and `SIGKILL` after `graceMs` when the
    /// process is still running. Never blocks.
    public func terminate(graceMs: Int = 1_000) {
        guard isRunning else { return }
        closeInput()
        let pid: Int32 = self.pid
        Darwin.kill(pid, SIGTERM)
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(graceMs)) { [weak self] in
            guard let self, self.isRunning else { return }
            Darwin.kill(pid, SIGKILL)
        }
    }

    /// `SIGKILL` at once.
    public func kill() {
        guard isRunning else { return }
        Darwin.kill(pid, SIGKILL)
    }

    /// Waits (without blocking a thread) until `exited` was called.
    public func waitForExit() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let done: Bool = lock.withLock {
                if state.finished || !state.started { return true }
                state.waiters.append(continuation)
                return false
            }
            if done {
                continuation.resume()
            }
        }
    }

    // MARK: - output

    private func stdout(_ data: Data) {
        var outputs: [PluginLineFramer.Output] = []
        let ended: Bool = data.isEmpty
        lock.withLock {
            outputs = ended ? state.framer.finish() : state.framer.feed(Array(data))
        }
        for output in outputs {
            switch output {
            case .overflow:
                handlers.protocolError("a line over \(PluginLineFramer.maxLineBytes) bytes was dropped")
            case .line(let line):
                do {
                    handlers.message(try PluginInbound.decode(line))
                } catch {
                    handlers.protocolError(error.message)
                }
            }
        }
        if ended {
            mark { $0.stdoutDone = true }
        }
    }

    private func stderr(_ data: Data) {
        var lines: [String] = []
        let ended: Bool = data.isEmpty
        lock.withLock {
            if ended {
                if let tail = state.stderrSplitter.finish() { lines = [tail] }
            } else {
                lines = state.stderrSplitter.feed(Array(data))
            }
        }
        for line in lines where !line.isEmpty {
            handlers.stderr(line.count > Self.maxStderrLine ? String(line.prefix(Self.maxStderrLine)) + "…" : line)
        }
        if ended {
            mark { $0.stderrDone = true }
        }
    }

    private func terminated(_ finished: Process) {
        let status: Int32 = finished.terminationStatus
        let code: Int32 = finished.terminationReason == .uncaughtSignal ? 128 + status : status
        mark { state in
            state.terminated = true
            state.code = code
        }
        // A child of the plugin may keep the pipes open: the end is reported after a short grace anyway.
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(Self.outputGraceMs)) { [weak self] in
            self?.mark { state in
                state.stdoutDone = true
                state.stderrDone = true
            }
        }
    }

    /// Updates the state; once the process ended and both outputs are done, `exited` runs (once).
    private func mark(_ change: (inout State) -> Void) {
        var report: (code: Int32, waiters: [CheckedContinuation<Void, Never>])?
        lock.withLock {
            change(&state)
            guard !state.finished, state.terminated, state.stdoutDone, state.stderrDone else { return }
            state.finished = true
            state.inputClosed = true
            report = (state.code, state.waiters)
            state.waiters = []
        }
        guard let report else { return }
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        handlers.exited(report.code)
        for waiter in report.waiters {
            waiter.resume()
        }
    }
}
