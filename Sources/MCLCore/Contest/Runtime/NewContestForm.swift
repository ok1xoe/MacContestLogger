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

    public init(category: [String: String] = [:], sentExchange: [String: String] = [:], operators: String = "",
                soapbox: String = "", startedAt: String = "", endedAt: String = "") {
        self.category = category
        self.sentExchange = sentExchange
        self.operators = operators
        self.soapbox = soapbox
        self.startedAt = startedAt
        self.endedAt = endedAt
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
        let midnight: Int64 = todayMidnightUtc(now)
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

    /// The setup saved on OK (and passed to `ContestActivation.createContest`).
    public func setup() -> ContestSetup {
        var setup = ContestSetup()
        setup.category = category
        setup.sentExchange = sentExchange
        setup.operators = operators
        setup.soapbox = soapbox
        setup.startedAt = startedAt
        setup.endedAt = endedAt
        return setup
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
