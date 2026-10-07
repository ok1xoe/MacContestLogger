import Foundation

/// Abstraction of transceiver control (CAT). The default implementation `RigctldClient` talks to the hamlib
/// daemon `rigctld`; the interface allows test doubles and later alternatives without affecting the UI.
/// Mirrors Java `cz.ok1xoe.maccontestlogger.cat.RigController`.
///
/// Methods are **synchronous and blocking** as in Java (called off the main thread — poller, CW queue);
/// Java `RuntimeException`s (`CatException`, `UncheckedIOException` from the CAT log…) are `throws` here.
/// Extended operations (split, second VFO, RIT, antennas, VFO select and swap) have a default implementation
/// that throws `CatException` with the same text as the Java `default` methods — a rig that does not support them
/// need not implement them.
public protocol RigController: AnyObject, Sendable {

    /// Reads the current rig state (frequency + mode).
    func read() throws -> RigState

    /// Sets the VFO frequency in Hz.
    func setFrequencyHz(_ freqHz: Int64) throws

    /// Sets the operating mode (`nil` = unknown; `RigctldClient` sends `USB`).
    func setMode(_ mode: Mode?, freqHz: Int64) throws

    /// Keys (`true`) or unkeys the transmitter — PTT for the voice keyer.
    func setPtt(_ on: Bool) throws

    /// Keys the transmitter unless `cancelled()` says otherwise when the command is about to be written (checked
    /// while the connection is held, so a release requested meanwhile always wins); `false` = not keyed.
    func keyPtt(unless cancelled: () -> Bool) throws -> Bool

    /// Unkeys the transmitter for a plugin release: like `setPtt(false)`, but never over a connection that may be
    /// out of step after a timeout.
    func releasePtt() throws

    /// Sends text through the rig's keyer (CW over CAT, hamlib `send_morse`).
    func sendMorse(_ text: String) throws

    /// Aborts CW transmission by the rig's keyer (hamlib `stop_morse`).
    func stopMorse() throws

    /// Sets the rig keyer speed in WPM (hamlib level `KEYSPD`).
    func setCwSpeed(_ wpm: Int) throws

    /// Split: transmit on the second VFO. `txFreqHz > 0` also sets the transmit frequency, 0 leaves the
    /// second VFO's frequency as is. Turning it off returns transmission to VFO A.
    func setSplit(_ on: Bool, txFreqHz: Int64) throws

    /// Sets the frequency of the second VFO (B) without enabling split.
    func setOtherVfoFrequencyHz(_ freqHz: Int64) throws

    /// RIT (receiver offset) in Hz; 0 = turn RIT off and zero it. Hamlib `J` (set_rit) + function `RIT`.
    func setRit(_ offsetHz: Int) throws

    /// Rig antenna connector (1 = ANT1…), hamlib `Y`.
    func setAntenna(_ antenna: Int) throws

    /// Switches the rig to VFO A (`false`) or B (`true`) for both receive and transmit (SO2V).
    func selectVfo(_ vfoB: Bool) throws

    /// Swaps VFO A and B (A↔B).
    func swapVfo() throws

    /// A raw `rigctld` command (the extended response form) for plugins with the `cat` permission: the reply lines
    /// and the `RPRT` code. Callers check the command with `PluginCatPolicy` first.
    func sendRaw(_ command: String) throws -> RigRawReply

    /// Where this controller is connected (`rigctld`'s host and port), `nil` when not a `rigctld` client.
    var endpoint: RigEndpoint? { get }

    /// Is the rig connection active?
    func isConnected() -> Bool

    /// Closes the connection (Java `AutoCloseable.close`; errors while closing are swallowed).
    func close()
}

/// The reply to a raw command: the lines before `RPRT` and its code (0 = OK).
public struct RigRawReply: Equatable, Sendable {
    public let lines: [String]
    public let code: Int

    public init(lines: [String], code: Int) {
        self.lines = lines
        self.code = code
    }
}

/// The `rigctld` a rig controller talks to.
public struct RigEndpoint: Equatable, Sendable {
    public let host: String
    public let port: Int

    public init(host: String, port: Int) {
        self.host = host
        self.port = port
    }
}

extension RigController {

    public var endpoint: RigEndpoint? {
        nil
    }

    public func sendRaw(_ command: String) throws -> RigRawReply {
        throw CatException("Rig surové příkazy nepodporuje")
    }

    public func setSplit(_ on: Bool, txFreqHz: Int64) throws {
        throw CatException("Rig split nepodporuje")
    }

    public func setOtherVfoFrequencyHz(_ freqHz: Int64) throws {
        throw CatException("Rig nastavení druhého VFO nepodporuje")
    }

    public func setRit(_ offsetHz: Int) throws {
        throw CatException("Rig RIT nepodporuje")
    }

    public func setAntenna(_ antenna: Int) throws {
        throw CatException("Rig přepínání antén nepodporuje")
    }

    public func selectVfo(_ vfoB: Bool) throws {
        throw CatException("Rig výběr VFO nepodporuje")
    }

    public func swapVfo() throws {
        throw CatException("Rig prohození VFO nepodporuje")
    }
}

/// CAT communication error with the transceiver (Java `CatException extends RuntimeException`). `message` goes
/// to the status line, hence verbatim as in Java; `cause` carries the original error (socket timeout…).
public struct CatException: Error, CustomStringConvertible {
    public let message: String
    public let cause: (any Error)?

    public init(_ message: String, cause: (any Error)? = nil) {
        self.message = message
        self.cause = cause
    }

    public var description: String { message }
}

/// Instantaneous transceiver state read over CAT (Java record `RigState`).
public struct RigState: Equatable, Sendable {
    /// VFO frequency (receive) in Hz.
    public let freqHz: Int64
    /// Mapped operating mode (`nil` if it cannot be mapped).
    public let mode: Mode?
    /// Original mode string from hamlib (USB, LSB, CW, PKTUSB…).
    public let rawMode: String
    /// Bandwidth in Hz (0 = unknown).
    public let passband: Int64
    /// Rig transmits on the second VFO (split).
    public let split: Bool
    /// Transmit frequency during split (0 = unknown / no split).
    public let txFreqHz: Int64

    /// Without `split`/`txFreqHz` = the Java four-parameter constructor (the rig does not report split).
    public init(freqHz: Int64, mode: Mode?, rawMode: String, passband: Int64, split: Bool = false, txFreqHz: Int64 = 0) {
        self.freqHz = freqHz
        self.mode = mode
        self.rawMode = rawMode
        self.passband = passband
        self.split = split
        self.txFreqHz = txFreqHz
    }

    /// `freqHz / 1000.0` (`long` → `double` conversion rounds to nearest, like Java).
    public var freqKHz: Double {
        Double(freqHz) / 1000.0
    }
}

extension RigController {
    public func keyPtt(unless cancelled: () -> Bool) throws -> Bool {
        if cancelled() {
            return false
        }
        try setPtt(true)
        return true
    }

    public func releasePtt() throws {
        try setPtt(false)
    }
}

/// `rigctld` answered a command with an error (`RPRT -n`): the command reached the rig's daemon and was refused, so
/// nothing changed (unlike a timeout or a lost connection, after which the outcome is unknown).
public struct CatRefusal: Error, CustomStringConvertible, Sendable {
    public let message: String

    public init(message: String) {
        self.message = message
    }

    public var description: String {
        message
    }
}

/// `T 1` went out and its reply never came: whether and when the rig keys is unknown. `drain` tells how the `T 0`
/// sent right behind it on the same connection ended.
public struct CatUnknownOutcome: Error, CustomStringConvertible, Sendable {
    public let message: String
    public let drain: PttKeyDrain

    public var description: String {
        message
    }
}

/// The connection of an unanswered `T 1`, read in the background until the replies of that `T 1` and of the `T 0`
/// sent right behind it came (or a bound passed).
public final class PttKeyDrain: @unchecked Sendable {
    /// How a drain ended.
    public enum Result: Sendable, Equatable {
        /// The `T 0` behind the key was accepted: released in order.
        case released
        /// The key's reply came (it ran), but its `T 0` was refused or never answered: a later `T 0` runs after it.
        case keyRan
        /// Not even the key's reply came: it may still run at any time.
        case unknown
    }

    /// Reads of one timeout each before a drain gives up.
    static let boundReads = 10

    private let lock = NSLock()
    private var result: Result?
    private var waiting: [@Sendable (Result) -> Void] = []

    public init() {}

    /// `body` once the drain ended (at once when it has).
    public func onDone(_ body: @escaping @Sendable (Result) -> Void) {
        let done: Result? = lock.withLock {
            if result == nil {
                waiting.append(body)
            }
            return result
        }
        if let done {
            body(done)
        }
    }

    func finish(_ value: Result) {
        let callbacks: [@Sendable (Result) -> Void] = lock.withLock {
            guard result == nil else { return [] }
            result = value
            defer { waiting = [] }
            return waiting
        }
        for callback in callbacks {
            callback(value)
        }
    }

    static func read(_ socket: LineSocket, sentRelease: Bool, maxWaitMs: Int, log: CatTrafficLog) -> Result {
        let deadline: Date = Date().addingTimeInterval(Double(maxWaitMs) / 1_000)
        var replies: [String] = []
        while replies.count < 2 && Date() < deadline {
            let read: String?
            do {
                read = try socket.readLine()
            } catch {
                if error.kind == .readTimeout {
                    continue // still waiting for the replies
                }
                break // reset, closed, another I/O error: no more replies on this connection
            }
            guard let line = read else {
                break // end of stream
            }
            let trimmed: String = JavaText.trim(line)
            if trimmed.isEmpty {
                continue
            }
            try? log.rx(trimmed)
            replies.append(trimmed)
        }
        if replies.count == 2 && sentRelease && replies[1].utf16.starts(with: "RPRT 0".utf16) {
            return .released
        }
        return replies.isEmpty ? .unknown : .keyRan
    }
}
