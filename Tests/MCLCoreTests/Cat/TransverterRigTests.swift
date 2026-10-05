import os
import Testing
@testable import MCLCore

/// Port of `cat/TransverterRigTest` + `XV.fromRig`/`XV.toRig` measurements + decorator behaviour
/// (read from `TransverterRig.java`).
@Suite struct TransverterRigTests {

    private let xv = [TransverterEntry(name: "2m", ifLowKHz: 28_000, ifHighKHz: 30_000, offsetKHz: 116_000, enabled: true)]

    @Test func offsets() {
        #expect(TransverterRig.fromRig(28_300_000, xv) == 144_300_000)
        #expect(TransverterRig.toRig(144_300_000, xv) == 28_300_000)
        #expect(TransverterRig.fromRig(14_025_000, xv) == 14_025_000, "outside the IF unchanged")
        #expect(TransverterRig.toRig(14_025_000, xv) == 14_025_000)
        let off = [TransverterEntry(name: "2m", ifLowKHz: 28_000, ifHighKHz: 30_000, offsetKHz: 116_000, enabled: false)]
        #expect(TransverterRig.fromRig(28_300_000, off) == 28_300_000, "transverter off = 10 m")
    }

    /// Probe list: two transverters on the same IF (the first wins), one off and one on at 2 m IF.
    private static let probeList: [TransverterEntry] = [
        TransverterEntry(name: "2m", ifLowKHz: 28_000, ifHighKHz: 30_000, offsetKHz: 116_000, enabled: true),
        TransverterEntry(name: "70", ifLowKHz: 28_000, ifHighKHz: 30_000, offsetKHz: 404_000, enabled: true),
        TransverterEntry(name: "off", ifLowKHz: 144_000, ifHighKHz: 146_000, offsetKHz: 10_224_000, enabled: false),
        TransverterEntry(name: "3cm", ifLowKHz: 144_000, ifHighKHz: 146_000, offsetKHz: 10_224_000, enabled: true),
    ]

    @Test func measuredFromRig() {
        let cases: [(Int64, Int64)] = [
            (27_999_999, 27_999_999), (28_000_000, 144_000_000), (30_000_000, 146_000_000),
            (30_000_001, 30_000_001), (144_000_000, 10_368_000_000), (145_000_000, 10_369_000_000),
            (0, 0), (-1, -1),
        ]
        for (rig, real) in cases {
            #expect(TransverterRig.fromRig(rig, Self.probeList) == real)
        }
    }

    @Test func measuredToRig() {
        let cases: [(Int64, Int64)] = [
            (144_000_000, 28_000_000), (146_000_000, 30_000_000), (432_000_000, 28_000_000),
            (10_368_100_000, 144_100_000), (14_000_000, 14_000_000), (0, 0),
        ]
        for (real, rig) in cases {
            #expect(TransverterRig.toRig(real, Self.probeList) == rig)
        }
    }

    /// Java computes `kHz * 1000` in `long` and silently overflows — Swift must not crash.
    @Test func overflowWrapsLikeJava() {
        let huge = [TransverterEntry(name: "x", ifLowKHz: Int.max, ifHighKHz: Int.max, offsetKHz: Int.max, enabled: true)]
        // Int64.max * 1000 (mod 2^64) = -1000, so the IF range is [-1000, -1000] and the offset -1000.
        #expect(TransverterRig.fromRig(-1000, huge) == -2000)
        #expect(TransverterRig.fromRig(5, huge) == 5)
        // toRig: (MAX + MAX) * 1000 = -2000 → realHz -2000 → -2000 - (-1000) = -1000.
        #expect(TransverterRig.toRig(-2000, huge) == -1000)
    }

    @Test func decoratorShiftsFrequencies() throws {
        let inner = RecordingRig(state: RigState(freqHz: 28_300_000, mode: .ssb, rawMode: "USB", passband: 2400,
                                                 split: true, txFreqHz: 28_305_000))
        let rig = TransverterRig(inner: inner) { [xv] in xv }
        let state = try rig.read()
        #expect(state == RigState(freqHz: 144_300_000, mode: .ssb, rawMode: "USB", passband: 2400,
                                  split: true, txFreqHz: 144_305_000))
        try rig.setFrequencyHz(144_300_000)
        // setMode sends the real frequency (sideband by 2 m, not by the IF).
        try rig.setMode(.ssb, freqHz: 144_300_000)
        try rig.setSplit(true, txFreqHz: 144_310_000)
        try rig.setSplit(false, txFreqHz: 0)
        try rig.setOtherVfoFrequencyHz(144_200_000)
        try rig.setRit(-100)
        try rig.setAntenna(2)
        try rig.selectVfo(true)
        try rig.swapVfo()
        try rig.setPtt(true)
        try rig.sendMorse("TEST")
        try rig.stopMorse()
        try rig.setCwSpeed(28)
        #expect(rig.isConnected())
        rig.close()
        let expected: [String] = [
            "read", "F 28300000", "M SSB 144300000", "S true 28310000", "S false 0", "O 28200000", "J -100",
            "Y 2", "V true", "X", "T true", "b TEST", "stop", "L 28", "isConnected", "close",
        ]
        #expect(inner.calls == expected)
    }

    @Test func readWithoutTxFrequencyKeepsZero() throws {
        let inner = RecordingRig(state: RigState(freqHz: 29_000_000, mode: nil, rawMode: "PKTAM", passband: 0))
        let rig = TransverterRig(inner: inner) { [xv] in xv }
        #expect(try rig.read() == RigState(freqHz: 145_000_000, mode: nil, rawMode: "PKTAM", passband: 0))
    }

    /// The transverter list is read on every call — a change in Settings applies immediately.
    @Test func transverterListIsReadOnEveryCall() throws {
        let inner = RecordingRig(state: RigState(freqHz: 28_000_000, mode: .cw, rawMode: "CW", passband: 500))
        let enabled = OSAllocatedUnfairLock(initialState: true)
        let rig = TransverterRig(inner: inner) {
            let on = enabled.withLock { $0 }
            return [TransverterEntry(name: "2m", ifLowKHz: 28_000, ifHighKHz: 30_000, offsetKHz: 116_000, enabled: on)]
        }
        #expect(try rig.read().freqHz == 144_000_000)
        enabled.withLock { $0 = false }
        #expect(try rig.read().freqHz == 28_000_000)
    }
}

/// Rig stand-in that records calls (synchronous, like Java `RecordingRig` in the `keyer/` tests).
final class RecordingRig: RigController {

    private let state: RigState
    private let log = OSAllocatedUnfairLock<[String]>(initialState: [])

    init(state: RigState) {
        self.state = state
    }

    var calls: [String] { log.withLock { $0 } }

    private func record(_ call: String) {
        log.withLock { $0.append(call) }
    }

    func read() throws -> RigState {
        record("read")
        return state
    }

    func setFrequencyHz(_ freqHz: Int64) throws { record("F \(freqHz)") }
    func setMode(_ mode: Mode?, freqHz: Int64) throws { record("M \(mode?.rawValue ?? "null") \(freqHz)") }
    func setPtt(_ on: Bool) throws { record("T \(on)") }
    func sendMorse(_ text: String) throws { record("b \(text)") }
    func stopMorse() throws { record("stop") }
    func setCwSpeed(_ wpm: Int) throws { record("L \(wpm)") }
    func setSplit(_ on: Bool, txFreqHz: Int64) throws { record("S \(on) \(txFreqHz)") }
    func setOtherVfoFrequencyHz(_ freqHz: Int64) throws { record("O \(freqHz)") }
    func setRit(_ offsetHz: Int) throws { record("J \(offsetHz)") }
    func setAntenna(_ antenna: Int) throws { record("Y \(antenna)") }
    func selectVfo(_ vfoB: Bool) throws { record("V \(vfoB)") }
    func swapVfo() throws { record("X") }

    func isConnected() -> Bool {
        record("isConnected")
        return true
    }

    func close() { record("close") }
}
