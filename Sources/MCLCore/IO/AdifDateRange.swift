import Foundation

/// The period of „Export ADIF podle data": whole UTC days, both ends included (N1MM „ADIF by date").
public struct AdifDateRange: Equatable, Sendable {

    /// First instant of the first day (00:00:00 UTC).
    public let start: Date
    /// First instant after the last day (00:00:00 UTC of the following day).
    public let endExclusive: Date

    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    /// The days of `first` and `last` (any instant of the day) and all days between; `nil` when `last` is before
    /// `first`.
    public init?(firstDay first: Date, lastDay last: Date) {
        let calendar = Self.utc
        let start: Date = calendar.startOfDay(for: first)
        let lastStart: Date = calendar.startOfDay(for: last)
        guard lastStart >= start, let end = calendar.date(byAdding: .day, value: 1, to: lastStart) else {
            return nil
        }
        self.start = start
        self.endExclusive = end
    }

    public static func dayText(_ date: Date) -> String {
        let parts = utc.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// A QSO is in when its time is; one without a time is not.
    public func contains(_ qso: Qso) -> Bool {
        guard let at = qso.timestampUtc else { return false }
        return at >= start && at < endExclusive
    }

    public func filter(_ qsos: [Qso]) -> [Qso] {
        qsos.filter(contains)
    }

    /// `maccontestlogger-2026-11-28-2026-11-29.adi` (one day: `maccontestlogger-2026-11-28.adi`).
    public func fileName(base: String = "maccontestlogger") -> String {
        let first: String = Self.dayText(start)
        let last: String = Self.dayText(endExclusive.addingTimeInterval(-1))
        let stem: String = base.hasSuffix(".adi") ? String(base.dropLast(4)) : base
        return first == last ? "\(stem)-\(first).adi" : "\(stem)-\(first)-\(last).adi"
    }
}
