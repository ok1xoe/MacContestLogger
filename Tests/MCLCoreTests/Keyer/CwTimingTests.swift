import Testing
@testable import MCLCore

/// Port of `keyer/CwTimingTest` (5) + `CWT.*`, `CWM.plainText` measurements (maintainer-only probe) and
/// `KDIT.*`, `KCWT.*`, `KCWM.*` (maintainer-only probe).
@Suite struct CwTimingTests {

    private static func text(_ s: String) -> CwMessage {
        CwMessage(parts: [.text(s)])
    }

    // MARK: - Port of CwTimingTest

    @Test func parisIsFortyThreeDitsWithoutTrailingSpace() {
        // PARIS = 50 dots including the word space (7); without it 43. At 12 WPM a dot is 100 ms.
        #expect(CwTiming.estimateMillis(Self.text("PARIS"), wpm: 12) == 4_300)
    }

    @Test func wordSpaceIsSevenDits() {
        // E (1) + word space (7) + E (1) = 9 dots
        #expect(CwTiming.estimateMillis(Self.text("E E"), wpm: 12) == 900)
    }

    @Test func fasterIsShorter() {
        #expect(CwTiming.estimateMillis(Self.text("CQ TEST"), wpm: 30) < CwTiming.estimateMillis(Self.text("CQ TEST"), wpm: 20))
    }

    @Test func prosignHasNoLetterGap() {
        // A (5) + intra-character space (1) + R (7) = 13 dots
        #expect(CwTiming.estimateMillis(CwMessage(parts: [.prosign("AR")]), wpm: 12) == 1_300)
    }

    @Test func inlineSpeedChangeCounts() {
        let m = CwMessage(parts: [.speed(12), .text("E")])
        #expect(CwTiming.estimateMillis(m, wpm: 12) == 50) // E at 24 WPM
    }

    // MARK: - Measurements

    /// `CWT.dits` (research): `Character.toUpperCase(char)` — `a` as `A`, `ı` as `I`, `İ` and `é` zero.
    @Test func measuredDits() {
        let cases: [(UInt16, Int)] = [
            (0x41, 5), (0x45, 1), (0x50, 11), (0x52, 7), (0x49, 3), (0x53, 5), (0x30, 19), (0x31, 17), (0x32, 15),
            (0x39, 17), (0x2F, 13), (0x3F, 15), (0x2E, 17), (0x2C, 19), (0x2D, 15), (0x61, 5), (0x20, 0), (0x7E, 0),
            (0x2A, 0), (0x00E9, 0), (0x0130, 0), (0x0131, 3),
        ]
        for (unit, dits) in cases {
            #expect(CwTiming.dits(unit) == dits, "\(unit)")
        }
    }

    /// `KDIT.unit`: all 65,536 units — 69 are non-zero (ASCII + `ı` + `ſ`).
    @Test func measuredDitsOverWholeBmp() {
        var rows: [String] = []
        for unit in 0...0xFFFF {
            let d = CwTiming.dits(UInt16(unit))
            if d != 0 {
                let hex = String(unit, radix: 16).uppercased()
                rows.append(ProbeText.row("KDIT.unit", [String(repeating: "0", count: 4 - hex.count) + hex, String(d)]))
            }
        }
        #expect(rows.count == 69)
        #expect(ProbeText.digest(rows) == "a34d609befb358a97a839b92c132af0379226f467e70b14fae3a7b7d8d698983")
    }

    private static func estimateRows(_ id: String, _ cases: [([CwMessage.Part], Int)]) -> [String] {
        cases.map { parts, wpm in
            let m = CwMessage(parts: parts)
            let ms = CwTiming.estimateMillis(m, wpm: wpm)
            return ProbeText.row(id, [ProbeText.esc(KeyerProbe.parts(m)), String(wpm), String(ms)])
        }
    }

    /// `CWT.estimate` (research): a leading space = 4 dots, `PARIS ` = 4,700, a prosign anywhere, `Speed(-30)`
    /// and a speed ≤ 5 → 5 WPM, `Math.round` rounding.
    @Test func measuredEstimates() {
        let cases: [([CwMessage.Part], Int)] = [
            ([.text("PARIS")], 12), ([.text("PARIS ")], 12), ([.text(" ")], 12), ([.text("  E")], 12),
            ([.prosign("AR"), .text("K")], 20), ([.text("K"), .prosign("AR")], 20), ([.speed(-30), .text("E")], 20),
            ([.text("E")], 0), ([.text("E")], -10), ([.text("EEE")], 7), ([.text("E")], 7),
            ([.text("CQ TEST OK1XOE")], 33), ([.prosign("ARX")], 25), ([.text("T")], 13), ([.text("TT")], 13),
        ]
        let rows = Self.estimateRows("CWT.estimate", cases)
        #expect(ProbeText.digest(rows) == "c4a902f0cb46427d6288fe8e12e6696e6b1ae70050b6c35a21531f93fa4f6680")
        #expect(rows[6] == "CWT.estimate\t[S-30,T'E']\t20\t240")
    }

    /// `KCWT.estimate`: non-ASCII in the text (`É` = 0 dots, but the space after the character yes), an empty and a three-character
    /// prosign, Java `int` overflow of the speed (`MAX + 1` → negative → 5 WPM), `wpm = MAX` → 0 ms.
    @Test func measuredEstimatesEdge() {
        let max = Int(Int32.max)
        let cases: [([CwMessage.Part], Int)] = [
            ([.text("\u{00C9}E")], 12), ([.text("\u{0131}")], 12), ([.text("e e")], 12), ([.prosign("")], 12),
            ([.prosign("SOS")], 12), ([.prosign("A")], 12), ([.text("A"), .prosign("AR")], 12),
            ([.speed(max), .speed(1), .text("E")], 20), ([.speed(max), .text("E")], 20), ([.text("E")], max),
            ([.text("E")], 7), ([.text("PARIS PARIS PARIS")], 13), ([.text("\t")], 12), ([.text(" "), .text("E")], 12),
            ([.speed(4), .text("EE"), .speed(-8), .text("EE")], 11),
        ]
        let rows = Self.estimateRows("KCWT.estimate", cases)
        #expect(ProbeText.digest(rows) == "b73228c3e1dace80906608176aead0490222451bc3274acc24059681c7b61c84")
    }

    /// `CWM.plainText` (research) + `KCWM.plainText`: a prosign padded with a space only after a non-space, Java
    /// `trim()` (NBSP stays, U+0001 and tab gone only at the edges), only U+0020 spaces are merged;
    /// empty text and a prosign both mean "non-empty message".
    @Test func measuredPlainText() {
        let research = CwMessage(parts: [.prosign("BT"), .text("TU"), .prosign("AR"), .text("  X  "), .prosign("SK")])
        #expect(research.plainText() == "BT TU AR X SK")
        #expect(!research.isEmpty)

        let cases: [[CwMessage.Part]] = [
            [], [.speed(2)], [.text("")], [.prosign("")], [.text("A"), .prosign("AR")],
            [.text("A "), .prosign("AR"), .text(" B")], [.prosign("SK"), .prosign("AR")],
            [.text("\u{00A0}A\u{00A0} \u{0001}"), .prosign("BT"), .text("\tX\t")],
            [.text("A\u{00A0}"), .prosign("BT")], [.text("  A    B  ")],
        ]
        let rows: [String] = cases.map { parts in
            let m = CwMessage(parts: parts)
            return ProbeText.row("KCWM.plainText", [ProbeText.esc(KeyerProbe.parts(m)), ProbeText.esc(m.plainText()),
                                                      String(m.isEmpty)])
        }
        #expect(ProbeText.digest(rows) == "d4f596c4eced2c3c64a3b1083cf45de9d6c00d444760bae5ea84a34d2dd3e441")
        #expect(rows[7] == "KCWM.plainText\t[T'\\u00A0A\\u00A0 \\u0001',PBT,T'\\tX\\t']\t\\u00A0A\\u00A0 \\u0001 BT \\tX\tfalse")
    }
}
