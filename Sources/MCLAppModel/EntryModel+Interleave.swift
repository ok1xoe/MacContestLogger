import Foundation
import MCLCore

/// N1MM 2BSIQ (two band split interleaved QSOs, SO2R): both entry windows run their own QSO at the same time. Each
/// window keeps its own ESM progress, Run/S&P state and last sent keys (`=`), and:
///
/// - typing in one window never interrupts a transmission on the other radio — AutoSend waits while the other radio
///   transmits (the ESM Enter then sends the call as usual);
/// - a CQ repeat ends when a message is sent on the other radio (the operator answered someone there);
/// - which radio transmits when both want to stays with the existing transmit focus and the TX lockouts.
extension EntryModel {

    /// SO2R with both entry windows on screen.
    var interleavedSo2r: Bool {
        guard let rig, rig.vfo.so2r else { return false }
        return rig.otherEntry(than: self) != nil
    }

    /// SO2R: the other radio is transmitting right now (the transmit focus is there and something is being sent).
    var otherRadioSending: Bool {
        guard interleavedSo2r, let rig, rig.vfo.txVfo != vfo else { return false }
        return ports.keyer.isSending || ports.keyer.isTuning
    }

    /// N1MM „CQ-repeat is terminated when a message is sent on the other radio": in SO2R the CQ repeat stays on the
    /// window it was switched on in; a message sent from the other window switches it off.
    func endCqRepeatOfOtherWindow() {
        guard operating.cqRepeat, operating.cqRepeatWindow != vfo, interleavedSo2r else { return }
        operating.applyCqRepeat(false)
        status.show("Opakování CQ ukončeno vysíláním na rádiu %s", .int(vfo + 1))
    }
}
