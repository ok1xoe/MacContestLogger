import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// A QSO replaced by an edit on another station: the receiving station takes the whole new QSO — fields the edit
/// cleared are cleared there too, and nothing of the old QSO stays behind (dupe, values); the logging station keeps
/// its run mode when its own edit comes back.
@MainActor @Suite struct SyncReplaceTests {

    @Test func anEditThatClearsFieldsLeavesNoOldValuesOnTheOtherStation() async throws {
        let hub = InMemorySyncTransport()
        let now = NetStation.start()
        let a = try await NetStation.make(id: "OP1", hub: hub, now: now)
        let b = try await NetStation.make(id: "OP2", hub: hub, now: now)
        try await a.activate()
        try await b.activate()

        await a.log("DL1ABC")
        await eventually("B sees the QSO") { b.model.logbook.rows.map(\.call) == ["DL1ABC"] }

        var filled: Qso = try #require(a.model.logbook.rows.first)
        let original: Qso = filled
        filled.comment = "tnx"
        filled.operator = "OK1XYZ"
        filled.serialRcvd = 42
        filled.radioNr = 2
        filled.runMode = .searchAndPounce
        _ = await a.model.logbook.update(LogbookMutations.Edit(old: original, new: filled))
        await eventually("B sees the filled fields") { b.model.logbook.rows.first?.comment == "tnx" }
        let before: Qso = try #require(b.model.logbook.rows.first)
        #expect(before.operator == "OK1XYZ")
        #expect(before.serialRcvd == 42)
        #expect(before.radioNr == 2)

        var cleared: Qso = try #require(a.model.logbook.rows.first)
        let old: Qso = cleared
        cleared.call = "DL2XYZ"
        cleared.comment = ""
        cleared.operator = ""
        cleared.serialRcvd = nil
        cleared.radioNr = 0
        _ = await a.model.logbook.update(LogbookMutations.Edit(old: old, new: cleared))
        await eventually("B sees the replacement") { b.model.logbook.rows.first?.call == "DL2XYZ" }
        await b.settle()

        let seen: Qso = try #require(b.model.logbook.rows.first)
        #expect(b.model.logbook.rows.count == 1)
        #expect(seen.comment == "")
        #expect(seen.operator == "")
        #expect(seen.serialRcvd == nil)
        #expect(seen.radioNr == 0)
        #expect(!b.model.logbook.isDupe(call: "DL1ABC", band: .m20))
        #expect(b.model.logbook.isDupe(call: "DL2XYZ", band: .m20))
        let stored: [Qso] = try await b.model.database.handle.run { try $0.service.findAllIncludingDeleted() }
        #expect(stored.count == 1)
        #expect(stored.first?.comment == "")
        #expect(stored.first?.operator == "")
        #expect(stored.first?.serialRcvd == nil)
        #expect(stored.first?.call == "DL2XYZ")
        // Run / S&P is not on the wire: the logging station keeps its own when its edit comes back.
        let own: [Qso] = try await a.model.database.handle.run { try $0.service.findAllIncludingDeleted() }
        #expect(own.first?.runMode == .searchAndPounce)
    }
}
