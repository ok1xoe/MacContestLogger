import Foundation
@testable import MCLCore

/// Writing `keyer/` values like the Java maintainer-only probes and
/// `…/keyer/ProbeKeyer.java` (`parts`, `describe`, Java `List.toString`, `safe`), so that rows can be
/// compared by fingerprint with `out-en_US.tsv`.
enum KeyerProbe {

    static func parts(_ message: CwMessage) -> String {
        var items: [String] = []
        for part in message.parts {
            switch part {
            case .text(let text): items.append("T'" + text + "'")
            case .prosign(let letters): items.append("P" + letters)
            case .speed(let delta): items.append("S" + String(delta))
            }
        }
        return "[" + items.joined(separator: ",") + "]"
    }

    static func javaList(_ items: [String]) -> String {
        "[" + items.joined(separator: ", ") + "]"
    }

    static func describe(_ message: CwMessage) -> String {
        parts(message) + " plain='" + message.plainText() + "' actions=" + javaList(message.actions.map(\.rawValue))
            + " unknown=" + javaList(message.unknownMacros) + " empty=" + String(message.isEmpty)
    }

    /// Java `safe(() -> { …; return "ok"; })`: `ok`, or `EXC <class>: <message>`.
    static func safe(_ body: () throws -> String) -> String {
        do {
            return try body()
        } catch let error as CwKeyerError {
            return "EXC " + error.kind.rawValue + ": " + error.message
        } catch let error as CatException {
            return "EXC CatException: " + error.message
        } catch {
            return "EXC " + String(describing: error)
        }
    }

    static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { byte in
            let text = String(byte, radix: 16)
            return byte < 16 ? "0" + text : text
        }.joined()
    }

    /// A UTC instant like `Instant.parse` (proleptic Gregorian calendar).
    static func instant(_ year: Int64, _ month: Int64, _ day: Int64, _ hour: Int64, _ minute: Int64,
                        _ second: Double) -> Date {
        let days = JavaLocalDate.epochDay(year: year, month: month, day: day)
        let whole = Double(days * 86_400 + hour * 3_600 + minute * 60)
        return Date(timeIntervalSince1970: whole + second)
    }
}

/// A serial port stand-in: a pair of pipes like the Java test (`PipedInputStream` from the key, `ByteArrayOutputStream`
/// to the key). `feed` = Java `fromKeyer.write`, `sent` = `toKeyer.toByteArray()`.
///
/// Synchronisation without time bounds: `waitUntilDrained` waits until the reader thread consumes everything and waits again
/// in `read` (= the previous byte is processed); `waitUntilEnded` waits until `read` returned end of stream.
/// Waits have only a generous guard against hangs.
final class PipeTransport: ByteTransport, @unchecked Sendable {
    private let condition = NSCondition()
    private var incoming: [UInt8] = []
    private var endOfStream = false
    private var waitingReaders = 0
    private var ended = false
    private var written: [UInt8] = []
    private var closes = 0
    private var writeCalls = 0
    /// An error thrown by every `write` (`nil` = the write goes through); Java `IOException.getMessage()`.
    var writeFailure: ByteTransportError?
    /// An error from `close` (port closed a second time…).
    var closeFailure: ByteTransportError?
    /// How the stand-in records `close` calls (for order with other events).
    var onClose: (@Sendable () -> Void)?

    init(incoming: [UInt8] = [], endOfStream: Bool = false) {
        self.incoming = incoming
        self.endOfStream = endOfStream
    }

    func feed(_ bytes: [UInt8]) {
        condition.lock()
        incoming.append(contentsOf: bytes)
        condition.broadcast()
        condition.unlock()
    }

    func finish() {
        condition.lock()
        endOfStream = true
        condition.broadcast()
        condition.unlock()
    }

    var sent: [UInt8] {
        condition.lock()
        defer { condition.unlock() }
        return written
    }

    var closeCount: Int {
        condition.lock()
        defer { condition.unlock() }
        return closes
    }

    /// Number of `write` calls including failed ones.
    var writeAttempts: Int {
        condition.lock()
        defer { condition.unlock() }
        return writeCalls
    }

    /// Java `toKeyer.reset()`.
    func resetSent() {
        condition.lock()
        written.removeAll()
        condition.unlock()
    }

    func read() throws -> Int {
        condition.lock()
        defer { condition.unlock() }
        while incoming.isEmpty && !endOfStream {
            waitingReaders += 1
            condition.broadcast()
            condition.wait()
            waitingReaders -= 1
        }
        if incoming.isEmpty {
            ended = true
            condition.broadcast()
            return -1
        }
        return Int(incoming.removeFirst())
    }

    func write(_ bytes: [UInt8]) throws {
        condition.lock()
        defer { condition.unlock() }
        writeCalls += 1
        if let writeFailure { throw writeFailure }
        written.append(contentsOf: bytes)
    }

    /// Closing the port unblocks the read (end of stream).
    func close() throws {
        condition.lock()
        closes += 1
        endOfStream = true
        condition.broadcast()
        let failure = closeFailure
        let hook = onClose
        condition.unlock()
        hook?()
        if let failure { throw failure }
    }

    /// Waits until the reader thread processes all fed bytes. `false` = the guard expired.
    @discardableResult
    func waitUntilDrained() -> Bool {
        wait { $0.incoming.isEmpty && ($0.waitingReaders > 0 || $0.ended) }
    }

    /// Waits until `read` returns end of stream (the read loop ended). `false` = the guard expired.
    @discardableResult
    func waitUntilEnded() -> Bool {
        wait { $0.ended }
    }

    private func wait(_ done: (PipeTransport) -> Bool) -> Bool {
        let safety = Date(timeIntervalSinceNow: 30)
        condition.lock()
        defer { condition.unlock() }
        while !done(self) {
            if !condition.wait(until: safety) { return done(self) }
        }
        return true
    }
}

/// A rig that records CAT calls (Java `RecordingRig` from the test and probe); `failOn` = a method that
/// after recording throws `CatException("selhalo <jméno>")`.
final class KeyerRecordingRig: RigController, @unchecked Sendable {
    private let lock = NSLock()
    private var log: [String] = []
    private var failing = ""

    var calls: [String] {
        lock.lock()
        defer { lock.unlock() }
        return log
    }

    var failOn: String {
        get { lock.lock(); defer { lock.unlock() }; return failing }
        set { lock.lock(); failing = newValue; lock.unlock() }
    }

    private func call(_ name: String, _ text: String) throws {
        lock.lock()
        log.append(text)
        let fail = failing == name
        lock.unlock()
        if fail { throw CatException("selhalo " + name) }
    }

    func read() throws -> RigState { RigState(freqHz: 14_025_000, mode: .cw, rawMode: "CW", passband: 500) }
    func setFrequencyHz(_ freqHz: Int64) throws {}
    func setMode(_ mode: Mode?, freqHz: Int64) throws {}
    func setPtt(_ on: Bool) throws { try call("ptt", "ptt " + String(on)) }
    func sendMorse(_ text: String) throws { try call("morse", "morse " + text) }
    func stopMorse() throws { try call("stop", "stop") }
    func setCwSpeed(_ wpm: Int) throws { try call("speed", "speed " + String(wpm)) }
    func isConnected() -> Bool { true }
    func close() {
        lock.lock()
        log.append("close")
        lock.unlock()
    }
}
