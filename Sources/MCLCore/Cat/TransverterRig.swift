import Foundation

/// Rig behind a transverter (Java `cat/TransverterRig`): frequencies read from the rig at the intermediate frequency of an enabled
/// transverter are shifted by the offset (the real frequency goes to the log, bandmap…) and frequencies entered
/// on the transverter band are shifted back before being sent to the rig. The transverter list is read on **every**
/// call — a change in Settings applies immediately.
///
/// Arithmetic is Java `long` (`kHz * 1000`, `+`, `-`) and silently overflows on nonsensical
/// configuration input (`&*`, `&+`, `&-`) — Swift must not crash.
public final class TransverterRig: RigController {

    private let inner: any RigController
    private let transverters: @Sendable () -> [TransverterEntry]

    public init(inner: any RigController, transverters: @escaping @Sendable () -> [TransverterEntry]) {
        self.inner = inner
        self.transverters = transverters
    }

    /// Frequency from the rig → real (IF + offset) by the first enabled transverter whose IF range
    /// (both bounds inclusive) contains it; otherwise unchanged.
    public static func fromRig(_ rigHz: Int64, _ list: [TransverterEntry]) -> Int64 {
        for t in list {
            let lo: Int64 = Int64(t.ifLowKHz) &* 1000
            let hi: Int64 = Int64(t.ifHighKHz) &* 1000
            if t.enabled && rigHz >= lo && rigHz <= hi {
                return rigHz &+ Int64(t.offsetKHz) &* 1000
            }
        }
        return rigHz
    }

    /// Real frequency → frequency for the rig (subtracts the offset if it lies in the transverter's shifted band).
    public static func toRig(_ realHz: Int64, _ list: [TransverterEntry]) -> Int64 {
        for t in list {
            let offset = Int64(t.offsetKHz)
            let lo: Int64 = (Int64(t.ifLowKHz) &+ offset) &* 1000
            let hi: Int64 = (Int64(t.ifHighKHz) &+ offset) &* 1000
            if t.enabled && realHz >= lo && realHz <= hi {
                return realHz &- offset &* 1000
            }
        }
        return realHz
    }

    public func read() throws -> RigState {
        let s = try inner.read()
        let list = transverters()
        let tx: Int64 = s.txFreqHz > 0 ? Self.fromRig(s.txFreqHz, list) : 0
        return RigState(freqHz: Self.fromRig(s.freqHz, list), mode: s.mode, rawMode: s.rawMode, passband: s.passband,
                        split: s.split, txFreqHz: tx)
    }

    public func setFrequencyHz(_ freqHz: Int64) throws {
        try inner.setFrequencyHz(Self.toRig(freqHz, transverters()))
    }

    public func setMode(_ mode: Mode?, freqHz: Int64) throws {
        // The sideband is chosen by the real frequency (2 m = USB), not by the IF.
        try inner.setMode(mode, freqHz: freqHz)
    }

    public func setSplit(_ on: Bool, txFreqHz: Int64) throws {
        try inner.setSplit(on, txFreqHz: txFreqHz > 0 ? Self.toRig(txFreqHz, transverters()) : 0)
    }

    public func setOtherVfoFrequencyHz(_ freqHz: Int64) throws {
        try inner.setOtherVfoFrequencyHz(Self.toRig(freqHz, transverters()))
    }

    public var endpoint: RigEndpoint? {
        inner.endpoint
    }

    public func sendRaw(_ command: String) throws -> RigRawReply {
        try inner.sendRaw(command)
    }

    public func setPtt(_ on: Bool) throws {
        try inner.setPtt(on)
    }

    public func sendMorse(_ text: String) throws {
        try inner.sendMorse(text)
    }

    public func stopMorse() throws {
        try inner.stopMorse()
    }

    public func setCwSpeed(_ wpm: Int) throws {
        try inner.setCwSpeed(wpm)
    }

    public func setRit(_ offsetHz: Int) throws {
        try inner.setRit(offsetHz)
    }

    public func setAntenna(_ antenna: Int) throws {
        try inner.setAntenna(antenna)
    }

    public func selectVfo(_ vfoB: Bool) throws {
        try inner.selectVfo(vfoB)
    }

    public func swapVfo() throws {
        try inner.swapVfo()
    }

    public func isConnected() -> Bool {
        inner.isConnected()
    }

    public func close() {
        inner.close()
    }
}
