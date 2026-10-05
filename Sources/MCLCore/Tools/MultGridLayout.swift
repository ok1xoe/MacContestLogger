import Foundation

/// The logic of the multiplier grid windows (Kotlin `MultiplierGridWindow.kt`, `MG:53-190, 270`): titles, the cell colours,
/// the sizes derived from the font size, the continent filter and the flow of rows into columns. Pure.
public enum MultGridLayout {

    /// The kinds of the window (menu order).
    public static let kinds: [String] = ["dxcc", "grid", "itu", "cq", "districts", "other", "sections"]

    /// The continents of the filter.
    public static let continents: [String] = ["AF", "AS", "EU", "NA", "OC", "SA"]

    /// Cell colours as `0xAARRGGBB` (worked, spotted, spotted with a double multiplier).
    public static let workedColor: UInt32 = 0xFF1E_88E5
    public static let spottedColor: UInt32 = 0xFFE5_3935
    public static let spottedDblColor: UInt32 = 0xFF43_A047

    /// `cellColor`: `nil` for an empty cell (drawn as an outline).
    public static func color(_ cell: MultCell) -> UInt32? {
        switch cell {
        case .worked: return workedColor
        case .spotted: return spottedColor
        case .spottedDbl: return spottedDblColor
        case .empty: return nil
        }
    }

    /// `kindTitle`: the window title of a kind (`DXCC`, `Okresy` and `Section/States` are not translated).
    public static func title(kind: String, translate: Translator) -> String {
        switch kind {
        case "dxcc": return "DXCC"
        case "grid": return translate.translate("Velké čtverce")
        case "itu": return translate.translate("ITU zóny")
        case "cq": return translate.translate("CQ zóny")
        case "districts": return "Okresy"
        case "other": return translate.translate("Ostatní")
        case "sections": return "Section/States"
        default: return translate.translate("Multiplikátory")
        }
    }

    /// The headline: `<title> — <worked> mults worked[ of <possible> possible]` (`possible < 0` = not enumerable).
    public static func headline(kind: String, worked: Int, possible: Int, translate: Translator) -> String {
        let name: String = title(kind: kind, translate: translate)
        if possible < 0 {
            return "\(name) — \(worked) mults worked"
        }
        return "\(name) — \(worked) mults worked of \(possible) possible"
    }

    /// Message without a contest.
    public static func noContestText(_ translator: Translator) -> String {
        translator.translate("Žádný aktivní závod.")
    }

    /// Message when the contest has no grid of this kind.
    public static func unavailableText(kind: String, translate: Translator) -> String {
        let first: String = translate.translate("Aktivní závod tento typ násobiče nemá, nebo mřížka pro %s ",
                                                [.string(title(kind: kind, translate: translate))])
        return first + translate.translate("zatím není implementovaná.")
    }

    /// Sizes derived from the font size (`GridMetrics`): every row has a fixed height so that the flow into columns
    /// fits exactly. All `Float` like Kotlin; the widths come from ~0.62 em per monospace character.
    public struct Metrics: Equatable, Sendable {
        public let fontSp: Int
        public let bandFontSp: Int
        public let cell: Float
        public let prefixW: Float
        public let square: Float
        public let colGap: Float
        public let prefixGap: Float
        public let rowH: Float
        public let headerH: Float

        public init(fontSp: Int) {
            self.fontSp = fontSp
            let band: Int = Swift.max(fontSp - 1, 6)
            self.bandFontSp = band
            let cellWidth: Float = Self.monoWidth(3, band)
            self.cell = cellWidth
            self.prefixW = Self.monoWidth(6, fontSp)
            let squareSize: Float = Float(fontSp + 3)
            self.square = squareSize
            let gap: Float = cellWidth - squareSize
            self.colGap = gap
            self.prefixGap = gap / 3
            let size: Float = Float(fontSp)
            self.rowH = size * 1.7 + 4
            self.headerH = size * 1.7 + 6
        }

        private static func monoWidth(_ chars: Int, _ sp: Int) -> Float {
            let perChar: Float = Float(chars) * 0.62
            return perChar * Float(sp) + 6
        }
    }

    /// Band header labels (`160`, `80`, …: the ADIF name without `m`).
    public static var bandHeaders: [String] {
        SpotAnalyzer.multGridBands.map { String($0.adif.dropLast()) }
    }

    /// The row label: the prefix, the key when the prefix is blank.
    public static func label(_ row: MultGridRow) -> String {
        KotlinText.isBlank(row.prefix) ? row.key : row.prefix
    }

    /// The cell of a row in a band (missing = empty).
    public static func cell(_ row: MultGridRow, band: Band) -> MultCell {
        row.cells[band.adif] ?? .empty
    }

    /// Hides rows without any record on a shown band and those outside the selected continents (a row without a
    /// continent always passes).
    public static func filter(rows: [MultGridRow], continents selected: Set<String>) -> [MultGridRow] {
        rows.filter { row in
            (KotlinText.isBlank(row.continent) || selected.contains(row.continent))
                && row.cells.values.contains { $0 != .empty }
        }
    }

    /// Does any row carry a continent (shows the filter)?
    public static func hasContinents(_ rows: [MultGridRow]) -> Bool {
        rows.contains { !KotlinText.isBlank($0.continent) }
    }

    /// "All" toggle: everything selected → none, otherwise all.
    public static func toggleAll(_ selected: Set<String>) -> Set<String> {
        selected.count == continents.count ? [] : Set(continents)
    }

    /// One continent toggle.
    public static func toggle(_ continent: String, in selected: Set<String>) -> Set<String> {
        var out = selected
        if out.contains(continent) {
            out.remove(continent)
        } else {
            out.insert(continent)
        }
        return out
    }

    /// Rows per column that fit a height: `((height − headerH) / rowH).toInt()`, at least 1.
    public static func rowsPerColumn(height: Float, rowHeight: Float, headerHeight: Float) -> Int {
        let fit: Float = (height - headerHeight) / rowHeight
        return Swift.max(Int(JavaMath.d2i(Double(fit))), 1)
    }

    /// The rows flowed into columns of `rowsPerColumn` (new rows only grow the end, the grid is not rearranged).
    public static func columns(rows: [MultGridRow], height: Float, rowHeight: Float, headerHeight: Float)
        -> [[MultGridRow]] {
        let per: Int = rowsPerColumn(height: height, rowHeight: rowHeight, headerHeight: headerHeight)
        var out: [[MultGridRow]] = []
        var from = 0
        while from < rows.count {
            out.append(Array(rows[from..<Swift.min(from + per, rows.count)]))
            from += per
        }
        return out
    }

    /// The same with the sizes of `metrics`.
    public static func columns(rows: [MultGridRow], height: Float, metrics: Metrics) -> [[MultGridRow]] {
        columns(rows: rows, height: height, rowHeight: metrics.rowH, headerHeight: metrics.headerH)
    }
}
