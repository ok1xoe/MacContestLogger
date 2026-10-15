import Foundation
import MCLCore

/// N1MM's „Non-Active Radio" keys (SO2V / SO2R): the other radio or VFO jumps to spots, changes band and returns to
/// its CQ frequency while the focus stays here, and the software band lockout between the two radios. Only
/// frequencies change — nothing transmits.
extension RigModel {

    /// The entry window of VFO / radio `index` while it is on screen.
    func entry(vfo index: Int) -> EntryModel? {
        var found: EntryModel?
        notifyEntries { entry in
            if found == nil && entry.vfo == index && entry.isWindowShown {
                found = entry
            }
        }
        return found
    }

    /// The band of the other radio / VFO (its reported or remembered frequency), `nil` without two windows.
    public var otherRadioBand: Band? {
        guard let hz = otherVfoFreqHz else { return nil }
        return Band.from(frequencyHz: Int(clamping: hz))
    }

    /// N1MM: in SO2R Ctrl+PgUp/PgDn skips the band the other radio is on (a software band lockout — no substitute
    /// for a hardware one). `allowed` without the other radio's band.
    func lockedOut(_ allowed: [Band], otherBand: Band?) -> [Band] {
        guard vfo.so2r, let otherBand else { return allowed }
        return allowed.filter { $0 != otherBand }
    }

    /// The other radio / VFO to a spot (N1MM Ctrl+Shift+↑/↓, Shift+click in the band map): its frequency, its window's
    /// call and predicted exchange (as a call from a spot); the focus stays.
    public func tuneOtherToSpot(_ spot: DxSpot) {
        guard otherVfoIndex != nil else {
            show(.tr("QSY druhého rádia: jen v režimu SO2V nebo SO2R"))
            return
        }
        qsyOtherRadio(Int64(spot.freqHz))
        guard let other = otherVfoIndex, let target = entry(vfo: other) else { return }
        target.selfSpot.prefilledFromSpot()
        target.setCallText(spot.dxCall)
        target.prefillExchange(spotSources.predictExchange(spot))
    }

    /// The other window's frequency field follows a QSY of its radio / VFO made from here.
    func showOtherFrequency(_ freqHz: Int64) {
        guard let other = otherVfoIndex, let target = entry(vfo: other) else { return }
        target.showInactiveFrequency(CatStatusLine.fieldText(freqHz))
    }
}
