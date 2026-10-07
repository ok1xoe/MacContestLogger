import Foundation
import MCLCore
import Testing
@testable import MCLAppModel

/// Field order of the entry window (`K:EntryPanel.kt:686-721`, `:1012-1027`, `:1100-1118`).
@Suite struct EntryFocusOrderTests {

    private static func field(_ id: String, _ type: ContestDefinition.FieldType) -> ContestDefinition.ExchangeField {
        ContestDefinition.ExchangeField(id: id, type: type, required: true, source: nil, appliesWhen: nil,
                                        validation: nil)
    }

    private static let cqWw: [ContestDefinition.ExchangeField] = [field("rst", .RST), field("zone", .CQ_ZONE)]

    @Test func freeLoggingOrder() {
        let order = EntryFocusOrder(contestActive: false, fields: Self.cqWw)
        #expect(order.entries.map(\.key) == [.call, .rstSent, .rstRcvd, .exchange])
        #expect(order.exchangeTarget == .exchange)
        // Tab walks every field and wraps; Shift+Tab goes back.
        #expect(order.next(from: .call, direction: 1, skipReports: false) == .rstSent)
        #expect(order.next(from: .exchange, direction: 1, skipReports: false) == .call)
        #expect(order.next(from: .call, direction: -1, skipReports: false) == .exchange)
        // Space skips the reports: Snt → Exch, Exch → call.
        #expect(order.next(from: .rstSent, direction: 1, skipReports: true) == .exchange)
        #expect(order.next(from: .exchange, direction: 1, skipReports: true) == .call)
    }

    @Test func contestOrderAndExchangeTarget() {
        let order = EntryFocusOrder(contestActive: true, fields: Self.cqWw)
        #expect(order.entries.map(\.key) == [.call, .rstSent, .contest("rst"), .contest("zone")])
        #expect(order.entries.map(\.isReport) == [false, true, true, false])
        #expect(order.exchangeTarget == .contest("zone"))
        #expect(order.next(from: .contest("rst"), direction: 1, skipReports: false) == .contest("zone"))
        #expect(order.next(from: .rstSent, direction: 1, skipReports: true) == .contest("zone"))
        #expect(order.next(from: .contest("zone"), direction: 1, skipReports: true) == .call)
        #expect(order.next(from: .rstRcvd, direction: 1, skipReports: false) == nil)
    }

    @Test func onlyReportsMeansTheFirstField() {
        let order = EntryFocusOrder(contestActive: true, fields: [Self.field("rs", .RS), Self.field("rst", .RST)])
        #expect(order.exchangeTarget == .contest("rs"))
        #expect(EntryFocusOrder(contestActive: true, fields: []).exchangeTarget == nil)
    }

    @Test func spaceInTheCallFieldKeepsArgumentCommands() {
        #expect(EntryFocusOrder.spaceJumpsFromCall("DL1ABC"))
        #expect(EntryFocusOrder.spaceJumpsFromCall(""))
        #expect(!EntryFocusOrder.spaceJumpsFromCall("OPON"))
        #expect(!EntryFocusOrder.spaceJumpsFromCall(" tour 3"))
        #expect(!EntryFocusOrder.spaceJumpsFromCall("bonus"))
        #expect(EntryFocusOrder.spaceJumpsFromCall("OPONX"))
    }
}

/// The band × mode grid (`K:EntryPanel.kt:1708-1786`, `KA:3766-3991`).
@MainActor @Suite struct EntryGridTests {

    @Test func outsideAContestEverythingIsShown() async throws {
        let app = try await TestApp.make()
        let grid: EntryGrid = EntryGrid.of(app.model.contest)
        #expect(grid.columns == [.CW, .PH, .RY, .DI])
        #expect(grid.rows.map(\.band) == Band.javaV111Cases)
        let row40: BandRows.Row = try #require(grid.rows.first { $0.band == .m40 })
        let cell = grid.cell(row40, .CW, currentBand: .m40, currentMode: .cw)
        #expect(cell == EntryGrid.Cell(kHz: 7_000, enabled: true, active: true))
        let row30: BandRows.Row = try #require(grid.rows.first { $0.band == .m30 })
        #expect(grid.cell(row30, .PH, currentBand: .m30, currentMode: .ssb).enabled == false)
    }

    /// Without a MODE category every column stays (Kotlin `columnsFor(null, …)` → all).
    @Test func cqWwCwShowsItsBands() async throws {
        let app = try await TestApp.make()
        try await app.startCqWwCw()
        let grid: EntryGrid = EntryGrid.of(app.model.contest)
        #expect(grid.columns == [.CW, .PH, .RY, .DI])
        #expect(grid.rows.map(\.band) == [.m160, .m80, .m40, .m20, .m15, .m10])
        let row20: BandRows.Row = try #require(grid.rows.first { $0.band == .m20 })
        #expect(grid.cell(row20, .CW, currentBand: .m20, currentMode: .cw).active)
        #expect(!grid.cell(row20, .CW, currentBand: .m40, currentMode: .cw).active)
    }

    @Test func singleBandCategoryDisablesTheOtherRows() async throws {
        let app = try await TestApp.make()
        var setup = ContestSetup()
        setup.sentExchange = ["zone": "15"]
        setup.category = ["BAND": "20M", "MODE": "CW"]
        let started: Bool = await app.model.contest.createAndStart(definitionId: "cq-ww-cw", setup: setup)
        try #require(started)
        let grid: EntryGrid = EntryGrid.of(app.model.contest)
        #expect(grid.enabledBands == [.m20])
        #expect(grid.columns == [.CW])
        #expect(grid.rows.count == 6)
    }

    @Test func columnModes() {
        #expect(EntryGridPolicy.ModeColumn.allCases.map(EntryGrid.mode) == [.cw, .ssb, .rtty, .digital])
        #expect(EntryGrid.isActive(.PH, mode: .fm))
        #expect(EntryGrid.isActive(.DI, mode: .ft8))
        #expect(!EntryGrid.isActive(.DI, mode: .jt65))
        #expect(!EntryGrid.isActive(.RY, mode: .psk))
    }
}

/// Score strip, status line and the feedback under the fields.
@MainActor @Suite struct MainWindowTextTests {

    @Test func fontStepperBounds() {
        #expect(WindowFont.clamp(7) == 8)
        #expect(WindowFont.clamp(29) == 28)
        #expect(WindowFont.clamp(15) == 15)
        #expect(WindowFont.size(20, windowSize: 12) == 20)
        #expect(WindowFont.size(12, windowSize: 16) == 16)
        #expect(WindowFont.size(14, windowSize: 20) == 14.0 * 20 / 12)
        #expect(WindowFont.size(24, windowSize: 8) == 16)
    }

    @Test func scoreAndStatusOutsideAContest() async throws {
        let app = try await TestApp.make()
        #expect(ScoreLine.of(contest: app.model.contest) == nil)
        let line: StatusLine = StatusLine.of(app.model)
        #expect(line.sentExchange == nil)
        #expect(line.message == "TRX odpojen")
        #expect(line.contestName == nil)
        app.model.status.showVerbatim("x")
        #expect(StatusLine.of(app.model).message == "x")
    }

    @Test func scoreStatusAndFeedbackInCqWwCw() async throws {
        let app = try await TestApp.make()
        try await app.startCqWwCw()
        await app.logContestQso(call: "DL1ABC", zone: "14")
        let score: ScoreLine = try #require(ScoreLine.of(contest: app.model.contest))
        #expect(score.qso == "1")
        #expect(score.mult == "2")
        let line: StatusLine = StatusLine.of(app.model)
        #expect(line.sentExchange == "599 15")
        #expect(line.contestName == "CQ WW DX Contest — CW")
        let entry: EntryModel = app.model.entry
        entry.callChanged("DL1ABC")
        entry.editContestField("zone", "14")
        guard case .contest(let dupe, let chips) = EntryFeedback.of(entry: entry, contest: app.model.contest) else {
            Issue.record("expected the contest preview")
            return
        }
        #expect(dupe)
        #expect(chips.map(\.stateKey) == ["už", "už"])
        #expect(chips.map(\.bindingId) == ["zones", "countries"])
        entry.callChanged("")
        #expect(EntryFeedback.of(entry: entry, contest: app.model.contest) == .none)
        #expect(!EntryFeedback.missingStationCall(app.model.contest))
    }

    /// Free logging: a repeated call shows no feedback, no contest score and no sent exchange.
    @Test func freeLoggingHasNoDupeFeedbackAndNoScore() async throws {
        let app = try await TestApp.make()
        try await app.startCqWwCw()
        app.model.contest.deactivate()
        await app.model.contest.settleActivations()
        let entry: EntryModel = app.model.entry
        entry.setFrequency("14025")
        entry.callChanged("OK1ABC")
        entry.submit()
        await entry.settle()
        entry.callChanged("OK1ABC")
        #expect(!entry.isDupe)
        #expect(EntryFeedback.of(entry: entry, contest: app.model.contest) == .none)
        #expect(ScoreLine.of(contest: app.model.contest) == nil)
        let line: StatusLine = StatusLine.of(app.model)
        #expect(line.sentExchange == nil)
        #expect(line.contestName == nil)
    }
}

/// n-2: no input while the app quits or switches the database.
@MainActor @Suite struct EntryInputGateTests {

    @Test func submitDuringShutdownIsIgnored() async throws {
        let app = try await TestApp.make()
        let entry: EntryModel = app.model.entry
        #expect(app.model.acceptsEntryInput && entry.acceptsInput)
        entry.setFrequency("14025")
        entry.callChanged("OK1ABC")
        await app.model.shutdown()
        #expect(!app.model.acceptsEntryInput)
        entry.submit()
        #expect(entry.form.call == "OK1ABC")
        #expect(entry.submitTask == nil)
    }

    @Test func entryIsBlockedWhileTheDatabaseSwitches() async throws {
        let app = try await TestApp.make()
        let model: AppModel = app.model
        var seen: [Bool] = []
        model.database.drain = { [weak model] in
            guard let model else { return }
            seen.append(model.acceptsEntryInput)
            model.entry.setFrequency("14025")
            model.entry.callChanged("OK1ABC")
            model.entry.submit()
            await model.drainDatabaseWork()
        }
        await model.database.create("Druhá")
        #expect(seen == [false])
        #expect(model.entry.submitTask == nil)
        #expect(model.acceptsEntryInput)
        #expect(model.logbook.rows.isEmpty)
    }
}

/// Typed text of the entry fields (`K:EntryPanel.kt:1102`, `:1144`, `:1155`, `:1566`).
@Suite struct EntryTextTransformTests {

    @Test func uppercaseIsKotlins() {
        #expect(EntryTextTransform.uppercase.apply("ok1xoe/p") == "OK1XOE/P")
        #expect(EntryTextTransform.uppercase.apply("ß") == "SS")
        #expect(EntryTextTransform.none.apply("5nn") == "5nn")
    }

    @Test func frequencyKeepsDigitsDotAndComma() {
        #expect(EntryTextTransform.frequency.apply("14 025,5 kHz") == "14025,5")
        #expect(EntryTextTransform.frequency.apply("7.010-") == "7.010")
        // Kotlin `isDigit` is Unicode Nd: Arabic-Indic digits pass the filter (and then do not parse).
        #expect(EntryTextTransform.frequency.apply("\u{0661}\u{0664}x") == "\u{0661}\u{0664}")
        #expect(EntryTextTransform.frequency.apply("\u{1D7CE}1") == "1")
    }

    /// The post-contest time field (`EP:1093`): digits, `:`, `-` and the space.
    @Test func paperTimeKeepsDigitsColonDashAndSpace() {
        #expect(EntryTextTransform.paperTime.apply("2026-10-02 14:32Z") == "2026-10-02 14:32")
        #expect(EntryTextTransform.paperTime.apply("14.32,a\t") == "1432")
        #expect(EntryTextTransform.paperTime.apply("\u{0661}\u{0664}\u{1D7CE}") == "\u{0661}\u{0664}")
    }
}

/// Important 1 of the review: SwiftUI's own frame records must not survive (the config is the only geometry store).
/// The store is in memory: no test creates a defaults domain (a plist in `~/Library/Preferences`).
@Suite struct WindowFrameDefaultsTests {

    /// The defaults' own domain plus a read-only global domain (`UserDefaults` shows both, removes from its own).
    final class MemoryStore: FrameRecordStore {
        var own: [String: String]
        let global: [String: String]

        init(own: [String: String], global: [String: String] = [:]) {
            self.own = own
            self.global = global
        }

        func recordKeys() -> [String] {
            Array(Set(own.keys).union(global.keys))
        }

        func hasRecord(forKey key: String) -> Bool {
            own[key] != nil || global[key] != nil
        }

        func removeRecord(forKey key: String) {
            own[key] = nil
        }
    }

    @Test func frameRecordsAreRemovedAndOtherKeysKept() {
        let store = MemoryStore(own: [
            "NSWindow Frame main": "3388 454 820 528 2056 360 3200 1770 ",
            "NSWindow Frame log": "578 453 900 450 0 0 2056 1290 ",
            "SomethingElse": "1",
        ])
        let removed: [String] = WindowFrameDefaults.removeFrameRecords(in: store)
        #expect(removed == ["NSWindow Frame log", "NSWindow Frame main"])
        #expect(store.own.keys.sorted() == ["SomethingElse"])
        #expect(WindowFrameDefaults.removeFrameRecords(in: store).isEmpty)
    }

    /// The open/save panels' size records go too; a record of the global domain is not reported as removed.
    @Test func navPanelSizeRecordsAreRemoved() {
        let store = MemoryStore(own: [
            "NSNavPanelExpandedSizeForOpenMode": "{712, 448}",
            "NSNavPanelExpandedSizeForSaveMode": "{800, 500}",
            "NSWindow Frame entry-vfob": "578 453 900 450 0 0 2056 1290 ",
            "NSNavLastRootDirectory": "kept",
        ], global: ["NSWindow Frame global": "1 2 3 4 "])
        let removed: [String] = WindowFrameDefaults.removeFrameRecords(in: store)
        #expect(removed == [
            "NSNavPanelExpandedSizeForOpenMode", "NSNavPanelExpandedSizeForSaveMode", "NSWindow Frame entry-vfob",
        ])
        #expect(store.own.keys.sorted() == ["NSNavLastRootDirectory"])
    }

    /// A window whose autosave name SwiftUI assigned again: its record is removed when the binder clears the name.
    @Test func theRecordOfAReassignedAutosaveNameIsRemoved() {
        let store = MemoryStore(own: [
            "NSWindow Frame main": "3388 454 820 528 2056 360 3200 1770 ",
            "NSWindow Frame log": "578 453 900 450 0 0 2056 1290 ",
        ])
        #expect(!WindowFrameDefaults.removeRecord(autosaveName: "", in: store))
        #expect(WindowFrameDefaults.removeRecord(autosaveName: "main", in: store))
        #expect(!WindowFrameDefaults.removeRecord(autosaveName: "main", in: store))
        #expect(store.own.keys.sorted() == ["NSWindow Frame log"])
    }
}
