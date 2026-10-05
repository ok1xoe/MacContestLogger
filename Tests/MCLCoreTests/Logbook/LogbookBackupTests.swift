import Foundation
import Testing
@testable import MCLCore

/// Port of `LogbookBackupTest.java` — `LogbookRepository.backupTo`: consistent copy
/// of the file via `VACUUM INTO` and refusal to overwrite an existing target.
@Suite struct LogbookBackupTests {

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - `LogbookBackupTest.backupContainsAllQsos`

    @Test func backupContainsAllQsos() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let backup = dir.appendingPathComponent("backup.sqlite")

        do {
            let repo = try LogbookRepository(url: dir.appendingPathComponent("log.sqlite"))
            defer { repo.close() }
            var q = Qso()
            q.call = "DL1ABC"
            q.timestampUtc = ISO8601DateFormatter().date(from: "2026-11-28T12:00:00Z")
            q.freqHz = 14_025_000
            q.mode = .cw
            _ = try repo.insert(&q)

            try repo.backupTo(backup)
        }

        #expect(FileManager.default.fileExists(atPath: backup.path))

        let copy = try LogbookRepository(url: backup)
        defer { copy.close() }
        let all = try copy.findAllIncludingDeleted()
        #expect(all.count == 1)
        #expect(all[0].call == "DL1ABC")
    }

    // MARK: - `LogbookBackupTest.existingTargetIsNotOverwritten`

    @Test func existingTargetIsNotOverwritten() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let backup = dir.appendingPathComponent("exists.sqlite")
        try "x".write(to: backup, atomically: true, encoding: .utf8)

        let repo = try LogbookRepository(url: dir.appendingPathComponent("log.sqlite"))
        defer { repo.close() }
        #expect(throws: LogbookError.self) {
            try repo.backupTo(backup)
        }
    }
}
