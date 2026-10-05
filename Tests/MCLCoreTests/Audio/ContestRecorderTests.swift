import AVFoundation
import CryptoKit
import Foundation
import Testing
@testable import MCLCore

/// Port of `audio/ContestRecorderTest` (2 tests, same names) and the file bytes of `ContestRecorder.write/close`
/// against the maintainer-only probe (rows `CR.*`, same scenarios).
@Suite struct ContestRecorderTests {

    static func instant(_ text: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)!
    }

    /// The test's temporary directory (deleted in the caller's `defer`).
    static func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cr-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return URL(fileURLWithPath: dir.path).resolvingSymlinksInPath()
    }

    /// Bytes `(byte) (i * 37 + 11)` as the probe's `pattern`.
    static func pattern(_ count: Int) -> [UInt8] {
        (0..<count).map { UInt8(truncatingIfNeeded: $0 &* 37 &+ 11) }
    }

    static func hex(_ bytes: some Sequence<UInt8>) -> String {
        bytes.map { ($0 < 16 ? "0" : "") + String($0, radix: 16) }.joined()
    }

    /// Rows `name, size, header hex, SHA-256` like the probe's `listDir`.
    static func listing(_ dir: URL) throws -> [[String]] {
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        return try names.map { name in
            let bytes = [UInt8](try Data(contentsOf: dir.appendingPathComponent(name)))
            return [name, String(bytes.count), hex(bytes.prefix(44)), hex(SHA256.hash(data: Data(bytes)))]
        }
    }

    static func java(_ id: String) -> [[String]] {
        ProbeRows.rows(AudioIoMeasured.rows, id)
    }

    static func recorder(_ dir: URL, _ rate: Int32 = 12_000) throws -> ContestRecorder {
        ContestRecorder(dir: try JavaPath(dir.path), sampleRate: rate)
    }

    // MARK: - Java tests

    @Test func rotatesPerHourAndWritesValidWav() throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let r = try Self.recorder(dir)
        try r.write([UInt8](repeating: 0, count: 24_000), at: Self.instant("2026-11-28T12:59:59Z")) // 1 s
        try r.write([UInt8](repeating: 0, count: 48_000), at: Self.instant("2026-11-28T13:00:00Z")) // 2 s
        try r.close()
        let a = dir.appendingPathComponent("20261128-12.wav")
        let b = dir.appendingPathComponent("20261128-13.wav")
        #expect(try FileManager.default.attributesOfItem(atPath: a.path)[.size] as? Int == 44 + 24_000)
        #expect(try FileManager.default.attributesOfItem(atPath: b.path)[.size] as? Int == 44 + 48_000)
        // Java `AudioSystem.getAudioFileFormat` → an independent `AVAudioFile` reader (file only, no device).
        let file = try AVAudioFile(forReading: b)
        #expect(file.length == 24_000)
        #expect(file.fileFormat.sampleRate == 12_000)
    }

    @Test func appendsAfterRestartAndFindsSegment() throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let r = try Self.recorder(dir)
        try r.write([UInt8](repeating: 0, count: 2_000), at: Self.instant("2026-11-28T12:00:00Z"))
        try r.close()
        let r2 = try Self.recorder(dir)
        try r2.write([UInt8](repeating: 0, count: 1_000), at: Self.instant("2026-11-28T12:00:05Z"))
        try r2.close()
        let size = try FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent("20261128-12.wav").path)
        #expect(size[.size] as? Int == 44 + 3_000)

        let seg = try #require(r2.segment(qsoTime: Self.instant("2026-11-28T12:10:00Z"), beforeSec: 10, afterSec: 5))
        #expect(seg.offsetBytes == 590 * 24_000)
        #expect(seg.lengthBytes == 15 * 24_000)
        #expect(r2.segment(qsoTime: Self.instant("2026-11-28T15:00:00Z"), beforeSec: 10, afterSec: 5) == nil)
    }

    // MARK: - File bytes against Java

    /// Probe scenario: `body` writes into a subdirectory, the listing is compared with the rows `CR.<id>`.
    static func scenario(_ id: String, sub: String = "", _ body: (URL) throws -> Void) throws {
        let root = try tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let dir = sub.isEmpty ? root.appendingPathComponent(id) : root.appendingPathComponent(sub)
        try body(dir)
        #expect(try listing(dir) == java("CR." + id), "CR.\(id)")
    }

    static func existing(_ dir: URL, _ bytes: [UInt8]) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(bytes).write(to: dir.appendingPathComponent("20261128-12.wav"))
    }

    @Test func filesMatchJava() throws {
        let t = Self.instant
        try Self.scenario("rotate") { d in
            let r = try Self.recorder(d)
            try r.write(Self.pattern(24_000), at: t("2026-11-28T12:59:59Z"))
            try r.write(Self.pattern(48_000), at: t("2026-11-28T13:00:00Z"))
            try r.close()
        }
        try Self.scenario("restart") { d in
            let r = try Self.recorder(d)
            try r.write(Self.pattern(2_000), at: t("2026-11-28T12:00:00Z"))
            try r.close()
            let r2 = try Self.recorder(d)
            try r2.write(Self.pattern(1_001), at: t("2026-11-28T12:00:05Z"))
            try r2.write(Self.pattern(3), at: t("2026-11-28T12:30:00Z"))
            try r2.close()
        }
        try Self.scenario("short") { d in
            try Self.existing(d, Self.pattern(43))
            let r = try Self.recorder(d)
            try r.write(Self.pattern(10), at: t("2026-11-28T12:00:00Z"))
            try r.close()
        }
        try Self.scenario("exact44") { d in
            try Self.existing(d, Self.pattern(44))
            let r = try Self.recorder(d)
            try r.write(Self.pattern(6), at: t("2026-11-28T12:00:00Z"))
            try r.close()
        }
        try Self.scenario("odd") { d in
            try Self.existing(d, Self.pattern(45))
            let r = try Self.recorder(d, 22_050)
            try r.write(Self.pattern(2), at: t("2026-11-28T12:00:00Z"))
            try r.close()
        }
        try Self.scenario("empty") { d in
            let r = try Self.recorder(d)
            try r.write([], at: t("2026-11-28T12:00:00Z"))
            try r.close()
            try r.close()
        }
        try Self.scenario("reopen", sub: "reopen/a/b") { d in
            let r = try Self.recorder(d)
            try r.write(Self.pattern(4), at: t("2026-11-28T12:00:00Z"))
            try r.close()
            try r.write(Self.pattern(6), at: t("2026-11-28T12:10:00Z"))
            try r.write(Self.pattern(8), at: t("2026-11-28T13:00:00Z"))
            try r.write(Self.pattern(10), at: t("2026-11-28T12:20:00Z"))
            try r.close()
        }
    }

    /// Without closing (application crash): the data and a header with zero length are on disk; closing fixes it.
    @Test func crashLeavesZeroLengthHeaderLikeJava() throws {
        let root = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let dir = root.appendingPathComponent("crash")
        let r = try Self.recorder(dir)
        try r.write(Self.pattern(100), at: Self.instant("2026-11-28T12:00:00Z"))
        try r.write(Self.pattern(7), at: Self.instant("2026-11-28T12:00:01Z"))
        #expect(try Self.listing(dir) == Self.java("CR.crash"))
        try r.close()
        #expect(try Self.listing(dir) == Self.java("CR.crashClosed"))
    }

    @Test func directoryThatIsAFileFailsLikeJava() throws {
        let root = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("cr").appendingPathComponent("isfile")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(Self.pattern(3)).write(to: file)
        let r = try Self.recorder(file)
        let expected: [String] = try #require(Self.java("CR.isfile").first)
        #expect(throws: AudioIOError(expected[1].replacingOccurrences(of: "<dir>", with: root.path),
                                     javaClass: expected[0])) {
            try r.write(Self.pattern(2), at: Self.instant("2026-11-28T12:00:00Z"))
        }
    }
}
