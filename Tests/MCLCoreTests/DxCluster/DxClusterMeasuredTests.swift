import Foundation
import Testing
@testable import MCLCore

/// Rows measured on Java v1.1.1 (maintainer-only probe: `DSP|`, `WWV|`, `SELF.*`,
/// `SMP|`, `SKIM|`, `BEACON*`, `RBN`, `URLENC`). They supplement the ported tests
/// with edges that the Java tests do not assert.
@Suite struct DxClusterMeasuredTests {

    private static func spot(_ spotter: String, _ freqHz: Int, _ dxCall: String, _ comment: String) -> DxSpot {
        DxSpot(spotter: spotter, freqHz: freqHz, dxCall: dxCall, comment: comment)
    }

    @Test func spotLines() {
        let cases: [(String, DxSpot?)] = [
            ("DX de OK1XOE:  14025.05  DL1AAA  cq test 1234Z", Self.spot("OK1XOE", 14_025_050, "DL1AAA", "cq test")),
            ("DX de OK1XOE:  14025.0005  DL1AAA  cq", Self.spot("OK1XOE", 14_025_001, "DL1AAA", "cq")),
            ("DX de OK1XOE:  14025.0015  DL1AAA  cq", Self.spot("OK1XOE", 14_025_002, "DL1AAA", "cq")),
            ("DX de OK1XOE:  99999999999999999999999  DL1AAA  x", Self.spot("OK1XOE", Int.max, "DL1AAA", "x")),
            ("DX de OK1XOE: 14025 dl1aaa", Self.spot("OK1XOE", 14_025_000, "DL1AAA", "")),
            ("dx de OK1XOE: 14025 DL1AAA", nil),
            ("DX de SK3W-#:    7020.0  DL1AAA       CW 21 dB 25 WPM CQ      1234Z",
             Self.spot("SK3W-#", 7_020_000, "DL1AAA", "CW 21 dB 25 WPM CQ")),
            ("DX de OK1XOE:14025.0 DL1AAA", nil),
            ("DX de OK1XOE:  14025.0  DL1AAA  ends 12Z", Self.spot("OK1XOE", 14_025_000, "DL1AAA", "ends 12Z")),
            ("DX de OK1XOE:  14025.0  DL1AAA  ends 0012Z  ", Self.spot("OK1XOE", 14_025_000, "DL1AAA", "ends")),
            ("  14025.0  DL1AAA  1-Jan-2026 1234Z  cq  <OK1XOE>", Self.spot("OK1XOE", 14_025_000, "DL1AAA", "cq")),
            ("12:00:00  14025.0  DL1AAA  12-Jul-2026 1824Z   <OK1XOE>", Self.spot("OK1XOE", 14_025_000, "DL1AAA", "")),
            ("DX de OK1\u{00C9}:  14025.0  DL1AAA", nil),
        ]
        for (line, expected) in cases {
            #expect(DxSpotParser.parse(line) == expected, "\(line)")
        }
    }

    @Test func wwvLines() throws {
        let standard = try WwvMessage.parse("WWV de VE7CC <18Z> :   SFI=142, A=8, K=3, No Storms -> No Storms")
        #expect(standard == WwvMessage(spotter: "VE7CC", hourUtc: 18, sfi: 142, aIndex: 8, kIndex: 3,
                                       conditions: "No Storms -> No Storms"))
        let tight = try WwvMessage.parse("wwv DE ve7cc<1Z>:sfi=1,a=2,k=3")
        #expect(tight == WwvMessage(spotter: "VE7CC", hourUtc: 1, sfi: 1, aIndex: 2, kIndex: 3, conditions: ""))
        let bare = try WwvMessage.parse("WWV de VE7CC <18Z> : SFI=1, A=2, K=3")
        #expect(bare == WwvMessage(spotter: "VE7CC", hourUtc: 18, sfi: 1, aIndex: 2, kIndex: 3, conditions: ""))
        // `conditions` after the last K, `kIndex` from the first.
        let twoK = try WwvMessage.parse("WWV de VE7CC <18Z> : K=3, SFI=1, A=2 tail, K=4 more")
        #expect(twoK == WwvMessage(spotter: "VE7CC", hourUtc: 18, sfi: 1, aIndex: 2, kIndex: 3, conditions: "more"))
    }

    /// Decision 7: the Java `NumberFormatException` escapes in Swift too.
    @Test func wwvLongNumberThrowsLikeJava() {
        #expect(throws: JavaNumberFormatError(message: "For input string: \"99999999999\"")) {
            try WwvMessage.parse("WWV de VE7CC <18> : SFI=99999999999, A=1, K=2")
        }
    }

    @Test func selfSpotEdges() throws {
        #expect(throws: JavaNumberFormatError(message: "For input string: \"99999999999\"")) {
            try SelfSpot.detect(Self.spot("X-#", 1, "OK1XOE", "CW 99999999999 dB 25 WPM"), myCall: "ok1xoe ",
                                at: Date(timeIntervalSince1970: 0))
        }
        let neg = try SelfSpot.detect(Self.spot("X", 1, "OK1XOE", "-5dB 30wpm"), myCall: "OK1XOE",
                                      at: Date(timeIntervalSince1970: 0))
        #expect(neg == SelfSpot(spotter: "X", freqHz: 1, rbn: true, snrDb: -5, wpm: 30, at: Date(timeIntervalSince1970: 0)))
    }

    @Test func modeEdges() {
        let cases: [(String, String?)] = [
            ("FT8", "FT8"), ("ft8", "FT8"), ("SCW", nil), ("BPSK31", "PSK"), ("QPSK63", "PSK"), ("PSK", "PSK"),
            ("CW/SSB", "CW"), ("PHONE", "SSB"), ("USB", "SSB"), ("\u{00E9}CW", "CW"), ("CW\u{00E9}", "CW"),
            ("x_CW", nil), ("FT8x", nil),
        ]
        for (comment, expected) in cases {
            #expect(SpotModeParser.fromComment(comment) == expected, "\(comment)")
        }
    }

    @Test func skimmerCommentEdges() {
        let cases: [(String, Bool)] = [
            ("19 dB 28 WPM CQ", true), ("-5dB 30wpm", true), ("5 db 100 bps", true), ("19dB28WPM", false),
            ("123 dB 28 WPM", false),
        ]
        for (comment, expected) in cases {
            #expect(SkimmerSpot.isSkimmer(Self.spot("X", 1, "Y", comment)) == expected, "\(comment)")
        }
    }

    @Test func beaconFileEdges() {
        let lines: [String] = [
            "# c", "60", "OZ7IGY/B;144471,1;JO55WM;", "GB3VHF/B;144430.4;JO01DH;QRG with a .", "bad", "X;1e3;;",
            "Y;144471.0001;;", "Z;-5;;", "\u{00FC}b;1;;",
        ]
        let b = BeaconFile.parse(lines.joined(separator: "\n"))
        let beacons: [DxSpot] = [
            Self.spot("BEACONS", 144_471_100, "OZ7IGY/B", "JO55WM"),
            Self.spot("BEACONS", 144_430_400, "GB3VHF/B", "JO01DH QRG with a ."),
            Self.spot("BEACONS", 1_000_000, "X", ""),
            Self.spot("BEACONS", -5000, "Z", ""),
            Self.spot("BEACONS", 1000, "\u{00DC}B", ""),
        ]
        #expect(b == BeaconFile.Beacons(hours: 60, beacons: beacons, skipped: ["bad", "Y;144471.0001;;"]))

        let noHours = BeaconFile.parse("OZ7IGY/B;144471;JO55WM;")
        #expect(noHours == BeaconFile.Beacons(hours: 48, beacons: [Self.spot("BEACONS", 144_471_000, "OZ7IGY/B", "JO55WM")],
                                              skipped: []))
        let longHours = BeaconFile.parse("99999999999\nA;1;;")
        #expect(longHours == BeaconFile.Beacons(hours: 48, beacons: [Self.spot("BEACONS", 1000, "A", "")],
                                                skipped: ["99999999999"]))
    }

    @Test func urlEncoding() {
        #expect(RbnLink.spotsOfStation(" ok1xoe/p *~ \u{010D}")
                == "https://www.reversebeacon.net/dxsd1/dxsd1.php?f=0&c=OK1XOE%2FP+*%7E+%C4%8C&t=dx")
        #expect(JavaUrlEncoder.encode("a b*~-_.!'()+&=/?\u{010D}\u{1F600}")
                == "a+b*%7E-_.%21%27%28%29%2B%26%3D%2F%3F%C4%8D%F0%9F%98%80")
    }

    /// Edges of `new BigDecimal(s).movePointRight(3).longValueExact()` from JDK 21 (read from the source).
    @Test func bigDecimalEdges() {
        let cases: [(String, Int64?)] = [
            ("144471.1", 144_471_100), (".5", 500), ("5.", 5000), ("+5", 5000), ("-0.001", -1), ("1E3", 1_000_000),
            ("1e-3", 1), ("1e-4", nil), ("0e99999", 0), ("0e9999999999", nil), ("1e00000000003", 1_000_000),
            ("9223372036854775.807", Int64.max), ("-9223372036854775.808", Int64.min),
            ("9223372036854775.808", nil), ("", nil), (".", nil), ("1..2", nil), ("1e", nil), ("1e+", nil),
            ("e5", nil), ("NaN", nil), ("1_000", nil), ("\u{0661}\u{0662}", 12_000), ("1e\u{0662}", 100_000),
            ("0.0001000", nil), ("0.1000", 100), ("1e2147483647", nil), ("1e-2147483648", nil),
        ]
        for (text, expected) in cases {
            let value = JavaBigDecimal(text)?.movePointRight(3)?.longValueExact()
            #expect(value == expected, "\(text)")
        }
    }
}
