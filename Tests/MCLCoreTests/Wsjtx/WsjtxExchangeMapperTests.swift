import Foundation
import Testing
@testable import MCLCore

/// Port of `WsjtxExchangeMapperTest.java` (7 tests).
@Suite struct WsjtxExchangeMapperTests {

    private static func field(_ id: String, _ type: ContestDefinition.FieldType) -> ContestDefinition.ExchangeField {
        ContestDefinition.ExchangeField(id: id, type: type, required: true, source: nil, appliesWhen: nil,
                                        validation: nil)
    }

    @Test func mapsLocatorFromGridsquare() {
        let raw = WsjtxExchangeMapper.toReceivedRaw([Self.field("grid", .LOCATOR)], ["gridsquare": "EM12"])
        #expect(raw["grid"] == "EM12")
    }

    @Test func mapsRstAndSerial() {
        let raw = WsjtxExchangeMapper.toReceivedRaw(
            [Self.field("rst", .RST), Self.field("nr", .SERIAL)],
            ["rst_rcvd": "599", "srx_string": "0012"])
        #expect(raw["rst"] == "599")
        #expect(raw["nr"] == "12")
    }

    @Test func srxStringWithReportDoesNotShiftTheExchange() {
        // MCL's own ADIF export writes the whole exchange including the report into srx_string.
        let raw = WsjtxExchangeMapper.toReceivedRaw(
            [Self.field("rst", .RST), Self.field("zone", .CQ_ZONE)],
            ["rst_rcvd": "599", "srx": "16", "srx_string": "599 16"])
        #expect(raw["rst"] == "599")
        #expect(raw["zone"] == "16")
    }

    @Test func srxStringWithoutReportStillMapsInOrder() {
        // WSJT-X does not put the report into srx_string — the behaviour must not change.
        let raw = WsjtxExchangeMapper.toReceivedRaw(
            [Self.field("rst", .RST), Self.field("zone", .CQ_ZONE)],
            ["rst_rcvd": "-10", "srx_string": "16"])
        #expect(raw["rst"] == "-10")
        #expect(raw["zone"] == "16")
    }

    @Test func exchangeStartingWithTheSameValueAsReportIsKept() {
        // Two fields and two tokens: the first token is the real exchange, not the report.
        let raw = WsjtxExchangeMapper.toReceivedRaw(
            [Self.field("rst", .RST), Self.field("a", .TEXT), Self.field("b", .TEXT)],
            ["rst_rcvd": "599", "srx_string": "599 20"])
        #expect(raw["rst"] == "599")
        #expect(raw["a"] == "599")
        #expect(raw["b"] == "20")
    }

    @Test func missingInputLeavesFieldUnset() {
        let raw = WsjtxExchangeMapper.toReceivedRaw([Self.field("grid", .LOCATOR)], [:])
        #expect(!raw.containsKey("grid"))
    }

    @Test func overlongSerialDigitsDoNotThrow() {
        let raw = WsjtxExchangeMapper.toReceivedRaw(
            [Self.field("nr", .SERIAL)],
            ["srx_string": "123456789012345678901234567890"])
        #expect(raw["nr"] != nil)
    }
}
