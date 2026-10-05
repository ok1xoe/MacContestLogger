import Darwin

/// Java `IOException` from the sound classes (`SoundCard`, `AudioCapture`, `ContestRecorder`): `message` is
/// Java `getMessage()` (e.g. `Nepodporovaný formát wav: cq.wav`), `javaClass` the name of the Java exception class
/// (`java.io.IOException`, `java.io.FileNotFoundException`…) — for comparison with the probe; `VoiceKeyer` shows
/// the user only `message` (`String(describing:)`).
public struct AudioIOError: Error, Equatable, Sendable, CustomStringConvertible {
    public let javaClass: String
    public let message: String

    public init(_ message: String, javaClass: String = "java.io.IOException") {
        self.javaClass = javaClass
        self.message = message
    }

    public var description: String { message }

    /// `FileNotFoundException` from `FileInputStream`/`RandomAccessFile`: `path (reason)` (reason = `strerror`).
    static func fileNotFound(_ path: String, _ code: Int32) -> AudioIOError {
        AudioIOError(path + " (" + String(cString: strerror(code)) + ")", javaClass: "java.io.FileNotFoundException")
    }

    /// Error of `read`/`write`/`lseek` on an open file (Java `IOException` with the `strerror` text).
    static func posix(_ code: Int32) -> AudioIOError {
        AudioIOError(String(cString: strerror(code)))
    }
}
