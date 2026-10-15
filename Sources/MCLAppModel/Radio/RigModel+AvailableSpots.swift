import Foundation
import MCLCore

/// The Available window's two-radio actions (N1MM Available with SO2V / SO2R): a spot on the other radio's band takes
/// the focus there before tuning (focus follows spot), and the row menu QSYs the other radio or VFO without moving the
/// focus. Only frequencies change — nothing transmits.
extension RigModel {

    /// The VFO / radio that is not active (SO2V, SO2R); `nil` with one entry window.
    public var otherVfoIndex: Int? {
        vfo.twoEntryWindows ? 1 - vfo.activeVfo : nil
    }

    /// The frequency of the other radio or VFO: in SO2R its rig's reported one, otherwise (or before a report) the
    /// frequency it had when it was left; `nil` when unknown.
    public var otherVfoFreqHz: Int64? {
        guard let other = otherVfoIndex else { return nil }
        if vfo.so2r, let state = snapshot(vfo: other).state, state.freqHz > 0 {
            return state.freqHz
        }
        let hz: Int64 = vfo.vfoFreq[other]
        return hz > 0 ? hz : nil
    }

    /// N1MM focus follows spot: a spot on the band of the other radio (and not on the active one's) activates that
    /// radio and moves the focus to its entry window. `true` = the focus moved.
    @discardableResult
    public func focusRadio(forSpotHz freqHz: Int) -> Bool {
        guard let other = otherVfoIndex, let otherHz = otherVfoFreqHz,
              let spotBand = Band.from(frequencyHz: freqHz),
              Band.from(frequencyHz: Int(clamping: otherHz)) == spotBand, currentBand != spotBand else { return false }
        requestFocusVfo(other)
        return true
    }

    /// N1MM's right click in the Available window: the other radio (SO2R) or VFO (SO2V) goes to `freqHz`, the focus
    /// stays. SO2V uses the rig's other VFO (`setOtherVfo`); SO2R tunes the other rig's own session.
    public func qsyOtherRadio(_ freqHz: Int64) {
        guard let other = otherVfoIndex, freqHz > 0 else {
            show(.tr("QSY druhého rádia: jen v režimu SO2V nebo SO2R"))
            return
        }
        vfo.setInactiveFrequency(freqHz, vfo: other)
        guard vfo.so2r else {
            setOtherVfo(freqHz)
            return
        }
        let rig: Int = vfo.catIndex(for: other)
        guard snapshot(vfo: other).connected else {
            show(.tr("Rig %s: připoj TRX (CAT)", .int(rig + 1)))
            return
        }
        lanes[rig].run { cat in
            try? cat.tune(freqHz)
        }
        show(.tr("Rig %s: %s", .int(rig + 1), .string(CatStatusLine.khz(freqHz))))
    }
}
