import Foundation

/// The pivot table of the Statistics window as text cells (`SW:85-104`).
public struct StatisticsTable: Equatable, Sendable {
    public struct Row: Equatable, Sendable {
        public let label: String
        /// The count per column, or `·` for zero.
        public let cells: [String]
        public let total: String
    }

    /// The header of the first column: the label of the row dimension.
    public let rowHeader: String
    public let columns: [String]
    public let rows: [Row]
    /// `Celkem` — the caption of the last column and of the totals row (a literal, not translated, as in Kotlin).
    public let totalLabel: String
    public let columnTotals: [String]
    public let grandTotal: String
}

/// The bar chart "QSO per hour" of the Statistics window (`SW:127-146`).
public struct HourlyChart: Equatable, Sendable {
    /// `QSO po hodinách (max N/h)` — without the bracket for an empty log.
    public let title: String
    /// The hour keys (`MM-dd HHZ`), chronological.
    public let hours: [String]
    public let values: [Int]
    /// The scale: the highest value, at least 1 (`values.max().coerceAtLeast(1)`); `1` for an empty chart.
    public let scale: Int
}

/// A titled block of lines of the reports view (`SW:152-181`).
public struct ReportSection: Equatable, Sendable {
    public let title: String
    /// The lines; `—` when there is nothing to show.
    public let lines: [String]
}

/// The score table of the Score window (`SC:62-109`) flattened to text cells.
public struct ScoreTable: Equatable, Sendable {
    /// The header: band, [mode], QSO, Dupe, Body and one label per multiplier binding.
    public let headers: [String]
    /// The number of leading (left-aligned) columns: 2 by band × mode, otherwise 1.
    public let lead: Int
    public let rows: [[String]]
    /// The totals row (`Celkem`).
    public let total: [String]
    /// `Po módech` and the per-mode rows when there is more than one mode (only in the band × mode view).
    public let modesTitle: String?
    public let modeRows: [[String]]
    /// `Body X × násobiče Y  =  skóre Z`, with `  ·  bonus N` when the bonus is not zero.
    public let footer: String
    /// `N QSO se nedalo započítat …` when some QSOs could not be replayed.
    public let skippedNote: String?
}

/// One column of the dupesheet.
public struct DupesheetColumn: Equatable, Sendable {
    public struct Call: Equatable, Sendable {
        public let text: String
        /// The typed text (two or more characters) is a substring of the call.
        public let hit: Bool
    }

    public let digit: Character
    /// `3 (12)` — the digit and the number of calls.
    public let header: String
    public let calls: [Call]
}

/// The visible dupesheet (`DS:53-102`): the title and the columns 0–9 and `#`.
public struct DupesheetView: Equatable, Sendable {
    public let title: String
    public let columns: [DupesheetColumn]
}

/// The statistics, score and dupesheet views of v1.1.1 (`ui/StatisticsWindow.kt`, `ui/ScoreWindow.kt`,
/// `ui/DupesheetWindow.kt`) as pure functions: the rows, totals and texts the windows draw. The numbers come from
/// `LogStatistics`, `RateReports`, `ScoreBreakdown` and `Dupesheet`; this layer adds the cell texts.
/// Measured through the real classes (maintainer-only probe, rows `pivot`, `hourly`, `reports`, `score`,
/// `dupesheet`); `ScoreWindowKt.cells` and `StatisticsWindowKt.TIME` are real, the rest of the glue is a
/// transcription of the composables.
public enum StatsViews {

    // MARK: - Statistics (pivot)

    /// The row choices of the Statistics window (every dimension but `NONE`, `SW:73`).
    public static var rowDimensions: [LogStatistics.Dimension] {
        LogStatistics.Dimension.allCases.filter { $0 != .NONE }
    }

    /// The column choices (every dimension).
    public static var columnDimensions: [LogStatistics.Dimension] {
        LogStatistics.Dimension.allCases
    }

    /// The dimension with the given label (`Dimension.entries.first { it.label() == l }`).
    public static func dimension(forLabel label: String) -> LogStatistics.Dimension? {
        LogStatistics.Dimension.allCases.first { JavaText.equals($0.label, label) }
    }

    /// The pivot table (`SW:85-104`): zero counts are `·`, totals are the pivot's.
    public static func statisticsTable(qsos: [Qso], rowDim: LogStatistics.Dimension,
                                       colDim: LogStatistics.Dimension) -> StatisticsTable {
        let pivot: LogStatistics.Pivot = LogStatistics.pivot(qsos, rowDim, colDim)
        let rows: [StatisticsTable.Row] = pivot.rows.map { row in
            let cells: [String] = pivot.cols.map { col in
                let count: Int = pivot.count(row, col)
                return count > 0 ? String(count) : "·"
            }
            return StatisticsTable.Row(label: row, cells: cells, total: text(pivot.rowTotal(row)))
        }
        return StatisticsTable(rowHeader: rowDim.label, columns: pivot.cols, rows: rows, totalLabel: "Celkem",
                               columnTotals: pivot.cols.map { text(pivot.colTotal($0)) },
                               grandTotal: String(pivot.total))
    }

    /// The bar chart under the table (`SW:127-146`).
    public static func hourlyChart(qsos: [Qso], translate: Translator = .source) -> HourlyChart {
        let perHour: JavaLinkedMap<Int> = LogStatistics.perHour(qsos)
        let hours: [String] = perHour.entries.compactMap { $0.key }
        let values: [Int] = perHour.entries.map { $0.value ?? 0 }
        var title: String = translate.translate("QSO po hodinách")
        if let max = values.max() {
            title += " (max " + String(max) + "/h)"
        }
        return HourlyChart(title: title, hours: hours, values: values, scale: max(values.max() ?? 1, 1))
    }

    /// A Kotlin string template of a nullable count.
    static func text(_ value: Int?) -> String {
        value.map { String($0) } ?? "null"
    }

    // MARK: - Reports (best rate, breaks, runs)

    /// The reports view (`SW:152-181`): the best rate over 10 and 60 minutes, breaks of at least 30 minutes and
    /// runs of at least 5 QSOs on one frequency. `perHour` cannot throw for the fixed windows.
    public static func reports(qsos: [Qso], translate: Translator = .source) -> [ReportSection] {
        let best: [String] = [10, 60].map { minutes -> String in
            guard let b = RateReports.bestRate(qsos, minutes) else { return "—" }
            let perHour: Int = (try? b.perHour()) ?? 0
            return String(b.windowMinutes) + " min: " + String(b.qsos) + " QSO (" + String(perHour) + "/h) od "
                + timeText(b.start)
        }
        let offs: [RateReports.OffTime] = RateReports.offTimes(qsos, 30)
        let offTotal: Int64 = offs.reduce(Int64(0)) { $0 &+ $1.minutes() }
        let offLines: [String] = offs.map { timeText($0.from) + " – " + timeText($0.to) + "  " + String($0.minutes()) + " min" }
        let runs: [RateReports.Run] = RateReports.runs(qsos, 5)
        let runLines: [String] = runs.map { r in
            JavaFormat.format("%s  %-5s %9.1f kHz  %3d QSO  %3d min  %3d/h", .string(timeText(r.start)),
                              .string(r.band), .double(Double(r.freqHz) / 1000.0), .int(r.qsos),
                              .int(Int(r.minutes())), .int(r.perHour()))
        }
        return [
            ReportSection(title: translate.translate("Nejlepší rate"), lines: best),
            ReportSection(title: translate.translate("Přestávky ≥ 30 min (celkem %s min)", [.int(Int(offTotal))]),
                          lines: offLines.isEmpty ? ["—"] : offLines),
            ReportSection(title: translate.translate("Běhy Run (≥ 5 QSO na jedné frekvenci)"),
                          lines: runLines.isEmpty ? ["—"] : runLines),
        ]
    }

    /// `MM-dd HH:mm'Z'` of an instant in UTC (`StatisticsWindowKt.TIME`).
    static func timeText(_ instant: JavaInstant) -> String {
        let day: Int64 = JavaMath.floorDiv(instant.epochSecond, 86_400)
        let second: Int64 = instant.epochSecond &- day &* 86_400
        let civil = JavaLocalDate.civil(epochDay: day)
        return JavaLocalDate.twoDigits(civil.month) + "-" + JavaLocalDate.twoDigits(civil.day) + " "
            + JavaLocalDate.twoDigits(second / 3600) + ":" + JavaLocalDate.twoDigits(second / 60 % 60) + "Z"
    }

    // MARK: - Score

    /// The texts above the table while there is no breakdown (`SC:62-69`).
    public static func scoreStatusText(isActive: Bool, translate: Translator = .source) -> String {
        isActive ? translate.translate("Počítám…")
            : translate.translate("Rozpad skóre je jen v závodě (volné logování nemá body).")
    }

    /// The score table (`SC:62-109`).
    ///
    /// - Parameters:
    ///   - bandOrder: the band order of the contest (`ContestRuntime.bandOrder`).
    ///   - byMode: `true` = band × mode rows plus the per-mode block; `false` = bands only.
    public static func scoreTable(breakdown b: ScoreBreakdown, bandOrder: [String?], byMode: Bool,
                                  translate: Translator = .source) -> ScoreTable {
        let mults: [String?] = b.multIds
        var headers: [String] = [translate.translate("Pásmo")]
        if byMode {
            headers.append(translate.translate("Mód"))
        }
        headers.append(contentsOf: ["QSO", "Dupe", "Body"])
        for id in mults {
            headers.append(b.multLabel(id) ?? "null")
        }
        var rows: [[String]] = []
        if byMode {
            for r in b.rows(bandOrder) {
                rows.append(cells([r.band, r.mode], r.cell, mults))
            }
        } else {
            for band in b.bands(bandOrder) {
                rows.append(cells([band], b.band(band), mults))
            }
        }
        let total: [String] = cells(byMode ? ["Celkem", ""] : ["Celkem"], b.total, mults)
        var modesTitle: String?
        var modeRows: [[String]] = []
        if byMode && b.modes.count > 1 {
            modesTitle = translate.translate("Po módech")
            for m in b.modes {
                modeRows.append(cells(["", m], b.mode(m), mults))
            }
        }
        let sc: ScoreState = b.score
        let bonus: String = sc.bonusPoints != 0 ? "  ·  bonus " + String(sc.bonusPoints) : ""
        let footer: String = translate.translate("Body %s × násobiče %s%s  =  skóre %s",
                                                 [.int(Int(sc.qsoPoints)), .int(Int(sc.multTotal)), .string(bonus),
                                                  .int(Int(sc.total))])
        var skipped: String?
        if b.skipped > 0 {
            skipped = translate.translate("%s QSO se nedalo započítat (chybí pásmo nebo volačka).",
                                          [.int(b.skipped)])
        }
        return ScoreTable(headers: headers, lead: byMode ? 2 : 1, rows: rows, total: total, modesTitle: modesTitle,
                          modeRows: modeRows, footer: footer, skippedNote: skipped)
    }

    /// `cells(lead, cell, mults)` of `ScoreWindow.kt` (`SC:116`).
    static func cells(_ lead: [String], _ cell: ScoreBreakdown.Cell, _ mults: [String?]) -> [String] {
        var out: [String] = lead
        out.append(String(cell.qsos))
        out.append(String(cell.dupes))
        out.append(String(cell.points))
        for id in mults {
            out.append(String(cell.mults(id)))
        }
        return out
    }

    // MARK: - Dupesheet

    /// The band shown by default: the tuned band, else the band of the last QSO (`DS:53`).
    public static func dupesheetBand(tuned: Band?, qsos: [Qso]) -> String? {
        tuned?.adif ?? qsos.last?.band?.adif
    }

    /// The mode shown by default: the radio's mode, else the mode of the last QSO (`DS:54`).
    public static func dupesheetMode(radio: Mode?, qsos: [Qso]) -> String? {
        radio?.rawValue ?? qsos.last?.mode?.rawValue
    }

    /// The dupesheet (`DS:55-102`).
    ///
    /// - Parameters:
    ///   - scope: the contest's dupe scope, `nil` outside a contest (then per band).
    ///   - typedCall: the call being typed; calls that contain it (from two characters, trimmed, upper case) are
    ///     highlighted.
    public static func dupesheet(qsos: [Qso], scope: ContestDefinition.Scope?, band: String?, mode: String?,
                                 typedCall: String, translate: Translator = .source) -> DupesheetView {
        let sheet: Dupesheet.Sheet = Dupesheet.build(qsos, band: band, mode: mode, scope: scope)
        let partial: String = InfoLines.normalizedCall(typedCall)
        let what: String
        switch scope ?? .PER_BAND {
        case .PER_BAND: what = band ?? "—"
        case .PER_BAND_MODE: what = (band ?? "—") + " " + (mode ?? "")
        case .PER_MODE: what = mode ?? "—"
        case .ONCE: what = translate.translate("celý závod")
        }
        let total: Int = sheet.columns.reduce(0) { $0 + $1.calls.count }
        let title: String = translate.translate("Dupesheet %s — %s volaček", [.string(what), .int(total)])
        let digits: [Character] = Array("0123456789") + [Dupesheet.noDigit]
        let partialLength: Int = partial.utf16.count
        let columns: [DupesheetColumn] = digits.map { digit in
            let calls: [String] = sheet[digit] ?? []
            let entries: [DupesheetColumn.Call] = calls.map { call in
                DupesheetColumn.Call(text: call, hit: partialLength >= 2 && containsUnits(call, partial))
            }
            return DupesheetColumn(digit: digit, header: String(digit) + " (" + String(calls.count) + ")",
                                   calls: entries)
        }
        return DupesheetView(title: title, columns: columns)
    }

    /// Kotlin `String.contains(CharSequence)`: a UTF-16 substring search (Swift's `contains` compares by
    /// canonical equivalence).
    static func containsUnits(_ text: String, _ part: String) -> Bool {
        let t: [UInt16] = Array(text.utf16)
        let p: [UInt16] = Array(part.utf16)
        if p.isEmpty { return true }
        if p.count > t.count { return false }
        for start in 0...(t.count - p.count) where Array(t[start..<(start + p.count)]) == p {
            return true
        }
        return false
    }
}
