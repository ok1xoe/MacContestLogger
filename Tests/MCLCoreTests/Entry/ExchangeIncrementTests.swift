import Testing
@testable import MCLCore

/// Ctrl+U (`incrementExchangeNumber`, `EP:599-609`); values from probe `inc`.
@Suite struct ExchangeIncrementTests {

    private static func field(_ id: String?, _ type: ContestDefinition.FieldType?) -> ContestDefinition.ExchangeField {
        ContestDefinition.ExchangeField(id: id, type: type, required: true, source: nil, appliesWhen: nil,
                                        validation: nil)
    }

    /// Probe `inc`: Kotlin `trim().toIntOrNull() ?: 0` plus one, `Int` wraps.
    @Test func incrementAsMeasured() {
        let table: [(String, String)] = [
            ("", "1"), ("5", "6"), (" 7 ", "8"), ("2147483647", "-2147483648"), ("-3", "-2"), ("x", "1"), ("+4", "5"),
            ("\u{0661}\u{0662}", "13"), ("007", "8"),
        ]
        for (input, output) in table {
            #expect(ExchangeIncrement.incremented(input) == output, "\(input)")
        }
    }

    @Test func serialFieldFirst() {
        var form = EntryForm()
        form.contestExchange = JavaLinkedMap([("rst", "599"), ("nr", "12"), ("loc", "JO70")])
        let fields = [Self.field("rst", .RST), Self.field("nr", .SERIAL), Self.field("loc", .LOCATOR)]
        let out = ExchangeIncrement.apply(form: form, fields: fields, contestActive: true)
        #expect(out.contestExchange["nr"] == "13")
        #expect(out.contestExchange.keys == ["rst", "nr", "loc"])
        #expect(out.touchedFields == ["nr"])
    }

    @Test func lastFieldWithoutSerial() {
        let fields = [Self.field("rst", .RST), Self.field("zone", .CQ_ZONE)]
        let out = ExchangeIncrement.apply(form: EntryForm(), fields: fields, contestActive: true)
        #expect(out.contestExchange["zone"] == "1")
        #expect(out.touchedFields == ["zone"])
        #expect(ExchangeIncrement.apply(form: EntryForm(), fields: [], contestActive: true) == EntryForm())
    }

    @Test func freeExchange() {
        var form = EntryForm()
        form.exch = " 41 "
        #expect(ExchangeIncrement.apply(form: form, fields: [], contestActive: false).exch == "42")
        form.exch = "abc"
        let out = ExchangeIncrement.apply(form: form, fields: [Self.field("nr", .SERIAL)], contestActive: false)
        #expect(out.exch == "1")
        #expect(out.touchedFields.isEmpty)
    }
}
