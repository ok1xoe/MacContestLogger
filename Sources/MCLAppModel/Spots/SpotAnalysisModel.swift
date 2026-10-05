import Foundation
import MCLCore
import Observation
import os

/// The current `SpotAnalyzer` of the spot windows and the callbook prefetch (Kotlin reads the `ContestController`
/// live; here a `Sendable` snapshot is rebuilt on demand). `current()` rebuilds when a trigger of the analyzer's
/// contract fired:
/// 1. a contest activation (also `SpotGridLog.reset()`, Kotlin `gridLogged.clear()`), 2. a deactivation and 3. every
///    `ContestRuntime.adopt`, 4. a change of my call or grid — 1–4 through `isCurrent(for:)` — and a new runtime
///    (contest-data reload: Kotlin builds a new controller with an empty grid log);
/// 5. a band-data reload (`ContestModel.environment` changes);
/// 6. the offline grid data loaded (`CallbookModel.gridGeneration`);
/// 7. the callbook closure reads the live cache, so new records need no rebuild.
@Observable @MainActor
public final class SpotAnalysisModel {

    /// Rises whenever something the analysis reads changed — an activation or deactivation, a rescore (score), the
    /// station, the band data, the grid data or a new runtime — so a window that redraws on it never shows a stale
    /// analysis.
    public private(set) var revision: Int = 0

    /// The decision log of the spot grids (written into the callbook's HTTP dump, Kotlin `gridLog`).
    @ObservationIgnored public let gridLog: SpotGridLog
    @ObservationIgnored private let contest: ContestModel
    @ObservationIgnored private let config: ConfigModel
    @ObservationIgnored private let callbook: CallbookModel
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var cached: SpotAnalyzer?
    /// The runtime the cache was built over (kept alive, compared by identity).
    @ObservationIgnored private var cachedRuntime: ContestRuntime?
    @ObservationIgnored private var cachedGridGeneration: Int = -1
    @ObservationIgnored private var environmentChanged = false
    /// How many analyzers were built (tests check the rebuild triggers).
    @ObservationIgnored private(set) var buildCount: Int = 0

    init(contest: ContestModel, config: ConfigModel, callbook: CallbookModel, translator: TranslatorBox,
         now: @escaping @Sendable () -> Date) {
        self.contest = contest
        self.config = config
        self.callbook = callbook
        self.now = now
        let log: HamQthLog = callbook.hamQthLog
        gridLog = SpotGridLog { message in
            try? log.info(translator.text(message))
        }
        observeEnvironment()
        observeInputs()
    }

    /// The analyzer for now.
    public func current() -> SpotAnalyzer {
        let runtime: ContestRuntime = contest.runtime
        let data: GridData? = callbook.gridData
        let generation: Int = callbook.gridGeneration
        if let cached, !environmentChanged, cachedRuntime === runtime, cachedGridGeneration == generation,
           cached.isCurrent(for: runtime) {
            return cached
        }
        if let previous = cachedRuntime, previous !== runtime {
            // Kotlin builds a new controller (with an empty grid log) when the contest data are reloaded.
            gridLog.reset()
        }
        let environment: ContestEnvironment = contest.environment
        let built = SpotAnalyzer(runtime: runtime, bandPlan: environment.bandPlan,
                                 digiFrequencies: environment.digiFrequencies,
                                 gridDatabase: data?.database ?? .empty, gridFieldMap: data?.fieldMap,
                                 callbook: callbook.analyzerLookup, gridLog: gridLog, now: now)
        cached = built
        cachedRuntime = runtime
        cachedGridGeneration = generation
        environmentChanged = false
        buildCount += 1
        return built
    }

    /// A contest was activated (Kotlin `activate` clears `gridLogged`).
    func activated() {
        gridLog.reset()
        cached = nil
        revision += 1
    }

    /// Trigger 5: the band data (the environment) — a rebuild is due even when nothing else changed.
    private func observeEnvironment() {
        withObservationTracking {
            _ = contest.environment
        } onChange: { [weak self] in
            MainHop.post {
                guard let self else { return }
                self.environmentChanged = true
                self.revision += 1
                self.observeEnvironment()
            }
        }
    }

    /// The other inputs only raise `revision` (`current()` detects them itself): the active contest, the score of a
    /// rescore, my station, the grid data.
    private func observeInputs() {
        withObservationTracking {
            _ = contest.activeId
            _ = contest.score
            _ = config.config.station.call
            _ = config.config.station.gridSquare
            _ = callbook.gridGeneration
        } onChange: { [weak self] in
            MainHop.post {
                guard let self else { return }
                self.revision += 1
                self.observeInputs()
            }
        }
    }
}

/// The UI language for the threads of the network sessions and the spot analysis (their `tr`), following
/// `LanguageModel`.
final class TranslatorBox: Sendable {
    private let state: OSAllocatedUnfairLock<(translator: Translator, separator: String)>

    init(translator: Translator, decimalSeparator: String) {
        state = OSAllocatedUnfairLock(initialState: (translator, decimalSeparator))
    }

    func translate(_ key: String) -> String {
        state.withLock { $0.translator }.translate(key)
    }

    func text(_ message: ContestMessage) -> String {
        let current = state.withLock { $0 }
        return message.text(current.translator, decimalSeparator: current.separator)
    }

    /// Keeps the box on the language's current translator. The decimal separator is not followed: it is a `let` of
    /// `LanguageModel` (read once from the system locale at start), so the value given to `init` stays current.
    @MainActor func follow(_ language: LanguageModel) {
        let translator: Translator = language.translator
        state.withLock { $0.translator = translator }
        withObservationTracking {
            _ = language.translator
        } onChange: { [weak self] in
            MainHop.post {
                self?.follow(language)
            }
        }
    }
}
