import Foundation
import Testing
@testable import MCLCore

/// The normalizing getters and setters of the configuration use Java `isBlank()` (`Character.isWhitespace`: NBSP
/// and U+2007 are not blank, U+3000 is) and Java `trim()` (up to U+0020), and `MenuState.fromString` upper-cases
/// with `Locale.ROOT` (`ı` → `I`, `ſ` → `S`). Values measured on the JVM (v1.1.1, JDK 21) — found by the Java parity suite
/// (`cfg.APPLY` pool configuration `c/20`, `cfg.TABS` state spellings).
@Suite struct ConfigJavaBlankTests {

    static func decoded(_ json: String) throws -> AppConfig {
        try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
    }

    @Test func nonBreakingSpacesAreNotBlank() throws {
        let config = try Self.decoded("""
            {"radioMode":"\\u00A0","scoreReportingUrl":"\\u2007","map":{"scheme":"\\u3000"},
             "voiceKeyer":{"lettersPath":"\\u00A0"},"digital":{"fldigiHost":" \\u00A0x "},
             "clubLog":{"enabled":true,"email":"\\u00A0","appPassword":"\\u2007","apiKey":"\\u00A0"}}
            """)
        #expect(config.radioMode == "\u{00A0}")
        #expect(config.scoreReportingUrl == "\u{2007}")
        #expect(config.map.scheme == "green")
        #expect(config.voiceKeyer.lettersPath == "\u{00A0}")
        #expect(config.digital.fldigiHost == "\u{00A0}x")
        #expect(config.clubLog.configured())
    }

    @Test func asciiWhitespaceIsBlank() throws {
        let config = try Self.decoded(#"{"radioMode":" \t","map":{"scheme":"\n"},"digital":{"fldigiHost":"\t"}}"#)
        #expect(config.radioMode == "SO1V")
        #expect(config.map.scheme == "green")
        #expect(config.digital.fldigiHost == "127.0.0.1")
    }

    @Test func menuStateReadsLikeJava() throws {
        let spellings: [String] = [
            "hidden\u{00A0}", "\u{3000}disable", "h\u{0131}dden", "d\u{0131}\u{017F}able", "H\u{0130}DDEN",
            "\thidden\n", " Disable ",
        ]
        let states: [MenuState] = try spellings.map { spelling in
            let data: Data = try JSONEncoder().encode([spelling])
            return try #require(try JSONDecoder().decode([MenuState].self, from: data).first)
        }
        #expect(states == [.enable, .enable, .hidden, .disable, .enable, .hidden, .disable])
    }
}
