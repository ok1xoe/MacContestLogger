import CryptoKit
import Foundation
import Testing
@testable import MCLCore

/// `JavaText.toLowerCase`, `indexOf` and `substring` by UTF-16 units against
/// tables from JDK 21 (`JavaFormatMeasured`, probe `ProbeFormat`). `AdifReader` stands
/// on them: it looks for `<eoh>`/`<eor>` in a `toLowerCase()` copy and uses the indices from it
/// on the original — after every `İ` (U+0130 → `i` + U+0307) they diverge
/// by one unit and Java crashes with `StringIndexOutOfBoundsException`.
@Suite struct JavaTextLowerCaseTests {

    @Test func toLowerCaseMatchesJava() {
        for row in JavaFormatMeasured.lower {
            #expect(JavaText.toLowerCase(row.input) == row.expected, "\(row.input.unicodeScalars.map(\.value))")
        }
    }

    @Test func dottedCapitalIGrowsByOneUnit() {
        let lower = JavaText.toLowerCase("<COMMENT:1>\u{130}<CALL:4>")
        #expect(lower == "<comment:1>i\u{307}<call:4>")
        #expect(lower.utf16.count == "<COMMENT:1>\u{130}<CALL:4>".utf16.count + 1)
    }

    /// `Character.toLowerCase(int)` over all code points against a fingerprint from Java
    /// (the Unicode version of JDK 21 vs. the Swift standard library).
    @Test func codePointTableMatchesJava() {
        var hasher = SHA256()
        var changed = 0
        for value in UInt32(0)...0x10FFFF {
            guard let scalar = Unicode.Scalar(value) else { continue }
            let lower = JavaText.lowerCodePoint(scalar)
            guard lower != scalar else { continue }
            let line = String(value, radix: 16).uppercased() + ":" + String(lower.value, radix: 16).uppercased() + "\n"
            hasher.update(data: Data(line.utf8))
            changed += 1
        }
        let hex = hasher.finalize().map { byte in
            let text = String(byte, radix: 16)
            return byte < 16 ? "0" + text : text
        }.joined()
        #expect(changed == JavaFormatMeasured.lowerTableCount)
        #expect(hex == JavaFormatMeasured.lowerTableSha256)
    }

    @Test func substringMatchesJava() {
        for row in JavaFormatMeasured.substring {
            let units = Array(row.text.utf16)
            let actual: String
            do {
                // `end == -1` = the one-parameter `substring(begin)` (the probe also writes `substring(-1)` that way).
                let part: String
                if row.end == -1 {
                    part = try JavaText.substring(units, row.begin)
                } else {
                    part = try JavaText.substring(units, row.begin, row.end)
                }
                actual = "OK " + part
            } catch {
                actual = "EXC StringIndexOutOfBoundsException: " + error.message
            }
            #expect(actual == row.expected, "\(row.begin) \(row.end)")
        }
    }

    @Test func indexOfMatchesJava() {
        for row in JavaFormatMeasured.indexOf {
            let haystack = Array(row.haystack.utf16)
            #expect(JavaText.indexOf(haystack, Array(row.needle.utf16), from: row.from) == row.found,
                    "\(row.haystack) \(row.from)")
            #expect(JavaText.indexOf(haystack, [], from: row.from) == row.empty, "\(row.haystack) \(row.from)")
        }
    }

    /// The algorithm of `AdifReader.readRecords` (`indexOfIgnoreCase` + `splitIgnoreCase`)
    /// composed of helpers — the same parts or the same exception as in Java.
    @Test func adifSplitArithmeticMatchesJava() {
        for row in JavaFormatMeasured.adifSplit {
            #expect(Self.adifSplit(row.input) == row.expected, "\(row.input)")
        }
    }

    private static func adifSplit(_ content: String) -> String {
        do {
            let units = Array(content.utf16)
            let eoh = JavaText.indexOf(Array(JavaText.toLowerCase(content).utf16), Array("<eoh>".utf16))
            let body = eoh >= 0 ? try JavaText.substring(units, eoh + 5) : content
            let bodyUnits = Array(body.utf16)
            let lower = Array(JavaText.toLowerCase(body).utf16)
            let delimiter = Array("<eor>".utf16)
            var parts: [String] = []
            var from = 0
            var index = JavaText.indexOf(lower, delimiter, from: from)
            while index >= 0 {
                parts.append(try JavaText.substring(bodyUnits, from, index))
                from = index + delimiter.count
                index = JavaText.indexOf(lower, delimiter, from: from)
            }
            parts.append(try JavaText.substring(bodyUnits, from))
            return "eoh=" + String(eoh) + parts.map { " [" + escape($0) + "]" }.joined()
        } catch {
            return "EXC StringIndexOutOfBoundsException: " + error.message
        }
    }

    /// Probe escaping (`\uXXXX` by UTF-16 units outside printable ASCII).
    private static func escape(_ text: String) -> String {
        var out = ""
        for unit in text.utf16 {
            if unit >= 0x20 && unit <= 0x7E && unit != 0x5C {
                out.unicodeScalars.append(Unicode.Scalar(unit)!)
            } else {
                let hex = String(unit, radix: 16).uppercased()
                out += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
            }
        }
        return out
    }
}
