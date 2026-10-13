import Foundation
@testable import MCLCore
import Testing

/// AutoTRXUpdate's frequency, the `{LDIGFQ}` / `{RDIGFQ}` macros, fldigi's modem list and the RTTY / PSK modems.
@Suite struct DigitalFrequencyTests {

    @Test func sidebandModesAddOrSubtractTheAudio() {
        #expect(DigitalFrequency.transmitHz(dialHz: 14_080_000, rawMode: "USB", carrierHz: 2_125) == 14_082_125)
        #expect(DigitalFrequency.transmitHz(dialHz: 14_080_000, rawMode: "pktusb", carrierHz: 1_000) == 14_081_000)
        #expect(DigitalFrequency.transmitHz(dialHz: 7_040_000, rawMode: "LSB", carrierHz: 2_125) == 7_037_875)
        #expect(DigitalFrequency.transmitHz(dialHz: 7_040_000, rawMode: "PKTLSB", carrierHz: 2_125) == 7_037_875)
    }

    @Test func fskCwAndUnknownKeepTheDial() {
        for raw in ["RTTY", "RTTYR", "CW", "FM", ""] {
            #expect(DigitalFrequency.transmitHz(dialHz: 14_080_000, rawMode: raw, carrierHz: 2_125) == 14_080_000)
        }
        #expect(DigitalFrequency.transmitHz(dialHz: 14_080_000, rawMode: "USB", carrierHz: nil) == 14_080_000)
        #expect(DigitalFrequency.transmitHz(dialHz: 0, rawMode: "USB", carrierHz: 1_500) == 0)
    }

    @Test func macroTextIsKilohertzWithOneDecimal() {
        #expect(DigitalFrequency.macroText(14_082_125) == "14082.1")
        #expect(DigitalFrequency.macroText(14_082_150) == "14082.2")
        #expect(DigitalFrequency.macroText(0) == "")
    }

    @Test func macrosInAMessage() {
        var ctx = CwMessageBuilder.Context(myCall: "OK1XOE", hisCall: "", lastLogged: "", serial: 1, rst: "599",
                                           exchange: "", cutNumbers: false, leadingZeros: false, now: nil)
        ctx.leftDigitalFrequency = "14082.1"
        ctx.rightDigitalFrequency = "7037.9"
        let message = CwMessageBuilder.build("QSY {LDIGFQ} {rdigfq}", ctx)
        #expect(message.plainText() == "QSY 14082.1 7037.9")
        #expect(message.unknownMacros.isEmpty)
    }

    @Test func modemNamesFromAnArray() throws {
        let xml = "<?xml version=\"1.0\"?><methodResponse><params><param><value><array><data>"
            + "<value>RTTY</value><value><string>BPSK31</string></value></data></array></value></param></params>"
            + "</methodResponse>"
        #expect(try XmlRpc.parseStringArray(xml) == ["RTTY", "BPSK31"])
        let scalar = "<methodResponse><params><param><value><string>RTTY</string></value></param></params>"
            + "</methodResponse>"
        #expect(try XmlRpc.parseStringArray(scalar) == nil)
        let fault = "<methodResponse><fault><value><string>nope</string></value></fault></methodResponse>"
        #expect(throws: XmlRpc.Failure.self) { try XmlRpc.parseStringArray(fault) }
    }

    @Test func modemsForTheEntryModes() {
        var digital = DigitalConfig()
        #expect(digital.modem(for: .rtty) == "RTTY")
        #expect(digital.modem(for: .psk) == "BPSK31")
        #expect(digital.modem(for: .cw) == nil)
        digital.pskModem = DigitalConfig.modemName("  BPSK63 ", fallback: "BPSK31")
        #expect(digital.modem(for: .psk) == "BPSK63")
        #expect(DigitalConfig.modemName(" ", fallback: "RTTY") == "RTTY")
        #expect(digital.autoTrxUpdate)
    }
}
