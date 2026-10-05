import Foundation

/// Reading and writing the goals file — in Java the Kotlin UI does it (`RateWindow.kt`: import `Files.readAllLines(path)`,
/// export `Files.writeString(path, GoalFileWriter.toText(goals))`); it lives in
/// the core so that the UI layer has no logic. The error carries the Java class and `getMessage()` (UI: "Cíle se nepodařilo přečíst (%s)",
/// "Export cílů selhal (%s)").
///
/// Blocking POSIX I/O — call off the main thread and off the shared pool.
public enum GoalFileIO {

    /// `Files.readAllLines(path)`: strict UTF-8 (a BOM stays as U+FEFF at the start of the first line — the parser
    /// reports such a line as unrecognised), lines split by `\n`, `\r` and `\r\n` (`JavaLines.split`).
    ///
    /// Errors like Java (measured): a missing file `NoSuchFileException: <path>`, without permission
    /// `AccessDeniedException: <path>`, a directory `IOException: Is a directory`, invalid UTF-8
    /// `MalformedInputException: Input length = <n>` (length of the first bad sequence per the JDK decoder).
    public static func readLines(_ path: String) throws(JavaIOError) -> [String] {
        let file: String = RawFileSystem.javaPath(path)
        let descriptor: Int32 = open(file, O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else {
            throw unixError(file, errno)
        }
        defer { close(descriptor) }
        var bytes: [UInt8] = []
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count: Int = buffer.withUnsafeMutableBytes { read(descriptor, $0.baseAddress, $0.count) }
            if count == 0 { break }
            if count < 0 {
                let code: Int32 = errno
                if code == EINTR { continue }
                throw JavaIOError(String(cString: strerror(code)))
            }
            bytes.append(contentsOf: buffer[0..<count])
        }
        if let length = malformedLength(bytes) {
            throw JavaIOError("Input length = " + String(length), javaClass: "java.nio.charset.MalformedInputException")
        }
        return JavaLines.split(String(decoding: bytes, as: UTF8.self))
    }

    /// `Files.writeString(path, GoalFileWriter.toText(goals))`: **not atomic** — `open(O_WRONLY | O_CREAT |
    /// O_TRUNC, 0666)` and write (measured: a new file has permissions per umask, an existing one keeps its own, a symbolic
    /// link is followed and its target is overwritten, no temporary file is created).
    ///
    /// Errors like Java: `NoSuchFileException: <path>` (missing directory), `AccessDeniedException: <path>`
    /// (read-only file, directory without write permission), `FileSystemException: <path>: Is a directory`.
    public static func write(_ goals: GoalSet, to path: String) throws(JavaIOError) {
        let file: String = RawFileSystem.javaPath(path)
        let bytes: [UInt8] = Array(GoalFileWriter.toText(goals).utf8)
        let descriptor: Int32 = open(file, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0o666)
        guard descriptor >= 0 else {
            throw unixError(file, errno)
        }
        var written = 0
        while written < bytes.count {
            let count: Int = bytes[written...].withUnsafeBytes { Darwin.write(descriptor, $0.baseAddress, $0.count) }
            if count < 0 {
                let code: Int32 = errno
                if code == EINTR { continue }
                close(descriptor)
                throw JavaIOError(String(cString: strerror(code)))
            }
            written += count
        }
        guard close(descriptor) == 0 else {
            throw JavaIOError(String(cString: strerror(errno)))
        }
    }

    /// `UnixException.translateToIOException(file, null)` (JDK 21).
    private static func unixError(_ file: String, _ code: Int32) -> JavaIOError {
        switch code {
        case EACCES: return JavaIOError(file, javaClass: "java.nio.file.AccessDeniedException")
        case ENOENT: return JavaIOError(file, javaClass: "java.nio.file.NoSuchFileException")
        case EEXIST: return JavaIOError(file, javaClass: "java.nio.file.FileAlreadyExistsException")
        default:
            let reason = String(cString: strerror(code))
            return JavaIOError(file + ": " + reason, javaClass: "java.nio.file.FileSystemException")
        }
    }

    // MARK: - Length of a bad UTF-8 sequence

    /// Length of the first bad sequence as reported by the UTF-8 `CharsetDecoder` (JDK 21 `UTF_8.Decoder.decodeArrayLoop`
    /// and `malformedN`) with action `REPORT`; a truncated sequence at the end of the file = the number of remaining bytes
    /// (`CharsetDecoder.decode(…, endOfInput)`). Valid UTF-8 → `nil`.
    static func malformedLength(_ bytes: [UInt8]) -> Int? {
        let src: [Int] = bytes.map { Int(Int8(bitPattern: $0)) }
        var sp = 0
        while sp < src.count {
            let b1: Int = src[sp]
            let remaining: Int = src.count - sp
            if b1 >= 0 {
                sp += 1
            } else if (b1 >> 5) == -2 && (b1 & 0x1E) != 0 {
                if remaining < 2 { return remaining }
                if isNotContinuation(src[sp + 1]) { return 1 }
                sp += 2
            } else if (b1 >> 4) == -2 {
                if let length = malformed3(src, sp, remaining) { return length }
                sp += 3
            } else if (b1 >> 3) == -2 {
                if let length = malformed4(src, sp, remaining) { return length }
                sp += 4
            } else {
                return 1
            }
        }
        return nil
    }

    private static func isNotContinuation(_ b: Int) -> Bool {
        (b & 0xC0) != 0x80
    }

    /// Three-byte sequence from `sp` (lead byte E0–EF); `nil` = valid.
    private static func malformed3(_ src: [Int], _ sp: Int, _ remaining: Int) -> Int? {
        let b1: Int = src[sp]
        if remaining < 3 {
            if remaining > 1 && isMalformed3and2(b1, src[sp + 1]) { return 1 }
            return remaining
        }
        let b2: Int = src[sp + 1]
        let b3: Int = src[sp + 2]
        if isMalformed3and2(b1, b2) { return 1 }
        if isNotContinuation(b3) { return 2 }
        let high: Int = ((b1 & 0x0F) << 12) | ((b2 & 0x3F) << 6)
        let c: Int = high | (b3 & 0x3F)
        return (0xD800...0xDFFF).contains(c) ? 3 : nil
    }

    private static func isMalformed3and2(_ b1: Int, _ b2: Int) -> Bool {
        (b1 == -32 && (b2 & 0xE0) == 0x80) || isNotContinuation(b2)
    }

    /// Four-byte sequence from `sp` (lead byte F0–F7); `nil` = valid.
    private static func malformed4(_ src: [Int], _ sp: Int, _ remaining: Int) -> Int? {
        let lead: Int = src[sp] & 0xFF
        if remaining < 4 {
            if lead > 0xF4 || (remaining > 1 && isMalformed4and2(lead, src[sp + 1] & 0xFF)) { return 1 }
            if remaining > 2 && isNotContinuation(src[sp + 2]) { return 2 }
            return remaining
        }
        let b2: Int = src[sp + 1] & 0xFF
        if lead > 0xF4 || isMalformed4and2(lead, b2) { return 1 }
        if isNotContinuation(src[sp + 2]) { return 2 }
        if isNotContinuation(src[sp + 3]) { return 3 }
        return nil
    }

    /// Bytes without sign (`& 0xff`).
    private static func isMalformed4and2(_ b1: Int, _ b2: Int) -> Bool {
        let overlong: Bool = b1 == 0xF0 && (b2 < 0x90 || b2 > 0xBF)
        let tooHigh: Bool = b1 == 0xF4 && (b2 & 0xF0) != 0x80
        return overlong || tooHigh || isNotContinuation(b2)
    }
}
