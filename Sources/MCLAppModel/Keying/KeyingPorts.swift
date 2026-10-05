import Foundation
import MCLCore
import os

/// A voice message recording in progress (`SoundCard.Recording`; tests pass a fake). `stop` and `cancel` block:
/// the voice keyer model calls them on its own lane.
public protocol MessageRecording: AnyObject, Sendable {
    /// The wav file the recording replaces when it is saved.
    var target: JavaPath { get }
    /// Ends the recording and saves it.
    func stop() throws
    /// Discards the recording (the original file stays).
    func cancel()
}

extension SoundCard.Recording: MessageRecording {}

/// The fldigi calls of the digital keyer (`FldigiClient`; tests pass a client of a fake server on the loopback).
/// Every call blocks: only on the keyer lane.
public protocol FldigiPort: AnyObject, Sendable {
    func transmit(_ text: String) throws
    func trxState() throws -> String
    func abort() throws
    /// The Digital Interface window's poll: the RX buffer's length, a slice of it and the modem's name.
    func rxLength() throws -> Int32
    func rxText(start: Int32, length: Int32) throws -> String
    func modemName() throws -> String
}

extension FldigiClient: FldigiPort {}

/// The ports every transmission passes: the multi-op TX interlock, the
/// network announcement of a transmission and the pileup simulator.
public struct TxPorts {
    /// Kotlin `txAllowed()`: `nil` = transmitting is allowed, otherwise the status to show (nothing is sent).
    public var txGate: @MainActor () -> EntryStatus? = { nil }
    /// Kotlin `announceTx()` (a no-op unless a port is installed).
    public var announceTx: @MainActor () -> Void = {}
    /// Kotlin `simulator?.let { sendSimulated(it, message, index) }`: `true` = the simulator took the CW message.
    public var simulatorRoute: (@MainActor (CwMessage, Int) -> Bool)?
    /// Kotlin `abortCw()` with a simulator (`AS:1741-1748`): the simulator's sound is cleared and the lit key goes out; the
    /// result is whether a message was lit, `nil` = no simulation runs (the keyer's own abort applies).
    public var simulatorAbort: (@MainActor () -> Bool?)?
    /// While the pileup simulator starts or runs, nothing keys the real rig — voice, digital, tune and
    /// the footswitch PTT ask this first; `nil` = allowed, otherwise the status to show. Never consulted by a release
    /// (PTT off, tune off, stop). CW is taken by `simulatorRoute` before any gate; `sendCw` asks this too, as a backstop.
    public var rigKeyingGate: @MainActor () -> EntryStatus? = { nil }

    public init() {}
}

/// Java `getMessage()` of a keying error (`nil` = `null`): the message of a keyer, audio, fldigi or inert-hardware
/// error, the Java message of a Java-shaped error, otherwise its description.
enum KeyingErrors {
    static func javaMessage(_ error: any Error) -> String? {
        if let error = error as? JavaIllegalArgumentError {
            return error.message
        }
        if let error = error as? KeyingFailure {
            return error.message
        }
        return JavaThrowables.describe(error).message
    }
}

/// An error the keying models raise themselves (Kotlin `error(tr("…"))`, already translated).
struct KeyingFailure: Error, CustomStringConvertible {
    let message: String

    var description: String { message }
}

/// The CAT session a keying thread reaches (`CatCwKeyer { cat.rigOrNull() }`, the voice keyer's PTT): set on the main
/// actor when a transmission starts, read on the keyer's thread.
final class ActiveCatBox: Sendable {
    private let state = OSAllocatedUnfairLock<(any CatPort)?>(initialState: nil)

    func set(_ cat: (any CatPort)?) {
        state.withLock { $0 = cat }
    }

    var cat: (any CatPort)? {
        state.withLock { $0 }
    }
}
