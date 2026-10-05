import Darwin

/// Reading the recording segment around a QSO (`AppState.playQsoRecording`, `AS:2455-2478`) — Kotlin
/// `RandomAccessFile`: `start = 44 + offsetBytes`, `len = min(lengthBytes, max(0, fileLength − start))`, `seek(start)`,
/// `readFully`, then only an even number of bytes is played (`buf.size - buf.size % 2`). The segment is read only from
/// the recording of its own hour: a QSO near the end of the hour plays to the end of that file and no further.
/// Blocking file I/O — call it on the playback queue, never on the main actor or in a `Task`.
public enum RecordingPlayback {

    /// The WAV header that `ContestRecorder` writes before the data.
    public static let headerBytes: Int64 = 44

    public static func read(segment: ContestRecorder.Segment) throws(AudioIOError) -> [UInt8] {
        let path = segment.file.description
        let fd = open(path, O_RDONLY | O_CLOEXEC)
        guard fd >= 0 else {
            throw AudioIOError.fileNotFound(path, errno)
        }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0 else {
            throw AudioIOError.posix(errno)
        }
        if (info.st_mode & S_IFMT) == S_IFDIR {
            throw AudioIOError.fileNotFound(path, EISDIR)
        }
        let start = headerBytes &+ segment.offsetBytes
        let available = Swift.max(0, Int64(info.st_size) &- start)
        let length = Int(Int32(truncatingIfNeeded: Swift.min(segment.lengthBytes, available)))
        guard length > 0 else { return [] }
        var buffer = [UInt8](repeating: 0, count: length)
        var done = 0
        while done < length {
            let n: Int = buffer.withUnsafeMutableBytes { raw in
                pread(fd, raw.baseAddress.map { $0 + done }, length - done, off_t(start) + off_t(done))
            }
            if n < 0 {
                if errno == EINTR { continue }
                throw AudioIOError.posix(errno)
            }
            if n == 0 {
                // `readFully` past the end (the file shrank meanwhile): Java `EOFException` without a message.
                throw AudioIOError("null", javaClass: "java.io.EOFException")
            }
            done += n
        }
        return Array(buffer.prefix(length - length % 2))
    }
}
