import Foundation
import MCLCore
import Observation
import os

/// The plugins of v1.1.1 (`AppState.firePlugins`, `AS:1927-1954`): executables in `plugins/<event>/` run on the events
/// `QSO_LOGGED` (a QSO logged here, never an import), `CONTEST_OPENED` (an opening activation, not a reopen after a
/// reload) and `SPOT_RECEIVED` (a spot of the own DX cluster, from its reader thread). Every run is one job on the
/// plugin lane (the process blocks up to its 10 s limit); the output comes back to the program messages as
/// `[plugin] line` and `tr("[%s] skončil s kódem %s")`.
///
/// The runner is absent (nothing fires) under `MCL_INERT_NETWORK` and `MCL_INERT_HARDWARE`: plugins run local
/// executables. A spot flood never queues without bound: past `maxPendingSpots` waiting runs a spot is
/// dropped.
@Observable @MainActor
public final class PluginsModel {

    /// Kotlin `PluginRunner(pluginsDir(), 10_000)`.
    public static let timeoutMs: Int64 = 10_000
    /// Spot events waiting for the lane beyond which further spots are dropped.
    nonisolated static let maxPendingSpots = 100

    @ObservationIgnored private let messages: MessagesModel
    @ObservationIgnored private let language: LanguageModel
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let runner: (any PluginRunning)?
    @ObservationIgnored private let lane = PluginLane(name: "plugins")
    @ObservationIgnored private let pendingSpots = OSAllocatedUnfairLock(initialState: 0)
    /// The end of the quit's wait (set by `drain`): later plugins are not started, the running one is cut short.
    @ObservationIgnored private let quitDeadline = OSAllocatedUnfairLock<Date?>(initialState: nil)
    /// The whole quit wait for plugins (10 s however many plugins there are); a test seam.
    @ObservationIgnored var quitBoundMs: Int = 10_000

    /// Plugin runs finished (tests wait for it instead of polling the messages).
    public private(set) var completedRuns: Int = 0

    init(ports: PluginsPorts, dataDir: URL, messages: MessagesModel, language: LanguageModel,
         now: @escaping @Sendable () -> Date) {
        self.messages = messages
        self.language = language
        self.now = now
        runner = ports.makeRunner(dataDir.appendingPathComponent("plugins").path, Self.timeoutMs)
    }

    /// `true` when plugins can run at all.
    public var isActive: Bool {
        runner != nil
    }

    /// `QSO_LOGGED` for a QSO logged here.
    public func qsoLogged(_ qso: Qso) {
        fire(.qsoLogged, json: PluginEventJson.qsoLogged(qso))
    }

    /// `CONTEST_OPENED` with the JSON the activation built.
    public func contestOpened(json: String) {
        fire(.contestOpened, json: json)
    }

    /// Runs the plugins of `event` on the lane; the results are shown on the main actor. The directory listing that
    /// decides whether anything runs is the first step of the lane job (never a file system call on the main actor);
    /// with no plugin for the event the job ends without a result and shows nothing.
    public func fire(_ event: PluginRunner.Event, json: String) {
        guard let runner else { return }
        let deadline = quitDeadline
        lane.submit({ () -> [PluginRunner.Result]? in
            guard !runner.plugins(event).isEmpty else { return nil }
            return runner.fire(event, json: json, deadline: { deadline.withLock { $0 } })
        }, then: { [weak self] results in
            if let results {
                self?.show(results)
            }
        })
    }

    /// The `SPOT_RECEIVED` hook for `DxClusterModel.pluginSpot`: called on a reader thread, only queues. The closure
    /// holds the lane and the runner, not the model.
    var spotHandler: @Sendable (DxSpot) -> Void {
        guard let runner else { return { _ in } }
        let lane: PluginLane = self.lane
        let pending = self.pendingSpots
        let deadline = self.quitDeadline
        return { [weak self] spot in
            // A job the closed lane skips keeps its count: harmless, a closed lane only exists at the quit.
            let admitted: Bool = pending.withLock { count in
                guard count < PluginsModel.maxPendingSpots else { return false }
                count += 1
                return true
            }
            guard admitted else { return }
            let json: String = PluginEventJson.spotReceived(spot)
            // The listing happens on the lane, not on the reader thread; no plugin = no run.
            lane.submit({ () -> [PluginRunner.Result]? in
                defer { pending.withLock { $0 -= 1 } }
                guard !runner.plugins(.spotReceived).isEmpty else { return nil }
                return runner.fire(.spotReceived, json: json, deadline: { deadline.withLock { $0 } })
            }, then: { results in
                if let results {
                    self?.show(results)
                }
            })
        }
    }

    /// Kotlin `withContext(Main) { results.forEach … messages.add; if (results.isNotEmpty()) messageRevision++ }`.
    private func show(_ results: [PluginRunner.Result]) {
        completedRuns += 1
        guard !results.isEmpty else { return }
        var texts: [String] = []
        for result in results {
            for line in result.output {
                texts.append("[" + result.plugin + "] " + line)
            }
            if result.exitCode != 0 {
                texts.append(language.tr("[%s] skončil s kódem %s", .string(result.plugin), .int(Int(result.exitCode))))
            }
        }
        messages.add(texts, at: now())
    }

    /// Waits for the runs queued so far (tests, the quit).
    func settle() async {
        await lane.settle()
        await drainMainQueue()
    }

    /// The quit's last step: queued runs are skipped, the one in flight finishes (its 10 s limit) — after the
    /// database was closed.
    func drain() async {
        startQuitDeadline()
        await lane.close()
    }

    /// Sets the quit deadline: from now on a plugin that has not started yet is not started.
    func startQuitDeadline() {
        let end = Date(timeIntervalSinceNow: Double(quitBoundMs) / 1000.0)
        quitDeadline.withLock { $0 = end }
    }
}
