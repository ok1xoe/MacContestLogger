import Foundation

/// Read side of the logbook table („Přehled spojení"): columns, their visibility, sort keys and
/// cell texts.
///
/// Port of the column model of the Kotlin `ui/LogTable.kt` (v1.1.1: `COLUMNS`, `SORT_KEYS`,
/// `visibleCols`, `effectiveSort`, `cellValue`, `fullTimestamp` and the texts of the points and
/// multiplier cells), measured by a maintainer-only probe. In-cell editing
/// (`applyEdit`) is `LogTableEdit`.
public enum LogTableColumns {

    /// The columns in Kotlin order; `rawValue` is the Kotlin column index.
    public enum Column: Int, CaseIterable, Sendable {
        case time = 0, call, band, mode, rstSent, rstRcvd, serialSent, serialRcvd, exchange, note
        case xqso, warning, points, mult

        /// Header text — the Czech translation key (the UI passes it through `tr`).
        public var title: String {
            switch self {
            case .time: return "Čas UTC"
            case .call: return "Volačka"
            case .band: return "Pásmo"
            case .mode: return "Mód"
            case .rstSent: return "RST tx"
            case .rstRcvd: return "RST rx"
            case .serialSent: return "Nr tx"
            case .serialRcvd: return "Nr rx"
            case .exchange: return "Exchange"
            case .note: return "Pozn."
            case .xqso: return "X"
            case .warning: return "⚠"
            case .points: return "Body"
            case .mult: return "Mult"
            }
        }

        /// Relative width (Kotlin `Modifier.weight`).
        public var weight: Double {
            switch self {
            case .time: return 2.0
            case .call: return 1.3
            case .band, .mode: return 0.9
            case .rstSent, .rstRcvd: return 0.8
            case .serialSent, .serialRcvd: return 0.7
            case .exchange: return 1.6
            case .note: return 1.4
            case .xqso, .warning: return 0.35
            case .points: return 0.5
            case .mult: return 1.0
            }
        }
    }

    /// Columns shown for the active contest: serial numbers only when the exchange has them,
    /// Exchange only when it receives more than the report, points and multipliers only in a contest.
    public static func visible(usesSerial: Bool, usesExchangeBeyondRst: Bool, contestActive: Bool) -> [Column] {
        Column.allCases.filter { column in
            switch column {
            case .serialSent, .serialRcvd: return usesSerial
            case .exchange: return usesExchangeBeyondRst
            case .points, .mult: return contestActive
            default: return true
            }
        }
    }

    /// Kotlin `effectiveSort`: a sort column that became hidden (contest switch) falls back to time.
    public static func effectiveSort(_ column: Column, visible: [Column]) -> Column {
        visible.contains(column) ? column : .time
    }

    /// Kotlin `SORT_KEYS`. X-QSO, warning, points and multiplier have no key of their own — clicking
    /// them sorts by the note (v1.1.1 behaviour, kept).
    public static func sortKey(for column: Column) -> QsoSort.Key {
        switch column {
        case .time: return .time
        case .call: return .call
        case .band: return .band
        case .mode: return .mode
        case .rstSent: return .rstSent
        case .rstRcvd: return .rstRcvd
        case .serialSent: return .serialSent
        case .serialRcvd: return .serialRcvd
        case .exchange: return .exchange
        case .note, .xqso, .warning, .points, .mult: return .note
        }
    }

    /// Text of a cell. Columns 0–10 are Kotlin `cellValue`; points and multiplier come from the
    /// QSO's mark (`"<points> D"` for a dupe, the multiplier values separated by a space), the
    /// warning cell is drawn from `LogWarnings` and has no text.
    ///
    /// The Kotlin selection mode draws every cell from `cellValue`, so points and multiplier are empty
    /// there — pass `marks: nil` for that. The X-QSO cell is `""` when not marked; the
    /// normal row shows a `·` in its place (a rendering detail of the view).
    public static func cellText(_ qso: Qso, column: Column, marks: QsoMarks.Mark?) -> String {
        switch column {
        case .time: return timeText(qso.timestampUtc)
        case .call: return qso.call
        case .band: return qso.band?.adif ?? ""
        case .mode: return qso.mode?.rawValue ?? ""
        case .rstSent: return qso.rstSent
        case .rstRcvd: return qso.rstRcvd
        case .serialSent: return qso.serialSent.map { String($0) } ?? ""
        case .serialRcvd: return qso.serialRcvd.map { String($0) } ?? ""
        case .exchange: return qso.exchangeRcvd
        case .note: return qso.comment
        case .xqso: return qso.xqso ? "X" : ""
        case .warning: return ""
        case .points: return pointsText(marks)
        case .mult: return marks?.multText ?? ""
        }
    }

    /// Kotlin points cell: `"7"`, `"0 D"` for a dupe, `""` without a mark.
    public static func pointsText(_ mark: QsoMarks.Mark?) -> String {
        guard let mark else {
            return ""
        }
        let points = String(mark.points)
        return mark.dupe ? points + " D" : points
    }

    /// Table time `MM-dd HH:mm:ss` in UTC (`java.time` semantics, fractions truncated toward the past);
    /// `nil` → `""`.
    public static func timeText(_ date: Date?) -> String {
        guard let date, let parts = JavaLocalDate.split(date) else {
            return ""
        }
        let civil = JavaLocalDate.civil(epochDay: parts.epochDay)
        let second: Int64 = parts.secondOfDay
        var text: String = JavaLocalDate.twoDigits(civil.month)
        text += "-" + JavaLocalDate.twoDigits(civil.day)
        text += " " + JavaLocalDate.twoDigits(second / 3600)
        text += ":" + JavaLocalDate.twoDigits(second / 60 % 60)
        text += ":" + JavaLocalDate.twoDigits(second % 60)
        return text
    }

    /// Full time for editing, `yyyy-MM-dd HH:mm:ss` in UTC (year of era as in `java.time`:
    /// 12026 → `+12026`, year 0 → `0001`); `nil` → `""`. The same text the `date:` search matches
    /// (`QsoSearch.timestamp`).
    public static func editTimeText(_ date: Date?) -> String {
        guard let date else {
            return ""
        }
        return BroadcastXml.formatUtc(date)
    }
}
