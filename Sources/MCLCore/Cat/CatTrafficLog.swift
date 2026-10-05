import Darwin
import Foundation
import os

/// Traffic log of the CAT/serial interface (Java `cat/CatTrafficLog`). Holds a ring buffer of the last
/// `maxLines` lines (for the live window) and optionally appends them to a file. Thread-safe — written by the poller,
/// the `rigctld` output reader and the UI.
///
/// Line: `HH:mm:ss.SSS` (local time of the system zone, milliseconds truncated) + two spaces + `→ `/`← `/`· `/
/// `rigctld: ` + text. The order in `record` is Java's: line into the buffer (under the lock), then append to the file,
/// then listeners — **synchronously on the writer's thread**.
///
/// A file error is **thrown** (`UncheckedIOError` „Nelze zapsat do CAT logu: <path>"):
/// the line is already in the buffer, listeners are not called and the caller (`RigctldClient.send`) lets the
/// error through — an unwritable CAT log thus breaks every command, in Java and here alike, and the poller disconnects the rig.
public final class CatTrafficLog: Sendable {

    /// Shared instance (Java `instance()`), 1,000 lines — a collection point so the logger need not be
    /// threaded through all constructors.
    public static let shared = CatTrafficLog(maxLines: 1000)

    /// Listener identity for `removeListener` (a Java `Runnable` is removed by object identity,
    /// a Swift closure has no identity).
    public struct ListenerID: Hashable, Sendable {
        fileprivate let raw: UInt64
    }

    private struct State {
        var lines: [String] = []
        var listeners: [(id: UInt64, run: @Sendable () -> Void)] = []
        var nextListenerID: UInt64 = 0
        var file: URL?
    }

    let maxLines: Int
    private let clock: @Sendable () -> Date
    private let state = OSAllocatedUnfairLock(initialState: State())

    /// - Parameters:
    ///   - maxLines: buffer capacity (negative leads, as in Java, to an error on the first write)
    ///   - clock: time source (tests); the zone is always the current system zone, like Java `LocalTime.now()`
    public init(maxLines: Int, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.maxLines = maxLines
        self.clock = clock
    }

    /// Sets the file to append to (parent directories are created on write). `nil` = no file.
    public func setFile(_ file: URL?) {
        state.withLock { $0.file = file }
    }

    /// Command sent to `rigctld`.
    public func tx(_ msg: String) throws {
        try record("\u{2192} " + msg)
    }

    /// Response received from `rigctld`.
    public func rx(_ msg: String) throws {
        try record("\u{2190} " + msg)
    }

    /// Informational/status message.
    public func info(_ msg: String) throws {
        try record("\u{00B7} " + msg)
    }

    /// Line of the `rigctld` process output.
    public func process(_ msg: String) throws {
        try record("rigctld: " + msg)
    }

    /// Current snapshot of the buffer (a copy).
    public func snapshot() -> [String] {
        state.withLock { $0.lines }
    }

    public func clear() {
        state.withLock { $0.lines.removeAll() }
    }

    /// Adds a listener (called after every line on the writer's thread). The same listener added
    /// twice is called twice, as in Java.
    @discardableResult
    public func addListener(_ listener: @escaping @Sendable () -> Void) -> ListenerID {
        state.withLock { s in
            let id = s.nextListenerID
            s.nextListenerID += 1
            s.listeners.append((id, listener))
            return ListenerID(raw: id)
        }
    }

    public func removeListener(_ id: ListenerID) {
        state.withLock { s in
            if let index = s.listeners.firstIndex(where: { $0.id == id.raw }) {
                s.listeners.remove(at: index)
            }
        }
    }

    private func record(_ body: String) throws {
        let line = Self.timestamp(clock(), timeZone: TimeZone.current) + "  " + body
        let file: URL? = try state.withLock { s -> URL? in
            s.lines.append(line)
            while s.lines.count > maxLines {
                // Negative capacity: Java empties the queue and `removeFirst` then throws.
                guard !s.lines.isEmpty else { throw JavaNoSuchElementError() }
                s.lines.removeFirst()
            }
            return s.file
        }
        if let file {
            try Self.append(line, to: file)
        }
        // Java `CopyOnWriteArrayList`: listeners by snapshot, called outside the lock.
        let listeners = state.withLock { $0.listeners }
        for listener in listeners {
            listener.run()
        }
    }

    /// Java `Files.createDirectories(parent)` + `Files.writeString(line + "\n", UTF_8, CREATE, APPEND)`.
    private static func append(_ line: String, to file: URL) throws {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let fd = file.path.withCString { Darwin.open($0, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0o666) }
            guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            defer { Darwin.close(fd) }
            let bytes: [UInt8] = Array((line + "\n").utf8)
            var offset = 0
            while offset < bytes.count {
                let written = bytes[offset...].withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
                if written < 0 {
                    if errno == EINTR { continue }
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
                offset += written
            }
        } catch {
            throw UncheckedIOError(message: "Nelze zapsat do CAT logu: " + file.path, cause: error)
        }
    }

    /// `LocalTime.format("HH:mm:ss.SSS")` of the instant in the given zone; milliseconds truncated (toward −∞).
    static func timestamp(_ date: Date, timeZone: TimeZone) -> String {
        // `Date` carries seconds in a `Double`: first to microseconds (round off noise), then truncate.
        let micros = Int64((date.timeIntervalSince1970 * 1_000_000).rounded())
        let epochMillis = micros >= 0 ? micros / 1000 : -((-micros + 999) / 1000)
        let local = epochMillis + Int64(timeZone.secondsFromGMT(for: date)) * 1000
        let dayMillis: Int64 = ((local % 86_400_000) + 86_400_000) % 86_400_000
        let hours = dayMillis / 3_600_000
        let minutes = dayMillis / 60_000 % 60
        let seconds = dayMillis / 1000 % 60
        let millis = dayMillis % 1000
        return pad(hours, 2) + ":" + pad(minutes, 2) + ":" + pad(seconds, 2) + "." + pad(millis, 3)
    }

    private static func pad(_ value: Int64, _ width: Int) -> String {
        let text = String(value)
        return String(repeating: "0", count: max(0, width - text.count)) + text
    }
}
