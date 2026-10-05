import Darwin
import Foundation

/// A running process with line-by-line output (Java `ProcessBuilder(cmd).redirectErrorStream(true).start()`
/// + the reader thread `BufferedReader(InputStreamReader(…, UTF_8)).readLine()` from `RigctldProcessManager`).
/// `Foundation.Process`, stdout and stderr into **one** `Pipe` (Java
/// `redirectErrorStream`), lines via `readabilityHandler` (a GCD queue, not Swift's shared pool) split like
/// `BufferedReader.readLine` (`\n`, `\r`, `\r\n`, `\r` at the end of one block and `\n` in the next; an unfinished
/// last line is emitted at the end of the output). UTF-8 with invalid sequences replaced by U+FFFD (the number of replacements
/// for some invalid sequences may differ from the Java decoder — `rigctld` output is ASCII).
///
/// `terminate()` = Java `RigctldProcessManager.terminate`: `SIGTERM`, wait up to 1 s, then `SIGKILL` and wait
/// up to 1 s. Blocking — call from your own thread or from the app shutdown handler.
///
/// The second variant (`init(executable:arguments:environment:pipesInput:)`, Java `PluginRunner`) does **not**
/// read the output continuously: like a Java `Process` it takes only what remained in the pipe after exit (`drainOutputAtExit`, Java
/// `ProcessPipeInputStream.processExited`); a process that fills the pipe (~64 KiB) blocks. Stdin can be
/// a pipe (`writeInputAndClose`) and the `environment` variables are added to the inherited environment.
///
/// A program that the kernel rejects with `ENOEXEC` (a script without `#!`) is, as in Java, started again via
/// `/bin/sh <path> <arguments>` (JDK 21 on macOS: `jspawnhelper` → `childproc.c`
/// `execve_with_shell_fallback` → libc `execvp`, which on `ENOEXEC` runs `_PATH_BSHELL`). Libc passes
/// `argv[0] = "sh"`, here `"/bin/sh"` — they differ only in the `ps` listing.
public final class ProcessRunner: @unchecked Sendable {

    public let executable: String
    public let arguments: [String]
    private let onLine: (@Sendable (String) -> Void)?
    private let environment: [String: String]
    private let pipesInput: Bool
    private var process = Process()
    private var pipe = Pipe()
    private var inputPipe: Pipe?
    private let exit = NSCondition()
    private var exited = false
    /// `readabilityHandler` calls come one after another, the lock is only a safeguard.
    private let splitLock = NSLock()
    private var splitter = JavaLineSplitter()
    private let outputDone = NSCondition()
    private var outputFinished = false

    /// Prepares the process; `onLine` is called from a GCD queue for each output line (stdout + stderr).
    public init(executable: String, arguments: [String], onLine: @escaping @Sendable (String) -> Void) {
        self.executable = executable
        self.arguments = arguments
        self.onLine = onLine
        self.environment = [:]
        self.pipesInput = false
    }

    /// Prepares the process without continuous output reading (Java `PluginRunner`): the output is returned after exit by
    /// `drainOutputAtExit`, `environment` is added to the inherited environment, `pipesInput` = stdin from a pipe
    /// (otherwise `/dev/null`).
    public init(executable: String, arguments: [String], environment: [String: String], pipesInput: Bool) {
        self.executable = executable
        self.arguments = arguments
        self.onLine = nil
        self.environment = environment
        self.pipesInput = pipesInput
    }

    /// Starts the process. A name without `/` is looked up in `PATH` (Java `ProcessBuilder`); a not-found or non-executable
    /// program → an error with text like Java `IOException` (`Cannot run program "x": error=2, No such file or directory`).
    public func start() throws {
        guard let path = Self.resolve(executable), access(path, F_OK) == 0 else {
            throw Self.startError(executable, ENOENT)
        }
        guard access(path, X_OK) == 0 else {
            throw Self.startError(executable, EACCES)
        }
        var code: Int32? = launch(path, arguments)
        if code == ENOEXEC {
            code = launch("/bin/sh", [path] + arguments)
        }
        if let code {
            throw Self.startError(executable, code)
        }
        // The write end of the pipe in the parent is already closed by `Process.run()` — end of stream arrives when the child exits.
    }

    /// One attempt to start; `nil` = running, otherwise `errno`. After a failure the process and pipes are prepared again.
    private func launch(_ path: String, _ args: [String]) -> Int32? {
        process = Process()
        pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        if !environment.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, added in added }
        }
        process.standardOutput = pipe
        process.standardError = pipe
        if pipesInput {
            let input = Pipe()
            inputPipe = input
            process.standardInput = input
        } else {
            process.standardInput = FileHandle.nullDevice
        }
        process.terminationHandler = { [weak self] _ in
            self?.markExited()
        }
        if onLine != nil {
            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil // even if the runner has gone away in the meantime
                }
                self?.consume(data)
            }
        }
        do {
            try process.run()
            return nil
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            return Self.posixCode(error as NSError)
        }
    }

    /// `errno` from the `Process.run()` error: directly `NSPOSIXErrorDomain`, otherwise the underlying error, otherwise `EIO`.
    private static func posixCode(_ error: NSError) -> Int32 {
        if error.domain == NSPOSIXErrorDomain {
            return Int32(error.code)
        }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError, underlying.domain == NSPOSIXErrorDomain {
            return Int32(underlying.code)
        }
        return EIO
    }

    /// Writes `bytes` to the process's stdin and closes the pipe (Java `getOutputStream().write` + `close`). A process that
    /// does not read stdin and has exited gives `EPIPE` without a signal (`F_SETNOSIGPIPE`) → `false` (Java `IOException`). Blocks
    /// until the process reads the data (like Java).
    @discardableResult
    public func writeInputAndClose(_ bytes: [UInt8]) -> Bool {
        guard let handle = inputPipe?.fileHandleForWriting else {
            return false
        }
        let fd: Int32 = handle.fileDescriptor
        _ = fcntl(fd, F_SETNOSIGPIPE, 1)
        var offset = 0
        var ok = true
        while offset < bytes.count {
            let written: Int = bytes[offset...].withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
            if written < 0 {
                if errno == EINTR {
                    continue
                }
                ok = false
                break
            }
            offset += written
        }
        try? handle.close()
        return ok
    }

    /// After the process exits, reads without blocking what remained in the output pipe and closes the pipe (Java
    /// `ProcessPipeInputStream.processExited` → `drainInputStream`). Output that a child running
    /// in the background writes later is lost as in Java. Only for the variant without continuous reading.
    public func drainOutputAtExit() -> [UInt8] {
        let handle: FileHandle = pipe.fileHandleForReading
        let fd: Int32 = handle.fileDescriptor
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        var out: [UInt8] = []
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count: Int = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
            if count > 0 {
                out += buffer[0..<count]
            } else if count < 0 && errno == EINTR {
                continue
            } else {
                break
            }
        }
        try? handle.close()
        return out
    }

    /// Java `destroyForcibly()`: `SIGKILL` if the process is still running; does not wait.
    public func destroyForcibly() {
        if isAlive {
            kill(pid, SIGKILL)
        }
    }

    /// Java `Process.pid()`.
    public var pid: Int32 { process.processIdentifier }

    /// Java `isAlive()`.
    public var isAlive: Bool {
        exit.lock()
        defer { exit.unlock() }
        return process.processIdentifier != 0 && !exited
    }

    /// Exit code (after exit), otherwise `nil`.
    public var exitCode: Int32? {
        exit.lock()
        defer { exit.unlock() }
        return exited ? process.terminationStatus : nil
    }

    /// Java `exitValue()` (after exit): the process code, on termination by a signal `128 + signal` (`SIGKILL` → 137).
    public var javaExitValue: Int32? {
        exit.lock()
        defer { exit.unlock() }
        guard exited else {
            return nil
        }
        let status: Int32 = process.terminationStatus
        return process.terminationReason == .uncaughtSignal ? 128 + status : status
    }

    /// Waits for exit at most `timeoutMs`; `true` = exited (Java `waitFor(timeout)`).
    @discardableResult
    public func waitForExit(timeoutMs: Int) -> Bool {
        let deadline = Date(timeIntervalSinceNow: Double(max(timeoutMs, 0)) / 1_000)
        exit.lock()
        defer { exit.unlock() }
        while !exited {
            if !exit.wait(until: deadline) {
                return exited
            }
        }
        return true
    }

    /// Waits until the whole output is processed (end of pipe) at most `timeoutMs` — for tests and cleanup.
    @discardableResult
    public func waitForOutput(timeoutMs: Int) -> Bool {
        let deadline = Date(timeIntervalSinceNow: Double(max(timeoutMs, 0)) / 1_000)
        outputDone.lock()
        defer { outputDone.unlock() }
        while !outputFinished {
            if !outputDone.wait(until: deadline) {
                return outputFinished
            }
        }
        return true
    }

    /// `SIGTERM`, up to 1 s wait, then `SIGKILL` and up to 1 s (Java `destroy` → `waitFor(1 s)` → `destroyForcibly`).
    public func terminate() {
        terminate(signal: { pid, sig in kill(pid, sig) })
    }

    /// `terminate` with a custom signal sender (escalation tests: a replacement that "swallows" `SIGTERM`).
    func terminate(signal: (Int32, Int32) -> Void) {
        guard isAlive else {
            return
        }
        signal(pid, SIGTERM)
        if !waitForExit(timeoutMs: 1_000) {
            signal(pid, SIGKILL)
            waitForExit(timeoutMs: 1_000)
        }
    }

    private static func startError(_ executable: String, _ code: Int32) -> ProcessRunnerError {
        ProcessRunnerError("Cannot run program \"" + executable + "\": error=" + String(code) + ", "
            + String(cString: strerror(code)))
    }

    /// `PATH` lookup like `execvp` (a name with `/` unchanged): the first executable; if none, but a
    /// non-executable file exists, it returns that (start then reports `error=13, Permission denied` like `execvp`/Java).
    static func resolve(_ executable: String) -> String? {
        if executable.contains("/") {
            return executable
        }
        let path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
        var notExecutable: String?
        for dir in path.split(separator: ":", omittingEmptySubsequences: false) {
            let base = dir.isEmpty ? "." : String(dir)
            let candidate = base + "/" + executable
            if access(candidate, X_OK) == 0 {
                return candidate
            }
            if notExecutable == nil && access(candidate, F_OK) == 0 {
                notExecutable = candidate
            }
        }
        return notExecutable
    }

    private func markExited() {
        exit.lock()
        exited = true
        exit.broadcast()
        exit.unlock()
    }

    private func consume(_ data: Data) {
        splitLock.lock()
        defer { splitLock.unlock() }
        if data.isEmpty {
            pipe.fileHandleForReading.readabilityHandler = nil
            if let tail = splitter.finish() {
                onLine?(tail)
            }
            outputDone.lock()
            outputFinished = true
            outputDone.broadcast()
            outputDone.unlock()
            return
        }
        for line in splitter.feed(Array(data)) {
            onLine?(line)
        }
    }
}

/// Process start error (Java `IOException` from `ProcessBuilder.start`).
public struct ProcessRunnerError: Error, Equatable, Sendable, CustomStringConvertible {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String { message }
}

/// Splitting a byte stream into lines after Java `BufferedReader.readLine` (UTF-8): terminators `\n`, `\r`, `\r\n`;
/// `\r` emits a line immediately and skips `\n` at the start of the next block. `finish` returns an unfinished non-empty line.
struct JavaLineSplitter {
    private var pending: [UInt8] = []
    private var skipLF = false

    mutating func feed(_ bytes: [UInt8]) -> [String] {
        var lines: [String] = []
        for b in bytes {
            if skipLF {
                skipLF = false
                if b == 0x0A {
                    continue
                }
            }
            if b == 0x0A || b == 0x0D {
                lines.append(String(decoding: pending, as: UTF8.self))
                pending.removeAll(keepingCapacity: true)
                skipLF = b == 0x0D
            } else {
                pending.append(b)
            }
        }
        return lines
    }

    mutating func finish() -> String? {
        defer { pending.removeAll() }
        return pending.isEmpty ? nil : String(decoding: pending, as: UTF8.self)
    }
}
