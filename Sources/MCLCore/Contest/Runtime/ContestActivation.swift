import Foundation

/// One step of activating a contest, in the Kotlin order (`AppState.activateContest`, v1.1.1). The app model
/// executes them one by one; when `activateDefinition` fails it stops and shows `ContestActivation.failure(_:)`.
public enum ActivationEffect: Equatable, Sendable {
    /// TOUR session (`Tour.effective`: the stored TOUR command, otherwise `period.sessions`) and bonus stations of
    /// the stored setup → `ContestRuntime.setSessionExtras` (must apply before the log is replayed).
    case setSessionExtras(tour: Tour?, bonusStations: [String])
    /// `ContestRuntime.activate(contestId:definition:)`; an error ends the activation.
    case activateDefinition
    /// `LogbookService.setActiveContest(contestId)` — new QSOs are stamped with it.
    case setActiveContest
    /// `meta.last_contest_id = contestId` (the „Pokračovat" button, AUTORELOAD).
    case setLastContestId
    /// Default filter of the Available window: all bands/modes of the definition (mode categories CW/PHONE/DIGI).
    case setDefaultSpotFilters(bands: Set<Band>, modes: Set<String>)
    /// QTCs of the contest from the logbook → `ContestRuntime.setQtcCount`.
    case reloadQtcs
    /// Plugin event `CONTEST_OPENED` (Kotlin fires only when a plugin listens to it).
    case firePlugin(PluginRunner.Event, json: String)
    /// Replays the contest's QSOs (`findAll(contestId)` in `ContestActivation.replayOrder`) into the session. Either
    /// synchronously into the live session (`ContestRuntime.replayLogged(_:)`, as Kotlin), or off the owner into a
    /// `freshSession()` with the log revision captured together with the snapshot, then
    /// `ContestRuntime.adopt(session:forContestId:replayedRevision:currentRevision:)`; a `.stale` result (a QSO was
    /// logged meanwhile) **must** be replayed again (or routed through `RescoreScheduler`), otherwise that QSO is
    /// missing from the score.
    case replayLog
    /// Reloads the log table state without a recount (`refreshFromLogbook(rescore = false)`).
    case refreshFromLogbook
    /// Starts the cluster sync when enabled and not running yet (only with an active contest, otherwise it would
    /// stamp `contest_id = NULL`).
    case startClusterIfIdle
}

/// Activation of one contest: its row, definition, decoded setup and the ordered effects.
public struct ActivationPlan: Equatable, Sendable {
    public let contestId: String
    public let definition: ContestDefinition
    /// The stored setup (`nil` = none or unreadable JSON).
    public let setup: ContestSetup?
    public let effects: [ActivationEffect]
}

/// One row of the contest browser (Kotlin `AppState.ContestBrowserRow`).
public struct ContestBrowserRow: Equatable, Sendable {
    public let contestId: String
    /// Contest name; a row without a name is Kotlin `null` (shown as is by the UI).
    public let name: String?
    /// `"2026-05-30 – 2026-05-31"`, a single date, or `"—"`.
    public let dateRange: String
    public let year: String
    public let qsoCount: Int64
    /// Raw band column values (`"M20, M40"`) or `"—"`.
    public let bands: String
    public let category: String
    public let power: String
}

/// Contest lifecycle from the Kotlin `AppState` (v1.1.1): new contest (`createAndStartContest`), continue
/// (`continueLastContest`), open (`openContest`), the activation plan (`activateContest`), the browser rows and the
/// last-contest label. Functions taking a `ContestStore`/`LogbookRepository` do **blocking SQLite I/O** — call them
/// off the main thread; the rest is pure.
public enum ContestActivation {

    /// A contest ready to be activated, with the status text shown after a successful activation.
    public struct Opening: Equatable, Sendable {
        public let row: ContestStore.ContestRow
        public let definition: ContestDefinition
        /// Status after a successful activation; `nil` = leave the status untouched (continue, as Kotlin).
        public let startedMessage: ContestMessage?
    }

    // MARK: - new, continue, open

    /// Kotlin `createAndStartContest` up to the activation: reads the live definition YAML (snapshot), parses it,
    /// creates the `contests` row (random lowercase UUID, `parseEpoch` of the setup times, setup and station as
    /// JSON) and inserts it. The caller then runs `plan(row:definition:stationCall:)` and, on success, shows
    /// `startedMessage` („Spuštěn závod %s").
    public static func createContest(definitionId: String, yaml: String?, setup: ContestSetup, station: StationConfig,
                                     configStore: ConfigStore, store: ContestStore,
                                     makeId: () -> String = { UUID().uuidString.lowercased() })
        throws -> Result<Opening, ContestMessage> {
        guard let yaml else {
            return .failure(ContestMessage("Nelze načíst definici závodu '%s' pro snapshot.", .string(definitionId)))
        }
        let definition: ContestDefinition
        do {
            definition = try ContestRuntime.parseDefinition(yaml)
        } catch {
            return .failure(ContestMessage("Definice závodu je nečitelná (%s).", .string(error.message)))
        }
        let name: String = definition.metadata?.name ?? definitionId
        let row = ContestStore.ContestRow(contestId: makeId(), definitionId: definitionId, name: name,
                                          startedAt: parseEpoch(setup.startedAt), endedAt: parseEpoch(setup.endedAt),
                                          definitionYaml: yaml, setupJson: configStore.toJSON(setup),
                                          stationJson: configStore.toJSON(station))
        try store.insert(row)
        return .success(Opening(row: row, definition: definition,
                                startedMessage: ContestMessage("Spuštěn závod %s", .string(name))))
    }

    /// Kotlin `continueLastContest`: the contest in `meta.last_contest_id` with a readable snapshot, otherwise `nil`
    /// (no message).
    public static func continueLastContest(repository: LogbookRepository, store: ContestStore) throws -> Opening? {
        guard let id = try repository.metaGet("last_contest_id"), let row = try store.find(id),
              let definition = try? ContestRuntime.parseDefinition(row.definitionYaml) else {
            return nil
        }
        // Kotlin sets no status on success here (AUTORELOAD sets its own).
        return Opening(row: row, definition: definition, startedMessage: nil)
    }

    /// Kotlin `openContest`: the stored contest or the error status.
    public static func openContest(contestId: String, store: ContestStore) throws -> Result<Opening, ContestMessage> {
        guard let row = try store.find(contestId) else {
            return .failure(ContestMessage("Závod nenalezen v databázi"))
        }
        guard let definition = try? ContestRuntime.parseDefinition(row.definitionYaml) else {
            return .failure(ContestMessage("Poškozená definice závodu — nelze otevřít"))
        }
        return .success(Opening(row: row, definition: definition,
                                startedMessage: ContestMessage("Otevřen závod %s", .string(row.name))))
    }

    /// Status when `activateDefinition` fails (Kotlin `tr("Nelze aktivovat závod: %s", error)`).
    public static func failure(_ error: ContestMessage) -> ContestMessage {
        ContestMessage("Nelze aktivovat závod: %s", parts: [.message(error)])
    }

    // MARK: - plan

    /// The effects of `activateContest(contestId, def)` in the Kotlin order. `row.setupJson` is the stored setup
    /// (Kotlin re-reads the same row from the DB).
    public static func plan(row: ContestStore.ContestRow, definition: ContestDefinition,
                            stationCall: String, configStore: ConfigStore) -> ActivationPlan {
        let setup: ContestSetup? = configStore.fromJSON(row.setupJson, as: ContestSetup.self)
        let tour: Tour? = Tour.effective(setup?.tour, definition)
        var bands: Set<Band> = []
        for case let band? in definition.bands ?? [] {
            if let parsed = Band.from(adif: band) {
                bands.insert(parsed)
            }
        }
        var modes: Set<String> = []
        for case let mode? in definition.modes ?? [] {
            modes.insert(modeCategory(mode))
        }
        let json: String = PluginEventJson.contestOpened(contestId: row.contestId, name: definition.metadata?.name,
                                                          call: stationCall)
        let effects: [ActivationEffect] = [
            .setSessionExtras(tour: tour, bonusStations: setup?.bonusStations ?? []),
            .activateDefinition,
            .setActiveContest,
            .setLastContestId,
            .setDefaultSpotFilters(bands: bands, modes: modes),
            .reloadQtcs,
            .firePlugin(.contestOpened, json: json),
            .replayLog,
            .refreshFromLogbook,
            .startClusterIfIdle,
        ]
        return ActivationPlan(contestId: row.contestId, definition: definition, setup: setup, effects: effects)
    }

    /// Kotlin `modeCategory` (`AvailFilterDialog.kt`): `mode.trim().uppercase()` → CW / PHONE / DIGI.
    public static func modeCategory(_ mode: String) -> String {
        switch JavaText.toUpperCase(KotlinText.trim(mode)) {
        case "CW":
            return "CW"
        case "SSB", "USB", "LSB", "PH", "PHONE", "FM", "AM":
            return "PHONE"
        default:
            return "DIGI"
        }
    }

    /// Kotlin `sortedBy { it.timestampUtc }`: stable, a QSO without a time **first** (Kotlin `compareValues`, `null`
    /// is the smallest) — unlike `ContestReplay`, which puts it last.
    public static func replayOrder(_ qsos: [Qso]) -> [Qso] {
        let indexed: [(offset: Int, element: Qso)] = Array(qsos.enumerated())
        let sorted = indexed.sorted { lhs, rhs in
            switch (lhs.element.timestampUtc, rhs.element.timestampUtc) {
            case let (l?, r?):
                return l == r ? lhs.offset < rhs.offset : l < r
            case (nil, .some):
                return true
            case (.some, nil):
                return false
            case (nil, nil):
                return lhs.offset < rhs.offset
            }
        }
        return sorted.map(\.element)
    }

    // MARK: - epoch

    /// Kotlin `parseEpoch`: `trim()` (Kotlin whitespace), blank → `nil`, every space → `T`, then
    /// `LocalDateTime.parse` (`ISO_LOCAL_DATE_TIME`, STRICT, case-insensitive `T`, seconds and 0–9 fraction digits
    /// optional) as UTC epoch milliseconds; `nil` where Java throws (also a `long` overflow).
    public static func parseEpoch(_ text: String) -> Int64? {
        let trimmed: String = KotlinText.trim(text)
        if KotlinText.isBlank(trimmed) {
            return nil
        }
        let units: [UInt16] = trimmed.utf16.map { $0 == 0x20 ? 0x54 : $0 }
        guard let separator = units.firstIndex(where: { $0 == 0x54 || $0 == 0x74 }) else { return nil }
        let datePart: String = JavaChar.string(Array(units[..<separator]))
        guard let epochDay = GoalFileParser.isoLocalDate(datePart),
              let time = isoLocalTime(Array(units[(separator + 1)...])) else {
            return nil
        }
        let seconds: Int64 = epochDay * 86_400 + time.secondOfDay
        return toEpochMilli(seconds: seconds, nanos: time.nanos)
    }

    /// `Instant.toEpochMilli` (JDK 21): `multiplyExact`/`addExact`, an overflow (Java `ArithmeticException`) → `nil`.
    static func toEpochMilli(seconds: Int64, nanos: Int64) -> Int64? {
        let base: Int64 = seconds < 0 && nanos > 0 ? seconds + 1 : seconds
        let adjustment: Int64 = seconds < 0 && nanos > 0 ? nanos / 1_000_000 - 1_000 : nanos / 1_000_000
        let (millis, overflow) = base.multipliedReportingOverflow(by: 1_000)
        if overflow { return nil }
        let (total, overflowSum) = millis.addingReportingOverflow(adjustment)
        return overflowSum ? nil : total
    }

    /// `ISO_LOCAL_TIME` → second of the day and nanoseconds: `HH:mm[:ss[.f{0,9}]]`, ASCII digits, hour 0–23,
    /// minute and second 0–59 (STRICT), nothing after. A `.` without digits is accepted (measured).
    static func isoLocalTime(_ units: [UInt16]) -> (secondOfDay: Int64, nanos: Int64)? {
        var position = 0
        guard let hour = twoDigits(units, &position), hour <= 23,
              expect(units, &position, 0x3A), let minute = twoDigits(units, &position), minute <= 59 else {
            return nil
        }
        var second: Int64 = 0
        var nanos: Int64 = 0
        var probe = position
        if expect(units, &probe, 0x3A), let parsed = twoDigits(units, &probe) {
            guard parsed <= 59 else { return nil }
            second = parsed
            position = probe
            if expect(units, &probe, 0x2E) {
                var digits = 0
                while probe < units.count, digits < 9, let digit = asciiDigit(units[probe]) {
                    nanos = nanos * 10 + digit
                    digits += 1
                    probe += 1
                }
                for _ in digits..<9 {
                    nanos *= 10
                }
                position = probe
            }
        }
        guard position == units.count else { return nil }
        let secondOfDay: Int64 = hour * 3_600 + minute * 60 + second
        return (secondOfDay, nanos)
    }

    private static func twoDigits(_ units: [UInt16], _ position: inout Int) -> Int64? {
        guard position + 2 <= units.count, let tens = asciiDigit(units[position]),
              let ones = asciiDigit(units[position + 1]) else {
            return nil
        }
        position += 2
        return tens * 10 + ones
    }

    private static func expect(_ units: [UInt16], _ position: inout Int, _ unit: UInt16) -> Bool {
        guard position < units.count, units[position] == unit else { return false }
        position += 1
        return true
    }

    private static func asciiDigit(_ unit: UInt16) -> Int64? {
        unit >= 0x30 && unit <= 0x39 ? Int64(unit - 0x30) : nil
    }

    // MARK: - browser and label

    /// Kotlin `lastContestLabel`: name of the contest in `meta.last_contest_id`, `nil` when there is none.
    public static func lastContestLabel(repository: LogbookRepository, store: ContestStore) throws -> String? {
        guard let id = try repository.metaGet("last_contest_id"), let row = try store.find(id) else { return nil }
        return row.name
    }

    /// Kotlin `contestBrowserRows`: summaries (newest start first) with category and power from the stored setup.
    public static func browserRows(store: ContestStore, configStore: ConfigStore) throws -> [ContestBrowserRow] {
        var rows: [ContestBrowserRow] = []
        for summary in try store.listSummaries() {
            let json: String? = try store.find(summary.contestId)?.setupJson
            let setup: ContestSetup? = configStore.fromJSON(json, as: ContestSetup.self)
            rows.append(browserRow(summary, setup: setup))
        }
        return rows
    }

    /// One browser row from a summary and its setup.
    public static func browserRow(_ summary: ContestStore.ContestSummary, setup: ContestSetup?) -> ContestBrowserRow {
        let start: Int64? = summary.startedAt ?? summary.firstQso
        let end: Int64? = summary.endedAt ?? summary.lastQso
        let dateRange: String
        if let start, let end {
            dateRange = fmtDate(start) + " – " + fmtDate(end)
        } else {
            dateRange = start.map(fmtDate) ?? "—"
        }
        let bands: String = summary.bands.joined(separator: ", ")
        return ContestBrowserRow(contestId: summary.contestId, name: summary.name, dateRange: dateRange,
                                 year: start.map(fmtYear) ?? "—", qsoCount: summary.qsoCount,
                                 bands: KotlinText.isBlank(bands) ? "—" : bands,
                                 category: nonBlank(setup?.category["OPERATOR"]) ?? "—",
                                 power: nonBlank(setup?.category["POWER"]) ?? "—")
    }

    private static func nonBlank(_ text: String?) -> String? {
        guard let text, !KotlinText.isBlank(text) else { return nil }
        return text
    }

    /// `Instant.ofEpochMilli(ms).atZone(UTC).toLocalDate().toString()`.
    static func fmtDate(_ epochMillis: Int64) -> String {
        isoDate(epochDay: epochDay(epochMillis))
    }

    /// `….year.toString()`.
    static func fmtYear(_ epochMillis: Int64) -> String {
        String(JavaLocalDate.civil(epochDay: epochDay(epochMillis)).year)
    }

    private static func epochDay(_ epochMillis: Int64) -> Int64 {
        let millisPerDay: Int64 = 86_400_000
        let quotient: Int64 = epochMillis / millisPerDay
        return epochMillis % millisPerDay < 0 ? quotient - 1 : quotient
    }

    /// `LocalDate.toString()`: a year below 1000 in absolute value padded to 4 digits (with `-` before the common
    /// era), above 9999 with `+`.
    static func isoDate(epochDay: Int64) -> String {
        let (year, month, day) = JavaLocalDate.civil(epochDay: epochDay)
        let absYear: Int64 = year < 0 ? -year : year
        let text: String
        if absYear < 1000 {
            let digits = String(absYear)
            let padded = String(repeating: "0", count: 4 - digits.count) + digits
            text = year < 0 ? "-" + padded : padded
        } else {
            text = year > 9999 ? "+" + String(year) : String(year)
        }
        let mm: String = twoDigitText(month)
        let dd: String = twoDigitText(day)
        return "\(text)-\(mm)-\(dd)"
    }

    static func twoDigitText(_ value: Int64) -> String {
        value < 10 ? "0" + String(value) : String(value)
    }
}
