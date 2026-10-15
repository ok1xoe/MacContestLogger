import Foundation
import MCLCore

/// The sub receiver (dual watch) of a rig with two receivers (N1MM Alt+F12 „Dual Receive toggle" and Ctrl+Alt+D in
/// SO2V): hamlib `U DUAL_WATCH 1` / `0`. Only rigs whose hamlib driver knows DUAL_WATCH follow it; nothing transmits.
extension RigModel {

    /// The sub receiver of the active rig as last set here (before that: its „Sub receiver always on" option).
    public var subReceiverOn: Bool {
        let index: Int = vfo.activeCatIndex
        return subReceiver[index] ?? rigConfig(vfo: vfo.activeVfo).subReceiverOn
    }

    /// N1MM Alt+F12 on a rig with a sub receiver (its „Sub receiver always on" option set): the dual watch on / off.
    /// Other rigs keep Alt+F12 as the copy of the frequency into VFO B.
    public var altF12TogglesSubReceiver: Bool {
        rigConfig(vfo: vfo.activeVfo).subReceiverOn
    }

    /// The sub receiver of the active rig on, off or toggled (`nil`).
    public func setSubReceiver(_ on: Bool?) {
        guard active.connected else {
            show(RigTexts.vfoNeedsCat(RigTexts.subReceiverLabel))
            return
        }
        let index: Int = vfo.activeCatIndex
        let next: Bool = on ?? !subReceiverOn
        subReceiver[index] = next
        lanes[index].run({ cat -> RigOutcome in
            RigOutcome.run(cat) { rig in
                let reply: RigRawReply = try rig.sendRaw(CatSession.dualWatchCommand.dropLast() + (next ? "1" : "0"))
                if reply.code < 0 {
                    throw CatException("RPRT " + String(reply.code))
                }
            }
        }, then: { [weak self] outcome in
            switch outcome {
            case .done:
                self?.show(next ? .tr("Druhý přijímač zapnut (dual watch)") : .tr("Druhý přijímač vypnut"))
            case .noRig:
                self?.show(RigTexts.vfoNeedsCat(RigTexts.subReceiverLabel))
            case .failed(let message):
                self?.show(RigTexts.vfoFailure(RigTexts.subReceiverLabel, message))
            }
        })
    }
}
