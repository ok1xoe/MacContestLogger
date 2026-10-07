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

    func releasePluginPtt(onRig index: Int) {
        pluginCatEpoch.withLock { $0 += 1 }
        guard pluginPttRig == index else { return }
        pluginPttRig = nil
        lanes[index].run { cat in
            try? cat.setPtt(false)
        }
        onPluginPttReleased?()
    }

    /// A rig lost its connection while a plugin keyed it: the state is cleared (and the plugin told); `T 0` goes out
    /// first when it is connected again.
    func pluginPttConnectionChanged(_ index: Int, connected: Bool) {
        if !connected, pluginPttRig == index {
            pluginPttRig = nil
            pluginPttOwed.insert(index)
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
        activeLane.run({ cat -> Result<RigRawReply, CatRawError> in
            // A release or stop since it was queued: dropped, the safety `T 0` behind it goes out at once.
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
