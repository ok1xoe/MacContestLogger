import Foundation

/// `{FREQ}` / `{FREQROUND}` (N1MM): the QSO frequency in kHz.
enum MacroFrequency {

    /// kHz with one decimal when it is not zero (`14025.3`, `14025`), or rounded to the kHz; `r` writes R for the
    /// decimal point (CW: `14025R3`). An unknown frequency is `""`.
    static func text(_ freqHz: Int64, round: Bool, r: Bool) -> String {
        guard freqHz > 0 else { return "" }
        if round {
            return String((freqHz + 500) / 1000)
        }
        let tenths: Int64 = (freqHz + 50) / 100
        let khz: String = String(tenths / 10)
        let decimal: Int64 = tenths % 10
        return decimal == 0 ? khz : khz + (r ? "R" : ".") + String(decimal)
    }
}

/// `{GRIDBEARING}`, `{REVGRIDBEARING}`, `{KMGRIDDISTANCE}` (N1MM): from my locator to the one in the entry window.
enum MacroGrid {

    /// The bearing in whole degrees `0…359` (`reverse`: the opposite one); `""` when either locator is invalid.
    static func bearing(from mine: String, to his: String, reverse: Bool) -> String {
        guard let a = Maidenhead.centerLatLon(mine), let b = Maidenhead.centerLatLon(his) else { return "" }
        var degrees: Int = Int(GreatCircle.bearingDeg(a.lat, a.lon, b.lat, b.lon).rounded()) % 360
        if reverse {
            degrees = (degrees + 180) % 360
        }
        return String(degrees)
    }

    /// The distance in whole km; `""` when either locator is invalid.
    static func distance(from mine: String, to his: String) -> String {
        let km: Double = Maidenhead.distanceKm(mine, his)
        return km < 0 ? "" : String(Int(km.rounded()))
    }
}

/// The time and date macros (N1MM): `{TIME1}` local `HH:mm:ss`, `{TIME2}` UTC `HHmm`, `{TIMEGMT}` UTC `HH:mm:ss`,
/// `{DATE}` the local short date, `{DATE1}` local `dd.MM.yy`, `{DAYTIME}` local `yyMMddHHmm`, `{DATEGMT}` the short
/// date and time in UTC, `{TIMESTAMP}` UTC `yyyy-MM-dd HHmm`. Without a moment the macros are empty.
enum MacroTime {

    static let utc = TimeZone(identifier: "UTC")!

    static func value(_ macro: String, _ now: Date?, timeZone: TimeZone, locale: Locale) -> String? {
        let pattern: (String, TimeZone)
        switch macro {
        case "{TIME1}": pattern = ("HH:mm:ss", timeZone)
        case "{TIME2}": pattern = ("HHmm", utc)
        case "{TIMEGMT}": pattern = ("HH:mm:ss", utc)
        case "{DATE1}": pattern = ("dd.MM.yy", timeZone)
        case "{DAYTIME}": pattern = ("yyMMddHHmm", timeZone)
        case "{TIMESTAMP}": pattern = ("yyyy-MM-dd HHmm", utc)
        case "{DATE}":
            return now.map { styled($0, date: .short, time: .none, timeZone, locale) } ?? ""
        case "{DATEGMT}":
            return now.map { styled($0, date: .short, time: .medium, utc, locale) } ?? ""
        default:
            return nil
        }
        return now.map { format($0, pattern.0, pattern.1) } ?? ""
    }

    static func format(_ date: Date, _ pattern: String, _ timeZone: TimeZone = utc) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    private static func styled(_ date: Date, date dateStyle: DateFormatter.Style, time: DateFormatter.Style,
                               _ timeZone: TimeZone, _ locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = dateStyle
        formatter.timeStyle = time
        return formatter.string(from: date)
    }
}
