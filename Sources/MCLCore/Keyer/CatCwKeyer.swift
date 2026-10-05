import Foundation

/// CW via the keyer built into the rig, controlled by CAT through rigctld (N1MM "CW Keying Using CAT Commands").
/// The rig handles plain text only — prosigns are sent as letter pairs and speed changes inside a message
/// (`<`, `>`) are not performed. Mirrors Java `keyer.CatCwKeyer`.
///
/// The rig is taken from a closure on every call: CAT may disconnect and reconnect and the keyer should not be
/// affected. The keyer remembers the last set speed (not the rig) and sends `KEYSPD` only on change; the speed
/// is remembered only after a successful `setCwSpeed`. `send`/`setSpeed` are under a lock (Java `synchronized`),
/// `abort`/`tune` are not.
public final class CatCwKeyer: CwKeyer, @unchecked Sendable {

    private let rig: @Sendable () -> (any RigController)?
    private let lock = NSLock()
    private var speed = -1

    public init(rig: @escaping @Sendable () -> (any RigController)?) {
        self.rig = rig
    }

    private func connectedRig() throws -> any RigController {
        guard let r = rig() else {
            throw CwKeyerError(.illegalState, "CW přes CAT: TRX není připojený")
        }
        return r
    }

    public func send(_ message: CwMessage, wpm: Int) throws {
        lock.lock()
        defer { lock.unlock() }
        let text = message.plainText()
        if text.isEmpty {
            return
        }
        let r = try connectedRig()
        if wpm != speed {
            try r.setCwSpeed(wpm)
            speed = wpm
        }
        try r.sendMorse(text)
    }

    public func abort() throws {
        if let r = rig() {
            try r.stopMorse()
        }
    }

    /// Tuning via CAT: PTT in CW mode — the rig transmits a carrier.
    public func tune(_ on: Bool) throws {
        try connectedRig().setPtt(on)
    }

    public func setSpeed(_ wpm: Int) throws {
        lock.lock()
        defer { lock.unlock() }
        try connectedRig().setCwSpeed(wpm)
        speed = wpm
    }

    public func name() -> String {
        "CAT"
    }

    public func close() {
        // the connection to the rig belongs to the CAT connection, not to the keyer
    }
}
