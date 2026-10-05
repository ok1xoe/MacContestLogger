import Foundation
import os

/// The spot analysis of the Kotlin `ContestController` (`ui/contest/ContestController.kt:19-65, 100-199, 484-747`,
/// v1.1.1) moved into the core: spot status (dupe / new multipliers), spot mode and category, band-plan category
/// and segments, the grid of a spot, exchange prediction, the rows of the Available window, the multiplier grid
/// and the grid tooltip.
///
/// **A `Sendable` snapshot.** It captures the live `ContestSession` (itself `Sendable`), the DXCC lookup, the HQ
/// callsign map, the band plan, the digi frequencies, the offline grid database, the field → DXCC map, a
/// callbook lookup and my station; it holds no state of its own except the shared `SpotGridLog`. Kotlin reads all
/// of these live on every call, so the snapshot must be **rebuilt** whenever one of them changes:
/// - contest activation, deactivation and every `ContestRuntime.adopt` (rescore, activation replay) — the live
///   session is replaced (`ContestRuntime.sessionGeneration` changes);
/// - a change of my station call or grid (region of the band plan, azimuth);
/// - a band-data reload (Kotlin `reloadBandData`: band plan, digi frequencies) and a new grid database or field map;
/// - a swap of the callbook lookup (a closure reading a live cache needs no rebuild for new cache entries).
/// QSOs logged into the same live session are seen without a rebuild (the session is shared, behind its lock).
/// `isCurrent(for:)` covers the first two triggers; the others are known to the caller that changes them.
///
/// Kotlin behaviour that is kept (measured by a maintainer-only probe):
/// - outside a contest: neutral status, no rows, an unavailable grid, an empty prediction; the mode still resolves
///   (primary mode CW) and the tooltip still renders;
/// - a spot whose mode is determined and outside the contest modes (CW in a digi contest) is neutral, its row has
///   no multiplier and no dupe, and the grid ignores it; an undeterminable mode is evaluated;
/// - the spot mode: comment → digi calibration frequency → band plan of the **DX** region → primary mode; the
///   band-plan category and segments use **my** region;
/// - the grid of a spot: comment (verified against the call's DXCC) → offline CSV → callbook; the callbook CQ/ITU
///   zone overrides the DXCC estimate of a `CQ_ZONE`/`ITU_ZONE` field;
/// - the decision log is written once per callsign (upper case) and only in a grid contest; `SpotGridLog.reset()`
///   is Kotlin `gridLogged.clear()` on activation;
/// - rows are sorted by frequency (stable); a spot without a band is skipped; the SNR is the first `(\d+)\s*dB`
///   (ASCII digits, an `Int` overflow → none).
///
/// Kotlin crashes not reproduced: a preview error (an expression error of the scoring) propagates out of the
/// Kotlin controller into Compose; here `spotStatus` is neutral, `spotRows` skips the spot and `multiplierGrid`
/// is unavailable when the session grid throws. A `nil` element of the definition's lists (a Kotlin NPE) is
/// skipped.
public struct SpotAnalyzer: Sendable {

    /// Bands of the multiplier grid (Kotlin `MULT_GRID_BANDS`, `ContestController.kt:65-66`).
    public static let multGridBands: [Band] = [.m160, .m80, .m40, .m20, .m15, .m10]

    let session: ContestSession?
    let dxcc: (any DxccLookup)?
    let hqCalls: JavaLinkedMap<String>
    let bandPlan: BandPlan
    let digiFrequencies: DigiFrequencies
    let gridDatabase: GridDatabase
    let gridFieldMap: (any GridFieldLookup)?
    let callbook: @Sendable (String) -> HamQthRecord?
    let gridLog: SpotGridLog?
    let myCall: String
    let myGrid: String
    let primaryModeName: String
    let now: @Sendable () -> Date
    let sessionGeneration: UInt64

    /// - Parameters:
    ///   - runtime: the contest runtime (its live session, DXCC, registry, my call and grid are captured now)
    ///   - gridDatabase: offline locators by callsign (Kotlin `gridFromCsv`)
    ///   - gridFieldMap: field → DXCC map for verifying a grid from a comment (Kotlin `gridFieldMap`)
    ///   - callbook: the merged callbook record of a callsign or `nil` (Kotlin `hamQthRecordFor`: the cache under
    ///     `callbookKey(call)`, an empty record is `nil`)
    ///   - gridLog: the decision log (HamQTH log window), or `nil` for none
    ///   - now: the time of the dupe check of a preview (Kotlin `Instant.now()`)
    public init(runtime: ContestRuntime, bandPlan: BandPlan = .defaultPlan(),
                digiFrequencies: DigiFrequencies = .defaultTable(), gridDatabase: GridDatabase = .empty,
                gridFieldMap: (any GridFieldLookup)? = nil,
                callbook: @escaping @Sendable (String) -> HamQthRecord? = { _ in nil },
                gridLog: SpotGridLog? = nil, now: @escaping @Sendable () -> Date = { Date() }) {
        self.session = runtime.activeSession
        self.dxcc = runtime.dxccLookup
        self.hqCalls = Self.buildHqCalls(definition: runtime.activeSession?.definition,
                                         registry: runtime.multiplierRegistry)
        self.bandPlan = bandPlan
        self.digiFrequencies = digiFrequencies
        self.gridDatabase = gridDatabase
        self.gridFieldMap = gridFieldMap
        self.callbook = callbook
        self.gridLog = gridLog
        self.myCall = runtime.stationCall
        self.myGrid = runtime.stationGrid
        self.primaryModeName = runtime.primaryMode.rawValue
        self.now = now
        self.sessionGeneration = runtime.sessionGeneration
    }

    /// `false` when the runtime's live session was replaced or dropped since this snapshot (activation, `adopt`,
    /// deactivation) or my station call or grid changed — rebuild the analyzer then.
    public func isCurrent(for runtime: ContestRuntime) -> Bool {
        sessionGeneration == runtime.sessionGeneration && myCall == runtime.stationCall
            && myGrid == runtime.stationGrid
    }

    /// The definition of the active contest, `nil` outside a contest.
    public var definition: ContestDefinition? {
        session?.definition
    }

    /// The key of the callbook cache (Kotlin `call.trim().uppercase()`).
    public static func callbookKey(_ call: String) -> String {
        JavaText.toUpperCase(KotlinText.trim(call))
    }

    // MARK: - status

    /// Kotlin `spotStatus` (`:487-504`).
    public func spotStatus(_ spot: DxSpot) -> SpotStatus {
        guard let session else { return .neutral }
        let call: String = spot.dxCall
        if KotlinText.isBlank(call) {
            return .neutral
        }
        guard let band = Band.from(frequencyHz: spot.freqHz) else { return .neutral }
        if !isColorRelevant(spot) {
            return .neutral
        }
        let mode: String = resolveSpotMode(call: call, freqHz: spot.freqHz, comment: spot.comment)
        let received: [ContestDefinition.ExchangeField?] = session.definition.exchange?.received ?? []
        let estimated = SpotExchangeEstimator.estimate(received, call, dxcc, hqCalls: hqCalls)
        let exchange = withHamQth(spot, received, estimated)
        guard let result = try? session.preview(call: call, band: band.adif, mode: mode, receivedRaw: exchange,
                                                at: now()) else {
            return .neutral
        }
        return SpotStatus(dupe: result.dupe, newMultCount: Self.newMultCount(result))
    }

    /// Kotlin `r.multipliers().count { it.countsAsMultiplier() && it.isNew() }`.
    static func newMultCount(_ result: ContestSession.LogResult) -> Int {
        result.multipliers.filter { $0.countsAsMultiplier && $0.isNew }.count
    }

    /// Kotlin `isColorRelevant` (`:510-515`): the spot's category is in the contest's categories, or the spot's
    /// category is undeterminable, or no contest/modes.
    public func isColorRelevant(_ spot: DxSpot) -> Bool {
        guard let category = spotModeCategory(spot) else { return true }
        guard let modes = definition?.modes else { return true }
        var categories: Set<String> = []
        for case let mode? in modes {
            categories.insert(SpotModeCategory.of(mode))
        }
        return categories.contains(category)
    }

    // MARK: - mode and band plan

    /// Kotlin `spotModeCategory` (`:518-532`): comment mode → its category; a digi calibration frequency → DIGI;
    /// otherwise the band plan in the DX station's region; `nil` = undeterminable.
    public func spotModeCategory(_ spot: DxSpot) -> String? {
        if let mode = SpotModeParser.fromComment(spot.comment) {
            return SpotModeCategory.of(mode)
        }
        if digiFrequencies.isDigi(spot.freqHz) {
            return SpotModeCategory.digi
        }
        let region = BandPlan.IaruRegion.forContinent(dxcc?.resolve(spot.dxCall)?.primaryContinent)
        return bandPlan.modeAt(Int64(spot.freqHz), region)?.rawValue
    }

    /// Kotlin `spotCategory` (`:145`) — the HamQTH lookup filter.
    public func spotCategory(_ spot: DxSpot) -> String? {
        spotModeCategory(spot)
    }

    /// Kotlin `bandPlanCategory` (`:535-539`): the band-plan category at a frequency in **my** region.
    public func bandPlanCategory(_ freqHz: Int64) -> BandPlan.ModeCategory? {
        bandPlan.modeAt(freqHz, myRegion())
    }

    /// Kotlin `bandPlanSegments` (`:546-553`): the band-plan segments of a window in **my** region (band map).
    public func bandPlanSegments(lo loHz: Int64, hi hiHz: Int64) -> [BandPlan.Segment] {
        bandPlan.segmentsIn(loHz, hiHz, myRegion())
    }

    private func myRegion() -> BandPlan.IaruRegion {
        BandPlan.IaruRegion.forContinent(dxcc?.resolve(myCall)?.primaryContinent)
    }

    /// Kotlin `resolveSpotMode` (`:559-567`): comment → digi calibration frequency → band plan (DX region,
    /// `categoryToMode`) → the contest's primary mode (`CW` outside a contest).
    public func resolveSpotMode(call: String, freqHz: Int, comment: String?) -> String {
        if let mode = SpotModeParser.fromComment(comment) {
            return mode
        }
        if let mode = digiFrequencies.modeAt(freqHz) {
            return mode
        }
        let region = BandPlan.IaruRegion.forContinent(dxcc?.resolve(call)?.primaryContinent)
        if let category = bandPlan.modeAt(Int64(freqHz), region) {
            return Self.categoryToMode(category)
        }
        return primaryModeName
    }

    /// Kotlin `categoryToMode` (`:569-574`): CW → CW, PHONE → SSB, DIGI → RTTY.
    public static func categoryToMode(_ category: BandPlan.ModeCategory) -> String {
        switch category {
        case .cw: return "CW"
        case .phone: return "SSB"
        case .digi: return "RTTY"
        }
    }

    // MARK: - exchange prediction

    /// Kotlin `predictExchange` (`:151-158`): the DXCC/HQ estimate plus the grid and callbook zones; empty outside
    /// a contest or without received fields.
    public func predictExchange(_ spot: DxSpot) -> JavaLinkedMap<String> {
        guard let received = session?.definition.exchange?.received else { return JavaLinkedMap() }
        let estimated = SpotExchangeEstimator.estimate(received, spot.dxCall, dxcc, hqCalls: hqCalls)
        return withHamQth(spot, received, estimated)
    }

    /// Kotlin `needsHamQthLookup` (`:161-164`): a received field estimated as `grid`/`cqZone`/`ituZone` (exact
    /// text), or a grid multiplier.
    public var needsHamQthLookup: Bool {
        guard let received = session?.definition.exchange?.received else { return false }
        let kinds: [String] = ["grid", "cqZone", "ituZone"]
        let estimated: Bool = received.contains { field in
            guard let estimate = field?.estimate else { return false }
            return kinds.contains { JavaText.equals($0, estimate) }
        }
        return estimated || needsGridLookup
    }

    /// Kotlin `needsGridLookup` (`:197-198`): a multiplier over the set `grid_fields`.
    public var needsGridLookup: Bool {
        guard let multipliers = session?.definition.multipliers else { return false }
        return multipliers.contains { binding in
            guard let set = binding?.set else { return false }
            return JavaText.equals("grid_fields", set)
        }
    }

    /// Kotlin `withHamQth` (`:171-194`): the grid into the first `LOCATOR` field, the callbook CQ/ITU zone (non-blank)
    /// into the first `CQ_ZONE`/`ITU_ZONE` field (Kotlin `map + pair`: an existing key keeps its position).
    func withHamQth(_ spot: DxSpot, _ received: [ContestDefinition.ExchangeField?],
                    _ base: JavaLinkedMap<String>) -> JavaLinkedMap<String> {
        var out = base
        if let grid = gridForSpot(spot), let field = Self.firstField(received, .LOCATOR) {
            out.put(field.id, grid)
        }
        if let record = callbook(spot.dxCall) {
            if !KotlinText.isBlank(record.cqZone), let field = Self.firstField(received, .CQ_ZONE) {
                out.put(field.id, record.cqZone)
            }
            if !KotlinText.isBlank(record.ituZone), let field = Self.firstField(received, .ITU_ZONE) {
                out.put(field.id, record.ituZone)
            }
        }
        return out
    }

    private static func firstField(_ received: [ContestDefinition.ExchangeField?],
                                   _ type: ContestDefinition.FieldType) -> ContestDefinition.ExchangeField? {
        for case let field? in received where field.type == type {
            return field
        }
        return nil
    }

    // MARK: - grid of a spot

    /// Kotlin `gridForSpot` (`:114-142`): from the comment (verified against the call's DXCC and the field map),
    /// then the offline CSV, then the callbook (non-blank); `nil` when unknown. Logs the decision once per call
    /// in a grid contest.
    public func gridForSpot(_ spot: DxSpot) -> String? {
        let call: String = spot.dxCall
        let entity: DxccEntity? = dxcc?.resolve(call)
        let logThis: Bool = needsGridLookup && (gridLog?.claim(JavaText.toUpperCase(call)) ?? false)
        var logger: ((String) -> Void)?
        if logThis, let gridLog {
            let prefix: String = entity?.primaryPrefix ?? "?"
            gridLog.write(.verbatim("\(call) (\(prefix)): „\(spot.comment)“"))
            logger = { line in gridLog.write(.verbatim(line)) }
        }
        if let fromComment = GridComment.extractGrid(spot.comment, entity, fieldMap: gridFieldMap, log: logger) {
            if logThis {
                gridLog?.write(ContestMessage("  → %s (z těla zprávy)", .string(fromComment)))
            }
            return fromComment
        }
        if let fromCsv = gridDatabase.grid(Self.callbookKey(call)) {
            if logThis {
                gridLog?.write(.verbatim("  → \(fromCsv) (z CSV)"))
            }
            return fromCsv
        }
        if let grid = callbook(call)?.grid, !KotlinText.isBlank(grid) {
            if logThis {
                gridLog?.write(.verbatim("  → \(grid) (z callbooku)"))
            }
            return grid
        }
        if logThis {
            gridLog?.write(ContestMessage("  → grid nezjištěn"))
        }
        return nil
    }

    // MARK: - spot rows

    /// Kotlin `spotRows` (`:577-607`): one row per spot with a band, sorted by frequency (stable).
    public func spotRows(_ spots: [DxSpot]) -> [SpotRow] {
        guard let session else { return [] }
        let myLatLon = dxcc == nil ? nil : Maidenhead.centerLatLon(myGrid)
        let received: [ContestDefinition.ExchangeField?] = session.definition.exchange?.received ?? []
        var rows: [SpotRow] = []
        for spot in spots {
            guard let band = Band.from(frequencyHz: spot.freqHz) else { continue }
            let mode: String = resolveSpotMode(call: spot.dxCall, freqHz: spot.freqHz, comment: spot.comment)
            let estimated = SpotExchangeEstimator.estimate(received, spot.dxCall, dxcc, hqCalls: hqCalls)
            let exchange = withHamQth(spot, received, estimated)
            guard let result = try? session.preview(call: spot.dxCall, band: band.adif, mode: mode,
                                                    receivedRaw: exchange, at: now()) else { continue }
            let relevant: Bool = isColorRelevant(spot)
            rows.append(SpotRow(call: spot.dxCall, freqHz: spot.freqHz,
                                azimuth: Self.azimuth(to: spot.dxCall, from: myLatLon, dxcc),
                                mode: mode, newMultCount: relevant ? Self.newMultCount(result) : 0,
                                dupe: relevant && result.dupe, snr: Self.parseSnr(spot.comment),
                                points: Int(result.points), spotter: spot.spotter))
        }
        let indexed: [(offset: Int, element: SpotRow)] = Array(rows.enumerated())
        return indexed.sorted { lhs, rhs in
            lhs.element.freqHz != rhs.element.freqHz ? lhs.element.freqHz < rhs.element.freqHz
                : lhs.offset < rhs.offset
        }.map(\.element)
    }

    /// Kotlin `azimuthTo` (`:716-723`) from my grid: `Math.round` of the great-circle bearing to the call's DXCC
    /// coordinates; `nil` without my grid, an entity or its coordinates.
    public func azimuthTo(call: String) -> Int? {
        let myLatLon = dxcc == nil ? nil : Maidenhead.centerLatLon(myGrid)
        return Self.azimuth(to: call, from: myLatLon, dxcc)
    }

    static func azimuth(to call: String, from myLatLon: (lat: Double, lon: Double)?,
                        _ dxcc: (any DxccLookup)?) -> Int? {
        GreatCircle.azimuth(from: myLatLon, toCall: call, dxcc: dxcc)
    }

    /// Java `Math.round(double)` (half up, NaN → 0, clamped to `long`) then Kotlin `Long.toInt()` (truncation).
    static func javaRound(_ value: Double) -> Int {
        Int(Int32(truncatingIfNeeded: JavaMath.round(value)))
    }

    private static let snrPattern: JavaRegex = DxClusterRegex.compile("(\\d+)\\s*dB")

    /// Kotlin `parseSnr` (`:725-729`): the first `(\d+)\s*dB` (Java classes: ASCII digits and whitespace), its digits
    /// by `toIntOrNull` (an overflow → `nil`).
    public static func parseSnr(_ comment: String?) -> Int? {
        guard let comment, let match = snrPattern.firstMatch(in: comment), let digits = match.group(1) else {
            return nil
        }
        return Int32(digits).map { Int($0) }
    }

    /// Kotlin `buildHqCalls` (`:732-745`): HQ callsign (trimmed, upper case) → set value key from the attribute
    /// `calls` (split by `,` and `;`) of every multiplier set of the definition; a later value wins; an unknown set
    /// is skipped (`runCatching`).
    public static func buildHqCalls(definition: ContestDefinition?, registry: MultiplierSetRegistry?)
        -> JavaLinkedMap<String> {
        var map = JavaLinkedMap<String>()
        guard let definition, let registry else { return map }
        for case let binding? in definition.multipliers ?? [] {
            guard let set = try? registry.get(binding.set) else { continue }
            for value in set.values {
                guard let calls = value.attributes["calls"] else { continue }
                for part in splitCalls(calls) {
                    let call: String = JavaText.toUpperCase(KotlinText.trim(part))
                    if !call.isEmpty {
                        map.put(call, value.key)
                    }
                }
            }
        }
        return map
    }

    /// Kotlin `split(",", ";")` by UTF-16 units (empty parts kept).
    private static func splitCalls(_ text: String) -> [String] {
        var parts: [String] = []
        var current: [UInt16] = []
        for unit in text.utf16 {
            if unit == 0x2C || unit == 0x3B {
                parts.append(JavaChar.string(current))
                current = []
            } else {
                current.append(unit)
            }
        }
        parts.append(JavaChar.string(current))
        return parts
    }
}

/// The grid decision log of the spot analysis (Kotlin `gridLogged` + `gridLog`, `ContestController.kt:89, 109`):
/// each callsign (upper case, by UTF-16 units) is logged once until `reset()` (Kotlin `gridLogged.clear()` on
/// activation). Lines go to the sink as messages (`verbatim` or a translation key — Kotlin `tr` vs. plain text).
public final class SpotGridLog: Sendable {

    private let logged = OSAllocatedUnfairLock<Set<JavaStringKey>>(initialState: [])
    private let sink: @Sendable (ContestMessage) -> Void

    public init(sink: @escaping @Sendable (ContestMessage) -> Void) {
        self.sink = sink
    }

    /// Forgets the logged callsigns (on contest activation).
    public func reset() {
        logged.withLock { $0.removeAll() }
    }

    /// Kotlin `gridLogged.add(call)`: `true` the first time.
    func claim(_ call: String) -> Bool {
        logged.withLock { $0.insert(JavaStringKey(call)).inserted }
    }

    func write(_ message: ContestMessage) {
        sink(message)
    }
}
