import Foundation

/// A UI text produced by the core: the Czech translation key (Kotlin `tr(cs, args…)`) and its arguments, translated
/// only where it is shown. An argument can itself be a message (Kotlin `tr("Nelze aktivovat závod: %s", error)`, where
/// `error` was already translated). A `verbatim` message is shown as is (Java exception texts, Kotlin strings
/// without `tr`).
public struct ContestMessage: Error, Equatable, Sendable {

    /// One argument: a value for `%s`, or a nested message translated first.
    public enum Part: Equatable, Sendable {
        case value(Translator.Arg)
        case message(ContestMessage)
    }

    public let key: String
    public let parts: [Part]
    /// `false` = the text is not translated (`key` is shown as is).
    public let translatable: Bool

    public init(_ key: String, _ args: Translator.Arg...) {
        self.key = key
        self.parts = args.map { Part.value($0) }
        self.translatable = true
    }

    public init(_ key: String, parts: [Part]) {
        self.key = key
        self.parts = parts
        self.translatable = true
    }

    private init(verbatim text: String) {
        self.key = text
        self.parts = []
        self.translatable = false
    }

    /// A text shown without translation.
    public static func verbatim(_ text: String) -> ContestMessage {
        ContestMessage(verbatim: text)
    }

    /// The text in the given language: without arguments Kotlin `tr(cs)` (no formatting), otherwise
    /// `tr(cs, args)` with nested messages translated first.
    public func text(_ translator: Translator, decimalSeparator: String = ".") -> String {
        if !translatable {
            return key
        }
        if parts.isEmpty {
            return translator.translate(key)
        }
        var args: [Translator.Arg] = []
        for part in parts {
            switch part {
            case .value(let arg):
                args.append(arg)
            case .message(let inner):
                args.append(.string(inner.text(translator, decimalSeparator: decimalSeparator)))
            }
        }
        return translator.translate(key, args, decimalSeparator: decimalSeparator)
    }

    /// The Czech text (no translation).
    public var czech: String {
        text(Translator.source)
    }
}

/// The non-UI counterpart of the Kotlin `ContestController` (`ui/contest/ContestController.kt`, v1.1.1): holds the
/// live `ContestSession` of the active contest, the last preview and the score, and answers questions about the
/// active definition. The spot/band-map/grid parts of the controller (`SpotStatus`, `SpotRow`, multiplier grid,
/// HamQTH/grid prediction) are not here — they are `SpotAnalyzer`, a `Sendable` snapshot built from this runtime
/// through the module-internal read accessors `activeSession`, `multiplierRegistry` and `stationGrid`;
/// `sessionGeneration` tells a stale analyzer apart.
///
/// **Not `Sendable`**: owned by one actor (the app's contest model on the main actor). Work that must run off it
/// takes a `freshSession()` (a `Sendable` `ContestSession`) and hands the result back through `adopt` (guarded by the
/// log revision, so a QSO logged meanwhile is never lost).
///
/// Kotlin behaviour that is kept:
/// - `activate` validates the multiplier sets and returns the Kotlin error text (`nil` = success); a missing set is
///   reported by the set id in definition order, joined by `", "`;
/// - a new session (activation, recount, marks) always gets the stored TOUR session, bonus stations and QTC count;
/// - `log`/`replayLogged`/`setQtcCount`/`adopt` refresh the score, `preview` does not;
/// - `usesSerial`/`usesExchangeBeyondRst` are `true` outside a contest (free logging numbers QSOs and has a generic
///   Exch field), `false` for an active contest without an exchange section;
/// - `primaryMode`: first definition mode by enum name, then by ADIF, otherwise CW.
///
/// Differences (technique): an exception that Kotlin lets propagate into Compose is a typed `throws` here; a score
/// formula error does not fail `activate`/`log`/`adopt`/`setQtcCount` — `score` becomes `nil` and the error is kept
/// in `scoreError` (Kotlin throws it out of those calls and keeps the previous score); a `nil` element in
/// `multipliers`/`exchange.sent`/`exchange` fields (a Kotlin NPE) is skipped.
public final class ContestRuntime {

    private let dxcc: (any DxccLookup)?
    private let registry: MultiplierSetRegistry?
    private let myCall: () -> String
    private let myGrid: () -> String
    private let myItuZone: () -> String

    /// Contest definitions from the contests directory (Kotlin `available`).
    public let available: [ContestDefinition]
    /// The contests directory (`contests/` or the data root), `nil` without data.
    public let contestsDir: URL?

    public private(set) var activeId: String?
    public private(set) var score: ScoreState?
    /// The error of the last score computation (`nil` = the score is valid or no contest is active).
    public private(set) var scoreError: ExpressionError?
    public private(set) var lastPreview: ContestSession.LogResult?
    /// TOUR session of the active contest (`nil` = none).
    public private(set) var tour: Tour?
    /// Bonus stations of the active contest (N1MM BONUS).
    public private(set) var bonusStations: [String] = []
    /// QTC count (WAE) — applies to the live session and to every recount.
    public private(set) var qtcCount: Int32 = 0
    /// Changes whenever the live session is replaced or dropped (activation, `adopt`, deactivation). A
    /// `SpotAnalyzer` built earlier holds the previous session — `SpotAnalyzer.isCurrent(for:)` compares it.
    public private(set) var sessionGeneration: UInt64 = 0

    private var session: ContestSession?
    private var activeContestName: String?

    /// Kotlin constructor with an already loaded catalog.
    public init(dxcc: (any DxccLookup)?, registry: MultiplierSetRegistry?, available: [ContestDefinition],
                contestsDir: URL?, myCall: @escaping () -> String, myGrid: @escaping () -> String = { "" },
                myItuZone: @escaping () -> String = { "" }) {
        self.dxcc = dxcc
        self.registry = registry
        self.available = available
        self.contestsDir = contestsDir
        self.myCall = myCall
        self.myGrid = myGrid
        self.myItuZone = myItuZone
    }

    /// Kotlin constructor: the catalog is loaded from `contestsDir` (an unreadable directory → empty, Kotlin
    /// `runCatching { catalog.fromDir(dir) }.getOrDefault(emptyList())`).
    public convenience init(dxcc: (any DxccLookup)?, registry: MultiplierSetRegistry?, contestsDir: URL?,
                            myCall: @escaping () -> String, myGrid: @escaping () -> String = { "" },
                            myItuZone: @escaping () -> String = { "" }) {
        let available: [ContestDefinition] = contestsDir.flatMap { try? ContestCatalog.fromDir($0) } ?? []
        self.init(dxcc: dxcc, registry: registry, available: available, contestsDir: contestsDir, myCall: myCall,
                  myGrid: myGrid, myItuZone: myItuZone)
    }

    /// The runtime over a loaded environment (Kotlin `buildContestController`).
    public convenience init(environment: ContestEnvironment, myCall: @escaping () -> String,
                            myGrid: @escaping () -> String = { "" }, myItuZone: @escaping () -> String = { "" }) {
        self.init(dxcc: environment.dxcc, registry: environment.registry, available: environment.catalog,
                  contestsDir: environment.contestsDir, myCall: myCall, myGrid: myGrid, myItuZone: myItuZone)
    }

    // MARK: - state

    public var engineAvailable: Bool {
        dxcc != nil && registry != nil
    }

    /// DXCC lookup (backfill of countries, azimuth); `nil` when the engine is not available.
    public var dxccLookup: (any DxccLookup)? {
        dxcc
    }

    public var isActive: Bool {
        activeId != nil
    }

    /// Callsign of my station (points are relative to its DXCC/continent).
    public var stationCall: String {
        myCall()
    }

    /// Name of the active contest (kept apart, a snapshot activation id is not in `available`).
    public var activeName: String? {
        activeContestName
    }

    /// Definition of the active contest, `nil` outside a contest.
    public var definition: ContestDefinition? {
        session?.definition
    }

    // MARK: - read access for the spot analysis

    /// The live session (`nil` outside a contest), read by `SpotAnalyzer` (spot previews, multiplier grid).
    var activeSession: ContestSession? {
        session
    }

    /// The multiplier set registry (`nil` without the engine), read by `SpotAnalyzer` (HQ callsign map).
    var multiplierRegistry: MultiplierSetRegistry? {
        registry
    }

    /// Grid square of my station (Kotlin `myGrid()`; the azimuth of spot rows).
    var stationGrid: String {
        myGrid()
    }

    // MARK: - activation

    /// Activates a contest from `available`; `nil` = success, otherwise the error message.
    public func activate(id: String) -> ContestMessage? {
        if !engineAvailable {
            return ContestMessage("Contest engine není dostupný.")
        }
        guard let definition = available.first(where: { $0.id.map { JavaText.equals($0, id) } ?? false }) else {
            return ContestMessage("Závod '%s' nenalezen.", .string(id))
        }
        return activate(contestId: id, definition: definition)
    }

    /// Activates a given definition (from the contest's snapshot) under `contestId` (Kotlin `activateFromDefinition`).
    public func activate(contestId: String, definition: ContestDefinition) -> ContestMessage? {
        if !engineAvailable {
            return ContestMessage("Contest engine není dostupný.")
        }
        guard let registry else {
            return ContestMessage("Multiplikátorové sady nejsou načtené.")
        }
        let missing: [String] = Self.missingSets(definition, registry)
        if !missing.isEmpty {
            return ContestMessage("Chybí multiplikátorové sady: %s", .string(missing.joined(separator: ", ")))
        }
        guard let created = newSession(definition) else {
            return ContestMessage("Contest engine není dostupný.")
        }
        session = created
        sessionGeneration &+= 1
        activeId = contestId
        activeContestName = definition.metadata?.name
        lastPreview = nil
        refreshScore()
        return nil
    }

    /// Set ids of the definition the registry does not have (definition order, duplicates kept).
    static func missingSets(_ definition: ContestDefinition, _ registry: MultiplierSetRegistry) -> [String] {
        var missing: [String] = []
        for case let binding? in definition.multipliers ?? [] {
            if let set = binding.set, !registry.contains(set) {
                missing.append(set)
            }
        }
        return missing
    }

    public func deactivate() {
        session = nil
        sessionGeneration &+= 1
        activeId = nil
        activeContestName = nil
        score = nil
        scoreError = nil
        lastPreview = nil
    }

    /// Sets the TOUR session and bonus stations; for the live session at once, for later ones when they are created.
    public func setSessionExtras(tour: Tour?, bonusStations: [String]) {
        self.tour = tour
        self.bonusStations = bonusStations
        if let session {
            applyExtras(session)
        }
    }

    /// QTC count (WAE) — the live session and every recount; refreshes the score.
    public func setQtcCount(_ count: Int32) {
        qtcCount = count
        session?.setQtcCount(count)
        refreshScore()
    }

    /// QTC settings of the active contest (`nil` = the contest has no QTC).
    public var qtcConfig: ContestDefinition.Qtc? {
        session?.definition.scoring?.qtc
    }

    private func applyExtras(_ session: ContestSession) {
        session.setTour(tour)
        session.setBonusStations(bonusStations)
        session.setQtcCount(qtcCount)
    }

    /// A session over the definition with the stored extras; `nil` without the engine (unreachable for an active
    /// contest — activation requires it).
    private func newSession(_ definition: ContestDefinition) -> ContestSession? {
        guard let dxcc, let registry else { return nil }
        let created = ContestSession(definition: definition, dxcc: dxcc, registry: registry,
                                     myCall: myCall(), myGrid: Self.nilIfBlank(myGrid()),
                                     myItuZone: Self.nilIfBlank(myItuZone()))
        applyExtras(created)
        return created
    }

    /// Kotlin `ifBlank { null }`.
    private static func nilIfBlank(_ text: String) -> String? {
        KotlinText.isBlank(text) ? nil : text
    }

    /// A new session of the active definition with the stored extras (recount off the owning actor: replay into it,
    /// then `adopt`). `nil` outside a contest.
    public func freshSession() -> ContestSession? {
        guard let definition = session?.definition else { return nil }
        return newSession(definition)
    }

    // MARK: - definition queries

    /// Received exchange fields for a callsign (also for an empty one — the default set); empty outside a contest.
    public func exchangeFields(call: String) throws(ExpressionError) -> [ContestDefinition.ExchangeField] {
        guard let session else { return [] }
        return try session.activeReceivedFields(call: call)
    }

    /// Are all required fields filled in? (saving with Enter)
    public func isComplete(call: String, exchange: JavaLinkedMap<String>) throws(ContestSessionError) -> Bool {
        if KotlinText.isBlank(call) {
            return false
        }
        guard let session else { return false }
        return try session.exchangeComplete(call: call, receivedRaw: exchange)
    }

    /// Does the sent exchange carry my county (`ROVER_QTH`)? Only then the county counts into the dupe.
    public var usesRoverQth: Bool {
        guard let sent = session?.definition.exchange?.sent else { return false }
        return sent.contains { $0?.source == .ROVER_QTH }
    }

    /// Dupe scope of the active contest (`nil` outside a contest).
    public var dupeScope: ContestDefinition.Scope? {
        session?.definition.dupe?.scope
    }

    /// Band order of the active contest (row ordering); empty outside a contest.
    public var bandOrder: [String?] {
        session?.definition.bands ?? []
    }

    /// Main mode of the contest (prefill of the entry window).
    public var primaryMode: Mode {
        guard let modes = session?.definition.modes, let first = modes.first, let name = first else {
            return .cw
        }
        return Mode(rawValue: name) ?? Mode.from(adif: name) ?? .cw
    }

    /// More than one mode? Then the operator chooses the mode.
    public var isMultiMode: Bool {
        (session?.definition.modes?.count ?? 0) > 1
    }

    /// Does the exchange carry a serial number? `true` outside a contest. Drives the „Nr tx/rx" columns.
    public var usesSerial: Bool {
        guard let exchange = definition?.exchange else { return session == nil }
        let fields: [ContestDefinition.ExchangeField?] = (exchange.sent ?? []) + (exchange.received ?? [])
        return fields.contains { $0?.type == .SERIAL }
    }

    /// Does the contest receive anything beyond the report? `true` outside a contest. Drives the „Exchange" column.
    public var usesExchangeBeyondRst: Bool {
        guard let received = definition?.exchange?.received else { return session == nil }
        return received.contains { field in
            guard let field else { return false }
            return field.type != .RST && field.type != .RS
        }
    }

    // MARK: - preview, log, replay

    /// Preview without writing (highlighting while typing); keeps `lastPreview` on an error. No-op outside a contest.
    public func preview(call: String, band: String, mode: String, exchange: JavaLinkedMap<String>,
                        ownQth: String? = nil, at: Date = Date()) throws(ContestSessionError) {
        guard let session else {
            lastPreview = nil
            return
        }
        lastPreview = try session.preview(call: call, band: band, mode: mode, receivedRaw: exchange, ownQth: ownQth,
                                          at: at)
    }

    /// Counts a QSO into the live session and refreshes the score; `nil` outside a contest.
    @discardableResult
    public func log(call: String, band: String, mode: String, exchange: JavaLinkedMap<String>, ownQth: String? = nil,
                    at: Date = Date()) throws(ContestSessionError) -> ContestSession.LogResult? {
        guard let session else {
            refreshScore()
            return nil
        }
        let result = try session.log(call: call, band: band, mode: mode, receivedRaw: exchange, at: at, ownQth: ownQth)
        refreshScore()
        return result
    }

    /// Replays logged QSOs into the live session (score after a contest is opened) and refreshes the score.
    public func replayLogged(_ qsos: [Qso]) {
        guard let session else { return }
        Self.replayLogged(qsos, into: session)
        refreshScore()
    }

    /// Kotlin `replayLogged` over a session: X-QSOs are left out, the order is the caller's, a QSO without a band
    /// goes through as `""` (the session does not count it), an error of one QSO is swallowed (`runCatching`).
    /// Unlike `ContestReplay` it neither sorts nor skips deleted QSOs or empty callsigns. Safe off the main actor.
    public static func replayLogged(_ qsos: [Qso], into session: ContestSession) {
        for q in qsos where !q.xqso {
            let band: String = q.band?.adif ?? ""
            let ownQth: String? = session.ownQthFromSent(q.exchangeSent)
            _ = try? session.replayLogged(call: q.call, band: band, mode: q.mode?.rawValue ?? "",
                                          exchangeRcvdFlat: q.exchangeRcvd, serialRcvd: q.serialRcvd,
                                          at: q.timestampUtc, ownQth: ownQth)
        }
    }

    /// Recount (N1MM Rescore) into a new session; the live one stays. `nil` outside a contest.
    public func replayed(_ qsos: [Qso], now: () -> Date = Date.init) -> ContestReplay.Outcome? {
        guard let fresh = freshSession() else { return nil }
        return ContestReplay.replay(fresh, qsos, now: now)
    }

    /// Score recomputed from zero in a separate session (CLAIMED-SCORE in Cabrillo); `nil` outside a contest.
    public func freshScore(_ qsos: [Qso]) throws(ExpressionError) -> ScoreState? {
        guard let outcome = replayed(qsos) else { return nil }
        return try outcome.session.score()
    }

    /// Points, dupe and new multipliers of every QSO (log table columns); empty outside a contest.
    public func qsoMarks(_ qsos: [Qso]) -> [Int64: QsoMarks.Mark] {
        guard let fresh = freshSession() else { return [:] }
        return QsoMarks.compute(fresh, qsos)
    }

    /// Takes a recounted session over as the live one. When the contest was switched meanwhile (or `forContestId`
    /// is `nil`) the result is dropped — it belongs to another log. The log revision is checked by
    /// `RescoreScheduler.finish` before this call.
    @discardableResult
    public func adopt(_ outcome: ContestReplay.Outcome, forContestId: String?) -> Bool {
        guard let forContestId, let activeId, JavaText.equals(forContestId, activeId) else { return false }
        install(outcome.session)
        return true
    }

    /// Result of `adopt(session:forContestId:replayedRevision:currentRevision:)`.
    public enum ReplayAdoption: Equatable, Sendable {
        /// The replayed session is now the live one.
        case adopted
        /// The log changed since the replay snapshot was taken (a QSO was logged into the live session meanwhile):
        /// nothing was adopted — replay the current log again (or route it through `RescoreScheduler`).
        case stale
        /// Another contest is active (or none) — the result belongs to another log and is dropped.
        case otherContest
    }

    /// Adopts a session replayed off the owning actor with `replayLogged(_:into:)` (activation, `replayLog`).
    ///
    /// Kotlin replays synchronously on the UI thread, so nothing can be logged between the replay and the live
    /// session. Off the owner a QSO may be logged into the old live session meanwhile; adopting the replay would lose
    /// it. Hence the guard: `replayedRevision` is the log revision of the replayed snapshot, `currentRevision` the
    /// log revision now; a mismatch returns `.stale` and keeps the live session — the owner must replay the current
    /// log again (a new `freshSession()` + snapshot) or request a recount.
    public func adopt(session replayed: ContestSession, forContestId: String?, replayedRevision: Int64,
                      currentRevision: Int64) -> ReplayAdoption {
        guard let forContestId, let activeId, JavaText.equals(forContestId, activeId) else { return .otherContest }
        if replayedRevision != currentRevision {
            return .stale
        }
        install(replayed)
        return .adopted
    }

    private func install(_ replayed: ContestSession) {
        session = replayed
        sessionGeneration &+= 1
        lastPreview = nil
        refreshScore()
    }

    // MARK: - definition snapshot

    /// Raw YAML of a definition from the live directory (for the snapshot); `nil` when unreadable or not UTF-8.
    public func rawYaml(definitionId: String) -> String? {
        Self.rawYaml(contestsDir: contestsDir, definitionId: definitionId)
    }

    /// `rawYaml` without the runtime (blocking file read for a background queue).
    public static func rawYaml(contestsDir: URL?, definitionId: String) -> String? {
        guard let contestsDir else { return nil }
        let file: URL = contestsDir.appendingPathComponent(definitionId + ".yaml")
        guard let data = try? Data(contentsOf: file) else { return nil }
        return ScoreCheck.decode(data)
    }

    /// Parses a definition from a YAML snapshot.
    public static func parseDefinition(_ yaml: String) throws(ContestDefinitionError) -> ContestDefinition {
        try ContestDefinitionLoader.load(Data(yaml.utf8))
    }

    private func refreshScore() {
        guard let session else {
            score = nil
            scoreError = nil
            return
        }
        do {
            score = try session.score()
            scoreError = nil
        } catch {
            score = nil
            scoreError = error
        }
    }
}
