import Foundation
import MCLCore
import Observation

/// The online services of v1.1.1: the Club Log live stream, the score reporting to a scoreboard and the NTP clock
/// check (`AS:1884-2039`).
///
/// - **Club Log.** `queueClubLog` appends the QSO as an ADIF record (only when `clubLog.configured()`); records go out
///   one at a time on the Club Log lane, each the moment it is first in the queue (Kotlin's `poll(5 s)` only wakes the
///   same loop). OK takes the next, REJECTED drops the record, anything else puts it back at the front and waits 60 s
///   on the injected clock. The queue lives in memory only and is **dropped at the quit** (as in Kotlin).
/// - **Score reporting.** Every 60 s (and for „Odeslat teď") `reportScoreIfDue` decides on the main actor, hands a
///   `Sendable` snapshot (the log rows, a fresh session, the station) to the scoreboard lane, which computes the
///   breakdown and posts; the outcome comes back to the main actor. The attempt time is remembered
///   whatever the result, the log revision only for a 2xx.
/// - **Clock check.** At the start and every 30 min `checkClock` asks the configured NTP server (a `ClockProbe`, never
///   a real host in tests); the offset may correct the QSO time (`ntpCorrectQsoTime`).
///
/// Credentials (the Club Log password and API key, the scoreboard URL) are passed to the ports and never written to
/// the log or a status text. Inert (`NetworkPorts.isInert`): nothing is sent, no NTP query is made.
@Observable @MainActor
public final class OnlineServicesModel {

    struct Dependencies {
        let config: ConfigModel
        let status: StatusModel
        let language: LanguageModel
        let contest: ContestModel
        let logbook: LogbookModel
        let messages: MessagesModel
        let network: NetworkPorts
        /// The clock of the 60 s score loop, the 30 min clock loop and the Club Log retry wait.
        let clock: any RescoreClock
        let now: @Sendable () -> Date
        let appVersion: String?
    }

    // MARK: - state

    /// The Club Log status (`clubLogStatus`).
    public internal(set) var clubLogStatus: EntryStatus = .tr(ClubLogQueuePolicy.idleStatus)
    /// The score reporting status (`scoreReportStatus`).
    public internal(set) var scoreReportStatus: EntryStatus = .tr(ScoreReportPolicy.idleStatus)
    /// The clock status (`clockStatus`).
    public internal(set) var clockStatus: EntryStatus = .tr(ClockCheck.neverChecked)
    /// The last measured offset in ms (positive = the computer is behind); `nil` = not measured.
    public internal(set) var clockOffsetMs: Int64?

    /// Records waiting for Club Log (the sending one included).
    public var clubLogQueued: Int { clubLogQueue.count + (clubLogSending == nil ? 0 : 1) }

    let deps: Dependencies
    @ObservationIgnored private let clubLogLane = HttpLane(name: "clublog")
    @ObservationIgnored private let scoreLane = HttpLane(name: "scoreboard")
    @ObservationIgnored private var clubLogQueue: [String] = []
    @ObservationIgnored private var clubLogSending: String?
    @ObservationIgnored private var clubLogRetryTimer: (any RescoreTimer)?
    @ObservationIgnored private var scoreTimer: (any RescoreTimer)?
    @ObservationIgnored private var clockTimer: (any RescoreTimer)?
    @ObservationIgnored private var lastScoreRevision: Int64 = -1
    @ObservationIgnored private var lastScoreAt: JavaInstant = JavaInstant.epoch
    @ObservationIgnored private var scoreInFlight = false
    @ObservationIgnored private var clockGeneration = 0
    @ObservationIgnored private var isClosed = false
    /// `false` while the pileup simulator runs — nothing is reported to the scoreboard then.
    @ObservationIgnored var outwardAllowed: @MainActor () -> Bool = { true }
    /// Test seam: runs after a Club Log upload outcome was handled.
    @ObservationIgnored var afterClubLogOutcome: (@MainActor () -> Void)?
    /// Test seam: runs after a score report outcome was handled.
    @ObservationIgnored var afterScoreOutcome: (@MainActor () -> Void)?
    /// Test seam: runs after a clock check ended.
    @ObservationIgnored var afterClockCheck: (@MainActor () -> Void)?

    init(_ dependencies: Dependencies) {
        deps = dependencies
    }

    private var config: AppConfig { deps.config.config }

    private func show(_ text: EntryStatus) {
        deps.status.showJoined(text.parts, separator: "")
    }

    /// Starts the loops: the score every 60 s, the clock now and every 30 min.
    func start() {
        scheduleScoreLoop()
        clockLoop()
    }

    // MARK: - Club Log

    /// Kotlin `queueClubLog(qso)`.
    func queueClubLog(_ qso: Qso) {
        guard ClubLogQueuePolicy.shouldQueue(configured: config.clubLog.configured()), !isClosed else { return }
        guard !deps.network.isInert else {
            appLog.notice("\(NetworkPorts.disabledMessage, privacy: .public): Club Log")
            return
        }
        clubLogQueue.append(AdifWriter().record(qso))
        sendNextClubLog()
    }

    private func sendNextClubLog() {
        guard !isClosed, clubLogSending == nil, clubLogRetryTimer == nil, !clubLogQueue.isEmpty else { return }
        let record: String = clubLogQueue.removeFirst()
        clubLogSending = record
        let cl: ClubLogConfig = config.clubLog
        let callsign: String = ClubLogQueuePolicy.callsign(configured: cl.callsign, stationCall: config.station.call)
        let upload = deps.network.online.uploadClubLog
        clubLogLane.submit({ () -> ClubLogAttempt in
            do {
                return .outcome(try upload(cl.email, cl.appPassword, callsign, cl.apiKey, record))
            } catch {
                return .failed(ErrorText.message(error))
            }
        }, then: { [weak self] attempt in
            self?.clubLogFinished(record, attempt)
        })
    }

    private func clubLogFinished(_ record: String, _ attempt: ClubLogAttempt) {
        clubLogSending = nil
        guard !isClosed else { return }
        let outcome: ClubLogClient.Outcome
        switch attempt {
        case .outcome(let value):
            outcome = value
        case .failed(let message):
            // Kotlin lets the exception end the sender loop; here the record waits and is tried again.
            clubLogStatus = .verbatim(message)
            ClubLogTrafficLog.shared.note("failed: \(message); retry in \(ClubLogQueuePolicy.retryDelayMs / 1000) s")
            retryClubLog(record)
            afterClubLogOutcome?()
            return
        }
        let handled = ClubLogQueuePolicy.handle(outcome, queued: clubLogQueue.count)
        clubLogStatus = handled.status
        ClubLogTrafficLog.shared.note(ClubLogQueuePolicy.logNote(outcome, queued: clubLogQueue.count))
        switch handled.action {
        case .done, .drop:
            sendNextClubLog()
        case .retryFront(let delayMs):
            retryClubLog(record, delayMs: delayMs)
        }
        afterClubLogOutcome?()
    }

    private func retryClubLog(_ record: String, delayMs: Int = ClubLogQueuePolicy.retryDelayMs) {
        clubLogQueue.insert(record, at: 0)
        clubLogRetryTimer = deps.clock.schedule(afterMilliseconds: delayMs) { [weak self] in
            guard let self else { return }
            self.clubLogRetryTimer = nil
            self.sendNextClubLog()
        }
    }

    // MARK: - score reporting

    private func scheduleScoreLoop() {
        scoreTimer = deps.clock.schedule(afterMilliseconds: ScoreReportPolicy.loopSeconds * 1000) { [weak self] in
            guard let self, !self.isClosed else { return }
            self.reportScoreIfDue(force: false)
            self.scheduleScoreLoop()
        }
    }

    /// „Odeslat teď": reports now whatever the interval and the log revision.
    public func reportScoreNow() {
        reportScoreIfDue(force: true)
    }

    /// Kotlin `reportScoreIfDue(force)`.
    public func reportScoreIfDue(force: Bool) {
        guard !isClosed, !scoreInFlight else { return }
        guard outwardAllowed() else { return }
        let now = JavaInstant(date: deps.now())
        let revision: Int64 = deps.logbook.revision
        let due: Bool = ScoreReportPolicy.due(
            force: force, enabled: config.scoreReportingEnabled, hasDefinition: deps.contest.definition != nil,
            revision: revision, lastRevision: lastScoreRevision, now: now, lastAt: lastScoreAt,
            minutes: config.scoreReportingMinutes)
        guard due, let definition = deps.contest.definition,
              let session = deps.contest.runtime.freshSession() else { return }
        guard !deps.network.isInert else {
            appLog.notice("\(NetworkPorts.disabledMessage, privacy: .public): score reporting")
            return
        }
        // `appVersion()`: the packaged version, otherwise the translated „vývojová verze".
        let version: String = deps.appVersion ?? deps.language.tr("vývojová verze")
        let job = ScoreJob(
            qsos: deps.logbook.rows, session: session, station: scoreStation(), contestName: scoreContestName(definition),
            withBreakdown: config.scoreReportingBreakdown, version: version, now: now, url: config.scoreReportingUrl,
            revision: revision)
        let post = deps.network.online.postScore
        scoreInFlight = true
        scoreLane.submit({ () -> ScoreAttempt in
            Self.runScoreJob(job, post: post)
        }, then: { [weak self] attempt in
            self?.scoreFinished(attempt, job: job)
        })
    }

    private func scoreStation() -> ScoreXml.Station {
        let station: StationConfig = config.station
        let setup: ContestSetup? = deps.contest.activeSetup
        return ScoreReportPolicy.station(call: station.call, operators: setup?.operators, club: station.club,
                                         cqZone: station.cqZone, ituZone: station.ituZone,
                                         gridSquare: station.gridSquare, category: setup?.category)
    }

    private func scoreContestName(_ definition: ContestDefinition) -> String? {
        ScoreReportPolicy.contestName(cabrilloName: definition.cabrillo?.contestName, definitionId: definition.id)
    }

    /// On the scoreboard lane: the breakdown (`nil` when it cannot be computed — Kotlin returns without a trace),
    /// the XML and the post.
    nonisolated private static func runScoreJob(_ job: ScoreJob, post: @Sendable (String, String) throws -> ScoreResponse)
        -> ScoreAttempt {
        let breakdown: ScoreBreakdown
        do {
            breakdown = try ScoreBreakdown.compute(job.session, job.qsos)
        } catch {
            return .skipped
        }
        let xml: String = ScoreXml.build(contestName: job.contestName, station: job.station, score: breakdown.score,
                                         breakdown: breakdown, withBreakdown: job.withBreakdown, version: job.version,
                                         now: job.now.date)
        let result: ScoreReportPolicy.PostResult
        do {
            let response: ScoreResponse = try post(job.url, xml)
            if let detail = response.detail, !(200...299).contains(response.status) {
                result = .rejected(response.status, detail: detail)
            } else {
                result = .http(response.status)
            }
        } catch {
            if let http = error as? JavaHttpError {
                result = ScoreReportPolicy.result(failure: http, url: job.url)
            } else {
                result = .failure(ErrorText.message(error))
            }
        }
        return .posted(result, total: breakdown.score.total)
    }

    private func scoreFinished(_ attempt: ScoreAttempt, job: ScoreJob) {
        scoreInFlight = false
        guard !isClosed else { return }
        guard case .posted(let result, let total) = attempt else { return }
        lastScoreAt = job.now
        let outcome = ScoreReportPolicy.outcome(result, total: total, now: job.now)
        if outcome.accepted {
            lastScoreRevision = job.revision
        }
        scoreReportStatus = outcome.status
        afterScoreOutcome?()
    }

    // MARK: - clock check

    private func clockLoop() {
        checkClock()
        clockTimer = deps.clock.schedule(afterMilliseconds: ClockCheck.intervalSeconds * 1000) { [weak self] in
            guard let self, !self.isClosed else { return }
            self.clockLoop()
        }
    }

    /// Kotlin `checkClock()`: asks the server (never blocks: the probe is `async`) and uses the offset.
    public func checkClock() {
        guard !isClosed else { return }
        guard let server = ClockCheck.server(config.ntpServer) else {
            clockStatus = ClockCheck.disabled
            return
        }
        guard !deps.network.isInert else {
            appLog.notice("\(NetworkPorts.disabledMessage, privacy: .public): clock check")
            return
        }
        clockGeneration += 1
        let generation: Int = clockGeneration
        let probe: ClockProbe = deps.network.clock
        Task { @MainActor [weak self] in
            let offset: Int64
            do {
                offset = try await probe(server)
            } catch {
                self?.clockFailed(error, server: server, generation: generation)
                return
            }
            self?.clockMeasured(offset, server: server, generation: generation)
        }
    }

    private func clockFailed(_ error: any Error, server: String, generation: Int) {
        guard !isClosed, generation == clockGeneration else { return }
        clockStatus = ClockCheck.failure(server: server, message: ErrorText.message(error))
        afterClockCheck?()
    }

    private func clockMeasured(_ offsetMs: Int64, server: String, generation: Int) {
        guard !isClosed, generation == clockGeneration else { return }
        let correct: Bool = config.ntpCorrectQsoTime
        let result: ClockCheck.Result = ClockCheck.result(offsetMs: offsetMs, server: server, correct: correct)
        clockOffsetMs = offsetMs
        let logbook: LogbookModel = deps.logbook
        let applied: Int64 = result.applyOffsetMs
        Task { @MainActor in
            await logbook.setClockOffset(milliseconds: applied)
        }
        clockStatus = result.status
        if result.warn, let warning = result.warnStatus {
            show(warning)
            let language: LanguageModel = deps.language
            deps.messages.add(result.status.text(language.translator, decimalSeparator: language.decimalSeparator),
                              at: deps.now())
        }
        afterClockCheck?()
    }

    // MARK: - the quit

    /// The quit: the loops stop, the Club Log queue is dropped (its records are lost, as in Kotlin), the
    /// lanes refuse further jobs. A request in flight is not awaited (its 20 s limit would hold the quit); its result
    /// is ignored.
    func shutdown() {
        isClosed = true
        scoreTimer?.cancel()
        scoreTimer = nil
        clockTimer?.cancel()
        clockTimer = nil
        clubLogRetryTimer?.cancel()
        clubLogRetryTimer = nil
        clubLogQueue.removeAll()
        clubLogLane.markClosed()
        scoreLane.markClosed()
    }

    /// Waits for the lanes (tests).
    func settle() async {
        await clubLogLane.settle()
        await scoreLane.settle()
        await drainMainQueue()
    }
}

/// How a Club Log attempt ended on the lane.
private enum ClubLogAttempt: Sendable {
    case outcome(ClubLogClient.Outcome)
    case failed(String)
}

/// What the scoreboard lane needs: a snapshot taken on the main actor.
private struct ScoreJob: Sendable {
    let qsos: [Qso]
    let session: ContestSession
    let station: ScoreXml.Station
    let contestName: String?
    let withBreakdown: Bool
    let version: String?
    let now: JavaInstant
    let url: String
    let revision: Int64
}

/// How a score report ended on the lane.
private enum ScoreAttempt: Sendable {
    /// The breakdown could not be computed: nothing was posted and nothing is remembered.
    case skipped
    case posted(ScoreReportPolicy.PostResult, total: Int64)
}
