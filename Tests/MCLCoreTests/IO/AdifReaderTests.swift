import Foundation
import Testing
@testable import MCLCore

/// Port of `AdifReaderTest.java` (2 tests). Edge inputs against Java: `AdifEdgeParityTests`.
@Suite struct AdifReaderTests {

    // MARK: - `AdifReaderTest.roundTripWithWriter`

    @Test func roundTripWithWriter() throws {
        var q = Qso()
        q.timestampUtc = ISO8601DateFormatter().date(from: "2026-06-17T12:00:00Z")
        q.call = "DL1ABC"
        q.freqHz = 14_074_000
        q.mode = .ssb
        q.rstSent = "59"
        q.rstRcvd = "59"
        q.serialSent = 1
        q.serialRcvd = 42

        let adif = AdifWriter().toAdif([q])
        let read = try AdifReader().read(adif)

        #expect(read.count == 1)
        let r = try #require(read.first)
        #expect(r.call == "DL1ABC")
        #expect(r.freqHz == 14_074_000)
        #expect(r.mode == .ssb)
        #expect(r.band == .m20)
        #expect(r.serialRcvd == 42)
        #expect(r.timestampUtc == ISO8601DateFormatter().date(from: "2026-06-17T12:00:00Z"))
    }

    // MARK: - `AdifReaderTest.skipsHeaderAndIgnoresUnknownFields`

    @Test func skipsHeaderAndIgnoresUnknownFields() throws {
        let adif = "Hlavička\n<ADIF_VER:5>3.1.4<EOH>\n"
            + "<CALL:6>OK1XOE<BAND:3>40m<MODE:2>CW<FOO:3>bar<EOR>\n"
        let read = try AdifReader().read(adif)
        #expect(read.count == 1)
        #expect(read.first?.call == "OK1XOE")
        #expect(read.first?.band == .m40)
        #expect(read.first?.mode == .cw)
    }

    // MARK: - Exceptions

    @Test func negativeLengthThrowsLikeJava() {
        let error = #expect(throws: JavaIndexOutOfBoundsError.self) {
            try AdifReader().read("<CALL:-1>W1AW")
        }
        #expect(error?.message == "Range [9, 8) out of bounds for length 13")
    }

    /// `valStart + len` overflows `int` as in Java.
    @Test func intOverflowLengthThrowsLikeJava() {
        let error = #expect(throws: JavaIndexOutOfBoundsError.self) {
            try AdifReader().readRecords("<CALL:2147483647>W1AW")
        }
        #expect(error?.message == "Range [17, -2147483632) out of bounds for length 21")
    }

    /// `"İ".toLowerCase()` has 2 units — indices from the lowercase copy shift. The input and message
    /// = a row of the probe output (and the fixture `AR21-tecka-nad-I.adi`).
    @Test func dottedCapitalIShiftsIndicesLikeJava() {
        let text = "<EOH><COMMENT:1>\u{0130}<CALL:4>W1AW<EOR><CALL:4>OK1A<EOR>"
        let error = #expect(throws: JavaIndexOutOfBoundsError.self) { try AdifReader().read(text) }
        #expect(error?.message == "Range [47, 46) out of bounds for length 46")
    }

    /// `readFile`: unreadable UTF-8 → `UncheckedIOError` with cause `MalformedInput`, the BOM stays.
    @Test func readFileWrapsDecodingErrors() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("adif-reader-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let bad = dir.appendingPathComponent("bad.adi")
        try Data([0x3C, 0x43, 0xFF, 0x3E]).write(to: bad)
        let error = try #require(throws: UncheckedIOError.self) { try AdifReader().readFile(bad) }
        #expect(error.message == "Nelze načíst ADIF: " + bad.path)
        #expect(error.cause is Utf8Text.MalformedInput)

        let missing = dir.appendingPathComponent("chybi.adi")
        let notFound = try #require(throws: UncheckedIOError.self) { try AdifReader().readFile(missing) }
        #expect(notFound.message == "Nelze načíst ADIF: " + missing.path)
    }
}
