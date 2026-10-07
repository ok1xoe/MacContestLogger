import Foundation
import MCLCore

/// What window plugins may do with the rig beyond the entry window's own paths: a raw CAT command (`cat`) and the
/// PTT (`transmit`). The PTT follows the footswitch PTT's rules: refused while the quit closed the transmitter or the
/// keying gate (the pileup simulator, …) refuses; released on Esc, before a user's disconnect, at the quit.
extension RigModel {

    /// Keys (`true`) or releases the active rig's PTT for a plugin; `nil` = done, else why not.
    public func pluginPtt(_ on: Bool) -> String? {
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
        pluginPttRig = index
        lanes[index].run { cat in
            try? cat.setPtt(true)
        }
        return nil
    }

    /// Releases a plugin's PTT; `true` = one was held.
    @discardableResult
    public func releasePluginPtt() -> Bool {
        guard let index = pluginPttRig else { return false }
        releasePluginPtt(onRig: index)
        return true
    }

    func releasePluginPtt(onRig index: Int) {
        guard pluginPttRig == index else { return }
        pluginPttRig = nil
        lanes[index].run { cat in
            try? cat.setPtt(false)
        }
    }

    /// A raw CAT command on the active rig (the caller checked it with `PluginCatPolicy`); the reply comes back on
    /// the main actor. Logged to the CAT log as every command.
    public func sendRawCat(_ command: String, then: @escaping @MainActor @Sendable (Result<RigRawReply, CatRawError>) -> Void) {
        activeLane.run({ cat -> Result<RigRawReply, CatRawError> in
            guard let rig = cat.rigOrNull() else { return .failure(CatRawError(message: "no rig connected")) }
            do {
                return .success(try rig.sendRaw(command))
            } catch {
                return .failure(CatRawError(message: ErrorText.message(error)))
            }
        }, then: then)
    }
}

public struct CatRawError: Error, Equatable, Sendable {
    public let message: String
}
