import Foundation
import Testing
@testable import MCLCore

/// Tests of byte-encoding detection and BOM handling.
///
/// Java Jackson (`ByteSourceJsonBootstrapper`) **infers the encoding from the first
/// four bytes**, so it also reads a file re-saved as UTF-16 or UTF-32.
/// `~/dxcc-json/dxcc.json` is a third-party data set we do not control — if the
/// Java application read it and the Swift one rejected it, the user would be left without DXCC,
/// hence without dupes, multipliers and score.
///
/// Inputs are built **from bytes**, not from Swift literals, and for each encoding its
/// beginning is also pinned so it is certain what exactly is being read. All
/// expected results are measured on Java v1.1.1 (probe `Probe14`).
@Suite struct DxccJsonEncodingTests {

    /// Contains a diacritic (`Ř` = U+0158) so that wrong decoding is noticed.
    private static let json = #"{"dxcc":[{"entityCode":7,"name":"Ř","countryCode":"CZ","prefixRegex":"^OK.*"}]}"#

    private static let utf8Bom: [UInt8] = [0xEF, 0xBB, 0xBF]

    private static func utf8Bytes(_ text: String = json) -> [UInt8] {
        Array(text.utf8)
    }

    private static func utf16Bytes(_ text: String = json, littleEndian: Bool) -> [UInt8] {
        text.utf16.flatMap { unit -> [UInt8] in
            let high = UInt8(truncatingIfNeeded: unit >> 8)
            let low = UInt8(truncatingIfNeeded: unit)
            return littleEndian ? [low, high] : [high, low]
        }
    }

    private static func utf32Bytes(_ text: String = json, littleEndian: Bool) -> [UInt8] {
        text.unicodeScalars.flatMap { scalar -> [UInt8] in
            let value = scalar.value
            let bigEndian = [UInt8(truncatingIfNeeded: value >> 24), UInt8(truncatingIfNeeded: value >> 16),
                             UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)]
            return littleEndian ? bigEndian.reversed() : bigEndian
        }
    }

    // MARK: encodings that Java accepts

    /// Six encodings in addition to UTF-8 without BOM: UTF-16LE/BE and UTF-32LE/BE, with BOM
    /// and without. Java returns `n=1` and `name=Ř` for all of them (measured).
    @Test func acceptsEveryEncodingJacksonDetects() throws {
        let variants: [(String, [UInt8], [UInt8])] = [
            ("UTF-8", Self.utf8Bytes(), [0x7B, 0x22, 0x64, 0x78]),
            ("UTF-8 + BOM", Self.utf8Bom + Self.utf8Bytes(), [0xEF, 0xBB, 0xBF, 0x7B]),
            ("UTF-16LE", Self.utf16Bytes(littleEndian: true), [0x7B, 0x00, 0x22, 0x00]),
            ("UTF-16LE + BOM", [0xFF, 0xFE] + Self.utf16Bytes(littleEndian: true), [0xFF, 0xFE, 0x7B, 0x00]),
            ("UTF-16BE", Self.utf16Bytes(littleEndian: false), [0x00, 0x7B, 0x00, 0x22]),
            ("UTF-16BE + BOM", [0xFE, 0xFF] + Self.utf16Bytes(littleEndian: false), [0xFE, 0xFF, 0x00, 0x7B]),
            ("UTF-32LE", Self.utf32Bytes(littleEndian: true), [0x7B, 0x00, 0x00, 0x00]),
            ("UTF-32LE + BOM", [0xFF, 0xFE, 0x00, 0x00] + Self.utf32Bytes(littleEndian: true),
             [0xFF, 0xFE, 0x00, 0x00]),
            ("UTF-32BE", Self.utf32Bytes(littleEndian: false), [0x00, 0x00, 0x00, 0x7B]),
            ("UTF-32BE + BOM", [0x00, 0x00, 0xFE, 0xFF] + Self.utf32Bytes(littleEndian: false),
             [0x00, 0x00, 0xFE, 0xFF]),
        ]
        for (label, bytes, prefixBytes) in variants {
            // First make sure the test feeds exactly the bytes it thinks it does.
            #expect(Array(bytes.prefix(4)) == prefixBytes, "\(label): start of bytes")

            let resolver = try DxccResolver.fromData(Data(bytes))
            #expect(resolver.entities().count == 1, "\(label)")
            #expect(resolver.entities().first?.entityCode == 7, "\(label)")
            #expect(resolver.entities().first?.name == "Ř", "\(label): diacritic")
            #expect(resolver.resolve("OK1XOE")?.countryCode == "CZ", "\(label)")

            let index = try DxccCodeIndex.fromData(Data(bytes))
            #expect(index.code("Ř", nil) == 7, "\(label): index")
        }
    }

    /// Java reads UTF-16 with an unpaired byte at the end (the document is already complete,
    /// the rest is content after the end).
    @Test func trailingHalfCodeUnitIsTolerated() throws {
        let bytes = Self.utf16Bytes(littleEndian: true) + [0x20]
        let resolver = try DxccResolver.fromData(Data(bytes))
        #expect(resolver.entities().count == 1)
    }

    // MARK: only one BOM is stripped

    /// One BOM passes, two or three do not (in Java `JsonParseException`). Foundation
    /// swallows one BOM by itself in `String(data:encoding:.utf8)`, so this
    /// is exactly the place where the port used to tolerate two.
    @Test func exactlyOneBomIsStripped() throws {
        let one = Self.utf8Bom + Self.utf8Bytes()
        #expect(Array(one.prefix(6)) == [0xEF, 0xBB, 0xBF, 0x7B, 0x22, 0x64])
        #expect(try DxccResolver.fromData(Data(one)).entities().count == 1)

        let two = Self.utf8Bom + Self.utf8Bom + Self.utf8Bytes()
        #expect(Array(two.prefix(6)) == [0xEF, 0xBB, 0xBF, 0xEF, 0xBB, 0xBF])
        for count in [2, 3, 4] {
            let bytes = Array(repeating: Self.utf8Bom, count: count).flatMap { $0 } + Self.utf8Bytes()
            #expect(throws: DxccError.self, "\(count)× BOM") {
                _ = try DxccResolver.fromData(Data(bytes))
            }
            #expect(throws: DxccError.self, "\(count)× BOM (index)") {
                _ = try DxccCodeIndex.fromData(Data(bytes))
            }
        }
    }

    /// Same for UTF-16: after the real BOM (`FF FE`) the encoded character U+FEFF
    /// is an error — Java reports "Unexpected character (U+FEFF)".
    @Test func bomCharacterAfterUtf16BomIsAnError() {
        let bytes: [UInt8] = [0xFF, 0xFE] + Self.utf16Bytes("\u{FEFF}" + Self.json, littleEndian: true)
        #expect(Array(bytes.prefix(4)) == [0xFF, 0xFE, 0xFF, 0xFE])
        #expect(throws: DxccError.self) {
            _ = try DxccResolver.fromData(Data(bytes))
        }
    }

    /// A U+FEFF character at the start **without** a BOM is byte-wise indistinguishable from a BOM
    /// (`EF BB BF` in UTF-8, `FF FE` in UTF-16LE), so Java — and the port —
    /// swallow it as a BOM. This is a property of the format, not a divergence.
    @Test func leadingBomCharacterIsIndistinguishableFromBom() throws {
        let utf8 = Self.utf8Bytes("\u{FEFF}" + Self.json)
        #expect(Array(utf8.prefix(4)) == [0xEF, 0xBB, 0xBF, 0x7B])
        #expect(try DxccResolver.fromData(Data(utf8)).entities().count == 1)

        let utf16 = Self.utf16Bytes("\u{FEFF}" + Self.json, littleEndian: true)
        #expect(Array(utf16.prefix(4)) == [0xFF, 0xFE, 0x7B, 0x00])
        #expect(try DxccResolver.fromData(Data(utf16)).entities().count == 1)
    }

    // MARK: what Java rejects

    /// Byte orders "2143" and "3412" are rejected by Java ("Unsupported UCS-4 endianness"),
    /// both by the placement of nulls and by the shuffled BOM.
    @Test func weirdUcs4ByteOrderIsRejected() {
        let inputs: [(String, [UInt8])] = [
            ("2143 without BOM", [0x00, 0x00, 0x7B, 0x00, 0x00, 0x00, 0x22, 0x00]),
            ("3412 without BOM", [0x00, 0x7B, 0x00, 0x00, 0x00, 0x22, 0x00, 0x00]),
            ("2143 BOM", [0x00, 0x00, 0xFF, 0xFE, 0x00, 0x00, 0x7B, 0x00]),
            ("3412 BOM", [0xFE, 0xFF, 0x00, 0x00, 0x00, 0x7B, 0x00, 0x00]),
        ]
        for (label, bytes) in inputs {
            #expect(throws: DxccError.self, "\(label)") {
                _ = try DxccResolver.fromData(Data(bytes))
            }
            #expect(throws: DxccError.self, "\(label) (index)") {
                _ = try DxccCodeIndex.fromData(Data(bytes))
            }
        }
    }

    /// Detection needs **four** bytes; with fewer, UTF-8 is assumed. Hence a lone
    /// `FF FE` is an error (not an empty UTF-16 document) and `{}` is read as an
    /// empty object in UTF-8 — that is, a Java `NullPointerException` because of
    /// the missing `dxcc` field.
    @Test func detectionNeedsFourBytesAndFallsBackToUtf8() {
        for shortInput in [[0xFF, 0xFE] as [UInt8], [0xEF, 0xBB, 0xBF], [0xFE, 0xFF], [0x00]] {
            #expect(throws: DxccError.self, "\(shortInput)") {
                _ = try DxccResolver.fromData(Data(shortInput))
            }
        }
        do {
            _ = try DxccResolver.fromData(Data([0x7B, 0x7D])) // "{}"
            Issue.record("should have ended with an error")
        } catch let failure as DxccError {
            #expect(failure.kind == .nullPointer)
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    /// Bad bytes remain an error in Java and here, albeit for a different reason:
    /// invalid UTF-8, a lone surrogate in UTF-16LE (`{` + `D800`, where Java
    /// substitutes U+FFFD and the parser then chokes on it, while Foundation decoding rejects it)
    /// and bytes detected as UTF-16BE that do not form valid JSON.
    @Test func invalidBytesAreStillAnError() {
        #expect(throws: DxccError.self) {
            _ = try DxccResolver.fromData(Data([0xFF, 0x41, 0x42, 0x43]))
        }
        #expect(throws: DxccError.self) {
            _ = try DxccResolver.fromData(Data([0x7B, 0x00, 0x00, 0xD8, 0x22, 0x00]))
        }
        #expect(throws: DxccError.self) {
            _ = try DxccResolver.fromData(Data([0x00, 0xD8, 0x7B, 0x00, 0x22, 0x00]))
        }
        // All zeros: UTF-32BE is detected and it ends in an error (as in Java).
        #expect(throws: DxccError.self) {
            _ = try DxccResolver.fromData(Data([0x00, 0x00, 0x00, 0x00]))
        }
    }

    /// A valid surrogate **pair** in UTF-16LE decodes correctly (Java `n=1`).
    @Test func surrogatePairInUtf16IsDecoded() throws {
        let json = #"{"dxcc":[{"entityCode":7,"name":"🇨","prefixRegex":"^OK.*"}]}"#
        let bytes = Self.utf16Bytes(json, littleEndian: true)
        #expect(Array(bytes.prefix(4)) == [0x7B, 0x00, 0x22, 0x00])
        let resolver = try DxccResolver.fromData(Data(bytes))
        #expect(resolver.entities().first?.name == "🇨")
    }
}
