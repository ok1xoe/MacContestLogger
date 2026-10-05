import Foundation
import Testing
@testable import MCLCore

/// Port of `WsjtxCodecTest.java` (6 tests).
@Suite struct WsjtxCodecTests {

    @Test func stringRoundTripIncludingNull() throws {
        #expect(try Self.roundTripString("Ahoj") == "Ahoj")
        #expect(try Self.roundTripString("") == "")
        #expect(try Self.roundTripString(nil) == nil)
    }

    @Test func stringEncodesLengthPrefixThenUtf8() {
        var out = WsjtxDataOutput()
        WsjtxCodec.writeString(&out, "AB")
        #expect(out.bytes == [0, 0, 0, 2, 0x41, 0x42])
    }

    @Test func nullStringEncodesMinusOneLength() {
        var out = WsjtxDataOutput()
        WsjtxCodec.writeString(&out, nil)
        #expect(out.bytes == [0xFF, 0xFF, 0xFF, 0xFF])
    }

    @Test func julianDayMatchesKnownEpochs() throws {
        #expect(WsjtxCodec.julianDay(year: 1970, month: 1, day: 1) == 2_440_588)
        #expect(WsjtxCodec.julianDay(year: 2000, month: 1, day: 1) == 2_451_545)
        let date = try WsjtxCodec.dateFromJulianDay(2_451_545)
        #expect(date.year == 2000 && date.month == 1 && date.day == 1)
    }

    @Test func dateTimeRoundTripSecondPrecisionUtc() throws {
        let t = try #require(ISO8601DateFormatter().date(from: "2026-07-03T06:40:26Z"))
        var out = WsjtxDataOutput()
        WsjtxCodec.writeDateTimeUtc(&out, t)
        var input = WsjtxDataInput(out.bytes)
        #expect(try WsjtxCodec.readDateTimeUtc(&input) == t)
    }

    @Test func readStringRejectsAbsurdLength() {
        var out = WsjtxDataOutput()
        out.writeInt(70000)
        out.write([1, 2, 3])
        var input = WsjtxDataInput(out.bytes)
        #expect(throws: WsjtxError.stringLengthOutOfRange(70000)) {
            try WsjtxCodec.readString(&input)
        }
    }

    private static func roundTripString(_ s: String?) throws -> String? {
        var out = WsjtxDataOutput()
        WsjtxCodec.writeString(&out, s)
        var input = WsjtxDataInput(out.bytes)
        return try WsjtxCodec.readString(&input)
    }
}
