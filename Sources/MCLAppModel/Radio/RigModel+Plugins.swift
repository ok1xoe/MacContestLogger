import Foundation
import os
import MCLCore

/// What window plugins may do with the rig beyond the entry window's own paths: a raw CAT command (`cat`) and the
/// PTT (`transmit`). The PTT follows the footswitch PTT's rules: refused while the quit closed the transmitter or the
/// keying gate (the pileup simulator, …) refuses; released on Esc, before a user's disconnect, at the quit.
extension RigModel {

    // MARK: - plugin PTT state machine
    //
    // Per rig: idle → keying (a plugin `T 1` in flight) → keyed (`pluginPttRig`) → release requested (epoch raised,
    // `pluginPttOwed`) → confirmed (owed cleared). A release is confirmed only by a `T 0` that went out after every
    // plugin `T 1` issued before it: the lane `T 0` (the lane is first in, first out) or a fresh-connection `T 0`
    // sent while no plugin `T 1` was pending on that rig. A plugin `T 1` that still keys after a release was requested
    // triggers another release at once. While a release is unconfirmed no plugin keys.

    /// Keys (`true`) or releases the active rig's PTT for a plugin; `nil` = done, else why not. Keying mirrors the
    /// voice keyer: a `T 1` that fails is followed by `T 0` at once on the same rig (and the rig counts as owed if
    /// that fails too). No rig connected: refused.
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
            return "the PTT moved to another rig; key again"
        }
        if pluginPttRig == index {
            return nil
        }
        let epochs: OSAllocatedUnfairLock<Int> = pluginKeyEpoch
        let issued: Int = epochs.withLock { $0 }
        pluginKeysInFlight[index, default: 0] += 1
        let outcome: PluginPttOutcome = await withCheckedContinuation { continuation in
            lanes[index].run({ cat -> PluginPttOutcome in
                guard cat.snapshot.connected, let rig = cat.rigOrNull() else { return .noRig }
                do {
                    // The last check right before the socket (with the connection held): a release requested since
                    // the key was asked for drops it.
                    guard try rig.keyPtt(unless: { epochs.withLock { $0 } != issued }) else { return .dropped }
                    return .keyed
                } catch {
                    let message: String = ErrorText.message(error)
                    return (try? rig.setPtt(false)) != nil ? .failed(message) : .stuck(message)
                }
            }, then: { continuation.resume(returning: $0) })
        }
        pluginKeysInFlight[index, default: 1] -= 1
        let stale: Bool = pluginKeyEpoch.withLock { $0 } != issued
        switch outcome {
        case .keyed where stale:
            // Keyed although a release was requested meanwhile: release again at once.
            pluginPttRig = index
            requestRelease(index)
            return "released meanwhile"
        case .keyed:
            pluginPttRig = index
            return nil
        case .dropped:
            return "released meanwhile"
        case .noRig:
            return "no rig connected"
        case .failed(let message):
            return message
        case .stuck(let message):
            // `T 1` and its `T 0` both failed: the rig may transmit — a release is owed.
            pluginPttRig = index
            requestRelease(index)
            return message
        }
    }

    /// Releases a plugin's PTT (and any plugin key on its way); `true` = something was keyed or keying.
    @discardableResult
    public func releasePluginPtt() -> Bool {
        var any = false
        for index in lanes.indices where pluginPttRig == index || pluginKeysInFlight[index, default: 0] > 0 {
            releasePluginPtt(onRig: index)
            any = true
        }
        return any
    }

    /// The operator stopped transmissions (Esc): the plugin model hears it first; queued plugin CAT is dropped.
    public func operatorStopped() {
        pluginCatEpoch.withLock { $0 += 1 }
        onOperatorStop?()
    }

    /// A release of rig `index` (Esc, Stop, the time limit, a revoke, the plugin's end, the quit, a disconnect).
    func releasePluginPtt(onRig index: Int) {
        pluginCatEpoch.withLock { $0 += 1 }
        guard pluginPttRig == index || pluginKeysInFlight[index, default: 0] > 0 || pluginPttOwed.contains(index) else {
            return
        }
        requestRelease(index)
    }

    /// Release requested: a new epoch (keys still queued are dropped), owed until a confirming `T 0`, then `T 0` on
    /// the lane (it confirms when it got through) and over a fresh connection (it confirms only when no plugin key
    /// was pending when it was sent).
    func requestRelease(_ index: Int) {
        pluginKeyEpoch.withLock { $0 += 1 }
        let wasKeyed: Bool = pluginPttRig == index
        if wasKeyed {
            pluginPttRig = nil
        }
        pluginPttOwed.insert(index)
        releaseAttempts[index] = 0
        laneRelease(index)
        releaseOverFreshConnection(index)
        if wasKeyed {
            onPluginPttReleased?()
        }
    }

    /// `T 0` on the lane: it follows every plugin `T 1` queued before it, so success confirms. A failure keeps the
    /// release owed and retries a few times (and again on the next connection).
    private func laneRelease(_ index: Int) {
        let epochs: OSAllocatedUnfairLock<Int> = pluginKeyEpoch
        lanes[index].run({ cat -> Bool in
            guard let rig = cat.rigOrNull(), rig.isConnected() else { return false }
            return (try? rig.setPtt(false)) != nil
        }, then: { [weak self] released in
            guard let self, self.pluginPttOwed.contains(index) else { return }
            _ = epochs
            if released {
                self.confirmRelease(index)
                return
            }
            let attempt: Int = self.releaseAttempts[index, default: 0] + 1
            self.releaseAttempts[index] = attempt
            guard attempt <= self.releaseRetries else { return }
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(attempt) * 500_000_000)
                guard let self, self.pluginPttOwed.contains(index) else { return }
                self.laneRelease(index)
            }
        })
    }

    private func confirmRelease(_ index: Int) {
        guard pluginPttRig != index else { return }
        pluginPttOwed.remove(index)
        releaseAttempts[index] = nil
    }

    /// `T 0` over a fresh connection to the `rigctld` the rig was last connected to (the quit waits for it). It
    /// confirms the release only when no plugin `T 1` was pending on the rig when it was sent.
    func releaseOverFreshConnection(_ index: Int) {
        pluginPttOwed.insert(index)
        guard let endpoint = rigEndpoints[index] else { return }
        let release: @Sendable (String, Int) -> Bool = freshPttRelease
        let clean: Bool = pluginKeysInFlight[index, default: 0] == 0
        nextRelease += 1
        let id: Int = nextRelease
        pendingReleases[id] = Task { [weak self] in
            let sent: Bool = (try? await BlockingQueue.run { release(endpoint.host, endpoint.port) }) ?? false
            guard let self else { return }
            self.pendingReleases[id] = nil
            if sent && clean {
                self.confirmRelease(index)
            }
        }
    }

    /// Plugins may not key while a release is unconfirmed.
    public var pluginPttUnconfirmed: Bool {
        !pluginPttOwed.isEmpty
    }

    /// A rig lost its connection while a plugin keyed it (or a release is owed): released over a fresh connection;
    /// on its next connection an owed `T 0` goes out first on the lane. A connection's endpoint is remembered.
    func pluginPttConnectionChanged(_ index: Int, connected: Bool) {
        if connected, let endpoint = lanes[index].cat.rigOrNull()?.endpoint {
            rigEndpoints[index] = endpoint
        }
        if !connected {
            pluginCat?.close()
            if pluginPttRig == index || pluginKeysInFlight[index, default: 0] > 0 {
                requestRelease(index)
            }
        } else if pluginPttOwed.contains(index) {
            releaseAttempts[index] = 0
            laneRelease(index)
        }
    }

    /// A raw CAT command for the active rig (the caller checked it with `PluginCatPolicy`), over the plugins' own
    /// connection to the rig's `rigctld` — never the operator's lane, so a stalled plugin command can never delay the
    /// app's own commands or a release. Logged to the CAT log as every command.
    public func sendRawCat(_ command: String, since admitted: Int? = nil,
                           then: @escaping @MainActor @Sendable (Result<RigRawReply, CatRawError>) -> Void) {
        let index: Int = vfo.activeCatIndex
        guard let channel = pluginCat, connected(vfo: index), let endpoint = rigEndpoints[index] else {
            then(.failure(CatRawError(message: "no rig connected")))
            return
        }
        let epochs: OSAllocatedUnfairLock<Int> = pluginCatEpoch
        let queued: Int = admitted ?? epochs.withLock { $0 }
        channel.send(command, to: endpoint, unless: { epochs.withLock { $0 } != queued }, then: then)
    }
}

/// The plugins' own `rigctld` connection: a serial queue of its own and a client per endpoint, made when needed,
/// dropped after any error (a reply is never read half) and closed when no plugin needs it (`close`). At most
/// `maxPending` commands wait or run at a time; more are refused (`busy`).
final class PluginCatChannel: @unchecked Sendable {
    static let maxPending = 16

    private let queue = DispatchQueue(label: "cz.ok1xoe.maccontestlogger.plugin.cat")
    private let log: CatTrafficLog
    private var client: RigctldClient?
    private let pending = OSAllocatedUnfairLock(initialState: 0)

    init(log: CatTrafficLog) {
        self.log = log
    }

    /// Commands waiting or running.
    var pendingCount: Int {
        pending.withLock { $0 }
    }

    /// Whether a plugin connection is open (tests).
    var isOpen: Bool {
        queue.sync { client != nil }
    }

    func send(_ command: String, to endpoint: RigEndpoint, unless cancelled: @escaping @Sendable () -> Bool,
              then: @escaping @MainActor @Sendable (Result<RigRawReply, CatRawError>) -> Void) {
        let admitted: Bool = pending.withLock { count in
            guard count < Self.maxPending else { return false }
            count += 1
            return true
        }
        guard admitted else {
            MainHop.post { then(.failure(CatRawError(message: "busy: too many plugin CAT commands waiting"))) }
            return
        }
        queue.async { [self] in
            let result: Result<RigRawReply, CatRawError>
            // A stop, release, revoke or the plugin's end since it was queued: dropped before it is written.
            if cancelled() {
                result = .failure(CatRawError(message: "cancelled by a stop or release"))
            } else {
                result = run(command, endpoint)
            }
            pending.withLock { $0 -= 1 }
            MainHop.post { then(result) }
        }
    }

    /// Closes the connection after what is running (reopened on the next command).
    func close() {
        queue.async { [self] in
            client?.close()
            client = nil
        }
    }

    private func run(_ command: String, _ endpoint: RigEndpoint) -> Result<RigRawReply, CatRawError> {
        if let current = client, current.endpoint != endpoint || !current.isConnected() {
            current.close()
            client = nil
        }
        do {
            let rig: RigctldClient = try client ?? RigctldClient(host: endpoint.host, port: endpoint.port, timeoutMs: 1000, log: log)
            client = rig
            return .success(try rig.sendRaw(command))
        } catch {
            client?.close()
            client = nil
            return .failure(CatRawError(message: ErrorText.message(error)))
        }
    }
}

extension RigModel {
    /// A plugin lost `cat` or stopped, or the quit: queued plugin commands are dropped; with `close` (no plugin needs
    /// raw CAT any more) the plugin connection closes too.
    public func pluginCatIdle(close: Bool = true) {
        pluginCatEpoch.withLock { $0 += 1 }
        if close {
            pluginCat?.close()
        }
    }
}

enum PluginPttOutcome: Sendable {
    case keyed
    case dropped
    case noRig
    case failed(String)
    case stuck(String)
}

public struct CatRawError: Error, Equatable, Sendable {
    public let message: String
}
