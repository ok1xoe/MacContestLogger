import Foundation
import MCLCore

/// The rig half of the entry window's actions over the app's `RigModel` (in place of `NoRig`).
struct LiveRig: RigPort {
    weak var model: RigModel?

    func qsy(hz: Int64) {
        model?.qsy(hz)
    }

    func setMode(_ mode: Mode, freqHz: Int64) {
        model?.setMode(mode, freqHz: freqHz)
    }

    func clearRit() -> EntryStatus? {
        model?.clearRit()
        return nil
    }

    func splitOff() -> EntryStatus? {
        model?.splitOff()
        return nil
    }
}
