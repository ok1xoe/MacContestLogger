import Testing
@testable import MCLCore

/// Port of `hamqth/CallbookPrefillTest` (1).
@Suite struct CallbookPrefillTests {

    private typealias FieldType = ContestDefinition.FieldType

    private func f(_ id: String, _ t: FieldType) -> ContestDefinition.ExchangeField {
        ContestDefinition.ExchangeField(id: id, type: t, required: true, source: nil, appliesWhen: nil,
                                        validation: nil, estimate: nil)
    }

    private func pairs(_ map: JavaLinkedMap<String>) -> [String] {
        map.keys.map { ($0 ?? "~") + "=" + (map[$0] ?? "~") }
    }

    @Test func mapsByFieldType() {
        let rec = HamQthRecord(grid: "jo70fc", name: "Tomas", cqZone: "15", ituZone: "28")
        let fields = [f("rst", .RST), f("loc", .LOCATOR), f("zone", .CQ_ZONE)]
        #expect(pairs(CallbookPrefill.prefill(rec, fields)) == ["loc=JO70FC", "zone=15"])
        #expect(pairs(CallbookPrefill.prefill(rec, [f("name", .TEXT)])) == ["name=TOMAS"])
        #expect(CallbookPrefill.prefill(HamQthRecord.empty, [f("loc", .LOCATOR)]).isEmpty)
        #expect(CallbookPrefill.describe(rec) == "Tomas \u{00B7} JO70FC \u{00B7} CQ 15 \u{00B7} ITU 28")
    }
}
