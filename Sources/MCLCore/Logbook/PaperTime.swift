import Foundation

/// QSO time when entering a paper log after the fact (DXLog „Postcontest mode",
/// N1MM „Entering Multiple QSOs After the Contest"). Only the time `HHmm` or
/// `HH:mm` is entered, the date is taken from the previous QSO; crossing midnight
/// is detected automatically. The date can also be entered explicitly: `2026-11-28 1432`.
///
/// Mirrors the Java `final class PaperTime` (private constructor, only static
/// methods) — a stateless utility, hence a caseless enum. Port of `PaperTime.java`.
///
/// `baseDate`/`previous` are `Date` here (not `LocalDate`/`Instant` — Swift has
/// no dedicated "date only" type in this port); the date is read from them via a
/// UTC calendar, the time of day is ignored.
public enum PaperTime {

    /// A step back by more than this = the paper log crossed midnight.
    static let rollover: TimeInterval = 12 * 3600

    private static let format = try! NSRegularExpression(
        pattern: "^(?:(\\d{4})-(\\d{2})-(\\d{2})\\s+)?(\\d{1,2}):?(\\d{2})$"
    )

    private static let utcCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    /// - Parameters:
    ///   - previous: time of the previously entered QSO (`nil` = none)
    ///   - baseDate: the date when there is no previous QSO (contest start, today)
    public static func parse(_ text: String?, previous: Date?, baseDate: Date) -> Date? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = format.firstMatch(in: trimmed, range: range) else { return nil }

        func group(_ idx: Int) -> String? {
            guard let r = Range(match.range(at: idx), in: trimmed) else { return nil }
            return String(trimmed[r])
        }

        guard let hourText = group(4), let hh = Int(hourText),
              let minuteText = group(5), let mm = Int(minuteText) else {
            return nil
        }
        guard hh <= 23, mm <= 59 else { return nil }

        if let yText = group(1), let moText = group(2), let dText = group(3),
           let y = Int(yText), let mo = Int(moText), let d = Int(dText) {
            guard isValidDate(year: y, month: mo, day: d) else { return nil }
            var comps = DateComponents()
            comps.year = y
            comps.month = mo
            comps.day = d
            comps.hour = hh
            comps.minute = mm
            comps.second = 0
            return utcCalendar.date(from: comps)
        }

        let dayComponents = utcCalendar.dateComponents(
            [.year, .month, .day],
            from: previous ?? baseDate
        )
        var comps = dayComponents
        comps.hour = hh
        comps.minute = mm
        comps.second = 0
        guard var t = utcCalendar.date(from: comps) else { return nil }
        if let previous, t < previous.addingTimeInterval(-rollover) {
            t = t.addingTimeInterval(24 * 3600) // 2355 → 0005: next day
        }
        return t
    }

    private static func isValidDate(year: Int, month: Int, day: Int) -> Bool {
        guard (1...12).contains(month), day >= 1 else { return false }
        let isLeap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
        let daysInMonth = [31, isLeap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        return day <= daysInMonth[month - 1]
    }
}
