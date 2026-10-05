import Testing
@testable import MCLCore

/// Call History Lookup in the entry window (`EP:271-295`) and the reverse lookup (`EP:1211-1232`).
@Suite struct CallHistoryFillTests {

    private static let history = CallHistory.parse([
        "!!Order!!,Call,Name,State", "W1AW,HIRAM,CT", "K1ABC,JOE,MA", "N1XYZ,JOE,MA",
    ])

    private static func field(_ id: String, _ type: ContestDefinition.FieldType) -> ContestDefinition.ExchangeField {
        ContestDefinition.ExchangeField(id: id, type: type, required: true, source: nil, appliesWhen: nil,
                                        validation: nil)
    }

    private static let fields = [field("rst", .RST), field("name", .TEXT), field("state", .STATE)]

    private static func form(_ cexch: [(String?, String?)], call: String = "") -> EntryForm {
        var f = EntryForm()
        f.call = call
        f.contestExchange = JavaLinkedMap(cexch)
        return f
    }

    @Test func fillOnlyInAContestWithThreeUnits() {
        #expect(CallHistoryFill.fill(callHistory: Self.history, call: "W1AW", fields: Self.fields,
                                     contestActive: false).isEmpty)
        #expect(CallHistoryFill.fill(callHistory: Self.history, call: " W1 ", fields: Self.fields,
                                     contestActive: true).isEmpty)
        let fill = CallHistoryFill.fill(callHistory: Self.history, call: "w1aw", fields: Self.fields,
                                        contestActive: true)
        #expect(fill == Self.history.prefill("w1aw", Self.fields))
        #expect(fill["name"] == "HIRAM")
    }

    @Test func fillsOnlyBlankFieldsAndRemembers() {
        let fill = JavaLinkedMap<String>([("name", "HIRAM"), ("state", "CT")])
        let start = Self.form([("rst", "599"), ("name", "BOB"), ("state", " ")])
        let out = CallHistoryFill.apply(form: start, fill: fill, previouslyFilled: JavaLinkedMap())
        #expect(out.form.contestExchange["name"] == "BOB")
        #expect(out.form.contestExchange["state"] == "CT")
        #expect(out.filled == JavaLinkedMap([("state", "CT")]))
        #expect(out.form.touchedFields.isEmpty)
    }

    /// A changed call takes back what the previous fill put in (unless the operator overwrote it, or the new fill
    /// repeats it).
    @Test func takesBackPreviousFill() {
        let previous = JavaLinkedMap<String>([("name", "HIRAM"), ("state", "CT")])
        let start = Self.form([("rst", "599"), ("name", "HIRAM"), ("state", "NY")])
        let out = CallHistoryFill.apply(form: start, fill: JavaLinkedMap([("state", "CT")]), previouslyFilled: previous)
        #expect(out.form.contestExchange["name"] == nil)
        #expect(out.form.contestExchange.keys == ["rst", "state"])
        #expect(out.form.contestExchange["state"] == "NY")
        // "state" is repeated by the new fill, so it stays remembered — but the field was overwritten and is kept.
        #expect(out.filled == JavaLinkedMap([("state", "CT")]))
        let cleared = CallHistoryFill.apply(form: out.form, fill: JavaLinkedMap(), previouslyFilled: out.filled)
        #expect(cleared.form.contestExchange["state"] == "NY")
        #expect(cleared.filled.isEmpty)
    }

    /// Same value for the new call: nothing changes.
    @Test func sameValueStays() {
        let previous = JavaLinkedMap<String>([("state", "MA")])
        let start = Self.form([("state", "MA")])
        let out = CallHistoryFill.apply(form: start, fill: previous, previouslyFilled: previous)
        #expect(out.form == start)
        #expect(out.filled == previous)
    }

    @Test func reverseLookup() {
        let joe = Self.form([("rst", "599"), ("name", "joe"), ("state", "MA")])
        #expect(CallHistoryFill.reverse(callHistory: Self.history, form: joe, fields: Self.fields, contestActive: true)
                == ["K1ABC", "N1XYZ"])
        #expect(CallHistoryFill.reverse(callHistory: Self.history, form: joe, fields: Self.fields,
                                        contestActive: false).isEmpty)
        var called = joe
        called.call = "K1"
        #expect(CallHistoryFill.reverse(callHistory: Self.history, form: called, fields: Self.fields,
                                        contestActive: true).isEmpty)
        let blank = Self.form([("name", " ")])
        #expect(CallHistoryFill.reverse(callHistory: Self.history, form: blank, fields: Self.fields,
                                        contestActive: true).isEmpty)
    }
}
