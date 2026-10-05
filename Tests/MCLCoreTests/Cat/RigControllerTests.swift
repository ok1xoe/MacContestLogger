import Testing
@testable import MCLCore

/// Default methods of `RigController` and `RigState` — measurements `RC.*` and `RS.*` (maintainer-only probe,
/// `…/research/`). There are no Java tests for them (newly written).
@Suite struct RigControllerTests {

    /// A rig with only the required methods — the others throw like the Java `default` methods of the interface.
    final class BareRig: RigController {
        func read() throws -> RigState { RigState(freqHz: 0, mode: nil, rawMode: "", passband: 0) }
        func setFrequencyHz(_ freqHz: Int64) throws {}
        func setMode(_ mode: Mode?, freqHz: Int64) throws {}
        func setPtt(_ on: Bool) throws {}
        func sendMorse(_ text: String) throws {}
        func stopMorse() throws {}
        func setCwSpeed(_ wpm: Int) throws {}
        func isConnected() -> Bool { true }
        func close() {}
    }

    private static func message(_ body: () throws -> Void) -> String {
        do {
            try body()
            return "ok"
        } catch let error as CatException {
            return "CatException: " + error.message
        } catch {
            return "jiná chyba"
        }
    }

    @Test func measuredDefaultMethodsThrow() {
        let rig: any RigController = BareRig()
        #expect(Self.message { try rig.setSplit(true, txFreqHz: 1) } == "CatException: Rig split nepodporuje")
        #expect(Self.message { try rig.setOtherVfoFrequencyHz(1) }
            == "CatException: Rig nastaven\u{00ED} druh\u{00E9}ho VFO nepodporuje")
        #expect(Self.message { try rig.setRit(0) } == "CatException: Rig RIT nepodporuje")
        #expect(Self.message { try rig.setAntenna(1) }
            == "CatException: Rig p\u{0159}ep\u{00ED}n\u{00E1}n\u{00ED} ant\u{00E9}n nepodporuje")
        #expect(Self.message { try rig.selectVfo(true) } == "CatException: Rig v\u{00FD}b\u{011B}r VFO nepodporuje")
        #expect(Self.message { try rig.swapVfo() } == "CatException: Rig prohozen\u{00ED} VFO nepodporuje")
    }

    /// `RC.transverter`: `TransverterRig` delegates the default methods too — an exception of the inner rig passes through unchanged.
    @Test func measuredTransverterPassesDefaultErrors() {
        let rig = TransverterRig(inner: BareRig()) { [] }
        #expect(Self.message { try rig.setRit(0) } == "CatException: Rig RIT nepodporuje")
        #expect(Self.message { try rig.setSplit(false, txFreqHz: 0) } == "CatException: Rig split nepodporuje")
    }

    /// `RS.state`/`RS.freqKHz`: the four-parameter constructor = without split, `freqKHz` is `freqHz / 1000.0`.
    @Test func measuredRigState() {
        let state = RigState(freqHz: 14_025_050, mode: .cw, rawMode: "CW", passband: 0)
        #expect(!state.split)
        #expect(state.txFreqHz == 0)
        #expect(state.freqKHz == 14025.05)
        #expect(RigState(freqHz: -1, mode: nil, rawMode: "", passband: 0).freqKHz == -0.001)
        #expect(RigState(freqHz: Int64.max, mode: nil, rawMode: "", passband: 0).freqKHz == 9.223372036854776e15)
    }

    @Test func catExceptionCarriesCause() {
        struct Timeout: Error {}
        let plain = CatException("Rig split nepodporuje")
        #expect(plain.message == "Rig split nepodporuje")
        #expect(plain.cause == nil)
        let wrapped = CatException("Chyba čtení odpovědi z rigctld", cause: Timeout())
        #expect(wrapped.cause is Timeout)
        #expect(wrapped.description == "Chyba čtení odpovědi z rigctld")
    }
}
