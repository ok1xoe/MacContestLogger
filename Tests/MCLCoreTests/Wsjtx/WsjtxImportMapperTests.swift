import Foundation
import Testing
@testable import MCLCore

/// Port `WsjtxImportMapperTest.java` (4 testy).
@Suite struct WsjtxImportMapperTests {

    private static let adif: String = "<call:4>AA5A <gridsquare:4>EM12 <mode:3>FT8 <rst_sent:3>-05 <rst_rcvd:3>+03 "
        + "<band:3>20m <freq:8>14.07400 <qso_date:8>20260703 <time_on:6>064026 "
        + "<srx_string:2>12 <eor>"

    @Test func mapsBasicFieldsFromAdif() throws {
        let imp = try #require(try WsjtxImportMapper.map(Self.adif))
        #expect(imp.qso.call == "AA5A")
        #expect(imp.qso.mode == .ft8)
        #expect(imp.qso.band == .m20)
        #expect(imp.qso.rstSent == "-05")
        #expect(imp.qso.rstRcvd == "+03")
    }

    @Test func exposesRawExchangeFields() throws {
        let imp = try #require(try WsjtxImportMapper.map(Self.adif))
        #expect(imp.adifFields["gridsquare"] == "EM12")
        #expect(imp.adifFields["srx_string"] == "12")
    }

    @Test func nullWhenNoRecord() throws {
        #expect(try WsjtxImportMapper.map("<eoh>") == nil)
    }

    @Test func parsesBareFldigiAdif() throws {
        let adif: String = "<CALL:6>II9WWA<MODE:2>CW<FREQ:9>14.028086<BAND:3>20m"
            + "<QSO_DATE:8>20260703<TIME_ON:4>1733<RST_SENT:3>599<RST_RCVD:3>599"
            + "<STX:3>000<OPERATOR:6>OK1XOE<STATION_CALLSIGN:6>OK1XOE<EOR>"
        let imp = try #require(try WsjtxImportMapper.map(adif))
        #expect(imp.qso.call == "II9WWA")
        #expect(imp.qso.mode == .cw)
        #expect(imp.qso.band == .m20)
        #expect(imp.qso.freqHz == 14_028_086)
        #expect(imp.qso.rstSent == "599")
        #expect(imp.qso.rstRcvd == "599")
    }
}
