import Foundation

/// Value state of the „Nový závod" window (Kotlin `NewContestWindow.kt`, v1.1.1): prefill when a contest is chosen,
/// the fixed category defaults, the unique contest labels and the setup saved on OK. The clock is injected.
///
/// Kotlin behaviour that is kept:
/// - a stored value wins even when it is empty, except operators/start/end (`ifBlank`), which fall back;
/// - BAND defaults to `ALL`; MODE to `MIXED` when the definition offers it (more than one mode), otherwise the first
///   mode option, otherwise `""`;
/// - the end is today's UTC midnight plus `period.durationHours`, **not** the stored start plus the duration;
///   without a duration it is `""`;
/// - the saved setup keeps only the form fields — TOUR, skeds and bonus stations of an earlier setup are dropped
///   (Kotlin builds a fresh `ContestSetup()`).
public struct NewContestForm: Equatable, Sendable {

    /// Cabrillo category values by key (`OPERATOR`, …, `BAND`, `MODE`).
    public var category: [String: String]
    /// Sent exchange values by field id (operator-entered fields only).
    public var sentExchange: [String: String]
    public var operators: String
    public var soapbox: String
    /// `"yyyy-MM-dd HH:mm"` UTC.
    public var startedAt: String
    public var endedAt: String
    /// N1MM Associated Files: the contest's own call history file (Swift-only); empty = the global one.
    public var callHistoryFile: String
    /// N1MM Associated Files: the contest's function key files (`ContestSetup.functionKeyFiles`, kept as saved).
    public var functionKeyFiles: [String: String] = [:]
    /// N1MM Associated Files: the contest's own master.scp (`ContestSetup.scpFile`); empty = the global one.
    public var scpFile: String = ""
    /// N1MM „start the serial from other than 1": the first serial of the log (`ContestSetup.firstSerial`).
    public var firstSerial: Int = 1

    public init(category: [String: String] = [:], sentExchange: [String: String] = [:], operators: String = "",
                soapbox: String = "", startedAt: String = "", endedAt: String = "", callHistoryFile: String = "") {
        self.category = category
        self.sentExchange = sentExchange
        self.operators = operators
        self.soapbox = soapbox
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.callHistoryFile = callHistoryFile
    }

    /// Prefill for a chosen definition (Kotlin `LaunchedEffect(selectedId)`); `saved` = the stored setup of this
    /// definition (`config.contestSetups[id]`), `stationCall` = my callsign, `now` = the injected clock.
    public static func prefill(definition: ContestDefinition, saved: ContestSetup?, stationCall: String,
                               now: Date) -> NewContestForm {
        var form = NewContestForm()
        for dim in CategoryCatalog.fixed() {
            form.category[dim.key] = saved?.category[dim.key] ?? defaultFor(dim.key)
        }
        form.category["BAND"] = saved?.category["BAND"] ?? "ALL"
        let modeOptions: [String] = CategoryCatalog.modeOptions(definition)
        let defaultMode: String = modeOptions.contains("MIXED") ? "MIXED" : (modeOptions.first ?? "")
        form.category["MODE"] = saved?.category["MODE"] ?? defaultMode
        for field in CategoryCatalog.sentFields(definition) {
            // A field without an id: Kotlin would put a `null` key; there is nothing to show or save for it.
            guard let id = field.id else { continue }
            form.sentExchange[id] = saved?.sentExchange[id] ?? ""
        }
        form.operators = nonBlank(saved?.operators) ?? stationCall
        form.soapbox = saved?.soapbox ?? ""
        form.callHistoryFile = saved?.callHistoryFile ?? ""
        form.functionKeyFiles = saved?.functionKeyFiles ?? [:]
        form.scpFile = saved?.scpFile ?? ""
        let midnight: Int64 = todayMidnightUtc(now)
        if let start = expectedStart(definition, now: now), !savedStartIsCurrent(saved, definition, now: now) {
            // N1MM: the start defaults to the next weekday the contest usually starts on (`period.startWeekday`).
            form.startedAt = format(epochSecond: start)
            form.endedAt = definition.period?.durationHours.map { format(epochSecond: start + Int64($0) * 3_600) } ?? ""
            return form
        }
        form.startedAt = nonBlank(saved?.startedAt) ?? format(epochSecond: midnight)
        if let ended = nonBlank(saved?.endedAt) {
            form.endedAt = ended
        } else if let hours = definition.period?.durationHours {
            form.endedAt = format(epochSecond: midnight + Int64(hours) * 3_600)
        } else {
            form.endedAt = ""
        }
        return form
    }

    /// `period.startWeekday` / `startTime`: the next start (epoch seconds) at or after today's UTC midnight — today
    /// when today is the weekday; `nil` without a readable weekday.
    public static func expectedStart(_ definition: ContestDefinition, now: Date) -> Int64? {
        let days: [String] = ["THU", "FRI", "SAT", "SUN", "MON", "TUE", "WED"]  // 1970-01-01 was a Thursday
        guard let weekday = definition.period?.startWeekday,
              let wanted = days.firstIndex(of: String(KotlinText.trim(weekday).uppercased().prefix(3))) else {
            return nil
        }
        let midnight: Int64 = todayMidnightUtc(now)
        let today = Int(((midnight / 86_400) % 7 + 7) % 7)
        let ahead = (wanted - today + 7) % 7
        var minutes: Int64 = 0
        if let time = definition.period?.startTime, let value = Int(KotlinText.trim(time)), value >= 0,
           value / 100 < 24, value % 100 < 60 {
            minutes = Int64(value / 100 * 60 + value % 100)
        }
        return midnight + Int64(ahead) * 86_400 + minutes * 60
    }

    /// A saved start that has not ended yet (the contest is being set up again during it) wins over the weekday.
    private static func savedStartIsCurrent(_ saved: ContestSetup?, _ definition: ContestDefinition, now: Date) -> Bool {
        guard let text = nonBlank(saved?.startedAt), let start = epochSecond(text) else {
            return false
        }
        let hours = Int64(definition.period?.durationHours ?? 0)
        return start + hours * 3_600 >= Int64(now.timeIntervalSince1970)
    }

    /// `"yyyy-MM-dd HH:mm"` (UTC) → epoch seconds; `nil` when unreadable.
    static func epochSecond(_ text: String) -> Int64? {
        let units = Array(KotlinText.trim(text).utf8)
        guard units.count >= 16 else { return nil }
        func number(_ range: Range<Int>) -> Int? {
            Int(String(decoding: units[range], as: UTF8.self))
        }
        guard let year = number(0..<4), let month = number(5..<7), let day = number(8..<10),
              let hour = number(11..<13), let minute = number(14..<16), (1...12).contains(month) else { return nil }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar.date(from: components).map { Int64($0.timeIntervalSince1970) }
    }

    /// The setup saved on OK (and passed to `ContestActivation.createContest`).
    public func setup() -> ContestSetup {
        var setup = ContestSetup()
        setup.category = category
        setup.sentExchange = sentExchange
        setup.operators = operators
        setup.soapbox = soapbox
        setup.startedAt = startedAt
        setup.endedAt = endedAt
        setup.callHistoryFile = KotlinText.trim(callHistoryFile)
        setup.functionKeyFiles = functionKeyFiles
        setup.scpFile = KotlinText.trim(scpFile)
        setup.firstSerial = max(1, firstSerial)
        return setup
    }

    /// The form over the stored setup of an existing log (File → Contest setup): every value as stored, the sent
    /// fields of the definition that the setup lacks are empty.
    public static func editing(definition: ContestDefinition, setup: ContestSetup) -> NewContestForm {
        var form = NewContestForm(category: setup.category, sentExchange: setup.sentExchange,
                                  operators: setup.operators, soapbox: setup.soapbox, startedAt: setup.startedAt,
                                  endedAt: setup.endedAt, callHistoryFile: setup.callHistoryFile)
        for field in CategoryCatalog.sentFields(definition) {
            guard let id = field.id, form.sentExchange[id] == nil else { continue }
            form.sentExchange[id] = ""
        }
        form.functionKeyFiles = setup.functionKeyFiles
        form.scpFile = setup.scpFile
        form.firstSerial = setup.firstSerial
        return form
    }

    /// The edited form written over the stored setup: TOUR, skeds and bonus stations stay.
    public func applied(to stored: ContestSetup) -> ContestSetup {
        var out: ContestSetup = setup()
        out.tour = stored.tour
        out.skeds = stored.skeds
        out.bonusStations = stored.bonusStations
        return out
    }

    /// N1MM „Populate all from last log": the Cabrillo categories and the operators of the previous log; a band or
    /// mode the chosen contest does not offer stays as it is.
    public mutating func populate(from last: ContestSetup, bandOptions: [String], modeOptions: [String]) {
        for (key, value) in last.category {
            if key == "BAND", !bandOptions.contains(value) { continue }
            if key == "MODE", !modeOptions.contains(value) { continue }
            category[key] = value
        }
        if !KotlinText.isBlank(last.operators) {
            operators = last.operators
        }
    }

    /// N1MM „Update Ops from Log": the distinct operators of the log's QSOs in their first order (blank ones and the
    /// station call alone do not make a list: then the station call stays).
    public static func operators(fromLog calls: [String]) -> String {
        var seen = Set<String>()
        var out: [String] = []
        for raw in calls {
            let call: String = KotlinText.trim(raw).uppercased()
            if !call.isEmpty, seen.insert(call).inserted {
                out.append(call)
            }
        }
        return out.joined(separator: " ")
    }

    /// Default of a fixed category when nothing is stored.
    public static func defaultFor(_ key: String) -> String {
        switch key {
        case "OPERATOR": return "SINGLE-OP"
        case "POWER": return "LOW"
        case "OVERLAY": return "N/A"
        case "STATION": return "FIXED"
        case "ASSISTED": return "NON-ASSISTED"
        case "TRANSMITTER": return "ONE"
        case "TIME": return "N/A"
        default: return ""
        }
    }

    /// One entry of the contest combo box.
    public struct Label: Equatable, Sendable {
        public let text: String
        public let id: String?
    }

    /// Unique contest labels in catalog order: the name (or the id), with `" (id)"` appended when several
    /// definitions share it. Kotlin `associate` into a `LinkedHashMap`: a repeated label keeps its first position
    /// and takes the later id. A definition without a name and id is labelled `"null"` (Kotlin string template).
    public static func labels(_ contests: [ContestDefinition]) -> [Label] {
        var counts: [String: Int] = [:]
        for definition in contests {
            counts[base(definition), default: 0] += 1
        }
        var order: [String] = []
        var ids: [String: String?] = [:]
        for definition in contests {
            let base: String = base(definition)
            let text: String = (counts[base] ?? 0) > 1 ? "\(base) (\(definition.id ?? "null"))" : base
            if ids[text] == nil {
                order.append(text)
            }
            ids[text] = .some(definition.id)
        }
        return order.map { Label(text: $0, id: ids[$0] ?? nil) }
    }

    /// Label of the selected contest: its entry in `labels`, otherwise the name (or the id).
    public static func selectedLabel(_ labels: [Label], definition: ContestDefinition) -> String {
        if let id = definition.id, let entry = labels.first(where: { $0.id.map { JavaText.equals($0, id) } ?? false }) {
            return entry.text
        }
        return base(definition)
    }

    private static func base(_ definition: ContestDefinition) -> String {
        definition.metadata?.name ?? definition.id ?? "null"
    }

    private static func nonBlank(_ text: String?) -> String? {
        guard let text, !KotlinText.isBlank(text) else { return nil }
        return text
    }

    /// `LocalDate.now(UTC).atStartOfDay()` as epoch seconds (floor of the clock's seconds).
    static func todayMidnightUtc(_ now: Date) -> Int64 {
        let seconds = Int64(now.timeIntervalSince1970.rounded(.down))
        let day: Int64 = seconds >= 0 ? seconds / 86_400 : -((-seconds + 86_399) / 86_400)
        return day * 86_400
    }

    /// Kotlin `fmt`: `LocalDateTime.toString().replace('T', ' ').take(16)` of a whole-minute time.
    static func format(epochSecond: Int64) -> String {
        let day: Int64 = epochSecond >= 0 ? epochSecond / 86_400 : -((-epochSecond + 86_399) / 86_400)
        let secondOfDay: Int64 = epochSecond - day * 86_400
        let hour: Int64 = secondOfDay / 3_600
        let minute: Int64 = secondOfDay % 3_600 / 60
        let date: String = ContestActivation.isoDate(epochDay: day)
        let hh: String = ContestActivation.twoDigitText(hour)
        let mm: String = ContestActivation.twoDigitText(minute)
        let full: String = "\(date) \(hh):\(mm)"
        return String(decoding: Array(full.utf16.prefix(16)), as: UTF16.self)
    }
}
