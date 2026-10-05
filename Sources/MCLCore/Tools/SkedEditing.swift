import Foundation

/// Why a sked could not be added (Kotlin `AppState.addSked`, `AS:2557-2572`); the checks run in this order.
public enum SkedError: Error, Equatable, Sendable {
    /// The callsign is blank (Kotlin `isBlank`).
    case missingCall
    /// The time text is neither `HHmm` nor `yyyy-MM-dd HHmm` (the original text is kept).
    case invalidTime(String)
    /// The frequency is not positive.
    case invalidFrequency

    /// The status line text (Czech key through `tr`; the time text is the `%s` argument).
    public func text(_ translator: Translator) -> String {
        switch self {
        case .missingCall:
            return translator.translate("Sked: chybí volačka")
        case .invalidTime(let text):
            return translator.translate("Sked: neplatný čas „%s“ (HHmm nebo 2026-11-28 1430)", [.string(text)])
        case .invalidFrequency:
            return translator.translate("Sked: neplatná frekvence")
        }
    }
}

/// Adding skeds and their texts (Kotlin `AppState` `addSked`, `skedTime`, `AS:2557-2579`). Pure: the caller stores the
/// entry in the contest setup and shows the text.
public enum SkedEditing {

    /// Validates the input and builds the entry (`at` stored as `Instant.toString()`, the note trimmed).
    ///
    /// Kotlin calls `SkedPlanner.parseTime(timeText, Instant.now())`, which throws `DateTimeException` for `now` at the
    /// edges of the `Instant` range (never in real use, a crash in Kotlin); here that is an invalid time (`try?`).
    public static func add(call: String, freqHz: Int, mode: String, timeText: String, note: String,
                           now: JavaInstant) -> Result<SkedEntry, SkedError> {
        let parsed: JavaInstant? = (try? SkedPlanner.parseTime(timeText, now: now)) ?? nil
        if KotlinText.isBlank(call) {
            return .failure(.missingCall)
        }
        guard let at = parsed else {
            return .failure(.invalidTime(timeText))
        }
        if freqHz <= 0 {
            return .failure(.invalidFrequency)
        }
        let entry = SkedEntry(call: call, freqHz: freqHz, mode: mode, atUtc: at.toString(), note: KotlinText.trim(note))
        return .success(entry)
    }

    /// Status text after a successful add: `Sked <call> v <HHmm> UTC na <kHz> kHz` (not translated, like Kotlin).
    public static func addedText(_ entry: SkedEntry) -> String {
        let when: String = skedTime(entry)
        let freq: String = CatStatusLine.khz(Int64(entry.freqHz))
        return "Sked \(entry.call) v \(when) UTC na \(freq)"
    }

    /// Texts of `AppState.updateSetup` (`AS:3832-3842`) that a failed setup update shows instead of the added text.
    public static func noActiveContestText(_ translator: Translator) -> String {
        translator.translate("Není aktivní závod")
    }

    /// The setup could not be written (`message` = the exception text).
    public static func setupSaveFailedText(message: String?, translate: Translator) -> String {
        translate.translate("Uložení nastavení závodu selhalo (%s)", [.string(message)])
    }

    /// The contest has no row in the database.
    public static func contestNotInDatabaseText(_ translator: Translator) -> String {
        translator.translate("Závod není v databázi — nastavení se neuložilo")
    }

    /// `AppState.skedTime`: `HHmm` in UTC, `?` for an unparseable time.
    public static func skedTime(_ sked: SkedEntry) -> String {
        guard let at = SkedPlanner.at(sked) else { return "?" }
        return ToolsFormat.hhmm(epochSecond: at.epochSecond)
    }
}

/// Reminders about skeds that are due (Kotlin `startSkedWatch`, `AS:2625-2642`): each sked is announced once; the set
/// of announced ids lives in memory only (after a restart a due sked is announced again, as in Kotlin).
public struct SkedWatch: Sendable {

    /// Ids already announced.
    public private(set) var reminded: Set<String> = []

    public init() {}

    /// One tick: the texts of the skeds that became due and were not announced yet, in list order.
    ///
    /// Kotlin lets a `DateTimeException` from `SkedPlanner.isDue` (time at the edge of the `Instant` range) kill the
    /// loop; here such a sked is simply not due (`try?`).
    public mutating func due(skeds: [SkedEntry], now: JavaInstant) -> [String] {
        var out: [String] = []
        for sked in skeds {
            guard (try? SkedPlanner.isDue(sked, now: now)) == true, reminded.insert(sked.id).inserted else { continue }
            out.append(Self.text(sked))
        }
        return out
    }

    /// `SKED <call> v <HHmm> UTC na <kHz> kHz <mode>[ — <note>] (okno Skedy: klik = QSY)` (not translated).
    public static func text(_ sked: SkedEntry) -> String {
        let when: String = SkedEditing.skedTime(sked)
        let freq: String = CatStatusLine.khz(Int64(sked.freqHz))
        var out: String = "SKED \(sked.call) v \(when) UTC na \(freq) \(sked.mode)"
        if !KotlinText.isBlank(sked.note) {
            out += " — \(sked.note)"
        }
        return out + " (okno Skedy: klik = QSY)"
    }

    /// Status line form of a reminder (`⏰ <text>`); the message log gets the text without the prefix.
    public static func statusLine(_ text: String) -> String {
        "⏰ " + text
    }
}

/// Announcement of a new TOUR session (Kotlin `startTourWatch`, `AS:2606-2622`): the first tick only remembers the
/// session, later ticks report a change while a contest is active.
public struct TourWatch: Sendable {

    /// The session number seen at the last tick (`nil` before the first tick or without a TOUR).
    public private(set) var lastSession: Int64?

    public init() {}

    /// One tick. Returns the report text on a session change (`tour` set, previous session known, contest active).
    ///
    /// Kotlin formats the boundaries with `sessionStart/End`, which throw at the edge of the `Instant` range (a crash
    /// in the loop); here that yields no report (`try?`). The session memory is updated either way.
    public mutating func tick(tour: Tour?, now: Date, active: Bool, translate: Translator) -> String? {
        let current: Int64? = tour?.session(at: now)
        let previous: Int64? = lastSession
        defer { lastSession = current }
        guard let tour, let previous, let current, current != previous, active else { return nil }
        guard let start = try? tour.sessionStart(at: now), let end = try? tour.sessionEnd(at: now) else { return nil }
        let first: String = ToolsFormat.hhmmZ(epochSecond: Tour.epochSecond(of: start))
        let second: String = ToolsFormat.hhmmZ(epochSecond: Tour.epochSecond(of: end))
        let head: String = translate.translate("Nové sezení závodu %s–%s", [.string(first), .string(second)])
        let tail: String = translate.translate(" — stanice z minulého sezení jdou pracovat znovu")
        return head + tail
    }

    /// Status line form of a report (`⏱ <text>`).
    public static func statusLine(_ text: String) -> String {
        "⏱ " + text
    }
}

/// Small formatting helpers shared by the tool windows (UTC clock text, Kotlin `padEnd`).
enum ToolsFormat {

    /// `HHmm` of the UTC time of day (`DateTimeFormatter.ofPattern("HHmm")` with `ZoneOffset.UTC`).
    static func hhmm(epochSecond: Int64) -> String {
        let secondOfDay: Int64 = daySecond(epochSecond)
        return two(secondOfDay / 3_600) + two(secondOfDay / 60 % 60)
    }

    /// `HHmm'Z'`.
    static func hhmmZ(epochSecond: Int64) -> String {
        hhmm(epochSecond: epochSecond) + "Z"
    }

    /// `HH:mm'Z'`.
    static func hhColonMmZ(epochSecond: Int64) -> String {
        let secondOfDay: Int64 = daySecond(epochSecond)
        return two(secondOfDay / 3_600) + ":" + two(secondOfDay / 60 % 60) + "Z"
    }

    private static func daySecond(_ epochSecond: Int64) -> Int64 {
        epochSecond - JavaMath.floorDiv(epochSecond, 86_400) * 86_400
    }

    static func two(_ value: Int64) -> String {
        value < 10 ? "0" + String(value) : String(value)
    }

    /// Kotlin `String.padEnd(length)`: spaces up to `length` UTF-16 units, never truncates.
    static func padEnd(_ text: String, _ length: Int) -> String {
        let missing: Int = length - text.utf16.count
        return missing > 0 ? text + String(repeating: " ", count: missing) : text
    }
}
