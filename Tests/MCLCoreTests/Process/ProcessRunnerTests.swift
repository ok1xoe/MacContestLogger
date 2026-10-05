import Darwin
import Foundation
import Testing
@testable import MCLCore

/// `ProcessRunner` only with harmless programs (`/bin/echo`, `/bin/sleep`). Blocking waits on its own thread.
@Suite(.ioSafetyNet) struct ProcessRunnerTests {

    final class Lines: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String] = []

        func add(_ line: String) {
            lock.lock()
            items.append(line)
            lock.unlock()
        }

        var all: [String] {
            lock.lock()
            defer { lock.unlock() }
            return items
        }
    }

    @Test func echoOutputArrivesAsLines() async throws {
        let lines = Lines()
        let runner = ProcessRunner(executable: "/bin/echo", arguments: ["-vvv", "rigctld", "ž"]) { lines.add($0) }
        try runner.start()
        let done: Bool = await onOwnThread { runner.waitForExit(timeoutMs: 30_000) && runner.waitForOutput(timeoutMs: 30_000) }
        #expect(done)
        #expect(lines.all == ["-vvv rigctld ž"])
        #expect(runner.exitCode == 0)
        #expect(!runner.isAlive)
    }

    /// A name without `/` is looked up in `PATH` (Java `ProcessBuilder`).
    @Test func bareNameIsFoundOnPath() {
        #expect(ProcessRunner.resolve("echo") != nil)
        #expect(ProcessRunner.resolve("/bin/echo") == "/bin/echo")
        #expect(ProcessRunner.resolve("mcl-no-such-program") == nil)
    }

    /// stderr goes into the same pipe as stdout (Java `redirectErrorStream(true)`): `sleep` without an argument
    /// prints the usage to stderr.
    @Test func stderrIsMerged() async throws {
        let lines = Lines()
        let runner = ProcessRunner(executable: "/bin/sleep", arguments: []) { lines.add($0) }
        try runner.start()
        let done: Bool = await onOwnThread { runner.waitForExit(timeoutMs: 30_000) && runner.waitForOutput(timeoutMs: 30_000) }
        #expect(done)
        #expect(!lines.all.isEmpty)
        #expect(lines.all.first?.contains("usage") == true)
        #expect(runner.exitCode != 0)
    }

    @Test func missingProgramFailsLikeJava() {
        let runner = ProcessRunner(executable: "mcl-no-such-program", arguments: []) { _ in }
        #expect(throws: ProcessRunnerError("Cannot run program \"mcl-no-such-program\": error=2, No such file or directory")) {
            try runner.start()
        }
        #expect(!runner.isAlive)
        runner.terminate() // a process not started: nothing
    }

    /// `SIGTERM` is enough: `sleep` ends with signal 15.
    @Test func terminateStopsRunningProcess() async throws {
        let runner = ProcessRunner(executable: "/bin/sleep", arguments: ["30"]) { _ in }
        try runner.start()
        #expect(runner.isAlive)
        // After `terminate`, still wait generously for the termination message (under load it may arrive only after the 1 s window).
        let exited: Bool = await onOwnThread {
            runner.terminate()
            return runner.waitForExit(timeoutMs: 30_000)
        }
        #expect(exited)
        #expect(!runner.isAlive)
        #expect(runner.exitCode == SIGTERM)
        await onOwnThread { runner.terminate() } // already finished: nothing
    }

    /// `SIGTERM` does not take effect (the sender stand-in does not send it), after 1 s a real `SIGKILL` arrives.
    @Test func terminateEscalatesToKill() async throws {
        let runner = ProcessRunner(executable: "/bin/sleep", arguments: ["30"]) { _ in }
        try runner.start()
        let sent = Lines()
        let exited: Bool = await onOwnThread {
            runner.terminate { pid, sig in
                sent.add(String(sig))
                if sig != SIGTERM { kill(pid, sig) }
            }
            return runner.waitForExit(timeoutMs: 30_000)
        }
        #expect(exited)
        #expect(sent.all == [String(SIGTERM), String(SIGKILL)])
        #expect(!runner.isAlive)
        #expect(runner.exitCode == SIGKILL)
    }

    // MARK: - Line splitting (Java BufferedReader.readLine, probe RL.*)

    @Test func lineSplitterMatchesBufferedReader() {
        func split(_ chunks: [String]) -> [String] {
            var s = JavaLineSplitter()
            var out: [String] = []
            for c in chunks { out += s.feed(Array(c.utf8)) }
            if let tail = s.finish() { out.append(tail) }
            return out
        }
        #expect(split(["a\nb\n"]) == ["a", "b"])
        #expect(split(["a\r\nb\r\n"]) == ["a", "b"])
        #expect(split(["a\rb\r"]) == ["a", "b"])
        #expect(split(["a\r\rb\n"]) == ["a", "", "b"])
        #expect(split(["a\n\rb\n"]) == ["a", "", "b"])
        #expect(split(["\n\r\n\r"]) == ["", "", ""])
        #expect(split(["a\r", "\nb\n"]) == ["a", "b"])
        #expect(split(["a\r", "\r\nb\n"]) == ["a", "", "b"])
        #expect(split(["ab", "cd\n"]) == ["abcd"])
        #expect(split(["abc"]) == ["abc"])
        #expect(split(["abc\r"]) == ["abc"])
        #expect(split(["\r"]) == [""])
        #expect(split([]) == [])
        #expect(split(["\u{17E}", "lu\n"]) == ["\u{17E}lu"])
    }
}
