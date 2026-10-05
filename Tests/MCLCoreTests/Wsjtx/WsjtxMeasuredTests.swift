import Foundation
import Testing
@testable import MCLCore

/// Rows measured on Java v1.1.1 (maintainer-only probe: `FT8|`, `WSJ.*`
/// 3.3). They supplement the ported tests with QDataStream edges that the Java tests do not assert: NaN canonicalisation,
/// the low 8 bits of `modifiers`, exception texts, invalid UTF-8, the range of the Julian day.
@Suite struct WsjtxMeasuredTests {

    private static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func javaError(_ body: () throws -> Void, fromDecode: Bool = true) -> String? {
        do {
            try body()
            return nil
        } catch let error as WsjtxError {
            return error.javaDescription(fromDecode: fromDecode)
        } catch {
            return "unexpected error \(error)"
        }
    }

    @Test func ft8Lines() {
        let cases: [(String, Ft8Message)] = [
            ("CQ OK1XOE JO70", Ft8Message(caller: "OK1XOE", target: "", cq: true, grid: "JO70")),
            ("CQ DX K1ABC FN42", Ft8Message(caller: "K1ABC", target: "", cq: true, grid: "FN42")),
            ("CQ K1ABC", Ft8Message(caller: "K1ABC", target: "", cq: true, grid: "")),
            ("CQ_NA K1ABC FN42", Ft8Message(caller: "K1ABC", target: "", cq: true, grid: "FN42")),
            ("OK1XOE K1ABC -12", Ft8Message(caller: "K1ABC", target: "OK1XOE", cq: false, grid: "")),
            ("<K1ABC> OK1XOE RR73", Ft8Message(caller: "OK1XOE", target: "K1ABC", cq: false, grid: "")),
            ("K1ABC OK1XOE RR73", Ft8Message(caller: "OK1XOE", target: "K1ABC", cq: false, grid: "")),
            ("CQ 123 K1ABC FN42", Ft8Message(caller: "K1ABC", target: "", cq: true, grid: "FN42")),
            ("CQ POTA", Ft8Message(caller: "", target: "", cq: true, grid: "")),
            ("CQ", Ft8Message(caller: "", target: "", cq: true, grid: "")),
            ("  ", Ft8Message(caller: "", target: "", cq: false, grid: "")),
            ("TNX 73", Ft8Message(caller: "", target: "", cq: false, grid: "")),
            ("OK1XOE K1ABC AA00", Ft8Message(caller: "K1ABC", target: "OK1XOE", cq: false, grid: "AA00")),
            ("cq ok1xoe jo70", Ft8Message(caller: "OK1XOE", target: "", cq: true, grid: "JO70")),
            ("CQ   K1ABC  \t FN42", Ft8Message(caller: "K1ABC", target: "", cq: true, grid: "FN42")),
        ]
        for (line, expected) in cases {
            #expect(Ft8Message.parse(line) == expected, "\(line)")
        }
        #expect(Ft8Message.parse(nil) == Ft8Message(caller: "", target: "", cq: false, grid: ""))
    }

    /// `WSJ.replyNaN`: a signalling NaN `7ff0000000000001` is canonicalised on write, `modifiers 0x1ff` → `ff`.
    @Test func replyCanonicalizesNaNAndTruncatesModifiers() {
        let d = WsjtxMessages.Decode(
            id: "WSJT-X", isNew: true, timeMs: 1000, snr: -12, deltaTime: Double(bitPattern: 0x7FF0_0000_0000_0001),
            deltaFrequency: 1500, mode: "~", message: "CQ K1ABC FN42", lowConfidence: false, offAir: false)
        let expected: String = "adbccbda00000002000000040000000657534a542d58000003e8fffffff47ff8000000000000"
            + "000005dc000000017e0000000d4351204b3141424320464e343200ff"
        #expect(Self.hex(WsjtxMessages.encodeReply(d, modifiers: 0x1FF)) == expected)
    }

    @Test func decodeErrorsMatchJava() {
        let badMagic: [UInt8] = [0xAD, 0xBC, 0xCB, 0xDB, 0, 0, 0, 2, 0, 0, 0, 2]
        #expect(Self.javaError { _ = try WsjtxMessages.decode(badMagic) }
            == "java.lang.IllegalArgumentException: Neplatné WSJT-X magic: adbccbdb")
        #expect(Self.javaError { _ = try WsjtxMessages.decode([0xAD, 0xBC, 0xCB, 0xDA, 0, 0]) }
            == "java.io.UncheckedIOException: java.io.EOFException")
        #expect(Self.javaError { _ = try WsjtxMessages.decode([]) }
            == "java.io.UncheckedIOException: java.io.EOFException")
        // A negative magic without leading zeros (`Integer.toHexString`).
        #expect(WsjtxError.badMagic(1).message == "Neplatné WSJT-X magic: 1")
        #expect(WsjtxError.stringLengthOutOfRange(70000).javaDescription(fromDecode: true)
            == "java.io.UncheckedIOException: java.io.IOException: WSJT-X string length out of range: 70000")
    }

    /// `WSJ.malformed`: `c3 28 e2 82 41 ff` → `U+FFFD ( U+FFFD A U+FFFD`; a non-zero bool byte = `true`.
    @Test func malformedUtf8AndNonZeroBoolean() throws {
        var out = WsjtxDataOutput()
        out.writeInt(WsjtxProtocol.magic)
        out.writeInt(3)
        out.writeInt(2)
        WsjtxCodec.writeString(&out, "id")
        out.writeBoolean(true)
        out.writeInt(5)
        out.writeInt(-3)
        out.writeDouble(0.1)
        out.writeInt(700)
        WsjtxCodec.writeString(&out, "~")
        out.writeInt(6)
        out.write([0xC3, 0x28, 0xE2, 0x82, 0x41, 0xFF])
        out.writeByte(2)
        let expected = WsjtxMessages.Decode(
            id: "id", isNew: true, timeMs: 5, snr: -3, deltaTime: 0.1, deltaFrequency: 700, mode: "~",
            message: "\u{FFFD}(\u{FFFD}A\u{FFFD}", lowConfidence: true, offAir: false)
        #expect(try WsjtxMessages.decode(out.bytes) == .decode(expected))
    }

    /// `WSJ.qsoLoggedTrunc`: spec 2 reads the offset, then the bytes run out.
    @Test func truncatedQsoLogged() {
        var out = WsjtxDataOutput()
        out.writeInt(WsjtxProtocol.magic)
        out.writeInt(2)
        out.writeInt(5)
        WsjtxCodec.writeString(&out, "id")
        out.writeLong(2_461_315)
        out.writeInt(-1000)
        out.writeByte(2)
        out.writeInt(3600)
        WsjtxCodec.writeString(&out, "K1ABC")
        let bytes: [UInt8] = out.bytes
        #expect(Self.javaError { _ = try WsjtxMessages.decode(bytes) }
            == "java.io.UncheckedIOException: java.io.EOFException")
    }

    /// `WSJ.jdHuge`, `WSJ.msHuge`, `WSJ.dtPre1970`.
    @Test func dateTimeEdges() throws {
        var huge = WsjtxDataInput([0x7F, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0, 0, 0, 0, 1])
        #expect(Self.javaError({ _ = try WsjtxCodec.readDateTimeUtc(&huge) }, fromDecode: false)
            == "java.time.DateTimeException: Invalid value for EpochDay (valid values -365243219162 - 365241780471): "
            + "9223372036852335219")

        var msHuge = WsjtxDataInput([0, 0, 0, 0, 0, 0x25, 0x8E, 0x83, 0x7F, 0xFF, 0xFF, 0xFF, 1])
        let expected = try #require(ISO8601DateFormatter().date(from: "2026-10-25T20:31:23Z"))
        let read = try #require(try WsjtxCodec.readDateTimeUtc(&msHuge))
        #expect(WsjtxCodec.epochMillis(read) == WsjtxCodec.epochMillis(expected) + 647)

        var out = WsjtxDataOutput()
        WsjtxCodec.writeDateTimeUtc(&out, Date(timeIntervalSince1970: -0.000001))
        #expect(Self.hex(out.bytes) == "0000000000253d8b05265bff01")

        var null = WsjtxDataOutput()
        WsjtxCodec.writeDateTimeUtc(&null, nil)
        #expect(Self.hex(null.bytes) == "00000000000000000000000001")
        var nullIn = WsjtxDataInput(null.bytes)
        #expect(try WsjtxCodec.readDateTimeUtc(&nullIn) == nil)
    }

    /// String lengths from the network: negative (not just −1) = `null`, 65,535 passes, `Int32.max` throws without allocation.
    @Test func stringLengthsFromNetwork() throws {
        var minusTwo = WsjtxDataInput([0xFF, 0xFF, 0xFF, 0xFE, 0x41])
        #expect(try WsjtxCodec.readString(&minusTwo) == nil)
        var maxLength = WsjtxDataInput([0, 0, 0xFF, 0xFF] + [UInt8](repeating: 0x41, count: 65_535))
        #expect(try WsjtxCodec.readString(&maxLength)?.utf8.count == 65_535)
        var short = WsjtxDataInput([0, 0, 0xFF, 0xFF, 0x41])
        #expect(throws: WsjtxError.endOfStream) { try WsjtxCodec.readString(&short) }
        var intMax = WsjtxDataInput([0x7F, 0xFF, 0xFF, 0xFF])
        #expect(throws: WsjtxError.stringLengthOutOfRange(Int32.max)) { try WsjtxCodec.readString(&intMax) }
    }

    /// An older WSJT-X without `lowConfidence`/`offAir`: the bools are read only when bytes remain; excess is ignored.
    @Test func decodeOptionalTrailingBooleans() throws {
        let full: [UInt8] = WsjtxMessages.encodeDecode(WsjtxDecodeTests.decode)
        let old: [UInt8] = Array(full.dropLast(2))
        var expected = WsjtxDecodeTests.decode
        #expect(try WsjtxMessages.decode(old) == .decode(expected))
        let extra: [UInt8] = full + [1, 2, 3]
        #expect(try WsjtxMessages.decode(extra) == .decode(expected))
        let oneMore: [UInt8] = old + [7]
        expected.lowConfidence = true
        #expect(try WsjtxMessages.decode(oneMore) == .decode(expected))
    }

    /// Decode equality like a Java record (`Double.compare`): NaN = NaN, `0.0` ≠ `-0.0`.
    @Test func decodeEqualityFollowsDoubleCompare() {
        var a = WsjtxDecodeTests.decode
        var b = WsjtxDecodeTests.decode
        a.deltaTime = Double(bitPattern: 0x7FF0_0000_0000_0001)
        b.deltaTime = .nan
        #expect(a == b)
        a.deltaTime = 0.0
        b.deltaTime = -0.0
        #expect(a != b)
    }

    /// Java `new String(b, UTF_8)` differs from Swift's maximal subparts for encoded surrogates
    /// (measured by the `wsjtx.DEC` section of the `net-ref-gen` generator); other shapes as Swift.
    @Test func javaUtf8Replacement() {
        let cases: [([UInt8], String)] = [
            ([0xED, 0xA0, 0x80], "\u{FFFD}"),
            ([0xED, 0xBF, 0xBF, 0x41], "\u{FFFD}A"),
            ([0xED, 0xA0, 0x41], "\u{FFFD}A"),
            ([0xED, 0xA0], "\u{FFFD}"),
            ([0xC3, 0x28, 0xE2, 0x82, 0x41, 0xFF], "\u{FFFD}(\u{FFFD}A\u{FFFD}"),
            ([0xC0, 0x80], "\u{FFFD}\u{FFFD}"),
            ([0xE0, 0x80, 0x80], "\u{FFFD}\u{FFFD}\u{FFFD}"),
            ([0xF4, 0x90, 0x80, 0x80], "\u{FFFD}\u{FFFD}\u{FFFD}\u{FFFD}"),
            ([0xF0, 0x9F, 0x98], "\u{FFFD}"),
            ([0xF0, 0x9F, 0x98, 0x80], "\u{1F600}"),
            ([0xEF, 0xBB, 0xBF, 0x41], "\u{FEFF}A"),
            ([0xC3, 0xA9, 0x00], "\u{E9}\u{0}"),
        ]
        for (bytes, expected) in cases {
            #expect(JavaUtf8.decode(bytes) == expected, "\(bytes)")
        }
    }

    /// A Julian day within the `LocalDate` range, but millions of years from today: Java returns an `Instant`, Swift `Date`
    /// cannot carry the milliseconds (a precision divergence) — mainly it does not crash.
    @Test func hugeInRangeJulianDayDoesNotCrash() throws {
        for jd: Int64 in [0x7FFF_FFFF, 365_241_780_471 + 2_440_588, -365_243_219_162 + 2_440_588] {
            var out = WsjtxDataOutput()
            out.writeLong(jd)
            out.writeInt(Int32.max)
            out.writeByte(1)
            var input = WsjtxDataInput(out.bytes)
            let date = try #require(try WsjtxCodec.readDateTimeUtc(&input))
            var again = WsjtxDataOutput()
            WsjtxCodec.writeDateTimeUtc(&again, date)
            #expect(again.bytes.count == 13)
        }
    }
}
