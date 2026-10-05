import Foundation
import Testing
@testable import MCLCore

/// Port of the Java `io/ImportedExchangeTest` (6 tests) over definitions from `contest-data`
/// (byte-for-byte the same files as in the Java test) + edge guards measured on JDK 21.0.2.
@Suite struct ImportedExchangeTests {

    private typealias Field = ContestDefinition.ExchangeField

    /// Java `defs.stream().filter(d -> d.id().equals(id))` — the file is named after the id.
    private static func def(_ id: String) throws -> ContestDefinition {
        let file = try PointsCalculatorTests.contestsDirectory().appendingPathComponent("\(id).yaml")
        let definition = try ContestDefinitionLoader.loadFile(file)
        try #require(definition.id == id)
        return definition
    }

    /// Java `received(d, workedClass)`: fields without `appliesWhen` or with the given `workedClass`.
    /// (Java `f.appliesWhen().workedClass().equals(null)` is always false.)
    private static func received(_ d: ContestDefinition, _ workedClass: String?) -> [Field] {
        (d.exchange?.received ?? []).compactMap { $0 }.filter { field in
            guard let applies = field.appliesWhen else { return true }
            guard let workedClass else { return false }
            return JavaText.equals(workedClass, applies.workedClass)
        }
    }

    private static func cabrilloLine(_ line: String) throws -> Qso {
        try #require(try CabrilloReader().read("QSO: " + line).first)
    }

    /// Java `cabrilloReportAndZoneBecomeEntryWindowFormat`.
    @Test func cabrilloReportAndZoneBecomeEntryWindowFormat() throws {
        let d = try Self.def("cq-ww-cw")
        let q = try Self.cabrilloLine("14025 CW 2026-11-28 0001 OK1XOE 599 15 DL1ABC 599 14")

        #expect(ImportedExchange.toFlat(d, Self.received(d, nil), q) == "599 14")
    }

    /// Java `cabrilloWithoutReportMapsTheOnlyField`.
    @Test func cabrilloWithoutReportMapsTheOnlyField() throws {
        // WW Digi: only the locator, no RST — CabrilloReader stores it in rstRcvd.
        let d = try Self.def("ww-digi")
        let q = try Self.cabrilloLine("14074 DG 2026-08-29 1200 OK1XOE JO70 DL1ABC JO61")

        #expect(ImportedExchange.toFlat(d, Self.received(d, nil), q) == "JO61")
    }

    /// Java `conditionalFieldsFollowCabrilloOrder`.
    @Test func conditionalFieldsFollowCabrilloOrder() throws {
        let d = try Self.def("ok-om-dx-cw")
        let okom = try Self.cabrilloLine("3520 CW 2026-12-05 0001 OK1XOE 599 APH OK2ABC 599 BRO")
        let dx = try Self.cabrilloLine("3525 CW 2026-12-05 0002 OK1XOE 599 APH DL1ABC 599 17")

        #expect(ImportedExchange.toFlat(d, Self.received(d, "okom"), okom) == "599 BRO")
        #expect(ImportedExchange.toFlat(d, Self.received(d, "dx"), dx) == "599 17")
    }

    /// Java `adifReportAndSerial`.
    @Test func adifReportAndSerial() throws {
        let d = try Self.def("cq-wpx-cw")
        var q = Qso()
        q.rstRcvd = "579"
        q.serialRcvd = 123

        #expect(ImportedExchange.toFlat(d, Self.received(d, nil), q) == "579 123")
    }

    /// Java `adifWithoutReportKeepsSerialOnItsField`.
    @Test func adifWithoutReportKeepsSerialOnItsField() throws {
        let d = try Self.def("cq-wpx-cw")
        var q = Qso()
        q.serialRcvd = 7

        #expect(ImportedExchange.toFlat(d, Self.received(d, nil), q) == "7")
    }

    /// Java `nothingToMapGivesNull`.
    @Test func nothingToMapGivesNull() throws {
        let d = try Self.def("cq-ww-cw")

        #expect(ImportedExchange.toFlat(d, Self.received(d, nil), Qso()) == nil)
    }

    // MARK: - edge guards (JDK 21.0.2, a maintainer-only probe)

    /// IE1 research: a 6-character locator (`JO70FC`) is a "callsign" for `CabrilloReader` — the other station
    /// shifts and the `iaru-r1-vhf` exchange starts with a callsign. The composed path reader → `toFlat`.
    @Test func vhfSixCharacterLocatorShiftsExchange() throws {
        let d = try Self.def("iaru-r1-vhf")
        let q = try Self.cabrilloLine("144 PH 2026-06-06 1400 OK1XOE 59 001 JO70FC DL1ABC 59 005 JO62QM")

        #expect(ImportedExchange.toFlat(d, (d.exchange?.received ?? []).compactMap { $0 }, q) == "DL1ABC 59 005")
    }

    /// IE2 research: with a 4-character locator the other station is right, the locator is enlarged.
    @Test func vhfFourCharacterLocatorKeepsExchange() throws {
        let d = try Self.def("iaru-r1-vhf")
        let q = try Self.cabrilloLine("144 PH 2026-06-06 1400 OK1XOE 59 001 JO70 DL1ABC 59 005 jo62qm")

        #expect(ImportedExchange.toFlat(d, (d.exchange?.received ?? []).compactMap { $0 }, q) == "59 005 JO62QM")
    }

    private static func field(_ id: String?, _ type: ContestDefinition.FieldType?) -> Field {
        Field(id: id, type: type, required: false, source: nil, appliesWhen: nil, validation: nil)
    }

    /// Java `loader.load("id: t\ncabrillo:\n  receivedOrder: <order>")` as in the probe.
    private static func definition(receivedOrder: String?) throws -> ContestDefinition {
        let cabrillo: String = receivedOrder.map { "cabrillo:\n  receivedOrder: \($0)\n" } ?? ""
        return try ContestDefinitionLoader.load(Data(("id: t\n" + cabrillo).utf8))
    }

    private static func qso(rst: String, exchange: String, serial: Int? = nil) -> Qso {
        var q = Qso()
        q.rstRcvd = rst
        q.exchangeRcvd = exchange
        q.serialRcvd = serial
        return q
    }

    /// The order of `receivedOrder` determines token assignment, the output goes in the order of active fields;
    /// fields outside `receivedOrder` follow them in the order of active fields.
    @Test func receivedOrderAssignsTokensOutputFollowsActive() throws {
        let active = [Self.field("zone", .CQ_ZONE), Self.field("rst", .RST), Self.field("name", .TEXT)]
        let d = try Self.definition(receivedOrder: "[rst, zone]")
        #expect(ImportedExchange.toFlat(d, active, Self.qso(rst: "599", exchange: "14 joe")) == "14 599 JOE")
    }

    /// An id twice in `receivedOrder`: the second occurrence consumes another token and overwrites the value.
    @Test func duplicateIdInReceivedOrderConsumesTwoTokens() throws {
        let active = [Self.field("rst", .RST), Self.field("zone", .CQ_ZONE)]
        let d = try Self.definition(receivedOrder: "[rst, zone, zone]")
        #expect(ImportedExchange.toFlat(d, active, Self.qso(rst: "599", exchange: "14 15")) == "599 15")
    }

    /// A control character: `isBlank` does not take it for empty, `trim` drops it → the token `""`, which takes
    /// a field's place and drops out of the output.
    @Test func controlCharacterExchangeYieldsEmptyToken() throws {
        let active = [Self.field("rst", .RST), Self.field("zone", .CQ_ZONE), Self.field("nr", .SERIAL)]
        let d = try Self.definition(receivedOrder: nil)
        let q = Self.qso(rst: "599", exchange: "\u{0001}", serial: 5)
        #expect(ImportedExchange.toFlat(d, active, q) == "599 5")
    }

    /// NBSP is not Java `\s` — the token stays whole; the output grows (`ß` → `SS`).
    @Test func nbspStaysInsideTokenAndOutputIsUppercased() throws {
        let active = [Self.field("rst", .RS), Self.field("name", .TEXT)]
        let d = try Self.definition(receivedOrder: nil)
        let q = Self.qso(rst: "59", exchange: "stra\u{00DF}e\u{00A0}x")
        #expect(ImportedExchange.toFlat(d, active, q) == "59 STRASSE\u{00A0}X")
    }

    /// A field with id `null`: the key `null` in the map is valid, it gets the value.
    @Test func nullIdFieldGetsValue() throws {
        let active = [Self.field(nil, .TEXT), Self.field("rst", .RST)]
        let d = try Self.definition(receivedOrder: nil)
        #expect(ImportedExchange.toFlat(d, active, Self.qso(rst: "599", exchange: "x")) == "599 X")
    }
}
