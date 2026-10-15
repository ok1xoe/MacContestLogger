import Foundation
import MCLCore

/// The N1MM Available window beyond v1.1.1: the chosen columns with their order and widths, the summary panel's
/// bands and its click, Alt+A / Shift+Alt+A, the row marks, the speaker column, the rotator and the other radio.
extension AvailMultModel {

    // MARK: - columns

    /// The visible columns in their order (`config.dxCluster.availColumns`).
    public var columns: [AvailableColumn] {
        AvailableColumn.visible(config.config.dxCluster.availColumns)
    }

    /// Shows or hides a column (the call always shows); a shown column goes to the end.
    public func setColumn(_ column: AvailableColumn, visible: Bool) {
        var list: [AvailableColumn] = columns
        if visible {
            guard !list.contains(column) else { return }
            list.append(column)
        } else {
            guard column != .call else { return }
            list.removeAll { $0 == column }
        }
        saveColumns(list)
    }

    /// Moves a visible column one place left (`-1`) or right (`+1`).
    public func moveColumn(_ column: AvailableColumn, by offset: Int) {
        var list: [AvailableColumn] = columns
        guard let index = list.firstIndex(of: column) else { return }
        let target: Int = index + offset
        guard list.indices.contains(target) else { return }
        list.swapAt(index, target)
        saveColumns(list)
    }

    /// The default columns, order and widths again.
    public func resetColumns() {
        saveDx(\.availColumns, [])
        saveDx(\.availColumnWidths, [:])
    }

    private func saveColumns(_ list: [AvailableColumn]) {
        let ids: [String] = list.map(\.rawValue)
        saveDx(\.availColumns, ids == AvailableColumn.defaultOrder.map(\.rawValue) ? [] : ids)
    }

    /// A column's share of the row width (a dragged width first).
    public func width(_ column: AvailableColumn) -> Int {
        if let dragged = draggedWidths[column.rawValue] {
            return dragged
        }
        return column.width(in: config.config.dxCluster.availColumnWidths)
    }

    /// The divider right of `column` is being dragged: its width changes live, nothing is saved yet.
    public func dragWidth(_ column: AvailableColumn, to width: Int) {
        let range: ClosedRange<Int> = AvailableColumn.widthRange
        draggedWidths[column.rawValue] = min(range.upperBound, max(range.lowerBound, width))
    }

    /// The drag ended: the widths are saved.
    public func endWidthDrag() {
        guard !draggedWidths.isEmpty else { return }
        var widths: [String: Int] = config.config.dxCluster.availColumnWidths
        for (id, width) in draggedWidths {
            widths[id] = width
        }
        draggedWidths = [:]
        saveDx(\.availColumnWidths, widths)
    }

    // MARK: - summary panel

    /// N1MM „Show Summary Panel".
    public var showSummary: Bool {
        config.config.dxCluster.availShowSummary
    }

    public func setShowSummary(_ on: Bool) {
        saveDx(\.availShowSummary, on)
    }

    /// The summary's bands: the chosen ones, otherwise the contest's, otherwise v1.1.1's six HF bands.
    public var summaryBands: [Band] {
        AvailableMults.summaryBands(configured: config.config.dxCluster.availSummaryBands, contestBands: supportedBands)
    }

    /// The bands ticked in the sheet (empty = automatic).
    public var chosenSummaryBands: Set<Band> {
        Set(config.config.dxCluster.availSummaryBands.compactMap { Band.from(adif: $0) })
    }

    public func setSummaryBand(_ band: Band, on: Bool) {
        var chosen: Set<Band> = chosenSummaryBands
        if on {
            chosen.insert(band)
        } else {
            chosen.remove(band)
        }
        saveDx(\.availSummaryBands, Band.allCases.filter { chosen.contains($0) }.map(\.adif))
    }

    /// A click on a band of the summary: the list shows only that band; a second click brings the bands back.
    public func clickSummary(_ band: Band) {
        if bands == [band], let previous = bandsBeforeSummary {
            bandsBeforeSummary = nil
            bands = previous
            return
        }
        bandsBeforeSummary = bands
        bands = [band]
    }

    // MARK: - Alt+A / Shift+Alt+A

    /// N1MM Alt+A (`forward`) / Shift+Alt+A: the next / previous spot of the list (as sorted and filtered) is tuned
    /// and its call taken, as a click on it does; the list starts at its top (or bottom) and wraps around.
    public func grab(forward: Bool) {
        let rows: [SpotRow] = snapshot().rows
        guard !rows.isEmpty else {
            status.show("Okno Dostupné: žádný spot")
            return
        }
        let current: Int? = grabbedCall.flatMap { call in rows.firstIndex { $0.call == call } }
        let next: Int
        if let current {
            next = (current + (forward ? 1 : -1) + rows.count) % rows.count
        } else {
            next = forward ? 0 : rows.count - 1
        }
        grabbedCall = rows[next].call
        click(rows[next])
    }

    // MARK: - row marks

    /// What the row shows beyond v1.1.1: the skimmer mark (`#`, `!` for one's own skimmer), the gray line and the
    /// split (QSX) frequency of the spot's comment (the band map's marks, `BandmapSpotInfo`).
    public struct Marks: Equatable, Sendable {
        public let skimmer: String?
        public let grayLine: Bool
        public let qsxHz: Int?
    }

    public func marks(_ row: SpotRow) -> Marks {
        guard let spot = feed.buffer.find(row.call)?.spot else {
            return Marks(skimmer: nil, grayLine: false, qsxHz: nil)
        }
        let grayLine: Bool
        if let entity = contest.runtime.dxccLookup?.resolve(row.call), entity.hasLatLon {
            grayLine = BandmapSpotInfo.onGrayLine(lat: entity.lat, lon: entity.lon, now: now())
        } else {
            grayLine = false
        }
        return Marks(skimmer: BandmapSpotInfo.skimmerMark(spot, myCall: config.config.station.call),
                     grayLine: grayLine, qsxHz: BandmapSpotInfo.qsxHz(spot))
    }

    /// The call cell: the call, the special-call heart, the skimmer mark and `¤` (as the band map draws them).
    public static func callText(_ call: String, special: Bool, marks: Marks) -> String {
        var text: String = call
        if special {
            text += SpecialCalls.mark
        }
        if let skimmer = marks.skimmer {
            text += skimmer
        }
        if marks.grayLine {
            text += BandmapSpotInfo.grayLineMark
        }
        return text
    }

    /// The Freq cell: the kHz and, for a split spot, `QSX 027`.
    public static func freqText(_ freqHz: Int, qsxHz: Int?) -> String {
        let khz: String = EntryFormat.oneDecimal(Double(freqHz) / 1000.0)
        guard let qsxHz else { return khz }
        return khz + " QSX " + BandmapSpotInfo.qsxText(qsxHz)
    }

    /// The Time cell: the spot's age in whole minutes (`3m`), empty when unknown.
    public func ageText(_ row: SpotRow, in snapshot: Snapshot, at date: Date) -> String {
        guard let spotted = snapshot.spottedAt[row.call.uppercased()] else { return "" }
        return String(BandmapSpotInfo.ageMinutes(spottedAt: spotted, now: date)) + "m"
    }

    /// The speaker column: the spot's signal is seen in the waterfall now (`false` with the waterfall closed).
    public func isHeard(_ row: SpotRow, spectrum: SignalHeard.Spectrum?) -> Bool {
        spectrum?.hears(freqHz: row.freqHz) ?? false
    }

    // MARK: - row actions

    /// The middle click: the spot under the pointer is deleted (`false` = no row under it).
    @discardableResult
    public func removeHovered() -> Bool {
        guard let call = hoveredCall else { return false }
        feed.buffer.remove(call)
        hoveredCall = nil
        return true
    }

    /// „Natočit rotátor": the rotator to the spotted station (short path), as Alt+J does with the call — by the spot's
    /// grid when one is known (the comment, the grid database, the callbook).
    public func turnRotor(_ row: SpotRow) {
        let grid: String? = feed.buffer.find(row.call).flatMap { analysis.current().gridForSpot($0.spot) }
        rotorTurner(row.call, grid)
    }

    /// The other radio or VFO exists (SO2V, SO2R): the row menu offers its QSY.
    public var hasOtherRadio: Bool {
        rig.otherVfoIndex != nil
    }

    /// „QSY druhého rádia": the other radio / VFO to the spot, the focus stays.
    public func qsyOtherRadio(_ row: SpotRow) {
        rig.qsyOtherRadio(Int64(row.freqHz))
    }

    private func saveDx<Value: Equatable>(_ field: WritableKeyPath<DxClusterConfig, Value>, _ value: Value) {
        guard config.config.dxCluster[keyPath: field] != value else { return }
        config.config.dxCluster[keyPath: field] = value
        config.save(failureKey: "Uložení nastavení okna Dostupné selhalo (%s)")
    }
}

extension AvailMultModel {

    /// The row's marks said in words for VoiceOver (each prefixed with `, `; empty without marks).
    public static func spokenMarks(_ marks: Marks, heard: Bool, translator: Translator) -> String {
        var parts: [String] = []
        if marks.skimmer != nil {
            parts.append(translator.translate("skimmer"))
        }
        if marks.grayLine {
            parts.append(translator.translate("na šedé zóně"))
        }
        if let qsx = marks.qsxHz {
            parts.append(translator.translate("split QSX %s", [.string(BandmapSpotInfo.qsxText(qsx))]))
        }
        if heard {
            parts.append(translator.translate("signál je ve vodopádu"))
        }
        return parts.map { ", " + $0 }.joined()
    }
}
