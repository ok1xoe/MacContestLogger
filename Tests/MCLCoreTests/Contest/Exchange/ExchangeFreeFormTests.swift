import Foundation
import Testing
@testable import MCLCore

/// N1MM's free-form Sweepstakes exchange (`exchange.freeForm`) and the 7QP received county line (`split`).
@Suite struct ExchangeFreeFormTests {

    private static func field(_ id: String, _ type: ContestDefinition.FieldType, regex: String? = nil,
                              split: Bool = false) -> ContestDefinition.ExchangeField {
        ContestDefinition.ExchangeField(
            id: id, type: type, required: true, source: nil, appliesWhen: nil,
            validation: regex.map { ContestDefinition.FieldValidation(regex: $0, min: nil, max: nil, length: nil) },
            split: split)
    }

    /// The published ARRL Sweepstakes received fields.
    private static let sweepstakes: [ContestDefinition.ExchangeField] = [
        field("nr", .SERIAL), field("prec", .TEXT, regex: "^[QABUMS]$"), field("ck", .TEXT, regex: "^[0-9]{2}$"),
        field("sec", .TEXT),
    ]

    private static func values(_ text: String) -> [String: String] {
        let result = ExchangeFreeForm.parse(text, fields: sweepstakes)
        var out: [String: String] = [:]
        for (key, value) in result.values.entries {
            out[key ?? ""] = value
        }
        return out
    }

    @Test func wordsGoToTheFieldTheyFitInAnyOrder() {
        let expected = ["nr": "123", "prec": "A", "ck": "72", "sec": "OH"]
        #expect(Self.values("123 A 72 OH") == expected)
        #expect(Self.values("A 123 OH 72") == expected)
        #expect(Self.values("oh 123 a 72") == expected)
        #expect(Self.values("123A 72OH") == expected)
        #expect(Self.values("123 a, 72, oh") == expected)
    }

    @Test func aValueTypedAgainCorrectsTheEarlierOne() {
        #expect(Self.values("123 A 72 OH 73") == ["nr": "123", "prec": "A", "ck": "73", "sec": "OH"])
        #expect(Self.values("123 A 72 OH B") == ["nr": "123", "prec": "B", "ck": "72", "sec": "OH"])
        #expect(Self.values("123 A 72 OH 1234") == ["nr": "1234", "prec": "A", "ck": "72", "sec": "OH"])
        #expect(Self.values("123 A 72 OH WMA") == ["nr": "123", "prec": "A", "ck": "72", "sec": "WMA"])
    }

    @Test func aCallInTheExchangeCorrectsTheLoggedCall() {
        let result = ExchangeFreeForm.parse("123 A K1ABC 72 OH", fields: Self.sweepstakes)
        #expect(result.call == "K1ABC")
        #expect(result.values["sec"] == "OH")
        #expect(ExchangeFreeForm.parse("4X1AB", fields: Self.sweepstakes).call == "4X1AB")
        #expect(ExchangeFreeForm.parse("W1AW/7", fields: Self.sweepstakes).call == "W1AW/7")
        #expect(ExchangeFreeForm.parse("72OH 1A", fields: Self.sweepstakes).call == nil)
    }

    @Test func callShapes() {
        for call in ["K1ABC", "OK1XOE", "4X1AB", "9A1A", "VE3XYZ", "W1AW/7"] {
            #expect(ExchangeFreeForm.looksLikeCall(call), "\(call)")
        }
        for word in ["72OH", "123A", "1A", "OH", "A", "72", "WMA"] {
            #expect(!ExchangeFreeForm.looksLikeCall(word), "\(word)")
        }
    }

    @Test func previewAndBoxText() {
        let result = ExchangeFreeForm.parse("123 A 72 OH K1ABC", fields: Self.sweepstakes)
        #expect(ExchangeFreeForm.preview(result, fields: Self.sweepstakes)
                    == "nr 123 · prec A · ck 72 · sec OH · call K1ABC")
        #expect(ExchangeFreeForm.text(result.values, fields: Self.sweepstakes) == "123 A 72 OH")
        // Without a free text field a word that fits nowhere is shown as not understood.
        let numbers = Array(Self.sweepstakes.prefix(3))
        let unparsed = ExchangeFreeForm.parse("123 A WMA", fields: numbers)
        #expect(unparsed.unparsed == ["WMA"])
        #expect(ExchangeFreeForm.preview(unparsed, fields: numbers) == "nr 123 · prec A · ? WMA")
    }

    @Test func publishedSweepstakesIsFreeForm() throws {
        for id in ["arrl-sweepstakes-cw", "arrl-sweepstakes-ssb"] {
            let url = PublishedContestDataTests.root.appendingPathComponent("contests/\(id).yaml")
            let definition = try ContestDefinitionLoader.loadFile(url)
            #expect(definition.exchange?.freeForm == true)
        }
    }

    // MARK: - split (7QP county line)

    @Test func splitPartsExpandTheShorthand() {
        #expect(ExchangeSplit.parts("ORDES/JEF") == ["ORDES", "ORJEF"])
        #expect(ExchangeSplit.parts("idfra/utcac") == ["IDFRA", "UTCAC"])
        #expect(ExchangeSplit.parts("WAKIN/PIE/SNO") == ["WAKIN", "WAPIE", "WASNO"])
        #expect(ExchangeSplit.parts("ORDES") == ["ORDES"])
        #expect(ExchangeSplit.parts("ORDES//") == ["ORDES"])
    }

    @Test func aSplitFieldValidatesEveryPart() throws {
        let county = Self.field("cnty", .DISTRICT, regex: "^[A-Z]{5}$", split: true)
        let engine = ExchangeEngine()
        let both = try engine.parse(county, "ORDES/JEF")
        #expect(both.valid)
        #expect(both.canonical == "ORDES/ORJEF")
        #expect(try !engine.parse(county, "ORDES/J1").valid)
        var plain = county
        plain.split = false
        #expect(try !engine.parse(plain, "ORDES/JEF").valid)
    }

    @Test func aSplitFieldLogsOneQsoPerCounty() {
        let fields = [Self.field("rst", .RST), Self.field("cnty", .DISTRICT, split: true)]
        var form = EntryForm()
        form.call = "W7AB"
        form.freqKHz = "14035"
        form.mode = .cw
        form.contestExchange = JavaLinkedMap([("rst", "599"), ("cnty", "ORDES/JEF")])
        let copies = QsoAssembly.contestQsos(
            form: form, fields: fields, rstFieldIds: ["rst"], serial: 5, runMode: .run, countyLine: ["A", "B"],
            usesRoverQth: true, roverQth: "", note: nil, at: nil) { qth in "599 " + (qth ?? "") }
        #expect(copies.map(\.qso.exchangeRcvd) == ["599 ORDES", "599 ORJEF", "599 ORDES", "599 ORJEF"])
        #expect(copies.map(\.qso.exchangeSent) == ["599 A", "599 A", "599 B", "599 B"])
        #expect(Set(copies.map(\.qso.serialSent)) == [5])
    }
}
