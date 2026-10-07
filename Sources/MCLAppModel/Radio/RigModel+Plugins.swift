import Foundation
import os
import MCLCore

/// What window plugins may do with the rig beyond the entry window's own paths: a raw CAT command (`cat`) and the
/// PTT (`transmit`). The PTT follows the footswitch PTT's rules: refused while the quit closed the transmitter or the
/// keying gate (the pileup simulator, …) refuses; released on Esc, before a user's disconnect, at the quit.
extension RigModel {

    /// Keys (`true`) or releases the active rig's PTT for a plugin; `nil` = done, else why not. Keying mirrors the
    /// voice keyer: a `T 1` that fails is followed by `T 0` at once on the same rig, and if that fails too the rig
    /// stays recorded as keyed (every release path sends `T 0` again). No rig connected: refused.
    public func pluginPtt(_ on: Bool) async -> String? {
        guard on else {
            releasePluginPtt()
            return nil
        }
        if transmitClosed {
            return "the transmitter is closed (quit)"
        }
        if let locked = keyingGate() {
            status.showJoined(locked.parts, separator: "")
            return locked.czech
        }
        let index: Int = vfo.activeCatIndex
        if let keyed = pluginPttRig, keyed != index {
            releasePluginPtt(onRig: keyed)
        }
        // Recorded before the rig answers: a release meanwhile (Esc, the quit) sends `T 0` behind the `T 1`.
        pluginPttRig = index
        let outcome: PluginPttOutcome = await withCheckedContinuation { continuation in
            lanes[index].run({ cat -> PluginPttOutcome in
                guard cat.snapshot.connected, cat.rigOrNull() != nil else { return .noRig }
                do {
                    try cat.setPtt(true)
                    return .keyed
                } catch {
                    let message: String = ErrorText.message(error)
                    return (try? cat.setPtt(false)) != nil ? .failed(message) : .stuck(message)
                }
            }, then: { continuation.resume(returning: $0) })
        }
        switch outcome {
        case .keyed:
            return pluginPttRig == index ? nil : "released meanwhile"
        case .noRig:
            if pluginPttRig == index { pluginPttRig = nil }
            return "no rig connected"
        case .failed(let message):
            if pluginPttRig == index { pluginPttRig = nil }
            return message
        case .stuck(let message):
            // Kept as keyed: Esc, the quit and the disconnect release send `T 0` again.
            status.showVerbatim(message)
            return message
        }
    }

    /// Releases a plugin's PTT; `true` = one was held.
    @discardableResult
    public func releasePluginPtt() -> Bool {
        guard let index = pluginPttRig else { return false }
        releasePluginPtt(onRig: index)
        return true
    }

    /// The operator stopped transmissions (Esc): the plugin model hears it first; queued plugin CAT is dropped.
    public func operatorStopped() {
        pluginCatEpoch.withLock { $0 += 1 }
        onOperatorStop?()
    }

    /// Releases a plugin's PTT on rig `index` — guaranteed: a plugin CAT command in flight on that rig has its
    /// connection closed first (its read ends at once instead of after the timeout), then `T 0` goes out on the rig's
    /// lane; if that fails (or the connection is gone) `T 0` goes over a fresh connection, and if that fails too the
    /// rig is owed `T 0` on its next connection and the operator is told.
    func releasePluginPtt(onRig index: Int) {
        pluginCatEpoch.withLock { $0 += 1 }
        guard pluginPttRig == index else { return }
        pluginPttRig = nil
        let lane: RigLane = lanes[index]
        if pluginCatInFlight.withLock({ $0.contains(index) }) {
            lane.cat.rigOrNull()?.close()
        }
        lane.run({ cat -> Bool in
            guard let rig = cat.rigOrNull(), rig.isConnected() else { return false }
            return (try? rig.setPtt(false)) != nil
        }, then: { [weak self] released in
            if !released {
                self?.releaseOverFreshConnection(index)
            }
        })
        onPluginPttReleased?()
    }

    /// `T 0` over a fresh connection; if that fails, owed on the next connection and shown.
    func releaseOverFreshConnection(_ index: Int) {
        let rc: RigConfig = rigConfig(vfo: index)
        let release: @Sendable (String, Int) -> Bool = freshPttRelease
        pluginPttOwed.insert(index)
        Task { [weak self] in
            let sent: Bool = (try? await BlockingQueue.run { release(rc.host, rc.port) }) ?? false
            guard let self else { return }
            if sent {
                self.pluginPttOwed.remove(index)
            } else {
                self.status.showVerbatim(self.language.tr("PTT pluginu se nepodařilo uvolnit — zkontroluj vysílač!"))
            }
        }
    }

    /// A rig lost its connection while a plugin keyed it: the state is cleared (and the plugin told); `T 0` goes out
    /// first when it is connected again.
    func pluginPttConnectionChanged(_ index: Int, connected: Bool) {
        if !connected, pluginPttRig == index {
            pluginPttRig = nil
            releaseOverFreshConnection(index)
            onPluginPttReleased?()
        } else if connected, pluginPttOwed.remove(index) != nil {
            lanes[index].run { cat in
                try? cat.setPtt(false)
            }
        }
    }

    /// A raw CAT command on the active rig (the caller checked it with `PluginCatPolicy`); the reply comes back on
    /// the main actor. Logged to the CAT log as every command.
    public func sendRawCat(_ command: String, then: @escaping @MainActor @Sendable (Result<RigRawReply, CatRawError>) -> Void) {
        let epochs: OSAllocatedUnfairLock<Int> = pluginCatEpoch
        let queued: Int = epochs.withLock { $0 }
        let index: Int = vfo.activeCatIndex
        let inFlight: OSAllocatedUnfairLock<Set<Int>> = pluginCatInFlight
        lanes[index].run({ cat -> Result<RigRawReply, CatRawError> in
            // A release or stop since it was queued: dropped, the safety `T 0` behind it goes out at once.
            guard epochs.withLock({ $0 }) == queued else {
                return .failure(CatRawError(message: "cancelled by a stop or release"))
            }
            inFlight.withLock { _ = $0.insert(index) }
            defer { inFlight.withLock { _ = $0.remove(index) } }
            // A release that came between the check and the mark closes nothing: check once more.
            guard epochs.withLock({ $0 }) == queued else {
                return .failure(CatRawError(message: "cancelled by a stop or release"))
            }
            guard let rig = cat.rigOrNull() else { return .failure(CatRawError(message: "no rig connected")) }
            do {
                return .success(try rig.sendRaw(command))
            } catch {
                return .failure(CatRawError(message: ErrorText.message(error)))
            }
        }, then: then)
    }
}

enum PluginPttOutcome: Sendable {
    case keyed
    case noRig
    case failed(String)
    case stuck(String)
}

public struct CatRawError: Error, Equatable, Sendable {
    public let message: String
}
