import Foundation
import Testing
@testable import MCLCore

/// The `Utf8Text` helper must behave the same on every Foundation version — it is tested
/// on bytes, not via `String(data:encoding:)`.
struct Utf8TextTests {

    private func scalars(_ bytes: [UInt8]) -> [UInt32]? {
        Utf8Text.decodeStrippingBom(Data(bytes))?.unicodeScalars.map(\.value)
    }

    @Test func stripsLeadingBom() {
        #expect(scalars([0xEF, 0xBB, 0xBF, 0x41]) == [0x41])
    }

    @Test func leavesTextWithoutBomUnchanged() {
        #expect(scalars([0x41, 0xC3, 0xA1]) == [0x41, 0xE1])
        #expect(scalars([]) == [])
    }

    @Test func stripsOnlyOneOfDoubleBom() {
        #expect(scalars([0xEF, 0xBB, 0xBF, 0xEF, 0xBB, 0xBF, 0x41]) == [0xFEFF, 0x41])
    }

    @Test func keepsBomInsideText() {
        #expect(scalars([0x41, 0xEF, 0xBB, 0xBF]) == [0x41, 0xFEFF])
    }

    @Test func rejectsInvalidUtf8() {
        #expect(scalars([0x41, 0xFF]) == nil)
        #expect(scalars([0xEF, 0xBB, 0xBF, 0xC3]) == nil)
    }

    @Test func readFileStripsBomAndRejectsInvalid() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("utf8text-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let ok = dir.appendingPathComponent("ok")
        try Data([0xEF, 0xBB, 0xBF, 0x41]).write(to: ok)
        #expect(try Utf8Text.readFile(ok) == "A")
        let bad = dir.appendingPathComponent("bad")
        try Data([0xFF]).write(to: bad)
        #expect(throws: (any Error).self) { try Utf8Text.readFile(bad) }
    }

    // MARK: - decodeKeepingBom (Java `Files.readString`)

    /// A table from JDK 21 (`JavaFormatMeasured.readString`): the BOM stays as
    /// U+FEFF, invalid UTF-8 (overlong, surrogate points, above U+10FFFF, truncation)
    /// is `MalformedInputException`.
    @Test func keepingBomMatchesJavaReadString() {
        for row in JavaFormatMeasured.readString {
            let decoded = Utf8Text.decodeKeepingBom(Data(row.bytes))
            let actual: JavaFormatMeasured.Utf8Outcome = decoded.map { .ok($0) } ?? .malformed
            #expect(actual == row.outcome, "\(row.bytes)")
        }
    }

    /// Comparison by scalars — Swift `==` would not reliably distinguish a BOM or canonical equivalence.
    @Test func keepingBomKeepsEveryBom() {
        let text = Utf8Text.decodeKeepingBom(Data([0xEF, 0xBB, 0xBF, 0x41, 0xEF, 0xBB, 0xBF]))
        #expect(text?.unicodeScalars.map(\.value) == [0xFEFF, 0x41, 0xFEFF])
        #expect(text?.utf16.count == 3)
    }

    @Test func readFileKeepingBomThrowsMalformedInput() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("utf8text-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let ok = dir.appendingPathComponent("ok")
        try Data([0xEF, 0xBB, 0xBF, 0x41]).write(to: ok)
        #expect(try Utf8Text.readFileKeepingBom(ok).unicodeScalars.map(\.value) == [0xFEFF, 0x41])
        let bad = dir.appendingPathComponent("bad")
        try Data([0xED, 0xA0, 0x80]).write(to: bad)
        #expect(throws: Utf8Text.MalformedInput.self) { try Utf8Text.readFileKeepingBom(bad) }
        let missing = dir.appendingPathComponent("missing")
        #expect(throws: CocoaError.self) { try Utf8Text.readFileKeepingBom(missing) }
    }
}
