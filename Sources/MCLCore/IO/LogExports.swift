import Foundation

/// Exception of `LogExports` — Java class and text.
public enum LogExportsError: Error, Equatable, Sendable {
    /// `java.lang.NullPointerException` from `DateTimeFormatter.format(null)` in `summary`: the first
    /// QSO (after sorting) has a time and the last does not. The text is Java's (`temporal`). Unreachable
    /// from the app (the DB has `timestamp_utc NOT NULL`), but the behaviour is kept.
    case nullPointer(message: String)

    /// Full name of the Java exception class.
    public var javaClass: String {
        switch self {
        case .nullPointer: return "java.lang.NullPointerException"
        }
    }
}

/// Other log exports (N1MM File → Export, DXLog Export): CSV for a spreadsheet,
/// a fixed-column text listing (print) and a contest summary. Port of `io/LogExports.java`
/// (Java v1.1.1).
///
/// Formatting via `JavaFormat`: `%.1f` rounds the decimal notation HALF_UP
/// (`14025.05` → `14025.1`, not `printf`'s `14025.0`), widths `%-Ns` are counted in UTF-16.
/// Java `null` of text fields is `""` here — CSV and text write it the same way.
public enum LogExports {

    /// Non-deleted QSOs sorted by time, QSOs without time at the end; stable.
    private static func sorted(_ qsos: [Qso]) -> [Qso] {
        let live: [(offset: Int, element: Qso)] = Array(qsos.filter { !$0.deleted }.enumerated())
        return live.sorted { a, b in
            switch (a.element.timestampUtc, b.element.timestampUtc) {
            case let (ta?, tb?):
                return ta != tb ? ta < tb : a.offset < b.offset
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            case (nil, nil):
                return a.offset < b.offset
            }
        }.map(\.element)
    }

    /// `yyyy-MM-dd HH:mm` in UTC; out of range (`UtcStamp` → `nil`) empty, like a missing time.
    static func time(_ date: Date) -> String {
        guard let s = UtcStamp(date) else { return "" }
        return s.yyyy + "-" + s.MM + "-" + s.dd + " " + s.HH + ":" + s.mm
    }

    private static let csvHeader: String =
        "time_utc,call,band,freq_khz,mode,rst_sent,rst_rcvd,nr_sent,nr_rcvd,exch_sent,exch_rcvd,"
        + "country,continent,run,operator,xqso,comment\r\n"

    /// CSV (RFC 4180, comma separator, header, `\r\n` rows).
    public static func csv(_ qsos: [Qso]) -> String {
        var out = csvHeader
        for q in sorted(qsos) {
            var cells: [String] = []
            cells.append(cell(q.timestampUtc.map(time) ?? ""))
            cells.append(cell(q.call))
            cells.append(cell(q.band?.adif ?? ""))
            cells.append(cell(JavaFormat.fixed(Double(q.freqHz) / 1000.0, precision: 1)))
            cells.append(cell(q.mode?.rawValue ?? ""))
            cells.append(cell(q.rstSent))
            cells.append(cell(q.rstRcvd))
            cells.append(cell(q.serialSent.map { String($0) } ?? ""))
            cells.append(cell(q.serialRcvd.map { String($0) } ?? ""))
            cells.append(cell(q.exchangeSent))
            cells.append(cell(q.exchangeRcvd))
            cells.append(cell(q.dxccName))
            cells.append(cell(q.continent))
            cells.append(cell(q.runMode.rawValue))
            cells.append(cell(q.operator))
            cells.append(q.xqso ? "1" : "0")
            cells.append(cell(q.comment))
            out += cells.joined(separator: ",")
            out += "\r\n"
        }
        return out
    }

    /// Quoted cell (`"` doubled) when it contains `,` `"` `\n` or `\r`. Searched by
    /// scalars, not Swift `Character`s — `\r\n` is one `Character` and so is a quote
    /// with a combining mark, but Java `contains` finds them.
    static func cell(_ v: String) -> String {
        let needsQuotes = v.unicodeScalars.contains { s in
            s == "," || s == "\"" || s == "\n" || s == "\r"
        }
        guard needsQuotes else { return v }
        var quoted = String.UnicodeScalarView()
        quoted.append("\"")
        for scalar in v.unicodeScalars {
            quoted.append(scalar)
            if scalar == "\"" { quoted.append("\"") }
        }
        quoted.append("\"")
        return String(quoted)
    }

    private static let textHeader: String = JavaFormat.format(
        "%5s %-16s %-12s %5s %9s %-5s %-4s %-12s %-4s %-14s %s%n",
        "#", "Čas UTC", "Volačka", "Pásmo", "kHz", "Mód", "RSTs", "Výměna odesl.", "RSTp", "Výměna přij.", "Pozn.")

    /// Fixed-column text listing (for printing / attachment).
    public static func text(_ title: String, _ qsos: [Qso]) -> String {
        var out = title + "\n"
        out += String(repeating: "-", count: max(20, title.utf16.count)) + "\n"
        out += textHeader
        var i = 1
        for q in sorted(qsos) {
            let args: [JavaFormat.Arg] = [
                .int(i), .string(q.timestampUtc.map(time) ?? ""), .string(q.call), .string(q.band?.adif ?? ""),
                .double(Double(q.freqHz) / 1000.0), .string(q.mode?.rawValue ?? ""), .string(q.rstSent),
                .string(q.exchangeSent), .string(q.rstRcvd), .string(q.exchangeRcvd),
                .string((q.xqso ? "X-QSO " : "") + q.comment),
            ]
            out += JavaFormat.format("%5d %-16s %-12s %5s %9.1f %-5s %-4s %-12s %-4s %-14s %s%n", arguments: args)
            i += 1
        }
        return out
    }

    /// Contest summary: station, score and breakdown by bands × modes.
    ///
    /// - Throws: `LogExportsError.nullPointer("temporal")` when the first QSO has a time and the last
    ///   does not (like Java).
    public static func summary(_ contestName: String, _ call: String, _ score: ScoreState?,
                               _ qsos: [Qso]) throws(LogExportsError) -> String {
        var out = "Souhrn závodu: " + contestName + "\n"
        out += "Stanice:       " + call + "\n"
        let s = sorted(qsos)
        if let first = s.first?.timestampUtc {
            guard let last = s[s.count - 1].timestampUtc else {
                throw .nullPointer(message: "temporal")
            }
            out += "Období:        " + time(first) + " – " + time(last) + " UTC\n"
        }
        if let score {
            let qtc = score.qtcPoints > 0 ? " · QTC " + String(score.qtcPoints) : ""
            let args: [JavaFormat.Arg] = [
                .int(Int(score.qsoCount)), .int(Int(score.qsoPoints)), .int(Int(score.multTotal)), .string(qtc),
                .int(Int(score.total)),
            ]
            out += JavaFormat.format("QSO %d · body %d · násobiče %d%s · skóre %d%n", arguments: args)
        }
        out += "\n"
        let p = LogStatistics.pivot(qsos, .BAND, .MODE)
        out += JavaFormat.format("%-6s", "Pásmo")
        for c in p.cols {
            out += JavaFormat.format("%7s", .string(c))
        }
        out += JavaFormat.format("%8s%n", "Celkem")
        for r in p.rows {
            out += JavaFormat.format("%-6s", .string(r))
            for c in p.cols {
                out += JavaFormat.format("%7d", .int(p.count(r, c)))
            }
            out += JavaFormat.format("%8d%n", .int(p.rowTotal(r) ?? 0))
        }
        out += JavaFormat.format("%-6s", "Celkem")
        for c in p.cols {
            out += JavaFormat.format("%7d", .int(p.colTotal(c) ?? 0))
        }
        out += JavaFormat.format("%8d%n", .int(p.total))
        return out
    }
}
