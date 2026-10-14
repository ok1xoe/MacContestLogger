import Foundation
import Testing
@testable import MCLAppModel
@testable import MCLCore

/// The Statistics window's contest dimensions, the dupes switch, the copy text, and typing that goes on in the
/// Entry window.
@MainActor @Suite struct StatisticsDimensionsTests {

    @Test func theContestsDimensionsComeFromItsReplay() async throws {
        let tool = try await ToolApp.make()
        let stats: StatisticsModel = tool.tools.statistics
        #expect(stats.contestDimensions.isEmpty)
        try await tool.start("cq-ww-cw")
        let dimensions: [StatsDimension] = stats.contestDimensions
        #expect(dimensions.contains(.points))
        #expect(dimensions.contains(.newMultiplier))
        #expect(dimensions.contains { if case .multiplier = $0 { return true } else { return false } })
        #expect(stats.rowChoices.contains(.minutes(10)))
        #expect(stats.columnChoices.last == .base(.NONE))
        #expect(stats.label(.minutes(10)) == "Po 10 minutách")

        stats.open()
        await tool.log("DL1ABC")
        await tool.log("DL1ABC")
        await tool.log("W1AW")
        stats.setRows(.newMultiplier)
        stats.setColumns(.NONE)
        await stats.settle()
        await eventually("three QSOs counted") { stats.snapshot?.table.grandTotal == "3" }
        let rows: [String] = stats.snapshot?.table.rows.map(\.label) ?? []
        #expect(Set(rows) == ["MULT", "—"], "\(rows)")
        stats.setIncludeDupes(false)
        await stats.settle()
        #expect(stats.snapshot?.table.grandTotal == "2", "the dupe is left out")
        #expect(stats.tableText?.hasPrefix("Nový násobič\tCelkem\tCelkem\n") == true, "\(stats.tableText ?? "")")
        stats.close()
    }

    @Test func typingGoesOnInTheEntryWindow() async throws {
        let app = try await TestApp.make()
        let model: AppModel = app.model
        model.entry.callChanged("OK1")
        model.typeIntoEntry("ab")
        #expect(model.entry.form.call == "OK1AB")
        #expect(model.rig.focusVfoRequest == 0)
        #expect(model.rig.focusCaretAtEnd)
        model.rig.focusVfoRequest = nil
        model.typeIntoEntry("!")
        #expect(model.entry.form.call == "OK1AB")
        #expect(model.rig.focusVfoRequest == nil)
    }
}
