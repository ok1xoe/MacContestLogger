import Foundation

/// Byte transport of a serial device (Winkeyer, OTRSP…) — the Java pair `InputStream`/`OutputStream`
/// + the `AutoCloseable` port. The real serial port is `SerialPort` (POSIX `termios`); tests use an in-memory
/// substitute (a pair of pipes like Java `PipedInputStream`).
///
/// The methods are synchronous and blocking; `read` is called by one reader thread, `write` by one writer under
/// the key lock.
public protocol ByteTransport: AnyObject, Sendable {

    /// Reads one byte (0…255); `-1` = end of stream (Java `InputStream.read()`). An error ends reading.
    func read() throws -> Int

    /// Writes and sends bytes (Java `write` + `flush`).
    func write(_ bytes: [UInt8]) throws

    /// Closes the port. A pending `read` ends with an error (or −1) and every further call throws. `close` does **not rely**
    /// on closing the descriptor unblocking `read(2)` (on macOS this is not reliable from another thread):
    /// `SerialPort` sets a flag, waits until the reader leaves `read(2)` — thanks to `VTIME` within 200 ms at most —
    /// and only then closes the descriptor; `close` may therefore block for up to the read timeout. In-memory substitutes
    /// unblock the reader immediately.
    func close() throws
}

/// Transport I/O error (Java `IOException`); `message` = `getMessage()` (may be missing — Java then
/// writes `null` in texts).
public struct ByteTransportError: Error, Equatable, Sendable, CustomStringConvertible {
    public let message: String?

    public init(_ message: String?) {
        self.message = message
    }

    public var description: String { message ?? "null" }
}
