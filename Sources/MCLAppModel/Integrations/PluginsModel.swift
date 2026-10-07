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
    @ObservationIgnored private let clock: any RescoreClock
    @ObservationIgnored private let appVersion: String?
    @ObservationIgnored private let runner: (any PluginRunning)?
    @ObservationIgnored private let lane = PluginLane(name: "plugins")
    @ObservationIgnored private let pendingSpots = OSAllocatedUnfairLock(initialState: 0)
    /// The end of the quit's wait (set by `drain`): later plugins are not started, the running one is cut short.
    @ObservationIgnored private let quitDeadline = OSAllocatedUnfairLock<Date?>(initialState: nil)
    /// The whole quit wait for plugins (10 s however many plugins there are); a test seam.
    @ObservationIgnored var quitBoundMs: Int = 10_000

    /// The window plugins that subscribed to events (every event is offered to them too).
    @ObservationIgnored var windowEvents: PluginEventRouter?

    /// Plugin runs finished (tests wait for it instead of polling the messages).
    public private(set) var completedRuns: Int = 0

    /// The settle time of a `FREQUENCY_CHANGED` (the frequency must stay put this long).
    nonisolated static let frequencySettleMs = 1_000
    /// The quiet time before a `SCORE_CHANGED` goes out (the latest score of the burst).
    nonisolated static let scoreSettleMs = 3_000

    /// The 0/1 radio's band, mode and frequency, as the active entry window reports them.
    @ObservationIgnored private var radios: [Int: RadioState] = [:]
    @ObservationIgnored private var scoreTimer: (any RescoreTimer)?
    @ObservationIgnored private var pendingScore: (contestId: String?, score: ScoreState)?
    @ObservationIgnored private var lastScoreJson: String?

    private struct RadioState {
        var band: Band?
        var mode: Mode?
        var reportedHz: Int64 = 0
        var pendingHz: Int64?
        var timer: (any RescoreTimer)?
    }

    init(ports: PluginsPorts, dataDir: URL, messages: MessagesModel, language: LanguageModel,
         now: @escaping @Sendable () -> Date, clock: any RescoreClock = MainQueueRescoreClock(),
         appVersion: String? = nil) {
        self.messages = messages
        self.language = language
        self.now = now
        self.clock = clock
        self.appVersion = appVersion
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

    // MARK: - further events

    /// `QSO_EDITED` (an operator's edit in this station).
    public func qsoEdited(old: Qso, new: Qso) {
        fire(.qsoEdited, json: PluginEventJson.qsoEdited(old: old, new: new))
    }

    /// `QSO_DELETED` (an operator's delete in this station).
    public func qsoDeleted(_ qso: Qso) {
        fire(.qsoDeleted, json: PluginEventJson.qsoDeleted(qso))
    }

    /// `CONTEST_CLOSED`: the operator left a contest (another one opened, or Contest → None).
    public func contestClosed(contestId: String, name: String?) {
        fire(.contestClosed, json: PluginEventJson.contestClosed(contestId: contestId, name: name))
    }

    /// `APP_STARTED`, once the start-up is complete.
    public func appStarted(contestId: String?, name: String?) {
        fire(.appStarted, json: PluginEventJson.app(version: appVersion, contestId: contestId, name: name))
    }

    /// `APP_QUITTING`, the first step of the quit. The quit deadline starts now, so no plugin — this one included —
    /// holds the quit beyond it; the run is a lane job and never blocks the main actor.
    public func appQuitting(contestId: String?, name: String?) {
        startQuitDeadline()
        fire(.appQuitting, json: PluginEventJson.app(version: appVersion, contestId: contestId, name: name))
    }

    /// `SELF_SPOTTED` (the "you were spotted" / RBN message).
    public func selfSpotted(_ spot: SelfSpot) {
        fire(.selfSpotted, json: PluginEventJson.selfSpotted(spot))
    }

    /// `NEW_MULTIPLIER` for a QSO logged here that made multipliers new.
    public func newMultiplier(contestId: String?, qso: Qso, result: ContestSession.LogResult) {
        guard result.counted, !result.dupe else { return }
        let fresh: [(set: String?, key: String?)] = result.multipliers.filter { $0.isNew && $0.countsAsMultiplier }
            .map { (set: $0.setId, key: $0.key) }
        guard !fresh.isEmpty else { return }
        fire(.newMultiplier, json: PluginEventJson.newMultiplier(
            contestId: contestId, call: qso.call, band: qso.band?.adif ?? "", mode: qso.mode?.rawValue ?? "",
            multipliers: fresh))
    }

    /// `SCORE_REPORTED`: the scoreboard post's result.
    public func scoreReported(host: String?, status: Int, accepted: Bool, message: String) {
        fire(.scoreReported, json: PluginEventJson.scoreReported(host: host, status: status, accepted: accepted,
                                                                message: message))
    }

    /// `CLUBLOG_UPLOAD`: the outcome of one upload attempt.
    public func clubLogUpload(outcome: String, call: String, status: String) {
        fire(.clublogUpload, json: PluginEventJson.clublogUpload(outcome: outcome, call: call, status: status))
    }

    /// `SCORE_CHANGED`, coalesced: the score of the active contest changed. The latest score of a burst (a rescore,
    /// a run of QSOs) goes out once, `scoreSettleMs` after the last change; an identical payload is not repeated.
    public func scoreChanged(contestId: String?, score: ScoreState?) {
        guard runner != nil, let score, contestId != nil else { return }
        pendingScore = (contestId, score)
        guard scoreTimer == nil else { return }
        scoreTimer = clock.schedule(afterMilliseconds: Self.scoreSettleMs) { [weak self] in
            guard let self else { return }
            self.scoreTimer = nil
            guard let pending = self.pendingScore else { return }
            self.pendingScore = nil
            let json: String = PluginEventJson.scoreChanged(contestId: pending.contestId, score: pending.score)
            guard json != self.lastScoreJson else { return }
            self.lastScoreJson = json
            self.fire(.scoreChanged, json: json)
        }
    }

    /// What the active entry window of radio `radio` is tuned to. `BAND_CHANGED` and `MODE_CHANGED` fire at once on a
    /// change; `FREQUENCY_CHANGED` only after the frequency stayed put for `frequencySettleMs` (so each firing is
    /// at least that far from the previous one). The first value seen, a value of 0 and a band-less frequency (a
    /// half-typed one) only set the baseline.
    public func operatingChanged(radio: Int, freqHz: Int64, mode: Mode) {
        guard runner != nil else { return }
        var state: RadioState = radios[radio] ?? RadioState()
        defer { radios[radio] = state }
        if let old = state.mode, old != mode {
            fire(.modeChanged, json: PluginEventJson.modeChanged(radio: radio, old: old.rawValue, new: mode.rawValue))
        }
        state.mode = mode
        guard freqHz > 0 else { return }
        if let band = Band.from(frequencyHz: Int(clamping: freqHz)) {
            if let old = state.band, old != band {
                fire(.bandChanged, json: PluginEventJson.bandChanged(radio: radio, old: old.adif, new: band.adif))
            }
            state.band = band
        }
        guard state.reportedHz > 0 else {
            state.reportedHz = freqHz
            return
        }
        if freqHz == state.reportedHz {
            state.timer?.cancel()
            state.timer = nil
            state.pendingHz = nil
            return
        }
        guard state.pendingHz != freqHz else { return }
        state.pendingHz = freqHz
        state.timer?.cancel()
        state.timer = clock.schedule(afterMilliseconds: Self.frequencySettleMs) { [weak self] in
            self?.frequencySettled(radio: radio)
        }
    }

    private func frequencySettled(radio: Int) {
        guard var state = radios[radio], let new = state.pendingHz else { return }
        let old: Int64 = state.reportedHz
        state.pendingHz = nil
        state.timer = nil
        state.reportedHz = new
        radios[radio] = state
        guard new != old else { return }
        fire(.frequencyChanged, json: PluginEventJson.frequencyChanged(radio: radio, oldHz: old, newHz: new))
    }

    /// Runs the plugins of `event` on the lane; the results are shown on the main actor. The directory listing that
    /// decides whether anything runs is the first step of the lane job (never a file system call on the main actor);
    /// with no plugin for the event the job ends without a result and shows nothing.
    public func fire(_ event: PluginRunner.Event, json: String) {
        windowEvents?.deliver(event, json: json)
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
        let router: PluginEventRouter? = windowEvents
        guard let runner else {
            return { spot in
                guard let router, router.wants("spot-received") else { return }
                router.deliver(.spotReceived, json: PluginEventJson.spotReceived(spot))
            }
        }
        let lane: PluginLane = self.lane
        let pending = self.pendingSpots
        let deadline = self.quitDeadline
        return { [weak self] spot in
            if let router, router.wants("spot-received") {
                router.deliver(.spotReceived, json: PluginEventJson.spotReceived(spot))
            }
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
        if quitDeadline.withLock({ $0 }) == nil {
            startQuitDeadline()
        }
        await lane.close()
    }

    /// Sets the quit deadline: from now on a plugin that has not started yet is not started.
    func startQuitDeadline() {
        let end = Date(timeIntervalSinceNow: Double(quitBoundMs) / 1000.0)
        quitDeadline.withLock { $0 = end }
    }
}
