import Testing
@testable import MCLCore

/// The public facade of the Kotlin text functions for the app layer forwards to the measured `KotlinText`.
@Suite struct KotlinStringsTests {

    @Test func blankAndTrimAreKotlins() {
        #expect(KotlinStrings.isBlank("\u{00A0} \u{2007}"))
        #expect(!KotlinStrings.isBlank("\u{0001}"))
        #expect(KotlinStrings.trim("\u{00A0} Deník \u{202F}") == "Deník")
        #expect(KotlinStrings.trim("\u{0001}x") == "\u{0001}x")
        for text in ["", " ", "\u{00A0}", "a", " a ", "\u{0001}", "\u{3000}b"] {
            #expect(KotlinStrings.isBlank(text) == KotlinText.isBlank(text))
            #expect(KotlinStrings.trim(text) == KotlinText.trim(text))
        }
    }

    @Test func nilIfBlank() {
        #expect(KotlinStrings.nilIfBlank(nil) == nil)
        #expect(KotlinStrings.nilIfBlank("\u{00A0}") == nil)
        #expect(KotlinStrings.nilIfBlank(" x ") == " x ")
    }

    @Test func uppercaseIsJavas() {
        #expect(KotlinStrings.uppercase("ok1xoe/p") == "OK1XOE/P")
        #expect(KotlinStrings.uppercase("straße") == "STRASSE")
        #expect(KotlinStrings.uppercase("ÿµ") == "\u{0178}\u{039C}")
        for text in ["", "dl1abc", "ß", "ﬃ", "č", "ok\u{00A0}1"] {
            #expect(KotlinStrings.uppercase(text) == JavaText.toUpperCase(text))
        }
    }
}
