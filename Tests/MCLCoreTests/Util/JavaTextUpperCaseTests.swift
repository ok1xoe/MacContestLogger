import CryptoKit
import Foundation
import Testing
@testable import MCLCore

/// `JavaText.toUpperCase` against JDK 21 under `en_US` (= `Locale.ROOT` = `cs_CZ`, `UPPER.rootSame`):
/// string cases, the full list of expanding mappings (`ß` → `SS`, `ŉ` → `ʼN`…) and a SHA-256
/// fingerprint over all code points (maintainer-only probe).
@Suite struct JavaTextUpperCaseTests {

    private static func rows(_ id: String) -> [[String]] {
        ProbeRows.rows(HelpersMeasured.rows, id)
    }

    @Test func toUpperCaseMatchesJava() {
        let rows: [[String]] = Self.rows("UPPER")
        #expect(rows.count == 48)
        for row in rows {
            let actual: String = JavaText.toUpperCase(row[0])
            #expect(Array(actual.utf16) == Array(row[1].utf16), "\(row[0].unicodeScalars.map(\.value))")
            #expect(actual.utf16.count == Int(row[2])!)
        }
        #expect(Self.rows("UPPER.rootSame") == [["true"]])
    }

    /// Latin-1 points on which `ScpDatabase` stands (3.2) — the length changes at `ß`.
    @Test func latin1SpecialsMatchJava() {
        #expect(JavaText.toUpperCase("ok1\u{DF}\u{FF}\u{B5}") == "OK1SS\u{178}\u{39C}")
        #expect(JavaText.toUpperCase("\u{DF}").utf16.count == 2)
        #expect(JavaText.toUpperCase("\u{149}") == "\u{2BC}N")
    }

    /// Points newer than Unicode 15.0 and points whose uppercase letter appeared only in 16.0
    /// (`ƛ` → U+A7DC, `ɤ` → U+A7CB), Java leaves unchanged.
    @Test func postUnicode15MappingsStayUnchanged() {
        #expect(JavaText.toUpperCase("\u{19B}\u{264}\u{1C8A}\u{A7CD}") == "\u{19B}\u{264}\u{1C8A}\u{A7CD}")
    }

    /// All mappings to more than one code point — exactly the Java list (102).
    @Test func expandingMappingsMatchJava() {
        let java: [[String]] = Self.rows("UPPER.expand")
        var swift: [[String]] = []
        for value in UInt32(0)...0x10FFFF {
            guard let scalar = Unicode.Scalar(value) else { continue }
            let mapped: [Unicode.Scalar] = JavaText.upperCodePoints(scalar)
            guard mapped.count > 1 else { continue }
            swift.append([Self.hex(value), mapped.map { Self.hex($0.value) }.joined(separator: ",")])
        }
        #expect(java.count == 102)
        #expect(swift == java)
    }

    /// A fingerprint over all code points (and separately over the BMP) against Java.
    @Test func codePointSweepMatchesJava() {
        var all = SHA256()
        var bmp = SHA256()
        var changedAll = 0
        var changedBmp = 0
        for value in UInt32(0)...0x10FFFF {
            guard let scalar = Unicode.Scalar(value) else { continue }
            let mapped: [Unicode.Scalar] = JavaText.upperCodePoints(scalar)
            if mapped == [scalar] { continue }
            let target: String = mapped.map { Self.hex($0.value) }.joined(separator: ",")
            let line = Data("\(Self.hex(value)):\(target)\n".utf8)
            all.update(data: line)
            changedAll += 1
            if value <= 0xFFFF {
                bmp.update(data: line)
                changedBmp += 1
            }
        }
        let sweep: [[String]] = Self.rows("UPPER.sweep")
        #expect(sweep == [
            ["all", String(changedAll), Self.digest(all)],
            ["bmp", String(changedBmp), Self.digest(bmp)],
        ])
    }

    static func hex(_ value: UInt32) -> String {
        String(value, radix: 16).uppercased()
    }

    static func digest(_ hasher: SHA256) -> String {
        hasher.finalize().map { byte in
            let text = String(byte, radix: 16)
            return byte < 16 ? "0" + text : text
        }.joined()
    }
}
