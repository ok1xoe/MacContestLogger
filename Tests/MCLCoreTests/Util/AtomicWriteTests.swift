import Foundation
import Testing
@testable import MCLCore

/// `RawFileSystem.writeAtomically` against the Java `createTempFile` + `Files.move(ATOMIC_MOVE)`
/// (`CallHistory.save`, `ScpDownloader.download`; maintainer-only probe,
/// rows `ATOMIC.*`): the target **always has 0600** — new and overwritten (0644, 0777), a symlink is replaced
/// by a file and its target stays, a directory in the target path makes the write fail and no temporary file remains anywhere.
/// The non-atomic `Files.writeString` (`PLAIN.*`), on the other hand, keeps permissions per umask/the existing file.
@Suite struct AtomicWriteTests {

    private static func rows(_ id: String) -> [[String]] {
        ProbeRows.rows(HelpersMeasured.rows, id)
    }

    private static func row(_ id: String, _ name: String) -> [String] {
        rows(id).first { $0.first == name }.map { Array($0.dropFirst()) } ?? []
    }

    /// Java `kind:PosixFilePermissions.toString` without following links.
    private static func mode(_ path: String) -> String {
        var info = stat()
        guard lstat(path, &info) == 0 else { return "missing" }
        let kind: String
        switch info.st_mode & S_IFMT {
        case S_IFLNK: kind = "link"
        case S_IFDIR: kind = "dir"
        default: kind = "file"
        }
        let letters: [Character] = ["r", "w", "x"]
        var text = ""
        for bit in 0..<9 {
            let mask = mode_t(0o400) >> mode_t(bit)
            text.append((info.st_mode & mask) != 0 ? letters[bit % 3] : "-")
        }
        return kind + ":" + text
    }

    private static func entries(_ dir: String) -> String {
        let names: [String] = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        return names.sorted { JavaText.compare($0, $1) < 0 }.joined(separator: ",")
    }

    private static func tempDir() throws -> String {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("atomic-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }

    private static func write(_ text: String, _ path: String) throws(RawFileSystem.AtomicWriteFailure) {
        try RawFileSystem.writeAtomically(Array(text.utf8), to: path, temporaryIn: (path as NSString).deletingLastPathComponent,
                                          prefix: "callhistory", suffix: ".tmp")
    }

    private static func chmod(_ path: String, _ mode: Int) throws {
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: path)
    }

    @Test func newAndOverwrittenTargetsAre0600() throws {
        let root = try Self.tempDir()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let file = root + "/ch.txt"
        try Self.write("new\n", file)
        #expect([Self.mode(file), Self.entries(root)] == [Self.row("ATOMIC.ch", "new")[0], "ch.txt"])

        try Self.chmod(file, 0o644)
        try Self.write("again\n", file)
        #expect([Self.mode(file), Self.entries(root)] == Self.row("ATOMIC.ch", "over0644"))

        try Self.chmod(file, 0o777)
        try Self.write("third\n", file)
        #expect([Self.mode(file), Self.entries(root)] == Self.row("ATOMIC.ch", "over0777"))
        #expect(try String(contentsOfFile: file, encoding: .utf8) == "third\n")
    }

    @Test func symlinkTargetIsReplacedNotFollowed() throws {
        let root = try Self.tempDir()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try Data("real\n".utf8).write(to: URL(fileURLWithPath: root + "/real.txt"))
        try Self.chmod(root + "/real.txt", 0o644)
        try FileManager.default.createSymbolicLink(atPath: root + "/ch.txt", withDestinationPath: "real.txt")
        try Self.write("new\n", root + "/ch.txt")
        let real: String = try String(contentsOfFile: root + "/real.txt", encoding: .isoLatin1)
        let actual: [String] = [Self.mode(root + "/ch.txt"), Self.mode(root + "/real.txt"), real, Self.entries(root)]
        #expect(actual == Self.row("ATOMIC.ch", "symlink"))
    }

    /// Java: `FileSystemException` from `rename`, the target stays a directory, the temporary file is deleted (`finally`).
    @Test func directoryTargetFailsWithoutLeftovers() throws {
        for name in ["targetIsEmptyDir", "targetIsFullDir"] {
            let root = try Self.tempDir()
            defer { try? FileManager.default.removeItem(atPath: root) }
            try FileManager.default.createDirectory(atPath: root + "/ch.txt", withIntermediateDirectories: true)
            if name == "targetIsFullDir" {
                try Data("x".utf8).write(to: URL(fileURLWithPath: root + "/ch.txt/x"))
            }
            var failure = "ok"
            do {
                try Self.write("new\n", root + "/ch.txt")
            } catch {
                if case .rename = error { failure = "FileSystemException" } else { failure = "\(error)" }
            }
            #expect([failure, Self.mode(root + "/ch.txt"), Self.entries(root)] == Self.row("ATOMIC.ch", name))
        }
    }

    /// `ScpDownloader`: a temporary `master*.scp.part` in the target directory, the result 0600 even over a former 0644.
    @Test func scpSuffixVariantMatchesJava() throws {
        let root = try Self.tempDir()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let target = root + "/master.scp"
        try RawFileSystem.writeAtomically(Array("OK1A\n".utf8), to: target, temporaryIn: root,
                                          prefix: "master", suffix: ".scp.part")
        #expect(Self.mode(target) == Self.row("ATOMIC.scp", "new")[1])
        #expect(Self.entries(root) == Self.row("ATOMIC.scp", "new")[3])
        try Self.chmod(target, 0o644)
        try RawFileSystem.writeAtomically(Array("OK1B\n".utf8), to: target, temporaryIn: root,
                                          prefix: "master", suffix: ".scp.part")
        #expect([Self.mode(target), Self.entries(root)] == Self.row("ATOMIC.scp", "over0644"))
    }
}
