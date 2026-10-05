import Foundation
import Testing
@testable import MCLCore

/// Port of `BackupRotationTest.java` — `BackupRotation.prune` deletes only the oldest
/// automatic backups of the given logbook beyond the `keep` count; nothing else in the directory
/// (another logbook, a manual backup without `-auto-`) is affected by the rotation.
@Suite struct BackupRotationTests {

    @Test func keepsNewest() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let t = ISO8601DateFormatter().date(from: "2026-11-28T12:00:00Z")!
        for i in 0..<5 {
            let target = BackupRotation.target(
                dir: dir, logName: "cqww.sqlite", now: t.addingTimeInterval(600 * Double(i)))
            try "x".write(to: target, atomically: true, encoding: .utf8)
        }
        // another logbook
        try "x".write(
            to: dir.appendingPathComponent("other-auto-20260101-000000.sqlite"), atomically: true, encoding: .utf8)
        // manual COPYLOG (without `-auto-`)
        try "x".write(
            to: dir.appendingPathComponent("cqww-20260101-000000.sqlite"), atomically: true, encoding: .utf8)

        #expect(try BackupRotation.prune(dir: dir, logName: "cqww.sqlite", keep: 3) == 2)
        #expect(!FileManager.default.fileExists(
            atPath: dir.appendingPathComponent("cqww-auto-20261128-120000.sqlite").path))
        #expect(FileManager.default.fileExists(
            atPath: dir.appendingPathComponent("cqww-auto-20261128-124000.sqlite").path))
        #expect(FileManager.default.fileExists(
            atPath: dir.appendingPathComponent("other-auto-20260101-000000.sqlite").path))
        #expect(FileManager.default.fileExists(
            atPath: dir.appendingPathComponent("cqww-20260101-000000.sqlite").path))
    }
}
