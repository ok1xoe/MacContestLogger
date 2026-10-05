import Foundation
import MCLCore
import Observation

/// State of the „Nový závod" window (Kotlin `NewContestWindow.kt`): the contest combo box, the form prefilled from
/// the saved setup of the chosen definition (`NewContestForm.prefill`) and the options derived from it
/// (`CategoryCatalog`). A new model per opening, as Kotlin's `remember` inside the window.
@Observable @MainActor
public final class NewContestModel {

    /// Definitions of the contest data directory (Kotlin `state.contest.available`).
    public let contests: [ContestDefinition]
    /// Unique combo-box labels, in catalog order.
    public let labels: [NewContestForm.Label]
    /// Kotlin `selectedId` (initially the first definition's id).
    public private(set) var selectedId: String?
    public var form: NewContestForm

    @ObservationIgnored private let config: ConfigModel
    @ObservationIgnored private let now: @Sendable () -> Date

    init(contests: [ContestDefinition], config: ConfigModel, now: @escaping @Sendable () -> Date) {
        self.contests = contests
        self.labels = NewContestForm.labels(contests)
        self.config = config
        self.now = now
        self.form = NewContestForm()
        self.selectedId = contests.first?.id
        prefill()
    }

    /// Kotlin `contests.first { it.id() == selectedId }`; `nil` without definitions.
    public var definition: ContestDefinition? {
        guard !contests.isEmpty else { return nil }
        return contests.first { $0.id == selectedId }
    }

    public var selectedLabel: String {
        guard let definition else { return "" }
        return NewContestForm.selectedLabel(labels, definition: definition)
    }

    public var fixedCategories: [CategoryCatalog.CategoryDim] {
        CategoryCatalog.fixed()
    }

    public var bandOptions: [String] {
        definition.map { CategoryCatalog.bandOptions($0) } ?? []
    }

    public var modeOptions: [String] {
        definition.map { CategoryCatalog.modeOptions($0) } ?? []
    }

    /// Ids of the sent fields the operator enters (fields without an id are not shown).
    public var sentFieldIds: [String] {
        guard let definition else { return [] }
        return CategoryCatalog.sentFields(definition).compactMap(\.id)
    }

    /// The combo box chose a label (Kotlin `labelToId[lbl]?.let { selectedId = it }`); a new id prefills the form.
    public func select(label: String) {
        guard let entry = labels.first(where: { $0.text == label }), let id = entry.id else { return }
        guard id != selectedId else { return }
        selectedId = id
        prefill()
    }

    public func category(_ key: String) -> String {
        form.category[key] ?? ""
    }

    public func setCategory(_ key: String, _ value: String) {
        form.category[key] = value
    }

    public func sent(_ id: String) -> String {
        form.sentExchange[id] ?? ""
    }

    public func setSent(_ id: String, _ value: String) {
        form.sentExchange[id] = value
    }

    // MARK: - date and time fields (Kotlin `DateTimeField`)

    /// The date shown on the date button (`value.take(10)`, blank → today).
    public func datePart(_ value: String) -> String {
        DateTimeText.datePart(value, now: now())
    }

    /// The `HH:mm` field.
    public func timePart(_ value: String) -> String {
        DateTimeText.timePart(value)
    }

    /// The date picker's initial date (midnight UTC; an unreadable date → today).
    public func pickerDate(_ value: String) -> Date {
        DateTimeText.pickerDate(value, now: now())
    }

    /// A typed time: `"<date> <time>"`.
    public func withTime(_ value: String, time: String) -> String {
        DateTimeText.datePart(value, now: now()) + " " + time
    }

    /// A picked date (its UTC day): `"<date> <time>"`.
    public func withDate(_ value: String, date: Date) -> String {
        DateTimeText.isoDate(date) + " " + DateTimeText.timePart(value)
    }

    /// The setup saved on OK.
    public func setup() -> ContestSetup {
        form.setup()
    }

    /// Kotlin `LaunchedEffect(selectedId)`.
    private func prefill() {
        guard let definition, let id = selectedId else { return }
        form = NewContestForm.prefill(definition: definition, saved: config.config.contestSetups[id],
                                      stationCall: config.config.station.call, now: now())
    }
}

/// Kotlin `DateTimeField` text handling over `"yyyy-MM-dd HH:mm"` (UTC).
public enum DateTimeText {

    /// `value.take(10).ifBlank { today }`.
    public static func datePart(_ value: String, now: Date) -> String {
        let head: String = take(value, 10)
        return KotlinStrings.isBlank(head) ? isoDate(now) : head
    }

    /// `if (value.length >= 16) value.substring(11, 16) else "00:00"`.
    public static func timePart(_ value: String) -> String {
        let units: [UInt16] = Array(value.utf16)
        guard units.count >= 16 else { return "00:00" }
        return String(decoding: units[11..<16], as: UTF16.self)
    }

    /// `LocalDate.parse(datePart)` at UTC midnight, today's midnight when it does not parse.
    public static func pickerDate(_ value: String, now: Date) -> Date {
        parseIsoDate(datePart(value, now: now)) ?? midnight(now)
    }

    /// The UTC day of `date` as `yyyy-MM-dd`.
    public static func isoDate(_ date: Date) -> String {
        let parts: DateComponents = utcCalendar.dateComponents([.year, .month, .day], from: date)
        let year: Int = parts.year ?? 1970
        let month: Int = parts.month ?? 1
        let day: Int = parts.day ?? 1
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    static func parseIsoDate(_ text: String) -> Date? {
        let pieces: [Substring] = text.split(separator: "-", omittingEmptySubsequences: false)
        guard pieces.count == 3, pieces[0].count == 4, pieces[1].count == 2, pieces[2].count == 2,
              pieces.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              let year = Int(pieces[0]), let month = Int(pieces[1]), let day = Int(pieces[2]) else {
            return nil
        }
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = day
        guard parts.isValidDate(in: utcCalendar) else { return nil }
        return utcCalendar.date(from: parts)
    }

    private static func midnight(_ now: Date) -> Date {
        utcCalendar.startOfDay(for: now)
    }

    private static func take(_ value: String, _ count: Int) -> String {
        String(decoding: Array(value.utf16.prefix(count)), as: UTF16.self)
    }

    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }()
}
