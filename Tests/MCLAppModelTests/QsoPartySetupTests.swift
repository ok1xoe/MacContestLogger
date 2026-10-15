import Foundation
import Testing
@testable import MCLAppModel
@testable import MCLCore

/// N1MM's QSO party setup: the in-state / out-of-state message of a new log and the section list editing of the
/// contest dialog.
@MainActor @Suite struct QsoPartySetupTests {

    static let party = """
        schemaVersion: 1
        id: test-party
        metadata: { name: "Test Party" }
        bands: [40m, 20m]
        modes: [CW]
        inState:
          sections: [SCV, EB]
        exchange:
          sent:
            - { id: rst, type: RST, source: AUTO_RST }
          received:
            - { id: rst,  type: RST,  required: true }
            - { id: cnty, type: TEXT, required: true }
        scoring:
          qsoPoints: { mode: FIRST_MATCH, default: 1 }
          total: "qsoPoints * multTotal"
        multipliers:
          - { id: counties, set: ok_om_districts, from: cnty, scope: ONCE, when: { inState: false } }
        dupe: { scope: PER_BAND_MODE }
        """

    @Test func aNewPartyLogSaysInStateOrOutOfState() async throws {
        let app = try await PortedApp.make(contests: ["test-party": Self.party]) { config in
            config.station.call = "K6ABC"
            config.station.arrlSection = "scv"
        }
        try await app.start("test-party")
        #expect(app.status == "QSO party: stanice ve státě (sekce SCV)")
    }

    @Test func theDialogEditsAndRestoresTheSectionList() async throws {
        let app = try await PortedApp.make(contests: ["test-party": Self.party])
        app.model.dialogs.setOpen(.newContest, true)
        let form = try #require(app.model.dialogs.newContest)
        form.select(label: try #require(form.visibleLabels.first { $0.contains("Test Party") }))
        #expect(form.sectionSets == ["ok_om_districts"])
        #expect(!form.sectionsEdited("ok_om_districts"))
        form.editSections("ok_om_districts")
        let editor = try #require(form.sectionEditor)
        #expect(editor.text.contains("APA,"))
        form.sectionEditor?.text = editor.text + "ZZZ,Test district\n"
        await form.saveSections()
        #expect(form.sectionEditor == nil)
        #expect(form.sectionsEdited("ok_om_districts"))
        let csv: URL = app.dir.child("contest-data").appendingPathComponent("multipliers/ok_om_districts.csv")
        #expect(try String(contentsOf: csv, encoding: .utf8).contains("ZZZ,Test district"))
        await form.restoreSections("ok_om_districts")
        #expect(!form.sectionsEdited("ok_om_districts"))
        #expect(try !String(contentsOf: csv, encoding: .utf8).contains("ZZZ"))
    }
}
