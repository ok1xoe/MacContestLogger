import Foundation

/// Calendar fields of an instant in UTC for export and statistics patterns (`yyyy-MM-dd HH:mm`,
/// `yyyy-MM-dd`, `yyyyMMdd`, `yyMMdd`, `HHmm`, `MM-dd HH'Z'`) — a thin view over
/// `JavaLocalDate` (`split` + `civil` + field formatting), same as `AdifWriter`.
///
/// Outside the `Int64` seconds range (Java cannot represent such an `Instant`, unreachable from the app) it is
/// `nil` and the caller treats the instant as a missing time — same as `AdifWriter`,
/// which omits the date and time in that case.
struct UtcStamp {
    let year: Int64
    let month: Int64
    let day: Int64
    let secondOfDay: Int64

    init?(_ date: Date) {
        guard let (epochDay, second) = JavaLocalDate.split(date) else { return nil }
        let civil = JavaLocalDate.civil(epochDay: epochDay)
        year = civil.year
        month = civil.month
        day = civil.day
        secondOfDay = second
    }

    var yyyy: String { JavaLocalDate.formatYearOfEra(year) }
    var yy: String { JavaLocalDate.formatReducedYear(year) }
    var MM: String { JavaLocalDate.twoDigits(month) }
    var dd: String { JavaLocalDate.twoDigits(day) }
    var HH: String { JavaLocalDate.twoDigits(secondOfDay / 3600) }
    var mm: String { JavaLocalDate.twoDigits(secondOfDay / 60 % 60) }
}
