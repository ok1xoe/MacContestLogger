import Foundation
import Testing
@testable import MCLCore

/// `EntryForm` per the source `ui/EntryPanel.kt:148-162` (state), `:267-269` (RST fields), `:326-351`
/// (`applyDefaultRst`, `applyContestRst`, `wipe`), `:1126` and `:1151` (edits).
@Suite struct EntryFormTests {

    private static let rst = ["rst"] as [String?]

    @Test func initialStateIsSsb() {
        let form = EntryForm()
        #expect(form.call == "")
        #expect(form.freqKHz == "")
        #expect(form.mode == .ssb)
        #expect(form.rstSent == "59")
        #expect(form.rstRcvd == "59")
        #expect(form.exch == "")
        #expect(form.contestExchange.isEmpty)
        #expect(form.touchedFields.isEmpty)
        #expect(!form.rstSentTouched)
    }

    @Test func applyDefaultRstSetsBothReports() {
        var form = EntryForm()
        form.applyDefaultRst(.cw)
        #expect(form.rstSent == "599")
        #expect(form.rstRcvd == "599")
        form.applyDefaultRst(.ft8)
        #expect(form.rstSent == "599")
        form.applyDefaultRst(.fm)
        #expect(form.rstRcvd == "59")
    }

    @Test func applyContestRstFillsUntouchedFieldsAndSentReport() {
        var form = EntryForm()
        form.applyContestRst(.cw, rstFieldIds: Self.rst)
        #expect(form.contestExchange["rst"] == "599")
        #expect(form.rstSent == "599")
        // The free-mode received report is not part of the contest fields.
        #expect(form.rstRcvd == "59")
    }

    @Test func applyContestRstKeepsTouchedValues() {
        var form = EntryForm()
        form.applyContestRst(.cw, rstFieldIds: Self.rst)
        form.editContestField("rst", "57")
        form.editRstSent("579")
        form.applyContestRst(.ssb, rstFieldIds: Self.rst)
        #expect(form.contestExchange["rst"] == "57")
        #expect(form.rstSent == "579")
        #expect(form.touchedFields == ["rst"])
        #expect(form.rstSentTouched)
    }

    @Test func applyContestRstOverwritesUntouchedOnModeChange() {
        var form = EntryForm()
        form.applyContestRst(.cw, rstFieldIds: Self.rst)
        form.editContestField("zone", "15")
        form.applyContestRst(.ssb, rstFieldIds: Self.rst)
        #expect(form.contestExchange["rst"] == "59")
        #expect(form.contestExchange["zone"] == "15")
        #expect(form.rstSent == "59")
    }

    @Test func applyContestRstWithSeveralRstFields() {
        var form = EntryForm()
        form.editContestField("rs2", "44")
        form.applyContestRst(.cw, rstFieldIds: ["rs1", "rs2"])
        #expect(form.contestExchange["rs1"] == "599")
        #expect(form.contestExchange["rs2"] == "44")
    }

    @Test func editContestFieldUppercasesLikeKotlin() {
        var form = EntryForm()
        form.editContestField("cnty", "dad")
        form.editContestField("name", "straße")
        #expect(form.contestExchange["cnty"] == "DAD")
        #expect(form.contestExchange["name"] == "STRASSE")
        #expect(form.touchedFields == ["cnty", "name"])
    }

    @Test func wipeInContestResetsAndPrefillsRst() {
        var form = EntryForm()
        form.call = "OK1ABC"
        form.freqKHz = "14025.00"
        form.mode = .cw
        form.exch = "12"
        form.editRstSent("579")
        form.rstRcvd = "339"
        form.editContestField("rst", "57")
        form.editContestField("zone", "15")
        let wiped = form.wiped(contestActive: true, rstFieldIds: Self.rst)
        #expect(wiped.call == "")
        #expect(wiped.exch == "")
        #expect(wiped.freqKHz == "14025.00")
        #expect(wiped.mode == .cw)
        #expect(wiped.rstSent == "599")
        #expect(wiped.rstRcvd == "599")
        #expect(wiped.contestExchange == JavaLinkedMap([("rst", "599")]))
        #expect(wiped.touchedFields.isEmpty)
        #expect(!wiped.rstSentTouched)
    }

    @Test func wipeOutsideContestLeavesContestFieldsEmpty() {
        var form = EntryForm()
        form.mode = .cw
        form.editContestField("rst", "57")
        let wiped = form.wiped(contestActive: false, rstFieldIds: Self.rst)
        #expect(wiped.contestExchange.isEmpty)
        #expect(wiped.rstSent == "599")
        #expect(wiped.rstRcvd == "599")
    }

    @Test func rstFieldIdsAreRstAndRsFieldsInOrder() throws {
        let fields: [ContestDefinition.ExchangeField] = [
            .init(id: "nr", type: .SERIAL, required: true, source: nil, appliesWhen: nil, validation: nil),
            .init(id: "rs", type: .RS, required: true, source: nil, appliesWhen: nil, validation: nil),
            .init(id: "name", type: .TEXT, required: true, source: nil, appliesWhen: nil, validation: nil),
            .init(id: "rst", type: .RST, required: true, source: nil, appliesWhen: nil, validation: nil),
            .init(id: "x", type: nil, required: false, source: nil, appliesWhen: nil, validation: nil),
        ]
        #expect(EntryForm.rstFieldIds(fields) == ["rs", "rst"])
        let cqww = EntryFixtures.received(try EntryFixtures.definition(EntryFixtures.cqww))
        #expect(EntryForm.rstFieldIds(cqww) == ["rst"])
    }

    @Test func freqHzParsesTheField() {
        var form = EntryForm()
        form.freqKHz = " 14025,5 "
        #expect(form.freqHz == 14_025_500)
    }
}
