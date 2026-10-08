import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// File → Post result to 3830: a preview and a copy of the form's data; the site is only opened (fake URL port).
@MainActor @Suite struct ScoreSubmitTests {

    @Test func needsAnActiveContest() async throws {
        let app = try await TestApp.make()
        #expect(!app.model.menu.runtimeEnabled("file.post3830"))
        #expect(MenuActions.perform("file.post3830", app: app.model) == nil)
        #expect(app.model.status.message == "Odeslat výsledek: není aktivní závod")
        #expect(app.model.dialogs.score3830 == nil)
    }

    @Test func thePreviewHasTheContestScoreAndSoapbox() async throws {
        let app = try await TestApp.make()
        let model: AppModel = app.model
        var setup = ContestSetup()
        setup.sentExchange = ["zone": "15"]
        setup.category = ["OPERATOR": "SINGLE-OP", "POWER": "LOW"]
        setup.soapbox = "Good fun"
        let started: Bool = await model.contest.createAndStart(definitionId: "cq-ww-cw", setup: setup)
        try #require(started)
        await app.logContestQso(call: "DL1ABC", zone: "14")
        await app.logContestQso(call: "W1AW", zone: "5")
        #expect(model.menu.runtimeEnabled("file.post3830"))

        #expect(MenuActions.perform("file.post3830", app: model) == nil)
        let window: ScoreSubmitModel = try #require(model.dialogs.score3830)
        #expect(window.soapbox == "Good fun")
        let total: Int64 = try #require(model.contest.score?.total)
        let lines: [String] = window.text.components(separatedBy: "\n")
        #expect(lines.contains("Volačka: OK1XOE"))
        #expect(lines.contains("Závod: CQ WW DX Contest — CW"))
        #expect(lines.contains("Kategorie: OPERATOR: SINGLE-OP, POWER: LOW"))
        #expect(lines.contains("QSO: 2"))
        #expect(lines.contains("Celkové skóre: \(total)"))
        #expect(lines.last == "Soapbox: Good fun")
        window.soapbox = "Edited"
        #expect(window.text.hasSuffix("Soapbox: Edited"))
        // The setup's own soapbox is not changed.
        #expect(model.contest.activeSetup?.soapbox == "Good fun")
        // English labels follow the language.
        await model.language.switchTo("en")
        #expect(window.text.hasPrefix("Call: OK1XOE\nContest: "))
        await model.language.switchTo("cs")
    }

    @Test func theSiteIsOnlyOpenedThroughTheUrlPort() async throws {
        let spot = try await SpotApp.make()
        try await spot.app.startCqWwCw()
        #expect(MenuActions.perform("file.post3830", app: spot.model) == nil)
        let window: ScoreSubmitModel = try #require(spot.model.dialogs.score3830)
        #expect(spot.opener.urls.isEmpty)
        window.openSite()
        await spot.model.callbook.settle()
        #expect(spot.opener.urls == ["https://www.3830scores.com/"])
    }
}
