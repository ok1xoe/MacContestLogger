import Foundation
import os

/// Live contest session error — the **single type** for everything Java `ContestSession` lets
/// propagate (`log`, `preview`, `replayLogged`, `exchangeComplete`, `multiplierGrid`), so that a
/// logbook replay (`ContestReplay`) can count `skipped` per QSO and continue.
public enum ContestSessionError: Error, Equatable, Sendable, CustomStringConvertible {
    /// An expression in the definition (points, bonus, condition, station class): Java `IllegalArgumentException`,
    /// `NumberFormatException`, `PatternSyntaxException`; additionally Swift nesting above 12.
    case expression(ExpressionError)
    /// A number above 2³¹−1 in a numeric exchange field (Java `NumberFormatException`).
    case exchange(ExchangeError)
    /// Unknown multiplier set (Java `MultiplierException`).
    case multiplier(MultiplierError)

    init(_ error: QsoContextError) {
        switch error {
        case .expression(let e): self = .expression(e)
        case .exchange(let e): self = .exchange(e)
        }
    }

    /// Text of the Java exception (`getMessage()`).
    public var message: String {
        switch self {
        case .expression(let e): return e.message
        case .exchange(let e): return e.message
        case .multiplier(let e): return e.message
        }
    }

    public var description: String { message }
}

/// Runtime state of a contest: ties together the definition, my station, multiplier sets and evaluators. `log`
/// counts a QSO (points + multipliers + dupe + bonuses), `preview` evaluates without side effects
/// (for the UI while typing), `score` returns the current score. Port of Java `runtime/ContestSession.java`.
///
/// **A `final class`, not a struct:** the session holds a `QsoContextFactory` (a class with the bonus-station
/// predicate); copies of a struct would share it and `setBonusStations` would leak into the copies.
///
/// **`Sendable` with a lock.** Java builds the session in the background (logbook replay) and the main thread
/// takes the finished one over (`ContestReplay` → `adopt`), then the UI touches it. All mutable
/// state (the tracker in the evaluator, dupe, totals, awarded bonuses, TOUR, bonus stations) is therefore
/// in one value behind an `OSAllocatedUnfairLock`; `log` holds the lock for the whole write, so
/// concurrent writes are serialized and nothing gets lost. A "non-`Sendable` + `sending`" variant
/// is not enough: `Task.detached` returns only a `Sendable` result. The other parts (`QsoContextFactory`,
/// `MultiplierSetRegistry`, `DxccLookup`, the definition) are `Sendable`.
/// **`MultiplierSetRegistry.loadDir` is not called on a registry shared with a session** — the registry is
/// filled at construction (as in Java) and the session then only reads it.
///
/// Java behaviour that is copied:
/// - **non-transactional `log`**: an error in a bonus expression after multipliers were written leaves the
///   multipliers in the tracker (also the bonuses awarded before it, and the bonus key whose value threw), the QSO
///   is not counted, not even into the dupe;
/// - a QSO without a band (`nil`/Java `isBlank`) and in a mode the contest does not have is not counted
///   (`counted == false`) and not written into the dupe either;
/// - `evaluator.commit` also for a dupe, bonuses only for a non-dupe; a dupe has 0 points unless
///   `dupeWorthZero` is `false`;
/// - a bonus once per key `id|scopeKey` (`id` `nil` → the text `null`), the first occurrence wins
///   (even with value 0); the `qsoPoints`/`bonusPoints` totals in `long` without wrapping in the real
///   range, `qsoCount` is `int`;
/// - `preview` does not zero dupe points and checks neither band nor mode; it judges the dupe at time `at`
///   (default "now" = Java `Instant.now()`).
public final class ContestSession: Sendable {

    /// Result of writing a QSO to the score. `counted == false`: the QSO was not counted into the score
    /// (a missing band, or a mode the contest does not have).
    public struct LogResult: Sendable {
        public let context: QsoContext
        /// Java `int`.
        public let points: Int32
        public let dupe: Bool
        public let multipliers: [MultiplierEvalResult]
        public let counted: Bool

        public init(context: QsoContext, points: Int32, dupe: Bool, multipliers: [MultiplierEvalResult],
                    counted: Bool = true) {
            self.context = context
            self.points = points
            self.dupe = dupe
            self.multipliers = multipliers
            self.counted = counted
        }
    }

    /// One row of the multiplier grid: a value + the bands on which it is worked (band order
    /// as in the parameter, without repeats — Java `LinkedHashSet`).
    public struct GridRow: Equatable, Sendable {
        public let key: String?
        public let label: String?
        public let prefix: String
        public let continent: String
        public let workedBands: [String]
    }

    /// Multiplier grid of the given type for the UI (worked per band). `possible == -1` for a set that
    /// cannot be enumerated.
    public struct MultiplierGrid: Equatable, Sendable {
        public let available: Bool
        public let worked: Int32
        public let possible: Int32
        public let rows: [GridRow]

        public static let unavailable = MultiplierGrid(available: false, worked: 0, possible: 0, rows: [])
    }

    /// Mutable session state (behind a lock). Bonus keys and bonus stations by UTF-16
    /// (Java `HashSet<String>`), not by Swift's canonical equality.
    private struct State: Sendable {
        var evaluator: MultiplierEvaluator
        var dupe: ContestDupeChecker
        var qsoPoints: Int64 = 0
        var bonusPoints: Int64 = 0
        var qtcCount: Int32 = 0
        var qsoCount: Int32 = 0
        var bonusesAwarded: Set<[UInt16]> = []
        var tour: Tour?
        var bonusCalls: [String] = []
    }

    public let definition: ContestDefinition
    private let exchange = ExchangeEngine()
    private let factory: QsoContextFactory
    private let registry: MultiplierSetRegistry
    private let state: OSAllocatedUnfairLock<State>

    public init(definition: ContestDefinition, dxcc: any DxccLookup, registry: MultiplierSetRegistry,
                myCall: String?, myGrid: String? = nil, myItuZone: String? = nil) {
        self.definition = definition
        self.factory = QsoContextFactory(definition: definition, dxcc: dxcc, exchange: exchange, myCall: myCall,
                                         myGrid: myGrid, myItuZone: myItuZone)
        self.registry = registry
        self.state = OSAllocatedUnfairLock(initialState: State(evaluator: MultiplierEvaluator(registry: registry),
                                                               dupe: ContestDupeChecker(definition: definition)))
    }

    // MARK: - exchange

    /// Active received exchange fields for a callsign (by the other station's class). Throws the `stationClasses`
    /// expression error like Java.
    public func activeReceivedFields(call: String?) throws(ExpressionError) -> [ContestDefinition.ExchangeField] {
        exchange.activeReceivedFields(definition, try factory.workedClass(call))
    }

    /// Are all required received fields for this callsign filled in and valid? `receivedRaw == nil`
    /// → all fields `""`; a key with a `nil` value → a `nil` input (Java `getOrDefault`).
    /// Throws like Java: a station-class expression, a number above 2³¹−1.
    public func exchangeComplete(call: String?, receivedRaw: JavaLinkedMap<String>?) throws(ContestSessionError) -> Bool {
        let fields: [ContestDefinition.ExchangeField]
        do {
            fields = try activeReceivedFields(call: call)
        } catch {
            throw .expression(error)
        }
        for field in fields where field.required {
            let raw: String?
            if let receivedRaw {
                raw = receivedRaw.containsKey(field.id) ? receivedRaw[field.id] : ""
            } else {
                raw = ""
            }
            do {
                if !(try exchange.parse(field, raw).valid) {
                    return false
                }
            } catch {
                throw .exchange(error)
            }
        }
        return true
    }

    /// My county from the QSO's stored sent exchange (a field with source `ROVER_QTH`); `nil` when the contest
    /// has no rover county or the token is `-`. The token is not changed (upper-casing is done by the factory).
    ///
    /// A `nil` field in `exchange.sent`: Java NPE; Swift keeps the index (the field = "is not `ROVER_QTH`"),
    /// tokens do not shift (a deliberate divergence from Java v1.1.1).
    public func ownQthFromSent(_ exchangeSentFlat: String?) -> String? {
        guard let exchangeSentFlat, !JavaText.isBlank(exchangeSentFlat),
              let sent = definition.exchange?.sent else { return nil }
        let tokens = JavaText.split(JavaText.trim(exchangeSentFlat), regex: Self.whitespace, limit: 0)
        for index in 0..<min(sent.count, tokens.count) where sent[index]?.source == .ROVER_QTH {
            return JavaText.equals("-", tokens[index]) ? nil : tokens[index]
        }
        return nil
    }

    /// Received exchange from the stored flat form (values of the active fields in order, Java
    /// `split("\\s+")` after `trim()`) + the serial number as `putIfAbsent("nr", …)` — literally
    /// the key `nr`. Excess tokens are dropped, missing fields are not inserted.
    public func receivedFromFlat(call: String?, exchangeRcvdFlat: String?,
                                 serialRcvd: Int?) throws(ExpressionError) -> JavaLinkedMap<String> {
        var received = JavaLinkedMap<String>()
        let fields = try activeReceivedFields(call: call)
        let flat = exchangeRcvdFlat.map(JavaText.trim) ?? ""
        let tokens = flat.isEmpty ? [] : JavaText.split(flat, regex: Self.whitespace, limit: 0)
        for index in 0..<min(fields.count, tokens.count) {
            received.put(fields[index].id, tokens[index])
        }
        if let serialRcvd, received["nr"] == nil {
            received.put("nr", String(serialRcvd))
        }
        return received
    }

    /// Java `"\\s+"` (ASCII whitespace only).
    private static let whitespace: JavaRegex = {
        do {
            return try JavaRegex("\\s+")
        } catch {
            preconditionFailure("pevný vzor '\\s+' musí jít zkompilovat: \(error)")
        }
    }()

    // MARK: - multipliers for the UI

    /// Multiplier grid for the first binding (in definition order) whose set passes the predicate
    /// (set type or its id). An enumerable set (DXCC, zones) → rows = all values
    /// in set order; otherwise (grid field, WPX) only the worked keys from the tracker and
    /// `possible == -1`. Without such a multiplier `MultiplierGrid.unavailable`.
    ///
    /// As in Java: the set is taken from the registry **before** the predicate, so an unknown set throws
    /// (`MultiplierError`); the mode for the scope is the definition's first mode (`CW` without modes); scope
    /// `ONCE` → worked on all bands. A `nil` binding: Java NPE, Swift skips.
    public func multiplierGrid(bands: [Band],
                               matching: (ContestDefinition.MultiplierBinding, any MultiplierSet) -> Bool)
        throws(ContestSessionError) -> MultiplierGrid {
        guard let multipliers = definition.multipliers else { return .unavailable }
        var selected: (binding: ContestDefinition.MultiplierBinding, set: any MultiplierSet)?
        for case let binding? in multipliers {
            let set: any MultiplierSet
            do {
                set = try registry.get(binding.set)
            } catch {
                throw .multiplier(error)
            }
            if matching(binding, set) {
                selected = (binding, set)
                break
            }
        }
        guard let selected else { return .unavailable }
        let binding = selected.binding
        let set = selected.set

        // scopeKey for each band (PER_BAND → band, ONCE → "*").
        let modes = definition.modes ?? []
        let mode: String? = modes.isEmpty ? "CW" : modes[0]
        var scopeKeys: [String] = []
        for band in bands {
            let context: QsoContext
            do {
                context = try factory.build(call: "", band: band.adif, mode: mode, receivedRaw: JavaLinkedMap())
            } catch {
                throw ContestSessionError(error)
            }
            scopeKeys.append(MultiplierEvaluator.scopeKey(binding.scope, context))
        }
        let tracker = self.tracker
        func workedBands(_ key: String?) -> [String] {
            var out: [String] = []
            for (index, band) in bands.enumerated()
            where tracker.isWorked(binding.id, scopeKeys[index], key) && !out.contains(band.adif) {
                out.append(band.adif)
            }
            return out
        }
        // "Enumerable" for the grid = has enumerated values (a grid field has them empty,
        // even though `enumerable` returns true → it is taken as non-enumerable).
        let canEnumerate = set.enumerable && !set.values.isEmpty
        var rows: [GridRow] = []
        if canEnumerate {
            for value in set.values {
                rows.append(GridRow(key: value.key, label: value.label, prefix: value.attributes["prefix"] ?? "",
                                    continent: value.attributes["continent"] ?? "", workedBands: workedBands(value.key)))
            }
        } else {
            // Tracker keys are already sorted by UTF-16 (Java Collections.sort).
            for key in tracker.keysForBinding(binding.id) {
                rows.append(GridRow(key: key, label: key, prefix: "", continent: "", workedBands: workedBands(key)))
            }
        }
        let possible: Int32 = canEnumerate ? Int32(truncatingIfNeeded: set.values.count) : -1
        return MultiplierGrid(available: true, worked: tracker.distinctForBinding(binding.id), possible: possible,
                              rows: rows)
    }

    /// Labels of the set's values for the „Mult" column: key → country prefix (`OM`), only non-empty
    /// ones (Java `isBlank`). An unregistered set or a `nil` id → empty.
    ///
    /// The map is Java's (keys by UTF-16, not canonical): the values `K` and KELVIN SIGN each have
    /// their own label, a Swift dictionary would merge them and foreign text would go into the „Mult" column.
    /// The same key twice → the later one wins (Java `HashMap.put`). The order is the order of
    /// the set's values (Java `Map.copyOf` has none; callers only look up).
    ///
    /// A value with a `nil` key and a prefix: Java NPE in `Map.copyOf`; Swift omits it
    /// (a deliberate divergence from Java v1.1.1).
    public func multiplierLabels(setId: String?) -> JavaLinkedMap<String> {
        var out = JavaLinkedMap<String>()
        guard let setId, registry.contains(setId), let set = try? registry.get(setId) else { return out }
        for value in set.values {
            guard let key = value.key, let prefix = value.attributes["prefix"], !JavaText.isBlank(prefix) else {
                continue
            }
            out.put(key, prefix)
        }
        return out
    }

    // MARK: - TOUR and bonus stations

    /// TOUR session: dupe only within a session. Applies to further writes — when it changes the
    /// contest must be recomputed (a new session).
    public func setTour(_ tour: Tour?) {
        state.withLock {
            $0.tour = tour
            $0.dupe.tour = tour
        }
    }

    public var tour: Tour? {
        state.withLock { $0.tour }
    }

    /// List of bonus stations (N1MM BONUS). The callsign base is enough — W1AW also applies to W1AW/M.
    /// A `nil` list → empty; `nil` and empty bases are omitted.
    public func setBonusStations(_ calls: [String?]?) {
        var list: [String] = []
        var keys: Set<[UInt16]> = []
        for call in calls ?? [] {
            let base = Self.baseCall(call)
            if !base.isEmpty, keys.insert(Array(base.utf16)).inserted {
                list.append(base)
            }
        }
        let sorted = list.sorted { $0.utf16.lexicographicallyPrecedes($1.utf16) }
        state.withLock { $0.bonusCalls = sorted }
        let frozen = keys
        factory.setBonusPredicate { frozen.contains(Array(ContestSession.baseCall($0).utf16)) }
    }

    /// Bonus stations (callsign bases), sorted by UTF-16. Java `Set.copyOf` has no order.
    public var bonusStations: [String] {
        state.withLock { $0.bonusCalls }
    }

    /// Keys of awarded bonuses (`id|scopeKey`) — only for gate-coverage tests (which bonus
    /// was awarded in a step); the Java session does not expose them.
    var awardedBonusKeys: Set<String> {
        state.withLock { state in Set(state.bonusesAwarded.map { String(decoding: $0, as: UTF16.self) }) }
    }

    /// Callsign without suffixes after the slash (`W1AW/M` → `W1AW`); the prefix before the slash (`OK/DL1ABC`)
    /// is kept. Java `trim().toUpperCase()`, `split("/")` (trailing empty parts dropped)
    /// and the longest part that `matches(".*\\d.*")` (an ASCII digit, `.` does not cross a line end),
    /// the first on equal length; none → the whole callsign.
    static func baseCall(_ call: String?) -> String {
        guard let call else { return "" }
        let c = JavaText.trim(call).uppercased()
        var parts: [[UInt16]] = [[]]
        for unit in c.utf16 {
            if unit == 0x2F {
                parts.append([])
            } else {
                parts[parts.count - 1].append(unit)
            }
        }
        while let last = parts.last, last.isEmpty, parts.count > 1 || !c.isEmpty {
            parts.removeLast()
        }
        var best: [UInt16] = []
        for part in parts where hasDigitOnOneLine(part) && part.count > best.count {
            best = part
        }
        return best.isEmpty ? c : JavaChar.string(best)
    }

    /// Java `s.matches(".*\\d.*")`: at least one ASCII digit and no Java line end
    /// (`\n`, `\r`, U+0085, U+2028, U+2029), which `.` does not cross.
    private static func hasDigitOnOneLine(_ units: [UInt16]) -> Bool {
        var digit = false
        for unit in units {
            switch unit {
            case 0x0A, 0x0D, 0x85, 0x2028, 0x2029: return false
            case 0x30...0x39: digit = true
            default: break
            }
        }
        return digit
    }

    // MARK: - preview and write

    /// Preview (without writing) — for highlighting in the UI while typing. Dupe at time `at` (default "now").
    public func preview(call: String?, band: String?, mode: String?, receivedRaw: JavaLinkedMap<String>?,
                        ownQth: String? = nil, at: Date = Date()) throws(ContestSessionError) -> LogResult {
        let context = try build(call, band, mode, receivedRaw, ownQth, at)
        let points: Int32
        do {
            points = try PointsCalculator.points(definition, context)
        } catch {
            throw .expression(error)
        }
        let second = Tour.epochSecond(of: at)
        let (dupe, evaluator) = state.withLock { ($0.dupe.isDupe(context, atEpochSecond: second), $0.evaluator) }
        do {
            return LogResult(context: context, points: points, dupe: dupe,
                             multipliers: try evaluator.preview(definition, context))
        } catch {
            throw .multiplier(error)
        }
    }

    /// Counts a QSO into the score at time `at` (TOUR session; default "now", `nil` = Java `null`
    /// `Instant` — the session is not counted). See the type description.
    ///
    /// The DXCC data are evaluated as of `dxccAt`, else `at` (else now) — only Club Log's `cty.xml` has
    /// date-ranged records, the other sources ignore the date.
    @discardableResult
    public func log(call: String?, band: String?, mode: String?, receivedRaw: JavaLinkedMap<String>?,
                    at: Date? = Date(), ownQth: String? = nil,
                    dxccAt: Date? = nil) throws(ContestSessionError) -> LogResult {
        try log(call: call, band: band, mode: mode, receivedRaw: receivedRaw,
                atEpochSecond: at.map { Tour.epochSecond(of: $0) }, ownQth: ownQth, dxccAt: dxccAt ?? at)
    }

    /// `log` with the time in epoch seconds (exact like Java `Instant`).
    @discardableResult
    public func log(call: String?, band: String?, mode: String?, receivedRaw: JavaLinkedMap<String>?,
                    atEpochSecond: Int64?, ownQth: String? = nil,
                    dxccAt: Date? = nil) throws(ContestSessionError) -> LogResult {
        let date: Date? = dxccAt ?? atEpochSecond.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        let context = try build(call, band, mode, receivedRaw, ownQth, date)
        guard let band, !JavaText.isBlank(band) else {
            // A QSO without a band cannot be scored or assigned to per-band multipliers, and the logbook
            // replay omits it (the live score must match the replayed one).
            return LogResult(context: context, points: 0, dupe: false, multipliers: [], counted: false)
        }
        if !ModeEligibility.counts(definition.modes, mode) {
            // A mode the contest does not have (typically FT8 received from WSJT-X into a CW contest).
            return LogResult(context: context, points: 0, dupe: false, multipliers: [], counted: false)
        }
        let definition = self.definition
        let outcome = state.withLock { state in
            Self.commit(definition, context, atEpochSecond, &state)
        }
        return try outcome.get()
    }

    /// Steps of Java `log` after the band and mode checks, under the lock. Mutations of `state` before an
    /// error stay (non-transactional like Java).
    private static func commit(_ definition: ContestDefinition, _ context: QsoContext, _ at: Int64?,
                               _ state: inout State) -> Result<LogResult, ContestSessionError> {
        let isDupe = state.dupe.isDupe(context, atEpochSecond: at)
        let points: Int32
        if isDupe && (definition.dupe?.dupeWorthZero ?? true) {
            points = 0
        } else {
            do {
                points = try PointsCalculator.points(definition, context)
            } catch {
                return .failure(.expression(error))
            }
        }
        let multipliers: [MultiplierEvalResult]
        do {
            multipliers = try state.evaluator.commit(definition, context)
        } catch {
            return .failure(.multiplier(error))
        }
        if !isDupe {
            do {
                try awardBonuses(definition, context, &state)
            } catch {
                return .failure(.expression(error))
            }
        }
        state.dupe.add(context, atEpochSecond: at)
        state.qsoPoints = JavaMath.addLong(state.qsoPoints, Int64(points))
        state.qsoCount = JavaMath.addInt(state.qsoCount, 1)
        return .success(LogResult(context: context, points: points, dupe: isDupe, multipliers: multipliers))
    }

    /// Bonuses from the definition (`scoring.bonuses`): condition met → points once per `id|scopeKey`.
    /// The key is written **before** computing the value (if the value throws, the key stays without points).
    ///
    /// A `nil` element of `bonuses`: Java NPE (bonuses already awarded before it stay); Swift skips it
    /// (a deliberate divergence from Java v1.1.1).
    private static func awardBonuses(_ definition: ContestDefinition, _ context: QsoContext,
                                     _ state: inout State) throws(ExpressionError) {
        guard let bonuses = definition.scoring?.bonuses else { return }
        for case let bonus? in bonuses {
            if !(try ConditionEvaluator.eval(bonus.when, context)) {
                continue
            }
            let scope = bonus.scope ?? .ONCE
            let key = (bonus.id ?? "null") + "|" + MultiplierEvaluator.scopeKey(scope, context)
            if state.bonusesAwarded.insert(Array(key.utf16)).inserted {
                let value = try PointsCalculator.value(bonus.value, context)
                state.bonusPoints = JavaMath.addLong(state.bonusPoints, Int64(value))
            }
        }
    }

    /// Re-counts a previously logged QSO (restoring state after a contest is opened): the received exchange
    /// from the flat form (`receivedFromFlat`) + `log`. Time `nil` → "now" (Java `at == null`).
    @discardableResult
    public func replayLogged(call: String?, band: String?, mode: String?, exchangeRcvdFlat: String?,
                             serialRcvd: Int?, at: Date? = nil,
                             ownQth: String? = nil) throws(ContestSessionError) -> LogResult {
        try replayLogged(call: call, band: band, mode: mode, exchangeRcvdFlat: exchangeRcvdFlat,
                         serialRcvd: serialRcvd, atEpochSecond: at.map { Tour.epochSecond(of: $0) }, ownQth: ownQth)
    }

    /// `replayLogged` with the time in epoch seconds; `nil` → "now".
    @discardableResult
    public func replayLogged(call: String?, band: String?, mode: String?, exchangeRcvdFlat: String?,
                             serialRcvd: Int?, atEpochSecond: Int64?,
                             ownQth: String? = nil) throws(ContestSessionError) -> LogResult {
        let received: JavaLinkedMap<String>
        do {
            received = try receivedFromFlat(call: call, exchangeRcvdFlat: exchangeRcvdFlat, serialRcvd: serialRcvd)
        } catch {
            throw .expression(error)
        }
        return try log(call: call, band: band, mode: mode, receivedRaw: received,
                       atEpochSecond: atEpochSecond ?? Tour.epochSecond(of: Date()), ownQth: ownQth)
    }

    private func build(_ call: String?, _ band: String?, _ mode: String?, _ receivedRaw: JavaLinkedMap<String>?,
                       _ ownQth: String?, _ date: Date?) throws(ContestSessionError) -> QsoContext {
        do {
            return try factory.build(call: call, band: band, mode: mode, receivedRaw: receivedRaw, ownQth: ownQth,
                                     at: date)
        } catch {
            throw ContestSessionError(error)
        }
    }

    // MARK: - QTC and score

    /// Sets the QTC count (sent and received) — from the logbook's QTC table; negative → 0.
    public func setQtcCount(_ count: Int32) {
        state.withLock { $0.qtcCount = max(0, count) }
    }

    public var qtcCount: Int32 {
        state.withLock { $0.qtcCount }
    }

    /// Worked multipliers (a snapshot of the evaluator's tracker).
    public var tracker: MultiplierTracker {
        state.withLock { $0.evaluator.tracker }
    }

    /// Score by `scoring.total`. QTC points = `(long) qtcCount * qtc.points` (without `scoring.qtc`
    /// zero). A formula expression error propagates (also nesting above 12 — never a silent zero).
    public func score() throws(ExpressionError) -> ScoreState {
        let snapshot = state.withLock { ($0.qsoPoints, $0.bonusPoints, $0.qtcCount, $0.qsoCount, $0.evaluator.tracker) }
        let (qsoPoints, bonusPoints, qtcCount, qsoCount, tracker) = snapshot
        var qtcPoints: Int64 = 0
        if let qtc = definition.scoring?.qtc {
            qtcPoints = JavaMath.multiplyLong(Int64(qtcCount), Int64(qtc.pointsOrDefault))
        }
        return try ScoreEngine.compute(definition, qsoPoints: qsoPoints, bonusPoints: bonusPoints,
                                       qtcPoints: qtcPoints, qsoCount: qsoCount, tracker: tracker)
    }
}
