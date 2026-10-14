import Foundation

/// N1MM Score window „Copy all" / „Print to file" and the station lines of the export summary: the contest setup and
/// the station as text lines, and the score table as aligned plain text.
public enum ScoreSummaryText {

    /// The setup and station lines (`Label:  value`, labels padded to 15 like `LogExports.summary`); empty values are
    /// left out. The category and the sent exchange are sorted by key. `translate` = `.source` keeps the Czech labels
    /// of the export summary.
    public static func setupLines(setup: ContestSetup?, station: StationConfig,
                                  translate: Translator = .source) -> [String] {
        var out: [String] = []
        func add(_ label: String, _ value: String) {
            let trimmed: String = KotlinText.trim(value)
            guard !trimmed.isEmpty else { return }
            out.append(pad(translate.translate(label) + ":") + trimmed)
        }
        if let setup {
            let category: String = setup.category.keys.sorted()
                .compactMap { key in
                    let value: String = KotlinText.trim(setup.category[key] ?? "")
                    return value.isEmpty ? nil : key + " " + value
                }
                .joined(separator: " · ")
            add("Kategorie", category)
            let sent: String = setup.sentExchange.keys.sorted()
                .compactMap { key in
                    let value: String = KotlinText.trim(setup.sentExchange[key] ?? "")
                    return value.isEmpty ? nil : key + " " + value
                }
                .joined(separator: " · ")
            add("Výměna", sent)
            add("Operátoři", setup.operators)
            if !KotlinText.trim(setup.startedAt).isEmpty {
                add("Začátek", setup.startedAt + " UTC")
            }
        }
        add("Jméno", station.name)
        add("Lokátor", station.gridSquare)
        let zones: String = [station.cqZone.isEmpty ? "" : "CQ " + station.cqZone,
                             station.ituZone.isEmpty ? "" : "ITU " + station.ituZone]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        add("Zóny", zones)
        add("Země", station.country)
        return out
    }

    /// The whole summary: the title (`<contest> — <call>`), the setup and station lines, then the table.
    public static func text(title: String, setupLines: [String], table: ScoreTable) -> String {
        var out: String = title + "\n"
        for line in setupLines {
            out += line + "\n"
        }
        out += "\n" + tableText(table)
        return out
    }

    /// The table with its columns aligned (leading columns to the left, numbers to the right), the totals, the
    /// per-mode rows, the formula and the note about QSOs that could not be counted.
    public static func tableText(_ table: ScoreTable) -> String {
        var rows: [[String]] = [table.headers]
        rows += table.rows
        rows.append(table.total)
        rows += table.modeRows
        let columns: Int = rows.map(\.count).max() ?? 0
        var widths = [Int](repeating: 0, count: columns)
        for row in rows {
            for (index, cell) in row.enumerated() {
                widths[index] = max(widths[index], cell.count)
            }
        }
        func line(_ cells: [String]) -> String {
            var parts: [String] = []
            for (index, cell) in cells.enumerated() {
                let gap = String(repeating: " ", count: max(0, widths[index] - cell.count))
                parts.append(index < table.lead ? cell + gap : gap + cell)
            }
            return parts.joined(separator: "  ").replacingOccurrences(of: "\\s+$", with: "",
                                                                      options: .regularExpression)
        }
        let rule = String(repeating: "-", count: widths.reduce(0, +) + max(0, columns - 1) * 2)
        var out: String = line(table.headers) + "\n" + rule + "\n"
        for row in table.rows {
            out += line(row) + "\n"
        }
        out += rule + "\n" + line(table.total) + "\n"
        if let title = table.modesTitle {
            out += "\n" + title + "\n"
            for row in table.modeRows {
                out += line(row) + "\n"
            }
        }
        out += "\n" + table.footer + "\n"
        if let skipped = table.skippedNote {
            out += skipped + "\n"
        }
        return out
    }

    private static func pad(_ label: String) -> String {
        label.count >= 15 ? label + " " : label + String(repeating: " ", count: 15 - label.count)
    }
}
