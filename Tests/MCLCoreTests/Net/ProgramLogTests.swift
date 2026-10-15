import Foundation
import Testing
@testable import MCLCore

/// The program's error and diagnostics log: what goes where, when, and the rotation.
@Suite struct ProgramLogTests {

    private static func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("program-log-\(UUID().uuidString)")
    }

    private static func read(_ url: URL?) -> String {
        guard let url, let data = try? Data(contentsOf: url) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    @Test func nothingIsWrittenWithoutADirectory() {
        let log = ProgramLog()
        log.setEnabled(true)
        log.message("x")
        #expect(log.errorFile == nil)
        #expect(log.ensureErrorFile() == nil)
    }

    @Test func messagesAlwaysGoToTheErrorLogTracesOnlyWhileLoggingIsOn() throws {
        let dir = Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = ProgramLog(clock: { Date(timeIntervalSince1970: 0) })
        log.setDirectory(dir)
        log.message("Club Log upload failed\nHTTP 500")
        log.trace("status", "not written")
        #expect(Self.read(log.errorFile).contains("message  Club Log upload failed HTTP 500\n"))
        #expect(!FileManager.default.fileExists(atPath: try #require(log.programFile).path))
        log.setEnabled(true)
        log.trace("status", "Uloženo")
        log.message("second")
        let program: String = Self.read(log.programFile)
        #expect(program.contains("log  program execution logging on"))
        #expect(program.contains("status  Uloženo"))
        #expect(program.contains("message  second"))
        log.setEnabled(false)
        log.trace("menu", "help.docs")
        #expect(!Self.read(log.programFile).contains("help.docs"))
        #expect(Self.read(log.programFile).hasSuffix("log  off\n"))
    }

    @Test func aFullFileIsRotated() {
        let dir = Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = ProgramLog(maxBytes: 300)
        log.setDirectory(dir)
        for index in 0..<20 {
            log.message("line \(index) " + String(repeating: "x", count: 40))
        }
        let current: String = Self.read(log.errorFile)
        let old: String = Self.read(log.errorFile?.appendingPathExtension("1"))
        #expect(current.utf8.count < 400)
        #expect(!old.isEmpty)
        #expect(current.contains("line 19 "))
        #expect(!current.contains("line 0 "))
    }

    @Test func theErrorFileExistsForTheHelpMenu() throws {
        let dir = Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = ProgramLog()
        log.setDirectory(dir)
        let file = try #require(log.ensureErrorFile())
        #expect(file.lastPathComponent == "errors.log")
        #expect(Self.read(file).hasPrefix("# MacContestLogger"))
        log.message("kept")
        log.ensureErrorFile()
        #expect(Self.read(file).contains("kept"))
    }

    @Test func aLineHasTheTimeTheCategoryAndOneLineOfText() {
        let utc = TimeZone(identifier: "UTC")!
        #expect(ProgramLog.line(Date(timeIntervalSince1970: 1.5), category: "menu", "a\r\nb", timeZone: utc)
            == "1970-01-01 00:00:01.500  menu  a b\n")
    }
}
