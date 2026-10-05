import Foundation

/// A harmless stand-in for the `rigctld`/`rigctl` binary for process tests: a shell script in a temporary directory.
/// A real hamlib is never started — the script only prints the arguments and sleeps, or exits.
final class FakeDaemon: @unchecked Sendable {

    let directory: URL
    let path: String

    /// `body` = the script body after `#!/bin/sh`.
    init(_ body: String) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("fake-daemon-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("fake-rigctld")
        try Data(("#!/bin/sh\n" + body + "\n").utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        path = file.path
    }

    /// Prints the arguments; with `-m 9` it exits at once (rig_open failed), otherwise it runs until the test terminates it
    /// (`SIGTERM`/`SIGKILL` goes directly to this shell) or until the test process dies.
    ///
    /// No fixed lifetime: the earlier `exec /bin/sleep 30` on a loaded CI (and under
    /// `LIBDISPATCH_COOPERATIVE_POOL_STRICT=1`) expired before the test even got to the `isAlive`
    /// check after `await`, and the session then started a second daemon.
    static func sleeper() throws -> FakeDaemon {
        try FakeDaemon("""
            echo "fake $*"
            case " $* " in *" -m 9 "*) exit 3;; esac
            \(untilParentDies)
            """)
    }

    /// The end of the script: waits while the parent (the test process) lives, in 0.2 s steps — it does not stay hanging after a test crash.
    static let untilParentDies = "while kill -0 $PPID 2>/dev/null; do sleep 0.2; done"

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }
}
