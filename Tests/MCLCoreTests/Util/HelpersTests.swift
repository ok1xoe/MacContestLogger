import CryptoKit
import Foundation
import Testing
@testable import MCLCore

/// Shared helpers against tables from JDK 21 (maintainer-only probe):
/// `JavaText.compare` (= `String.compareTo`), `JavaLines.split` (= `BufferedReader.readLine`,
/// `String.lines()`, `Files.readAllLines`) and `JavaMath.round(Float)` (= `Math.round(float)`).
@Suite struct HelpersTests {

    private static func rows(_ id: String) -> [[String]] {
        ProbeRows.rows(HelpersMeasured.rows, id)
    }

    // MARK: - compareTo

    /// The exact Java value: the difference of the first differing UTF-16 unit, otherwise the difference of lengths.
    /// `😀` (D83D…) is before `ａ` (FF41), `é` (NFC) after `e` + U+0301 (NFD).
    @Test func compareMatchesJavaCompareTo() {
        let rows: [[String]] = Self.rows("CMP")
        #expect(rows.count == 20)
        for row in rows {
            #expect(JavaText.compare(row[0], row[1]) == Int(row[2])!, "\(row[0]) \(row[1])")
        }
    }

    // MARK: - readLine

    @Test func splitMatchesJavaReadLine() {
        let rows: [[String]] = Self.rows("LINES")
        #expect(rows.count == 27)
        for row in rows {
            let expected: [String] = row.dropFirst(2).map { String($0.dropFirst().dropLast()) }
            #expect(Int(row[1])! == expected.count)
            let actual: [String] = JavaLines.split(row[0])
            #expect(actual.map { Array($0.utf16) } == expected.map { Array($0.utf16) }, "\(row[0].debugDescription)")
        }
        #expect(Self.rows("LINES.agree") == [["true"]])
    }

    /// `\r\n` is one `Character` in Swift; it is split by scalars, not by characters.
    @Test func crlfGraphemeIsOneTerminator() {
        let text: String = "a\r\nb\r\n\r\nc"
        #expect(JavaLines.split(text) == ["a", "b", "", "c"])
    }

    // MARK: - Math.round(float)

    @Test func roundFloatMatchesJava() {
        let rows: [[String]] = Self.rows("ROUNDF")
        #expect(rows.count == 45)
        for row in rows {
            let value = Float(bitPattern: UInt32(row[0], radix: 16)!)
            #expect(JavaMath.round(value) == Int32(row[2])!, "\(row[0]) \(row[1])")
        }
    }

    /// Every 4099th `float` bit pattern (1,047,809 values incl. NaN, infinities and subnormals).
    @Test func roundFloatSweepMatchesJava() {
        var hasher = SHA256()
        var count = 0
        var bits: UInt64 = 0
        while bits < (1 << 32) {
            let pattern = UInt32(bits)
            let result: Int32 = JavaMath.round(Float(bitPattern: pattern))
            hasher.update(data: Data("\(Self.hex8(pattern)):\(result)\n".utf8))
            count += 1
            bits += 4099
        }
        let digest: String = JavaTextUpperCaseTests.digest(hasher)
        #expect(Self.rows("ROUNDF.sweep") == [["4099", String(count), digest]])
    }

    private static func hex8(_ value: UInt32) -> String {
        let text: String = String(value, radix: 16).uppercased()
        return String(repeating: "0", count: 8 - text.count) + text
    }
}
