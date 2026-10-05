import Foundation
import Testing
@testable import MCLCore

/// `RecordingPlayback.read` against `AppState.playQsoRecording` (`AS:2464-2471`, `RandomAccessFile`): synthetic
/// recordings in a temporary directory only.
@Suite struct RecordingPlaybackTests {

    static func withRecording(dataBytes: Int, _ body: (JavaPath) throws -> Void) throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rp-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("rec.wav")
        let header = ContestRecorder.wavHeader(sampleRate: 12_000, data: Int64(dataBytes))
        let data: [UInt8] = (0..<dataBytes).map { UInt8(truncatingIfNeeded: $0) }
        try Data(header + data).write(to: file)
        try body(try JavaPath(file.path))
    }

    static func segment(_ file: JavaPath, offset: Int64, length: Int64) -> ContestRecorder.Segment {
        ContestRecorder.Segment(file: file, offsetBytes: offset, lengthBytes: length)
    }

    @Test func readsFromAfterTheHeaderAtTheOffset() throws {
        try Self.withRecording(dataBytes: 1_000) { file in
            let bytes = try RecordingPlayback.read(segment: Self.segment(file, offset: 10, length: 6))
            #expect(bytes == [10, 11, 12, 13, 14, 15])
        }
    }

    /// A QSO near the end of the hour: the segment is cut at the end of that hour's file (no next file is read).
    @Test func segmentStopsAtTheEndOfTheHourFile() throws {
        try Self.withRecording(dataBytes: 1_000) { file in
            let bytes = try RecordingPlayback.read(segment: Self.segment(file, offset: 900, length: 360_000))
            #expect(bytes.count == 100)
            #expect(bytes.first == UInt8(truncatingIfNeeded: 900))
        }
    }

    /// Only an even number of bytes is played (`buf.size - buf.size % 2`).
    @Test func oddLengthIsTrimmedToWholeSamples() throws {
        try Self.withRecording(dataBytes: 1_001) { file in
            let long = try RecordingPlayback.read(segment: Self.segment(file, offset: 0, length: 5_000))
            let short = try RecordingPlayback.read(segment: Self.segment(file, offset: 0, length: 7))
            #expect(long.count == 1_000)
            #expect(short.count == 6)
        }
    }

    @Test func startPastTheEndReadsNothing() throws {
        try Self.withRecording(dataBytes: 100) { file in
            let bytes = try RecordingPlayback.read(segment: Self.segment(file, offset: 5_000, length: 100))
            #expect(bytes.isEmpty)
        }
    }

    @Test func missingFileIsJavaFileNotFound() throws {
        let path = try JavaPath(FileManager.default.temporaryDirectory.path + "/rp-missing-" + UUID().uuidString)
        #expect(throws: AudioIOError(path.description + " (No such file or directory)",
                                     javaClass: "java.io.FileNotFoundException")) {
            try RecordingPlayback.read(segment: Self.segment(path, offset: 0, length: 10))
        }
    }

    /// The segment `ContestRecorder` computes (10 s before, 5 s after at 12 kHz) is read from its own file.
    @Test func recorderSegmentIsReadable() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rp-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let recorder = ContestRecorder(dir: try JavaPath(dir.path), sampleRate: 12_000)
        let at = Date(timeIntervalSince1970: 1_790_000_000) // 800 s into its hour
        try recorder.write([UInt8](repeating: 7, count: 24_000), at: at)
        try recorder.close()
        let segment = try #require(recorder.segment(qsoTime: at, beforeSec: 10, afterSec: 5))
        #expect(segment.lengthBytes == 15 * 24_000)
        // The file holds only one second of audio, written at the start of the file: the segment lies past it.
        #expect(try RecordingPlayback.read(segment: segment).isEmpty)
        let fromStart = ContestRecorder.Segment(file: segment.file, offsetBytes: 0, lengthBytes: segment.lengthBytes)
        #expect(try RecordingPlayback.read(segment: fromStart) == [UInt8](repeating: 7, count: 24_000))
    }
}
