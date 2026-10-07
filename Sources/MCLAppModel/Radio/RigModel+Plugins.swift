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
        if pluginPttUnconfirmed {
            return "an earlier PTT release is not confirmed yet"
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

    /// Releases a plugin's PTT on rig `index` — guaranteed, and without touching the operator's connection: `T 0`
    /// goes out on the rig's lane (behind at most one poll or command of the app) and at the same time over a fresh
    /// connection to the rig's `rigctld`. The release counts as confirmed when either got through; until then the
    /// rig is owed `T 0` (sent again on its next connection), plugins key nothing, and the main window warns.
    func releasePluginPtt(onRig index: Int) {
        pluginCatEpoch.withLock { $0 += 1 }
        guard pluginPttRig == index else { return }
        pluginPttRig = nil
        pluginPttOwed.insert(index)
        lanes[index].run({ cat -> Bool in
            guard let rig = cat.rigOrNull(), rig.isConnected() else { return false }
            return (try? rig.setPtt(false)) != nil
        }, then: { [weak self] released in
            if released {
                self?.pluginPttOwed.remove(index)
            }
        })
        releaseOverFreshConnection(index)
        onPluginPttReleased?()
    }

    /// `T 0` over a fresh connection to the `rigctld` the rig was last connected to (the quit waits for it).
    func releaseOverFreshConnection(_ index: Int) {
        pluginPttOwed.insert(index)
        guard let endpoint = rigEndpoints[index] else { return }
        let release: @Sendable (String, Int) -> Bool = freshPttRelease
        nextRelease += 1
        let id: Int = nextRelease
        pendingReleases[id] = Task { [weak self] in
            let sent: Bool = (try? await BlockingQueue.run { release(endpoint.host, endpoint.port) }) ?? false
            guard let self else { return }
            self.pendingReleases[id] = nil
            if sent {
                self.pluginPttOwed.remove(index)
            }
        }
    }

    /// Plugins may not key while a release is unconfirmed.
    public var pluginPttUnconfirmed: Bool {
        !pluginPttOwed.isEmpty
    }

    /// A rig lost its connection while a plugin keyed it: the state is cleared (and the plugin told) and released
    /// over a fresh connection; on its next connection an owed `T 0` goes out first — confirmed only when it got
    /// through. A connection's endpoint is remembered.
    func pluginPttConnectionChanged(_ index: Int, connected: Bool) {
        if connected, let endpoint = lanes[index].cat.rigOrNull()?.endpoint {
            rigEndpoints[index] = endpoint
        }
        if !connected, pluginPttRig == index {
            pluginPttRig = nil
            releaseOverFreshConnection(index)
            onPluginPttReleased?()
        } else if connected, pluginPttOwed.contains(index) {
            lanes[index].run({ cat -> Bool in
                (try? cat.rigOrNull()?.setPtt(false)) != nil
            }, then: { [weak self] released in
                if released {
                    self?.pluginPttOwed.remove(index)
                }
            })
        }
    }

    /// A raw CAT command for the active rig (the caller checked it with `PluginCatPolicy`), over the plugins' own
    /// connection to the rig's `rigctld` — never the operator's lane, so a stalled plugin command can never delay the
    /// app's own commands or a release. Logged to the CAT log as every command.
    public func sendRawCat(_ command: String, then: @escaping @MainActor @Sendable (Result<RigRawReply, CatRawError>) -> Void) {
        let index: Int = vfo.activeCatIndex
        guard let channel = pluginCat, connected(vfo: index), let endpoint = rigEndpoints[index] else {
            then(.failure(CatRawError(message: "no rig connected")))
            return
        }
        let epochs: OSAllocatedUnfairLock<Int> = pluginCatEpoch
        let queued: Int = epochs.withLock { $0 }
        channel.send(command, to: endpoint, unless: { epochs.withLock { $0 } != queued }, then: then)
    }
}

/// The plugins' own `rigctld` connection: a serial queue of its own and a client per endpoint, made when needed and
/// dropped after any error (a reply is never read half).
final class PluginCatChannel: @unchecked Sendable {
    private let queue = DispatchQueue(label: "cz.ok1xoe.maccontestlogger.plugin.cat")
    private let log: CatTrafficLog
    private var client: RigctldClient?

    init(log: CatTrafficLog) {
        self.log = log
    }

    func send(_ command: String, to endpoint: RigEndpoint, unless cancelled: @escaping @Sendable () -> Bool,
              then: @escaping @MainActor @Sendable (Result<RigRawReply, CatRawError>) -> Void) {
        queue.async { [self] in
            let result: Result<RigRawReply, CatRawError>
            if cancelled() {
                result = .failure(CatRawError(message: "cancelled by a stop or release"))
            } else {
                result = run(command, endpoint)
            }
            MainHop.post { then(result) }
        }
    }

    private func run(_ command: String, _ endpoint: RigEndpoint) -> Result<RigRawReply, CatRawError> {
        if let current = client, current.endpoint != endpoint || !current.isConnected() {
            current.close()
            client = nil
        }
        do {
            let rig: RigctldClient = try client ?? RigctldClient(host: endpoint.host, port: endpoint.port, log: log)
            client = rig
            return .success(try rig.sendRaw(command))
        } catch {
            client?.close()
            client = nil
            return .failure(CatRawError(message: ErrorText.message(error)))
        }
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
