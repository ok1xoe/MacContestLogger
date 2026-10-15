import Darwin
import Foundation
import os

/// The program's own log files in `<data>/diagnostics` (N1MM's `Errorlog.txt` and „Program Execution Logging"):
///
/// - `errors.log` — always written: the program messages of the Info window (failed downloads and uploads, Cabrillo
///   warnings, definition updates…), so a problem can be looked up after the fact (Help → View error log);
/// - `program.log` — only while program execution logging is on (Tools menu or `MCL_DIAGNOSTICS=1` at start): the
///   messages, every status line and every menu action, for a bug report.
///
/// A line is `yyyy-MM-dd HH:mm:ss.SSS` (local time) + two spaces + the category + two spaces + the text on one line.
/// A file that reaches `maxBytes` is renamed to `<name>.1` (replacing the older copy) before the next line, so the
/// logs never grow without bound. Nothing is written before `setDirectory` (tests, the inert app); a file error is
/// ignored — a log must never break the program. Thread-safe.
public final class ProgramLog: Sendable {

    /// The shared instance the app points at its data directory.
    public static let shared = ProgramLog()

    public static let folderName = "diagnostics"
    public static let errorFileName = "errors.log"
    public static let programFileName = "program.log"
    /// The size at which a file is rotated.
    public static let defaultMaxBytes = 1_000_000

    private struct State {
        var directory: URL?
        var enabled = false
    }

    private let state = OSAllocatedUnfairLock<State>(initialState: State())
    /// Serialises the writes so the lines of two threads do not interleave.
    private let writing = OSAllocatedUnfairLock()
    private let clock: @Sendable () -> Date
    private let maxBytes: Int

    public init(clock: @escaping @Sendable () -> Date = { Date() }, maxBytes: Int = ProgramLog.defaultMaxBytes) {
        self.clock = clock
        self.maxBytes = max(256, maxBytes)
    }

    /// The folder of the logs (`<data>/diagnostics`); `nil` = write nothing.
    public func setDirectory(_ directory: URL?) {
        state.withLock { $0.directory = directory }
    }

    public var directory: URL? {
        state.withLock { $0.directory }
    }

    /// Program execution logging (`program.log`).
    public var isEnabled: Bool {
        state.withLock { $0.enabled }
    }

    public func setEnabled(_ enabled: Bool) {
        let changed: Bool = state.withLock { s in
            defer { s.enabled = enabled }
            return s.enabled != enabled
        }
        if changed {
            append(Self.programFileName, category: "log", enabled ? "program execution logging on" : "off")
        }
    }

    public var errorFile: URL? {
        directory?.appendingPathComponent(Self.errorFileName)
    }

    public var programFile: URL? {
        directory?.appendingPathComponent(Self.programFileName)
    }

    /// A program message: always into `errors.log`, and into `program.log` while logging is on.
    public func message(_ text: String) {
        append(Self.errorFileName, category: "message", text)
        if isEnabled {
            append(Self.programFileName, category: "message", text)
        }
    }

    /// A trace line (`status`, `menu`, …) into `program.log` while logging is on.
    public func trace(_ category: String, _ text: @autoclosure () -> String) {
        guard isEnabled else { return }
        append(Self.programFileName, category: category, text())
    }

    /// `errors.log` with a header line when it does not exist yet, so Help → View error log always has a file.
    @discardableResult
    public func ensureErrorFile() -> URL? {
        guard let url = errorFile else { return nil }
        writing.withLock {
            guard !FileManager.default.fileExists(atPath: url.path) else { return }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: url.path,
                                           contents: Data("# MacContestLogger program messages and errors\n".utf8))
        }
        return url
    }

    // MARK: - lines

    /// `2026-10-15 14:03:22.123  message  text` (line breaks inside the text become spaces).
    public static func line(_ date: Date, category: String, _ text: String, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        let flat: String = text.replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
        return formatter.string(from: date) + "  " + category + "  " + flat + "\n"
    }

    private func append(_ name: String, category: String, _ text: String) {
        guard let directory = directory else { return }
        let url: URL = directory.appendingPathComponent(name)
        let bytes = Array(Self.line(clock(), category: category, text).utf8)
        writing.withLock {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                return
            }
            rotateIfNeeded(url)
            let fd = url.path.withCString { Darwin.open($0, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0o644) }
            guard fd >= 0 else { return }
            defer { Darwin.close(fd) }
            var offset = 0
            while offset < bytes.count {
                let n = bytes[offset...].withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
                if n < 0 {
                    if errno == EINTR { continue }
                    return
                }
                offset += n
            }
        }
    }

    /// Under `writing`: a file at `maxBytes` or more becomes `<name>.1`.
    private func rotateIfNeeded(_ url: URL) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber, size.intValue >= maxBytes else { return }
        let old: URL = url.appendingPathExtension("1")
        try? FileManager.default.removeItem(at: old)
        try? FileManager.default.moveItem(at: url, to: old)
    }
}
