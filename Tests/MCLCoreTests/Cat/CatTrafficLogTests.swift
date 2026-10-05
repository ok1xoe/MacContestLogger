import Foundation
import os
import Testing
@testable import MCLCore

/// Port of `cat/CatTrafficLogTest` + `CTL.*` measurements (maintainer-only probe). Files only in the test's
/// temporary directory.
@Suite struct CatTrafficLogTests {

    @Test func ringBufferKeepsLastLines() throws {
        let log = CatTrafficLog(maxLines: 2)
        try log.tx("f")
        try log.rx("14074000")
        try log.info("třetí")
        #expect(log.snapshot().count == 2, "the buffer should hold only the last 2 rows")
        #expect(log.snapshot()[1].contains("třetí"))
    }

    @Test func notifiesListeners() throws {
        let log = CatTrafficLog(maxLines: 10)
        let hits = OSAllocatedUnfairLock(initialState: 0)
        log.addListener { hits.withLock { $0 += 1 } }
        try log.tx("F 14074000")
        try log.rx("RPRT 0")
        #expect(hits.withLock { $0 } == 2)
    }

    @Test func appendsToFile() throws {
        try withTemporaryDirectory { dir in
            let file = dir.appendingPathComponent("cat.log")
            let log = CatTrafficLog(maxLines: 10)
            log.setFile(file)
            try log.tx("f")
            let content = try String(contentsOf: file, encoding: .utf8)
            #expect(content.contains("→ f"), "the file should contain the sent command: \(content)")
        }
    }

    // MARK: - Measurements (`CTL.*`)

    /// `CTL.line`: `HH:mm:ss.SSS`, two spaces, prefix `→ `/`← `/`· `/`rigctld: `; capacity 3 keeps the last three.
    @Test func measuredLineShapes() throws {
        let log = CatTrafficLog(maxLines: 3)
        try log.tx("f")
        try log.rx("14074000")
        try log.info("t\u{0159}et\u{00ED}")
        try log.process("Opened rig model 1")
        try log.tx("")
        let shapes: [String] = log.snapshot().map { line in
            let units = Array(line.utf16)
            let stamp = String(decoding: units.prefix(12), as: UTF16.self)
            let rest = String(decoding: units.dropFirst(12), as: UTF16.self)
            return (Self.isTimestamp(stamp) ? "<HH:mm:ss.SSS>" : "BAD ") + rest
        }
        let expected: [String] = [
            "<HH:mm:ss.SSS>  \u{00B7} t\u{0159}et\u{00ED}",
            "<HH:mm:ss.SSS>  rigctld: Opened rig model 1",
            "<HH:mm:ss.SSS>  \u{2192} ",
        ]
        #expect(shapes == expected)
    }

    private static func isTimestamp(_ text: String) -> Bool {
        let units = Array(text.utf16)
        guard units.count == 12 else { return false }
        for (index, unit) in units.enumerated() {
            switch index {
            case 2, 5: if unit != 0x3A { return false }
            case 8: if unit != 0x2E { return false }
            default: if unit < 0x30 || unit > 0x39 { return false }
            }
        }
        return true
    }

    /// The time from `LocalTime.now()` in the system zone, milliseconds truncated (not rounded).
    @Test func timestampFormat() throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        let prague = try #require(TimeZone(identifier: "Europe/Prague"))
        let instant = Date(timeIntervalSince1970: 1_700_000_000.1239)
        #expect(CatTrafficLog.timestamp(instant, timeZone: utc) == "22:13:20.123")
        #expect(CatTrafficLog.timestamp(instant, timeZone: prague) == "23:13:20.123")
        let beforeEpoch = Date(timeIntervalSince1970: -0.5)
        #expect(CatTrafficLog.timestamp(beforeEpoch, timeZone: utc) == "23:59:59.500")
        #expect(CatTrafficLog.timestamp(Date(timeIntervalSince1970: 86_399.999), timeZone: utc) == "23:59:59.999")

        let log = CatTrafficLog(maxLines: 5, clock: { instant })
        try log.info("x")
        let expected = CatTrafficLog.timestamp(instant, timeZone: TimeZone.current) + "  \u{00B7} x"
        #expect(log.snapshot() == [expected])
    }

    /// `CTL.zero`: capacity 0 keeps nothing, the listener is still called. `CTL.negative`: negative capacity
    /// in Java throws `NoSuchElementException` from `removeFirst` (the row is lost, neither listeners nor the file get anything).
    @Test func measuredCapacityEdges() throws {
        let zero = CatTrafficLog(maxLines: 0)
        let hits = OSAllocatedUnfairLock(initialState: 0)
        zero.addListener { hits.withLock { $0 += 1 } }
        try zero.info("x")
        #expect(zero.snapshot().isEmpty)
        #expect(hits.withLock { $0 } == 1)

        let negative = CatTrafficLog(maxLines: -1)
        #expect(throws: JavaNoSuchElementError()) { try negative.info("x") }
        #expect(negative.snapshot().isEmpty)
    }

    /// `CTL.clear` and `CTL.listenerTwice`: a listener added twice is called twice, removal takes off only
    /// one occurrence (Java `CopyOnWriteArrayList.remove`; Swift via the returned token).
    @Test func measuredClearAndListeners() throws {
        let log = CatTrafficLog(maxLines: 5)
        try log.info("a")
        log.clear()
        try log.info("b")
        #expect(log.snapshot().count == 1)
        #expect(log.snapshot()[0].hasSuffix("\u{00B7} b"))

        let twice = CatTrafficLog(maxLines: 5)
        let hits = OSAllocatedUnfairLock(initialState: 0)
        let listener: @Sendable () -> Void = { hits.withLock { $0 += 1 } }
        let first = twice.addListener(listener)
        twice.addListener(listener)
        try twice.info("x")
        twice.removeListener(first)
        try twice.info("y")
        #expect(hits.withLock { $0 } == 3)
    }

    /// `CTL.file`/`CTL.fileAfterNull`: creates parent directories, UTF-8 + `\n` after every row;
    /// `setFile(nil)` turns off further writing to the file.
    @Test func measuredFileAppend() throws {
        try withTemporaryDirectory { dir in
            let nested = dir.appendingPathComponent("a").appendingPathComponent("b").appendingPathComponent("cat.log")
            let log = CatTrafficLog(maxLines: 5)
            log.setFile(nested)
            try log.tx("f")
            try log.info("\u{017E}lu\u{0165}ou\u{010D}k\u{00FD}")
            let content = try String(contentsOf: nested, encoding: .utf8)
            let lines: [String] = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            #expect(lines.count == 3)
            #expect(lines[0].utf16.dropFirst(12).elementsEqual("  \u{2192} f".utf16))
            #expect(lines[1].utf16.dropFirst(12).elementsEqual("  \u{00B7} \u{017E}lu\u{0165}ou\u{010D}k\u{00FD}".utf16))
            #expect(lines[2].isEmpty)
            log.setFile(nil)
            try log.info("bez souboru")
            #expect(try String(contentsOf: nested, encoding: .utf8) == content)
            #expect(log.snapshot().count == 3)
        }
    }

    /// `CTL.fileError`/`CTL.fileIsDir`: the file error is thrown (`Nelze zapsat do CAT logu:
    /// <cesta>`), the row is already in the buffer, listeners are not called.
    @Test func measuredFileErrors() throws {
        try withTemporaryDirectory { dir in
            let blocker = dir.appendingPathComponent("blocker")
            try Data("x".utf8).write(to: blocker)
            let bad = CatTrafficLog(maxLines: 5)
            let hits = OSAllocatedUnfairLock(initialState: 0)
            bad.addListener { hits.withLock { $0 += 1 } }
            let target = blocker.appendingPathComponent("cat.log")
            bad.setFile(target)
            let error = try #require(throws: UncheckedIOError.self) { try bad.tx("f") }
            #expect(error.message == "Nelze zapsat do CAT logu: " + target.path)
            #expect(bad.snapshot().count == 1)
            #expect(hits.withLock { $0 } == 0)

            let asDir = dir.appendingPathComponent("isdir")
            try FileManager.default.createDirectory(at: asDir, withIntermediateDirectories: true)
            let bad2 = CatTrafficLog(maxLines: 5)
            bad2.setFile(asDir)
            let error2 = try #require(throws: UncheckedIOError.self) { try bad2.rx("x") }
            #expect(error2.message == "Nelze zapsat do CAT logu: " + asDir.path)
        }
    }

    /// The shared instance (Java `instance()`) holds 1,000 rows.
    @Test func sharedInstanceCapacity() {
        #expect(CatTrafficLog.shared.maxLines == 1000)
    }

    private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cat-log-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try body(dir)
    }
}
