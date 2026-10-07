import Darwin
import Foundation

/// What became of a line handed to `PluginProcess.send`.
public enum PluginSendResult: Equatable, Sendable {
    case sent
    /// The plugin does not read its input: more than `maxPendingInputBytes` wait unwritten.
    case full
    /// Not running, or its input is closed (by the app, or by the plugin itself — a broken pipe).
    case closed
}

/// The process of a window plugin: JSON lines both ways, read **while it runs** (unlike `PluginRunner`, which reads
/// after the exit).
///
/// - Stdout is read by a thread of its own with blocking reads, framed and decoded there; `Handlers.message` may block
///   (the receiver's backpressure): reading then pauses and the plugin blocks on its own output.
/// - Stderr is split into lines on a GCD reader.
/// - Stdin is non-blocking: lines are buffered and written by a serial queue, resumed by a writability source, so
///   no thread ever blocks on a plugin that does not read (or on a child that inherited the pipe).
/// - The object keeps itself alive while the process runs, so a stop's `SIGKILL` fallback always fires even when
///   nobody else holds it.
///
/// `exited` is called once, after the process ended and its output reached the end (or, as a fallback for a child of
/// the plugin that keeps the pipe open, `outputFallbackMs` after the end), with the exit code (`128 + signal`).
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
    /// How long the output may stay open after the process ended before the end is reported anyway (only a child of
    /// the plugin holding the pipe gets this far; a normal exit reports at the end of the output).
    static let outputFallbackMs = 10_000

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
    private var writeSource: (any DispatchSourceWrite)?
    /// The write end of stdin, kept as a number: the handle is closed by the source's cancel handler, and every
    /// write checks `inputClosed` (set first, on the same queue) before using it.
    private var inputFD: Int32 = -1

    private struct State {
        var started = false
        var terminated = false
        var stdoutDone = false
        var stderrDone = false
        var finished = false
        var inputClosed = false
        /// The plugin closed its input (a broken pipe).
        var inputBroken = false
        var closeRequested = false
        var pendingInput = 0
        var outBuffer: [UInt8] = []
        var outOffset = 0
        var sourceArmed = false
        /// Holds the object while the process runs.
        var keepAlive: PluginProcess?
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
        let input: Int32 = stdinPipe.fileHandleForWriting.fileDescriptor
        inputFD = input
        _ = fcntl(input, F_SETNOSIGPIPE, 1)
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
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            throw ProcessRunnerError("Cannot run program \"\(executable)\": error=\(code), "
                + String(cString: strerror(code)))
        }
        _ = fcntl(input, F_SETFL, fcntl(input, F_GETFL) | O_NONBLOCK)
        let source: any DispatchSourceWrite = DispatchSource.makeWriteSource(fileDescriptor: input, queue: writeQueue)
        let handle: FileHandle = stdinPipe.fileHandleForWriting
        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.lock.withLock { self.state.sourceArmed = false }
            source.suspend()
            self.flush()
        }
        source.setCancelHandler {
            try? handle.close()
        }
        writeSource = source
        lock.withLock {
            state.started = true
            state.keepAlive = self
        }
        let output: Int32 = stdoutPipe.fileHandleForReading.fileDescriptor
        let reader = Thread { [self] in
            readStdout(output)
        }
        reader.name = "plugin stdout"
        reader.start()
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

    /// Queues one line for stdin (never blocks).
    @discardableResult
    public func send(_ line: String) -> PluginSendResult {
        let bytes: [UInt8] = Array(line.utf8) + [0x0A]
        let result: PluginSendResult = lock.withLock {
            guard state.started, !state.terminated, !state.inputClosed, !state.closeRequested else { return .closed }
            guard state.pendingInput + bytes.count <= Self.maxPendingInputBytes else { return .full }
            state.pendingInput += bytes.count
            state.outBuffer += bytes
            return .sent
        }
        if result == .sent {
            writeQueue.async { [self] in flush() }
        }
        return result
    }

    /// The plugin closed its own input (writing failed with a broken pipe).
    public var inputBroken: Bool {
        lock.withLock { state.inputBroken }
    }

    /// Writes what the buffer holds until the pipe is full (then the writability source resumes it). On the write
    /// queue only.
    private func flush() {
        let fd: Int32 = inputFD
        while true {
            let chunk: [UInt8]? = lock.withLock {
                guard !state.inputClosed, state.outOffset < state.outBuffer.count else { return nil }
                let end: Int = min(state.outBuffer.count, state.outOffset + 65_536)
                return Array(state.outBuffer[state.outOffset..<end])
            }
            guard let chunk else { break }
            let written: Int = chunk.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
            if written > 0 {
                lock.withLock {
                    state.outOffset += written
                    state.pendingInput -= written
                    if state.outOffset == state.outBuffer.count {
                        state.outBuffer.removeAll(keepingCapacity: true)
                        state.outOffset = 0
                    } else if state.outOffset > 1 << 20 {
                        state.outBuffer.removeFirst(state.outOffset)
                        state.outOffset = 0
                    }
                }
                continue
            }
            let error: Int32 = errno
            if written < 0 && error == EINTR {
                continue
            }
            if written < 0 && error == EAGAIN {
                let arm: Bool = lock.withLock {
                    guard !state.sourceArmed else { return false }
                    state.sourceArmed = true
                    return true
                }
                if arm {
                    writeSource?.resume()
                }
                return
            }
            // A broken pipe: the plugin closed its input (or ended).
            lock.withLock { state.inputBroken = true }
            finishInput()
            return
        }
        let close: Bool = lock.withLock { state.closeRequested && state.outOffset >= state.outBuffer.count }
        if close {
            finishInput()
        }
    }

    /// Closes the input for good: the buffer is dropped, the writability source cancelled (its cancel handler
    /// closes the pipe). On the write queue only.
    private func finishInput() {
        let source: (any DispatchSourceWrite)? = lock.withLock {
            guard !state.inputClosed || writeSource != nil else { return nil }
            state.inputClosed = true
            state.outBuffer = []
            state.outOffset = 0
            state.pendingInput = 0
            let source = writeSource
            if let source, !state.sourceArmed {
                // A suspended source must be resumed before it is cancelled.
                state.sourceArmed = true
                source.resume()
            }
            writeSource = nil
            return source
        }
        source?.cancel()
    }

    /// Waits until the writer has handled everything queued before (tests).
    func settleInput() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writeQueue.async {
                continuation.resume()
            }
        }
    }

    /// Closes stdin after the lines queued so far (the plugin reads the end of its input and may exit on its own).
    public func closeInput() {
        let started: Bool = lock.withLock {
            guard state.started else { return false }
            state.closeRequested = true
            return true
        }
        guard started else { return }
        writeQueue.async { [self] in flush() }
    }

    /// The regular stop: stdin is closed (after the queued lines), `SIGTERM`, and `SIGKILL` after `graceMs` when the
    /// process is still running. Never blocks. The kill timer holds the object, so the fallback fires even when the
    /// caller let go of it.
    public func terminate(graceMs: Int = 1_000) {
        guard isRunning else { return }
        closeInput()
        let pid: Int32 = self.pid
        Darwin.kill(pid, SIGTERM)
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(graceMs)) { [self] in
            guard isRunning else { return }
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

    /// The stdout thread: blocking reads until the end of the pipe; a blocking handler pauses it.
    private func readStdout(_ fd: Int32) {
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let count: Int = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
            if count > 0 {
                stdout(Array(buffer[0..<count]))
            } else if count < 0 && errno == EINTR {
                continue
            } else {
                break
            }
        }
        stdout([])
    }

    private func stdout(_ data: [UInt8]) {
        var outputs: [PluginLineFramer.Output] = []
        let ended: Bool = data.isEmpty
        lock.withLock {
            outputs = ended ? state.framer.finish() : state.framer.feed(data)
        }
        for output in outputs {
            switch output {
            case .overflow:
                handlers.protocolError("a line over \(PluginLineFramer.maxLineBytes) bytes was dropped")
            case .line(let line):
                do throws(PluginJSON.ParseError) {
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
        // A child of the plugin may keep the pipes open: the end is reported after the fallback anyway.
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(Self.outputFallbackMs)) { [weak self] in
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
            state.closeRequested = true
            report = (state.code, state.waiters)
            state.waiters = []
        }
        guard let report else { return }
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        writeQueue.async { [self] in finishInput() }
        handlers.exited(report.code)
        for waiter in report.waiters {
            waiter.resume()
        }
        // The process is over: the object may go once its holders let go.
        lock.withLock { state.keepAlive = nil }
    }
}
