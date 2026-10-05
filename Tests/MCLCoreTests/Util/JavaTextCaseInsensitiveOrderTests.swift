import CryptoKit
import Foundation
import Testing
@testable import MCLCore

/// `JavaText.caseInsensitiveOrder` — Java `String.CASE_INSENSITIVE_ORDER` (`RigModelFilter`:
/// ordering of manufacturers and models, the `TreeSet` of manufacturers). Measured on JDK 21.0.2
/// (maintainer-only probe, rows `CI.*`).
///
/// Java compares by UTF-16 units: if they differ, it compares `Character.toUpperCase` of both and if those differ
/// too, the difference of `Character.toLowerCase` of the uppercase ones decides (`ß` < `É`, because `ß` < `é`;
/// `µ` > `¶`, because `µ` → `Μ` → `μ`). If **both** strings are in UTF-16 representation (they contain a
/// character above U+00FF), it additionally composes surrogate pairs into a code point (`𐐀` > U+FFFF, `𐐀` = `𐐨`);
/// if one is Latin-1, it goes purely by units (`𐐀` − `é` = 0xD801 − 0xE9).
@Suite struct JavaTextCaseInsensitiveOrderTests {

    /// The sign of `compare(a, b)` for all pairs (row = `a`, column = `b` in list order).
    /// Java rows with a lone half of a surrogate pair (`\uD801`, `\uDC28`, `\uD801x`) are
    /// missing here — a Swift `String` cannot carry them (the probe output has them).
    static let signs: [(String, String)] = [
        ("", "0-------------------------------------------------"),
        ("x", "+0+++-+++++-----------++++++++++------++++++------"),
        ("_x", "+-0-----------------------------------------------"),
        ("elan", "+-+00-----------------++++++----------------------"),
        ("Elan", "+-+00-----------------++++++----------------------"),
        ("\u{C9}lan", "+++++0++++++++-----+--++++++++++------++++++------"),
        ("Hamlib", "+-+++-00--------------++++++----------------------"),
        ("hamlib", "+-+++-00--------------++++++----------------------"),
        ("I\u{130}", "+-+++-++0-------------++++++++++------------------"),
        ("Kenwood", "+-+++-+++0------------++++++++++---------+++------"),
        ("SS", "+-+++-++++0-----------++++++++++------++++++------"),
        ("Zeta", "+++++-+++++0----------++++++++++------++++++------"),
        ("\u{DF}", "+++++-++++++0------+--++++++++++------++++++------"),
        ("\u{E9}", "+++++-+++++++0-----+--++++++++++------++++++------"),
        ("\u{FF}", "++++++++++++++00---+--++++++++++------++++++------"),
        ("\u{178}", "++++++++++++++00---+--++++++++++------++++++------"),
        ("\u{B5}", "++++++++++++++++000+--+++++++++++++---++++++------"),
        ("\u{3BC}", "++++++++++++++++000+--+++++++++++++---++++++------"),
        ("\u{39C}", "++++++++++++++++000+--+++++++++++++---++++++------"),
        ("\u{B6}", "+++++-++++++-------0--++++++++++------++++++------"),
        ("\u{10400}", "++++++++++++++++++++00++++++++++++++++++++++++++++"),
        ("\u{10428}", "++++++++++++++++++++00++++++++++++++++++++++++++++"),
        ("a\u{10400}", "+-+-------------------00++++----------------------"),
        ("a\u{10428}", "+-+-------------------00++++----------------------"),
        ("A", "+-+---------------------00------------------------"),
        ("a", "+-+---------------------00------------------------"),
        ("ab", "+-+---------------------++00----------------------"),
        ("aB", "+-+---------------------++00----------------------"),
        ("\u{131}", "+-+++-++--------------++++++0000------------------"),
        ("I", "+-+++-++--------------++++++0000------------------"),
        ("i", "+-+++-++--------------++++++0000------------------"),
        ("\u{130}", "+-+++-++--------------++++++0000------------------"),
        ("\u{1C4}", "++++++++++++++++---+--++++++++++000---++++++------"),
        ("\u{1C5}", "++++++++++++++++---+--++++++++++000---++++++------"),
        ("\u{1C6}", "++++++++++++++++---+--++++++++++000---++++++------"),
        ("\u{3C2}", "++++++++++++++++++++--+++++++++++++000++++++------"),
        ("\u{3C3}", "++++++++++++++++++++--+++++++++++++000++++++------"),
        ("\u{3A3}", "++++++++++++++++++++--+++++++++++++000++++++------"),
        ("\u{17F}", "+-+++-++++------------++++++++++------000+++------"),
        ("s", "+-+++-++++------------++++++++++------000+++------"),
        ("S", "+-+++-++++------------++++++++++------000+++------"),
        ("\u{212A}", "+-+++-+++-------------++++++++++---------000------"),
        ("k", "+-+++-+++-------------++++++++++---------000------"),
        ("K", "+-+++-+++-------------++++++++++---------000------"),
        ("\u{10A0}", "++++++++++++++++++++--++++++++++++++++++++++00++--"),
        ("\u{2D00}", "++++++++++++++++++++--++++++++++++++++++++++00++--"),
        ("\u{1C90}", "++++++++++++++++++++--++++++++++++++++++++++--00--"),
        ("\u{10D0}", "++++++++++++++++++++--++++++++++++++++++++++--00--"),
        ("\u{FB01}", "++++++++++++++++++++--++++++++++++++++++++++++++0-"),
        ("\u{FFFF}", "++++++++++++++++++++--+++++++++++++++++++++++++++0"),
    ]

    @Test func signMatrixMatchesJava() {
        let strings: [String] = Self.signs.map(\.0)
        for (row, (left, expected)) in Self.signs.enumerated() {
            var actual = ""
            for right in strings {
                let order: Int = JavaText.caseInsensitiveOrder(left, right)
                actual += order < 0 ? "-" : order > 0 ? "+" : "0"
            }
            #expect(actual == expected, "row \(row) \(left.debugDescription)")
        }
    }

    /// Exact values (Java returns the difference of units / code points, not just the sign).
    @Test func exactValuesMatchJava() {
        let measured: [(String, String, Int)] = [
            ("x", "\u{C9}lan", -113),
            ("x", "\u{178}", -135),
            ("x", "\u{10428}", -55177),
            ("x", "a", 23),
            ("x", "\u{FFFF}", -65415),
            ("\u{DF}", "\u{C9}lan", -10),
            ("\u{DF}", "\u{B6}", 41),
            ("\u{FF}", "\u{B6}", 73),
            ("\u{B5}", "\u{B6}", 774),
            ("\u{B5}", "\u{178}", 701),
            ("\u{10400}", "\u{E9}", 55064),
            ("\u{10400}", "\u{178}", 66345),
            ("\u{10400}", "\u{FFFF}", 1065),
            ("\u{FFFF}", "\u{10428}", -1065),
            ("\u{FFFF}", "a", 65438),
        ]
        for (left, right, expected) in measured {
            #expect(JavaText.caseInsensitiveOrder(left, right) == expected,
                    "\(left.debugDescription) vs \(right.debugDescription)")
        }
    }

    /// `TreeSet<>(CASE_INSENSITIVE_ORDER)` of manufacturers: those equal regardless of case are merged into the first
    /// inserted (`Hamlib`/`hamlib` → `Hamlib`), order `[_x, elan, Hamlib, Iİ, …, ß, Élan]` (`CI.treeSet`).
    @Test func treeSetOrderMatchesJava() {
        let inserted: [String] = [
            "Zeta", "\u{C9}lan", "elan", "\u{DF}", "Kenwood", "SS", "_x", "x", "Hamlib", "hamlib", "I\u{130}",
        ]
        var set: [String] = []
        for item in inserted where !set.contains(where: { JavaText.caseInsensitiveOrder($0, item) == 0 }) {
            set.append(item)
        }
        set.sort { JavaText.caseInsensitiveOrder($0, $1) < 0 }
        let expected: [String] = ["_x", "elan", "Hamlib", "I\u{130}", "Kenwood", "SS", "x", "Zeta", "\u{DF}", "\u{C9}lan"]
        #expect(set == expected)
    }

    /// The comparison key `toLowerCase(toUpperCase(cp))` over all code points against a fingerprint from Java
    /// (`CI.keyTable`: changed points as rows `HEX:HEX\n`). Guards the Unicode version: points and mappings
    /// newer than 15.0 (JDK 21) are unknown to Java and left unchanged. The fingerprint depends on the Unicode data of the running
    /// system: **red = check the Unicode version** (a mapping change of an older character in a new macOS), not the code.
    @Test func keyTableMatchesJava() {
        var hasher = SHA256()
        var changed = 0
        for value in UInt32(0)...0x10FFFF {
            let key: UInt32 = JavaText.caseInsensitiveKey(value)
            guard key != value else { continue }
            let line: String = String(value, radix: 16).uppercased() + ":" + String(key, radix: 16).uppercased() + "\n"
            hasher.update(data: Data(line.utf8))
            changed += 1
        }
        let hex: String = hasher.finalize().map { byte in
            let text = String(byte, radix: 16)
            return byte < 16 ? "0" + text : text
        }.joined()
        #expect(changed == 1456)
        #expect(hex == "b83ba5297e87edba1ceb9b51147db71e29bd1f5cca08302a9d4aa016de25ebd0")
    }
}
