import Foundation

/// Recording of the whole contest (Java `audio/ContestRecorder`, N1MM QSO recording / DXLog Audio recorder):
/// PCM from the receiver audio is written to WAV files by UTC hour (`yyyyMMdd-HH.wav`); for a QSO time the
/// file and position for playback are found.
///
/// Own WAV writer 1:1 with Java `RandomAccessFile` (not `AVAudioFile` — because of
/// continuation after a restart and length truncation; file bytes measured by the maintainer-only probe):
/// - lengths in the header are Java `(int)` truncation (`3 000 000 000` → `005ed0b2`);
/// - `segment` counts whole seconds from the start of the hour (`Duration.getSeconds` = floor) × `sampleRate × 2`;
///   `beforeSec + afterSec` overflows in `int` as in Java;
/// - `write` on an hour change closes the file (rewrites the header with the actual data length) and opens the file of the new hour;
///   an existing file ≥ 44 B continues at the end (app restart, also a return to an earlier hour), a shorter one is
///   truncated to zero and gets a header with zero length. The header is rewritten only on close/rotation — an app
///   crash leaves the header with the length from the last close (zero for a new file), the data remain;
/// - a lock instead of Java `synchronized`; called from the `AudioCapture` listener queue.
///
/// **Divergence:** when opening the file fails during rotation and the next block arrives in the **old** hour, Java crashes
/// with `NullPointerException` (`out == null`); here `AudioIOError` with the same Java class.
public final class ContestRecorder: @unchecked Sendable {

    static let headerSize = 44

    private let dir: JavaPath
    private let sampleRate: Int32
    /// Write state (Java `out`, `currentHour`, `dataBytes`) under `lock`.
    private let lock = NSLock()
    private var fd: Int32 = -1
    private var currentHour: String?
    private var dataBytes: Int64 = 0

    public init(dir: JavaPath, sampleRate: Int32) {
        self.dir = dir
        self.sampleRate = sampleRate
    }

    /// An unclosed writer only releases the descriptor (does not rewrite the header — like the Java `Cleaner` of `RandomAccessFile`).
    deinit {
        if fd >= 0 {
            Darwin.close(fd)
        }
    }

    /// File of the hour the instant belongs to (UTC; a year above 9999 with a `+` sign like `yyyy` in Java).
    public func fileFor(_ at: Date) -> JavaPath {
        dir.resolve(fileName: Self.hourName(at) + ".wav")
    }

    static func hourName(_ at: Date) -> String {
        guard let parts = JavaLocalDate.split(at) else {
            preconditionFailure("okamžik mimo rozsah Instant: \(at)")
        }
        let secondOfDay = parts.secondOfDay
        let (year, month, day) = JavaLocalDate.civil(epochDay: parts.epochDay)
        return JavaLocalDate.formatYearOfEra(year) + JavaLocalDate.twoDigits(month)
            + JavaLocalDate.twoDigits(day) + "-" + JavaLocalDate.twoDigits(secondOfDay / 3600)
    }

    /// Writes a block of 16-bit mono PCM received at instant `at` (rotation by UTC hours).
    public func write(_ pcm: [UInt8], at: Date) throws(AudioIOError) {
        lock.lock()
        defer { lock.unlock() }
        let hour = Self.hourName(at)
        if hour != currentHour {
            try closeFile()
            try open(fileFor(at))
            currentHour = hour
        }
        guard fd >= 0 else {
            throw AudioIOError("Cannot invoke \"java.io.RandomAccessFile.write(byte[])\" because \"this.out\" is null",
                               javaClass: "java.lang.NullPointerException")
        }
        try Self.writeAll(fd, pcm)
        dataBytes &+= Int64(pcm.count)
    }

    /// Closes the file and rewrites its header with the actual data length; the next `write` opens the file again.
    public func close() throws(AudioIOError) {
        lock.lock()
        defer { lock.unlock() }
        try closeFile()
        currentHour = nil
    }

    private func open(_ file: JavaPath) throws(AudioIOError) {
        try Self.createDirectories(dir.description)
        let path = file.description
        let opened = Darwin.open(path, O_RDWR | O_CREAT | O_CLOEXEC, 0o644)
        guard opened >= 0 else {
            throw AudioIOError.fileNotFound(path, errno)
        }
        fd = opened
        var info = stat()
        guard fstat(opened, &info) == 0 else {
            throw AudioIOError.posix(errno)
        }
        let length = Int64(info.st_size)
        if length >= Int64(Self.headerSize) {
            dataBytes = length - Int64(Self.headerSize) // continuing in the same hour (app restart)
            guard lseek(opened, 0, SEEK_END) >= 0 else {
                throw AudioIOError.posix(errno)
            }
        } else {
            guard ftruncate(opened, 0) == 0 else {
                throw AudioIOError.posix(errno)
            }
            try Self.writeAll(opened, header(0))
            dataBytes = 0
        }
    }

    private func closeFile() throws(AudioIOError) {
        guard fd >= 0 else {
            return
        }
        guard lseek(fd, 0, SEEK_SET) >= 0 else {
            throw AudioIOError.posix(errno)
        }
        try Self.writeAll(fd, header(dataBytes))
        Darwin.close(fd)
        fd = -1
    }

    static func writeAll(_ fd: Int32, _ bytes: [UInt8]) throws(AudioIOError) {
        var offset = 0
        while offset < bytes.count {
            let written: Int = bytes.withUnsafeBytes { raw in
                Darwin.write(fd, raw.baseAddress! + offset, bytes.count - offset)
            }
            if written < 0 {
                if errno == EINTR { continue }
                throw AudioIOError.posix(errno)
            }
            offset += written
        }
    }

    /// Java `Files.createDirectories`: an existing directory passes, an existing file →
    /// `FileAlreadyExistsException` with the path as text; other errors `FileSystemException` (`path: reason`).
    static func createDirectories(_ path: String) throws(AudioIOError) {
        var info = stat()
        if stat(path, &info) == 0 {
            if (info.st_mode & S_IFMT) == S_IFDIR {
                return
            }
            throw AudioIOError(path, javaClass: "java.nio.file.FileAlreadyExistsException")
        }
        let parent = (path as NSString).deletingLastPathComponent
        if !parent.isEmpty && parent != path {
            try createDirectories(parent)
        }
        if mkdir(path, 0o755) != 0 {
            let code = errno
            if code == EEXIST && stat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFDIR {
                return
            }
            if code == EEXIST {
                throw AudioIOError(path, javaClass: "java.nio.file.FileAlreadyExistsException")
            }
            throw AudioIOError(path + ": " + String(cString: strerror(code)),
                               javaClass: "java.nio.file.FileSystemException")
        }
    }

    /// WAV header of 16-bit mono PCM with a data length.
    func header(_ data: Int64) -> [UInt8] {
        Self.wavHeader(sampleRate: sampleRate, data: data)
    }

    /// WAV header of 16-bit mono PCM (shared by `SoundCard.Recording` — Java `WaveFileWriter` writes
    /// the same bytes for a recording, measured by the probe `REC.wav`).
    static func wavHeader(sampleRate: Int32, data: Int64) -> [UInt8] {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(Self.headerSize)
        func int(_ value: Int32) {
            withUnsafeBytes(of: value.littleEndian) { bytes.append(contentsOf: $0) }
        }
        func short(_ value: Int16) {
            withUnsafeBytes(of: value.littleEndian) { bytes.append(contentsOf: $0) }
        }
        bytes.append(contentsOf: Array("RIFF".utf8))
        int(Int32(truncatingIfNeeded: 36 &+ data))
        bytes.append(contentsOf: Array("WAVE".utf8))
        bytes.append(contentsOf: Array("fmt ".utf8))
        int(16)
        short(1)
        short(1)
        int(sampleRate)
        int(sampleRate &* 2)
        short(2)
        short(16)
        bytes.append(contentsOf: Array("data".utf8))
        int(Int32(truncatingIfNeeded: data))
        return bytes
    }

    /// Segment to play: file and offset in data bytes (start `before` seconds before the QSO).
    public struct Segment: Equatable, Sendable {
        public let file: JavaPath
        public let offsetBytes: Int64
        public let lengthBytes: Int64
    }

    /// Recording segment around a QSO; `nil` when the recording of that hour is not on disk (`Files.exists`).
    public func segment(qsoTime: Date, beforeSec: Int32, afterSec: Int32) -> Segment? {
        let file = fileFor(qsoTime)
        guard FileManager.default.fileExists(atPath: file.description) else {
            return nil
        }
        guard let parts = JavaLocalDate.split(qsoTime) else {
            preconditionFailure("okamžik mimo rozsah Instant: \(qsoTime)")
        }
        let secIntoHour = parts.secondOfDay % 3600
        let rate = Int64(sampleRate)
        let start = Swift.max(0, secIntoHour - Int64(beforeSec)) &* rate &* 2
        let length = Int64(beforeSec &+ afterSec) &* rate &* 2
        return Segment(file: file, offsetBytes: start, lengthBytes: length)
    }
}
