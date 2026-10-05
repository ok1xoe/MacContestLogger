import Foundation

/// CW keyer: transmits a message, changes speed and interrupts transmission on Esc. Implementations: `CatCwKeyer`
/// (rig keyer via rigctld) and `WinkeyerKeyer` (K1EL Winkeyer over a serial line). Mirrors the Java
/// interface `keyer.CwKeyer`.
///
/// Calls may block on I/O — the UI calls them off the main thread. Java
/// `RuntimeException`s are `throws` here (`CwKeyerError`, `CatException` from the rig).
public protocol CwKeyer: AnyObject, Sendable {

    /// Transmits a message at the base speed `wpm` (`<`/`>` changes are added to it).
    func send(_ message: CwMessage, wpm: Int) throws

    /// Immediately interrupts transmission and discards the rest of the message.
    func abort() throws

    /// Sets the keyer speed in WPM.
    func setSpeed(_ wpm: Int) throws

    /// Tuning (N1MM Ctrl+T): continuous carrier on / off. The default implementation throws like the Java
    /// `default` method (`UnsupportedOperationException`).
    func tune(_ on: Bool) throws

    /// Name for the status line ("Winkeyer v31", "CAT").
    func name() -> String

    /// Closes the keyer (errors are swallowed as in Java).
    func close()
}

extension CwKeyer {

    public func tune(_ on: Bool) throws {
        throw CwKeyerError(.unsupportedOperation, "Tento klíč ladění nosnou neumí")
    }
}

/// CW keyer error — a Java exception; `kind.rawValue` is the Java class name, `message` verbatim as in Java
/// (goes to the status line).
public struct CwKeyerError: Error, Equatable, Sendable, CustomStringConvertible {

    public enum Kind: String, Sendable {
        /// `IllegalStateException` (CAT keyer without a connected rig).
        case illegalState = "IllegalStateException"
        /// `UnsupportedOperationException` (keyer without carrier tuning).
        case unsupportedOperation = "UnsupportedOperationException"
        /// `IOException` (Winkeyer does not answer host open).
        case io = "IOException"
        /// `UncheckedIOException` (write to the Winkeyer failed).
        case uncheckedIO = "UncheckedIOException"
    }

    public let kind: Kind
    public let message: String

    public init(_ kind: Kind, _ message: String) {
        self.kind = kind
        self.message = message
    }

    public var description: String { message }
}
