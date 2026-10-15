import Foundation
import MCLCore

/// N1MM band map „Transceiver timeout" and „Radio Problem" / „Reset Radio": a rig whose connection was lost (a
/// failed poll, not a disconnect by the user) and that has had no contact for `RigConfig.timeoutSeconds` gets an
/// alert in the band map; „Reset Radio" connects it again. A timeout of 0 turns the alert off.
extension RigModel {

    /// The configuration rig `index` connects with (0 = `config.rig`, 1 = `config.rig2`).
    func rigConfig(index: Int) -> RigConfig {
        index == 1 ? config.config.rig2 : config.config.rig
    }

    /// Every snapshot of rig `index`: a state is a contact, a connection clears the alert, a lost connection
    /// schedules the check.
    func radioContact(_ index: Int, _ snapshot: CatSession.Snapshot) {
        let now: Date = clock()
        if snapshot.state != nil {
            lastContact[index] = now
        }
        if snapshot.connected || !snapshot.lost {
            problemChecks.removeValue(forKey: index)?.cancel()
            radioProblems.remove(index)
            return
        }
        guard problemChecks[index] == nil else { return }
        let since: Date = lastContact[index] ?? now
        lastContact[index] = since
        guard let wait = RadioProblemAlert.delay(timeoutSeconds: rigConfig(index: index).timeoutSeconds,
                                                 lastContact: since, now: now) else { return }
        problemChecks[index] = Task { @MainActor [weak self] in
            if wait > 0 {
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            self?.checkRadioProblem(index)
        }
    }

    /// Shows the alert of rig `index` when it is due (the scheduled check; tests call it with their clock).
    func checkRadioProblem(_ index: Int) {
        problemChecks[index] = nil
        let snapshot: CatSession.Snapshot = index == 1 ? cat2 : cat1
        guard let since = lastContact[index] else { return }
        if RadioProblemAlert.isDue(lost: snapshot.lost, connected: snapshot.connected,
                                   timeoutSeconds: rigConfig(index: index).timeoutSeconds, lastContact: since,
                                   now: clock()) {
            radioProblems.insert(index)
        }
    }

    /// „Reset Radio": every rig with the alert connects again with its configuration; the alert goes.
    public func resetRadios() {
        let rigs: [Int] = radioProblems.sorted()
        radioProblems = []
        for index in rigs where index < lanes.count {
            let rc: RigConfig = rigConfig(index: index)
            lanes[index].run { cat in
                if cat.isConnecting {
                    cat.disconnectCancellingConnect(nil)
                }
                cat.connect(rc)
            }
        }
    }

    /// The alert closed without a reset (the band map's ×).
    public func dismissRadioProblem() {
        radioProblems = []
    }
}
