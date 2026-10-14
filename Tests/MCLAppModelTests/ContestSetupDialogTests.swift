import Foundation
import MCLCore
import Testing
@testable import MCLAppModel

/// File → Contest setup over the open log, the contest browser's Delete and the New contest list's search.
@MainActor @Suite struct ContestSetupDialogTests {

    @Test func contestSetupEditsTheOpenLog() async throws {
        let app = try await TestApp.make()
        let dialogs: DialogsModel = app.model.dialogs
        dialogs.openContestSetup()
        #expect(dialogs.newContest == nil, "no open contest")
        try await app.startCqWwCw()
        await app.logContestQso(call: "DL1ABC", zone: "14")
        dialogs.openContestSetup()
        let form: NewContestModel = try #require(dialogs.newContest)
        #expect(form.isEditing)
        #expect(form.form.sentExchange["zone"] == "15")
        form.select(label: "anything")
        #expect(form.selectedId == "cq-ww-cw")
        form.form.soapbox = "Great"
        form.firstSerialText = "201"
        form.updateOperatorsFromLog()
        #expect(form.form.operators == "OK1XOE")
        dialogs.confirmNewContest()
        await dialogs.settle()
        #expect(dialogs.newContest == nil)
        #expect(app.model.contest.activeSetup?.soapbox == "Great")
        #expect(app.model.contest.activeSetup?.firstSerial == 201)
        #expect(app.model.logbook.nextSerial == 202)
        #expect(app.model.status.message == "Nastavení závodu uloženo")
    }

    @Test func deleteRefusesTheOpenContestAndRemovesAnother() async throws {
        let app = try await TestApp.make()
        try await app.startCqWwCw()
        await app.logContestQso(call: "DL1ABC", zone: "14")
        let first: String = try #require(app.model.contest.activeId)
        #expect(!(await app.model.contest.deleteContest(first)))
        try await app.startCqWwCw()
        #expect(app.model.contest.activeId != first)
        #expect((await app.model.contest.browserRows()).count == 2)
        #expect(await app.model.contest.deleteContest(first))
        #expect((await app.model.contest.browserRows()).map(\.contestId) == [app.model.contest.activeId])
        #expect(!app.model.contest.recent.contains { $0.contestId == first })
    }

    @Test func newContestListSearchAndOrder() async throws {
        let app = try await TestApp.make()
        let dialogs: DialogsModel = app.model.dialogs
        dialogs.setOpen(.newContest, true)
        let form: NewContestModel = try #require(dialogs.newContest)
        let all: [String] = form.visibleLabels
        form.search = "wpx"
        #expect(!form.visibleLabels.isEmpty)
        #expect(form.visibleLabels.allSatisfy { $0.lowercased().contains("wpx") })
        form.search = ""
        form.sortByName = true
        #expect(form.visibleLabels == all.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
        #expect(form.rulesUrl != nil || form.definition?.metadata?.officialUrl == nil)
    }
}
