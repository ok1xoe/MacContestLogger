import os

/// Buffer of program messages for the message window of the Info window — "you were spotted", RBN spots of your own
/// callsign and the like (Java `message/MessageLog` v1.1.1).
///
/// The history is bounded: the window runs for the whole contest and without a cap it would grow without end. Once full,
/// the oldest messages drop out. Java `synchronized` methods = a lock; the class is shared between the main
/// thread and plugin results.
public final class MessageLog: Sendable {

    /// One message.
    public struct Entry: Equatable, Sendable {
        /// When it was created.
        public let at: JavaInstant
        /// Content (trimmed by Java `trim()`).
        public let text: String

        public init(at: JavaInstant, text: String) {
            self.at = at
            self.text = text
        }
    }

    private let maxEntries: Int
    private let state = OSAllocatedUnfairLock<[Entry]>(initialState: [])

    /// Cap of at least 1 (Java `Math.max(1, maxEntries)`).
    public init(maxEntries: Int) {
        self.maxEntries = max(1, maxEntries)
    }

    /// Adds a message; blank ones (`isBlank`) are discarded so that spaces do not fill the window. The trim is Java's
    /// `trim()` (characters ≤ U+0020) — a message of NBSP therefore passes and stays `"\u{A0}"`, one of U+3000 is dropped.
    public func add(_ at: JavaInstant, _ text: String?) {
        guard let text, !JavaText.isBlank(text) else { return }
        let entry = Entry(at: at, text: JavaText.trim(text))
        let cap = maxEntries
        state.withLock { entries in
            entries.append(entry)
            if entries.count > cap {
                entries.removeFirst(entries.count - cap)
            }
        }
    }

    /// Messages from oldest to newest.
    public var entries: [Entry] {
        state.withLock { $0 }
    }

    /// The whole content as clipboard text — each message with the time `HHmm` in UTC and `"Z  "`, lines
    /// joined by `System.lineSeparator()` (`\n`). An instant outside the `LocalDateTime` range (years
    /// ±999 999 999) is rejected by the Java formatter → `JavaDateTimeException` (measured).
    public func asText() throws(JavaDateTimeException) -> String {
        let snapshot: [Entry] = entries
        var lines: [String] = []
        lines.reserveCapacity(snapshot.count)
        for entry in snapshot {
            let time: String = try Self.hhmm(entry.at)
            lines.append("\(time)Z  \(entry.text)")
        }
        return lines.joined(separator: "\n")
    }

    public func clear() {
        state.withLock { $0.removeAll() }
    }

    /// `DateTimeFormatter.ofPattern("HHmm").withZone(UTC)`.
    static func hhmm(_ at: JavaInstant) throws(JavaDateTimeException) -> String {
        let day: Int64 = try JavaDateTimeException.utcEpochDay(at)
        let secondOfDay: Int64 = at.epochSecond - day * 86_400
        let hours: Int64 = secondOfDay / 3_600
        let minutes: Int64 = (secondOfDay / 60) % 60
        return JavaLocalDate.twoDigits(hours) + JavaLocalDate.twoDigits(minutes)
    }
}
