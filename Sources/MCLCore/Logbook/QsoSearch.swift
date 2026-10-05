import Foundation

/// Full-text search over the logbook for the „Přehled spojení" window.
///
/// The query is a single field: space-separated terms that **all** must hold
/// (AND). A term can target one column with the prefix `column:value`
/// (see `prefixHelp`), otherwise it searches across callsign, exchange, band
/// and mode; a purely numeric term additionally compares both serial numbers.
///
/// Comparison is case-insensitive, textually always "contains".
/// Serial numbers are compared for an exact match (otherwise "5"
/// would also find 15, 50, 105 and the filter would be useless).
public enum QsoSearch {

    /// Help for the prefixes (shown in the UI as the field's tooltip).
    public static let prefixHelp =
        "call: volačka, nrtx:/nrrx:/nr: pořadové číslo, ex: exchange, "
            + "band: pásmo, mode: mód, rsttx:/rstrx:/rst: report, date: čas UTC"

    /// Returns the QSOs matching the query; an empty query returns the input unchanged.
    public static func filter(_ qsos: [Qso], _ query: String?) -> [Qso] {
        let terms = terms(query)
        if terms.isEmpty {
            return qsos
        }
        return qsos.filter { matches($0, terms: terms) }
    }

    /// Does the QSO match the whole query (all terms)?
    public static func matches(_ qso: Qso, _ query: String?) -> Bool {
        matches(qso, terms: terms(query))
    }

    private static func terms(_ query: String?) -> [String] {
        guard let query else { return [] }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return []
        }
        return trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private static func matches(_ qso: Qso, terms: [String]) -> Bool {
        terms.allSatisfy { matchesTerm(qso, term: $0) }
    }

    private static func matchesTerm(_ qso: Qso, term: String) -> Bool {
        if let colon = term.firstIndex(of: ":"), colon != term.startIndex {
            let prefix = String(term[term.startIndex..<colon]).lowercased()
            let value = String(term[term.index(after: colon)...])
            // An empty value („call:") filters nothing — the user is still typing the prefix.
            if value.isEmpty {
                return true
            }
            if let byPrefix = matchesPrefix(qso, prefix: prefix, value: value) {
                return byPrefix
            }
            // Unknown prefix (e.g. a callsign with a colon) → treat as free text.
        }
        return matchesFree(qso, term: term)
    }

    /// `nil` = the prefix is unknown (the caller uses free search).
    private static func matchesPrefix(_ qso: Qso, prefix: String, value: String) -> Bool? {
        switch prefix {
        case "call", "cs":
            return contains(qso.call, value)
        case "ex", "exch", "exchange":
            return contains(qso.exchangeRcvd, value)
        case "band":
            return contains(qso.band?.adif, value)
        case "mode":
            return contains(qso.mode?.rawValue, value)
        case "rsttx":
            return contains(qso.rstSent, value)
        case "rstrx":
            return contains(qso.rstRcvd, value)
        case "rst":
            return contains(qso.rstSent, value) || contains(qso.rstRcvd, value)
        case "nrtx":
            return serialMatches(qso.serialSent, value: value)
        case "nrrx":
            return serialMatches(qso.serialRcvd, value: value)
        case "nr":
            return serialMatches(qso.serialSent, value: value)
                || serialMatches(qso.serialRcvd, value: value)
        case "date", "time":
            return contains(timestamp(qso), value)
        default:
            return nil
        }
    }

    private static func matchesFree(_ qso: Qso, term: String) -> Bool {
        if contains(qso.call, term)
            || contains(qso.exchangeRcvd, term)
            || contains(qso.band?.adif, term)
            || contains(qso.mode?.rawValue, term) {
            return true
        }
        guard let number = parseInt(term) else { return false }
        return number == qso.serialSent || number == qso.serialRcvd
    }

    private static func serialMatches(_ serial: Int?, value: String) -> Bool {
        if let number = parseInt(value) {
            return number == serial
        }
        return contains(serial.map(String.init), value)
    }

    private static func contains(_ haystack: String?, _ needle: String) -> Bool {
        guard let haystack else { return false }
        return haystack.uppercased().contains(needle.uppercased())
    }

    /// Text the `date:`/`time:` prefix searches in: Java `DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss")`
    /// in UTC (year of era as in `java.time`, shared with `LogTableColumns.editTimeText`); `nil` without a time.
    public static func timestamp(_ qso: Qso) -> String? {
        guard let ts = qso.timestampUtc else { return nil }
        return LogTableColumns.editTimeText(ts)
    }

    private static func parseInt(_ s: String) -> Int? {
        Int(s)
    }
}
