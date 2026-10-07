import Foundation
import os
import MCLCore

/// What window plugins may do with the rig beyond the entry window's own paths: a raw CAT command (`cat`) and the
/// PTT (`transmit`). The PTT follows the footswitch PTT's rules: refused while the quit closed the transmitter or the
/// keying gate (the pileup simulator, …) refuses; released on Esc, before a user's disconnect, at the quit.
extension RigModel {

    // MARK: - plugin PTT state machine
    //
    // Per rig: idle → keying (a plugin `T 1` in flight) → keyed (`pluginPttRig`) → release requested (the rig's
    // release epoch raised, `pluginPttOwed`) → confirmed (owed cleared).
    // - A plugin `T 1` carries its rig's epoch and is dropped right before it is written (the connection held) when
    //   a release was requested since; one that keyed anyway triggers another release at once.
    // - Every `T 0` carries the epoch it was sent for and confirms only that epoch while it is still the rig's
    //   current one: the lane `T 0` (the lane is first in, first out, so it follows every earlier plugin `T 1`), or a
    //   fresh-connection `T 0` sent while no plugin `T 1` was pending on the rig.
    // - While the operator's own transmission (footswitch, voice, CW, tune) runs on the rig, the plugin's `T 0` waits
    //   (it would cut the operator; the operator owns the PTT) and goes out when that transmission ended.
    // - A refused `T 0` is retried after 0.5, 1, 1.5 s, then every 10 s while the rig is connected, and on its next
    //   connection; after the quick retries the warning offers „Uvolnit znovu".
    // While a release of any rig is unconfirmed no plugin keys.

    /// The rig's current release epoch.
    func pluginKeyEpoch(_ index: Int) -> Int {
        pluginKeyEpochs.withLock { $0[index, default: 0] }
    }

    /// Keys (`true`) or releases the active rig's PTT for a plugin; `nil` = done, else why not. A `T 1` the rig's
    /// `rigctld` refuses (`RPRT -n`) keyed nothing and is only reported; one whose outcome is unknown (a timeout, a
    /// lost connection) is followed by `T 0` at once, and the rig counts as owed if that fails too. No rig connected:
    /// refused.
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
        let epochs: OSAllocatedUnfairLock<[Int: Int]> = pluginKeyEpochs
        let issued: Int = pluginKeyEpoch(index)
        pluginKeysInFlight[index, default: 0] += 1
        let outcome: PluginPttOutcome = await withCheckedContinuation { continuation in
            lanes[index].run({ cat -> PluginPttOutcome in
                guard cat.snapshot.connected, let rig = cat.rigOrNull() else { return .noRig }
                do {
                    // The last check right before the socket (with the connection held): a release of this rig
                    // requested since the key was asked for drops it.
                    guard try rig.keyPtt(unless: { epochs.withLock { $0[index, default: 0] } != issued }) else {
                        return .dropped
                    }
                    return .keyed
                } catch let refusal as CatRefusal {
                    return .refused(refusal.message)
                } catch {
                    let message: String = ErrorText.message(error)
                    return (try? rig.setPtt(false)) != nil ? .failed(message) : .stuck(message)
                }
            }, then: { continuation.resume(returning: $0) })
        }
        pluginKeysInFlight[index, default: 1] -= 1
        let stale: Bool = pluginKeyEpoch(index) != issued
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
        case .refused(let message):
            return "the rig refused the PTT, nothing was keyed: " + message
        case .failed(let message):
            return message
        case .stuck(let message):
            // The outcome of `T 1` is unknown and its `T 0` failed: the rig may transmit — a release is owed.
            pluginPttRig = index
            requestRelease(index)
            return message
        }
    }

    /// Releases a plugin's PTT (and any plugin key on its way); `true` = something was keyed or keying.
    /// `stoppingEverything` (Esc, Stop): the operator's own transmission stops too, so the release never waits for it.
    @discardableResult
    public func releasePluginPtt(stoppingEverything: Bool = false) -> Bool {
        var any = false
        for index in lanes.indices where pluginPttRig == index || pluginKeysInFlight[index, default: 0] > 0 {
            releasePluginPtt(onRig: index, waitForOperator: !stoppingEverything)
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
    func releasePluginPtt(onRig index: Int, waitForOperator: Bool = false) {
        pluginCatEpoch.withLock { $0 += 1 }
        guard pluginPttRig == index || pluginKeysInFlight[index, default: 0] > 0 || pluginPttOwed.contains(index) else {
            return
        }
        requestRelease(index, waitForOperator: waitForOperator)
    }

    /// Release requested: a new epoch of this rig (its plugin keys still queued are dropped), owed until a `T 0` of
    /// this epoch confirms, then `T 0` on the lane and over a fresh connection — or, while the operator transmits on
    /// the rig, once that transmission ended.
    func requestRelease(_ index: Int, waitForOperator: Bool = true) {
        pluginKeyEpochs.withLock { $0[index, default: 0] += 1 }
        let wasKeyed: Bool = pluginPttRig == index
        if wasKeyed {
            pluginPttRig = nil
        }
        pluginPttOwed.insert(index)
        releaseAttempts[index] = 0
        if waitForOperator && !transmitClosed && operatorTransmitting(index) {
            pluginReleaseDeferred.insert(index)
        } else {
            pluginReleaseDeferred.remove(index)
            sendRelease(index)
        }
        if wasKeyed {
            onPluginPttReleased?()
        }
    }

    /// `T 0` on the lane and over a fresh connection, both for the rig's current epoch.
    func sendRelease(_ index: Int) {
        let epoch: Int = pluginKeyEpoch(index)
        laneRelease(index, epoch: epoch)
        releaseOverFreshConnection(index, epoch: epoch)
    }

    /// `T 0` on the lane: it follows every plugin `T 1` queued before it, so success confirms its epoch. A failure
    /// keeps the release owed and retries.
    private func laneRelease(_ index: Int, epoch: Int) {
        lanes[index].run({ cat -> Bool in
            guard let rig = cat.rigOrNull(), rig.isConnected() else { return false }
            return (try? rig.setPtt(false)) != nil
        }, then: { [weak self] released in
            guard let self, self.pluginPttOwed.contains(index) else { return }
            if released {
                self.confirmRelease(index, epoch: epoch)
            } else {
                self.releaseFailed(index)
            }
        })
    }

    /// A refused or impossible lane `T 0`: retried after 0.5, 1, 1.5 s, then every `releaseSlowRetryMs` while the
    /// rig is connected (and on its next connection); after the quick retries the warning offers a manual release.
    private func releaseFailed(_ index: Int) {
        let attempt: Int = releaseAttempts[index, default: 0] + 1
        releaseAttempts[index] = attempt
        if attempt > releaseRetries {
            pluginPttCannotConfirm.insert(index)
        }
        guard !releaseRetryScheduled.contains(index) else { return }
        let delayMs: Int = attempt <= releaseRetries ? attempt * 500 : releaseSlowRetryMs
        releaseRetryScheduled.insert(index)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
            guard let self else { return }
            self.releaseRetryScheduled.remove(index)
            guard self.pluginPttOwed.contains(index), !self.pluginReleaseDeferred.contains(index),
                  self.connected(vfo: index) else { return }
            self.sendRelease(index)
        }
    }

    /// „Uvolnit znovu": every unconfirmed release goes out again at once.
    public func retryPluginRelease() {
        for index in pluginPttOwed.sorted() where !pluginReleaseDeferred.contains(index) {
            releaseAttempts[index] = 0
            pluginPttCannotConfirm.remove(index)
            sendRelease(index)
        }
    }

    /// A `T 0` sent for `epoch` got through: it confirms only that epoch while it is still the rig's current one.
    private func confirmRelease(_ index: Int, epoch: Int) {
        guard pluginPttRig != index, pluginKeyEpoch(index) == epoch else { return }
        pluginPttOwed.remove(index)
        pluginPttCannotConfirm.remove(index)
        pluginReleaseDeferred.remove(index)
        releaseAttempts[index] = nil
    }

    /// `T 0` over a fresh connection to the `rigctld` the rig was last connected to (the quit waits for it). It
    /// confirms its epoch only when no plugin `T 1` was pending on the rig when it was sent.
    func releaseOverFreshConnection(_ index: Int, epoch: Int) {
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
                self.confirmRelease(index, epoch: epoch)
            }
        }
    }

    /// Plugins may not key while a release is unconfirmed.
    public var pluginPttUnconfirmed: Bool {
        !pluginPttOwed.isEmpty
    }

    /// Every snapshot of rig `index`. On a connected → disconnected transition: the plugin CAT connection closes and
    /// a plugin key (keyed or on its way) is released. On a disconnected → connected transition: an owed `T 0` goes
    /// out first. A release waiting for the operator's transmission goes out once that ended. A connection's
    /// endpoint is remembered.
    func pluginPttConnectionChanged(_ index: Int, connected: Bool) {
        if connected, let endpoint = lanes[index].cat.rigOrNull()?.endpoint {
            rigEndpoints[index] = endpoint
        }
        let was: Bool = rigConnected[index] ?? false
        rigConnected[index] = connected
        if was && !connected {
            pluginCat?.close()
            if pluginPttRig == index || pluginKeysInFlight[index, default: 0] > 0 {
                requestRelease(index, waitForOperator: false)
            }
        } else if !was && connected && pluginPttOwed.contains(index) && !pluginReleaseDeferred.contains(index) {
            releaseAttempts[index] = 0
            sendRelease(index)
        }
        operatorTransmissionMayHaveEnded(index)
    }

    /// A plugin release that waited for the operator's own transmission on rig `index` goes out once it ended.
    func operatorTransmissionMayHaveEnded(_ index: Int) {
        guard pluginReleaseDeferred.contains(index), transmitClosed || !operatorTransmitting(index) else { return }
        pluginReleaseDeferred.remove(index)
        sendRelease(index)
    }

    /// Whether the operator's own transmission (footswitch, voice, CW, tune) runs on rig `index`.
    func operatorTransmitting(_ index: Int) -> Bool {
        footswitchPttRig == index || operatorKeying(index)
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
    /// How long a plugin command waits for its reply (a test seam: slow CI runners hold replies on purpose).
    private let replyTimeoutMs = OSAllocatedUnfairLock(initialState: 1_000)

    func setReplyTimeout(ms: Int) {
        replyTimeoutMs.withLock { $0 = ms }
    }

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
            let rig: RigctldClient = try client ?? RigctldClient(host: endpoint.host, port: endpoint.port, timeoutMs: replyTimeoutMs.withLock { $0 }, log: log)
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
    case refused(String)
    case noRig
    case failed(String)
    case stuck(String)
}

public struct CatRawError: Error, Equatable, Sendable {
    public let message: String
}
