import Foundation
import os

/// Live dump of the callbook HTTP communication (Java `hamqth.HamQthLog`) for debugging grid lookup:
/// sent requests (password masked) and received responses. A ring buffer of the last `maxLines`
/// lines, thread-safe; modelled on `DxClusterTrafficLog`.
///
/// Line: `HH:mm:ss` (Java `LocalTime.now()` = **local** time of the system zone, seconds truncated) + two
/// spaces + `→ GET `/`← [status]` + LF + body/`· ` + text. Listeners are called outside the lock, synchronously
/// on the writer's thread.
///
/// Negative capacity: after inserting, Java empties the queue and `removeFirst` then throws
/// `NoSuchElementException` — here `JavaNoSuchElementError` (the buffer stays empty, listeners are not
/// called), so `request`/`response`/`info` throw.
public final class HamQthLog: Sendable {

    /// Listener identity for `removeListener`.
    public struct ListenerID: Hashable, Sendable {
        fileprivate let raw: UInt64
    }

    private struct State {
        var lines: [String] = []
        var listeners: [(id: UInt64, run: @Sendable () -> Void)] = []
        var nextListenerID: UInt64 = 0
    }

    private static let passwordParam: JavaRegex = CallbookXml.compile("(?i)([?&]p=)[^&]*")

    let maxLines: Int
    private let clock: @Sendable () -> Date
    private let state = OSAllocatedUnfairLock(initialState: State())

    /// - Parameters:
    ///   - maxLines: buffer capacity (Java default constructor: 400)
    ///   - clock: time source (tests); the zone is always the current system one
    public init(maxLines: Int = 400, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.maxLines = maxLines
        self.clock = clock
    }

    /// Outgoing GET request (the `p=` password in the URL is masked).
    public func request(_ url: String?) throws {
        try record("\u{2192} GET " + HamQthLog.mask(url))
    }

    /// Received response (HTTP status + body `trim()`; `nil` body = empty).
    public func response(_ status: Int, _ body: String?) throws {
        let text = body.map { JavaText.trim($0) } ?? ""
        try record("\u{2190} [\(status)]\n\(text)")
    }

    /// Informational/status message (error, timeout, result).
    public func info(_ msg: String) throws {
        try record("\u{00B7} " + msg)
    }

    /// Java `mask(url)`: the value of the parameter `p=` (after `?` or `&`, name case-insensitive
    /// ASCII) → `***`; `nil` → `""`.
    static func mask(_ url: String?) -> String {
        guard let url else { return "" }
        return CallbookXml.maskGroup1(passwordParam, url)
    }

    /// Current snapshot of the buffer (a copy).
    public func snapshot() -> [String] {
        state.withLock { $0.lines }
    }

    public func clear() {
        state.withLock { $0.lines.removeAll() }
    }

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
        // `LocalTime.format("HH:mm:ss")` = the first eight characters of `HH:mm:ss.SSS` from `CatTrafficLog`.
        let stamp = String(CatTrafficLog.timestamp(clock(), timeZone: TimeZone.current).prefix(8))
        let line = stamp + "  " + body
        try state.withLock { s in
            s.lines.append(line)
            while s.lines.count > maxLines {
                guard !s.lines.isEmpty else { throw JavaNoSuchElementError() }
                s.lines.removeFirst()
            }
        }
        let listeners = state.withLock { $0.listeners }
        for listener in listeners {
            listener.run()
        }
    }
}
