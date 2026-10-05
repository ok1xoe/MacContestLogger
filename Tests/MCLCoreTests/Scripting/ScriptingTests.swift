import Darwin
import Foundation
import Testing
@testable import MCLCore

/// Helpers of the `scripting/` tests: a temporary directory (cleaned up by the caller's `defer`) and synthetic `/bin/sh` scripts.
enum ScriptingFixture {

    static func makeDirectory() -> String? {
        let template: String = FileManager.default.temporaryDirectory.path + "/mcl-scripting.XXXXXX"
        var bytes: [CChar] = Array(template.utf8CString)
        guard let made = mkdtemp(&bytes) else {
            return nil
        }
        // Java `toRealPath`: `/var` → `/private/var`, so that paths in messages match the probe's `<ROOT>`.
        return URL(fileURLWithPath: String(cString: made)).resolvingSymlinksInPath().path
    }

    static func remove(_ directory: String) {
        _ = chmodTree(directory)
        try? FileManager.default.removeItem(atPath: directory)
    }

    private static func chmodTree(_ directory: String) -> Bool {
        guard let items = FileManager.default.enumerator(atPath: directory) else {
            return false
        }
        for case let item as String in items {
            let path: String = directory + "/" + item
            var info = stat()
            // Do not follow a symlink — `chmod` would change the permissions of its target (even outside the temporary directory).
            guard lstat(path, &info) == 0, (info.st_mode & S_IFMT) != S_IFLNK else { continue }
            chmod(path, 0o755)
        }
        return true
    }

    static func mkdirs(_ path: String) {
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    /// A file with byte content. POSIX `open` with the name in bytes as is (Java `Files.write`) —
    /// `FileManager` would convert the name to NFD (`é` → `e\u{301}`) and change the byte order.
    static func write(_ path: String, _ bytes: [UInt8]) {
        let fd: Int32 = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        guard fd >= 0 else {
            return
        }
        _ = bytes.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
        close(fd)
    }

    /// Executable script (Java `setExecutable(true)` = owner only: 0744).
    static func script(_ dir: String, _ name: String, _ body: String) {
        mkdirs(dir)
        write(dir + "/" + name, Array(body.utf8))
        chmod(dir + "/" + name, 0o744)
    }
}

/// Port of the Java `ScriptingTest` (3 tests) — real `/bin/sh` processes in a temporary directory. The blocking
/// `fire` runs on its own thread. The time limit of the successful path is a generous guard (Java 5,000 ms).
@Suite(.ioSafetyNet) struct ScriptingTests {

    @Test func pluginGetsJsonAndEvent() async throws {
        let root: String = try #require(ScriptingFixture.makeDirectory())
        defer { ScriptingFixture.remove(root) }
        let dir: String = root + "/qso-logged"
        ScriptingFixture.script(dir, "echo.sh", "#!/bin/sh\necho \"event=$MCL_EVENT\"\ncat\n")
        ScriptingFixture.write(dir + "/notes.txt", Array("nespustitelný".utf8))

        let runner = PluginRunner(root: root, timeoutMs: 120_000)
        let r: [PluginRunner.Result] = await onOwnThread { runner.fire(.qsoLogged, json: "{\"call\":\"W1AW\"}") }
        #expect(r.count == 1)
        #expect(r.first?.exitCode == 0)
        #expect(r.first?.output == ["event=qso-logged", "{\"call\":\"W1AW\"}"])
        let none: [PluginRunner.Result] = await onOwnThread { runner.fire(.spotReceived, json: "{}") }
        #expect(none.isEmpty)
    }

    @Test func slowPluginIsKilled() async throws {
        let root: String = try #require(ScriptingFixture.makeDirectory())
        defer { ScriptingFixture.remove(root) }
        ScriptingFixture.script(root + "/contest-opened", "slow.sh", "#!/bin/sh\nsleep 5\n")
        let runner = PluginRunner(root: root, timeoutMs: 300)
        let r: [PluginRunner.Result] = await onOwnThread { runner.fire(.contestOpened, json: "{}") }
        #expect(r.first?.exitCode == -1)
    }

    @Test func macroScript() throws {
        let dir: String = try #require(ScriptingFixture.makeDirectory())
        defer { ScriptingFixture.remove(dir) }
        ScriptingFixture.write(dir + "/run20.txt", Array("# přechod na 20 m CW\nCW\n\n14025\nRIT 0\n".utf8))
        #expect(MacroScript.load(dir, "RUN20") == ["CW", "14025", "RIT 0"])
        #expect(MacroScript.load(dir, "../etc") == nil)
        #expect(MacroScript.load(dir, "missing") == nil)
    }
}
