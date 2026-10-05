import Testing
@testable import MCLCore

/// `HardwareSummary` (`HW:107-118`), `LanguageChoice` (`MT:127-160`) and `SettingsTexts` (`DX:164-165`).
@Suite struct SettingsHelpersTests {

    @Test func hardwareLine() {
        #expect(HardwareSummary.line(
            mode: .connectRunning, host: "localhost", port: "4532", baud: 9600, parity: .none, dataBits: 8,
            stopBits: 1) == "localhost:4532")
        #expect(HardwareSummary.line(
            mode: .launchDaemon, host: "localhost", port: "4532", baud: 38400, parity: .even, dataBits: 7,
            stopBits: 2) == "38400,Even,7,2")
        // The port text is shown as typed, not parsed.
        #expect(HardwareSummary.line(
            mode: .connectRunning, host: "", port: " x", baud: 0, parity: .none, dataBits: 0, stopBits: 0) == ": x")
    }

    @Test func hardwareCellIfBlank() {
        #expect(HardwareSummary.cell("") == "None")
        #expect(HardwareSummary.cell(" \t") == "None")
        #expect(HardwareSummary.cell("\u{00A0}") == "None") // Kotlin isBlank: U+00A0 is blank
        #expect(HardwareSummary.cell("/dev/cu.usbserial") == "/dev/cu.usbserial")
        #expect(HardwareSummary.cell(" 1 — Hamlib Dummy") == " 1 — Hamlib Dummy")
    }

    private static let languages: [LanguageCatalog.Language] = [
        LanguageCatalog.Language(code: "cs", label: "Čeština", file: nil),
        LanguageCatalog.Language(code: "en", label: "English", file: "/x/lang_en.json"),
    ]

    @Test func languageLabels() {
        #expect(LanguageChoice.label(Self.languages[1]) == "English  (en)")
        #expect(LanguageChoice.selectedLabel(code: "en", in: Self.languages) == "English  (en)")
        #expect(LanguageChoice.selectedLabel(code: "pl", in: Self.languages) == "pl")
        #expect(LanguageChoice.code(forLabel: "Čeština  (cs)", in: Self.languages) == "cs")
        #expect(LanguageChoice.code(forLabel: "Čeština (cs)", in: Self.languages) == nil)
    }

    private static func bundled(_ code: String) throws -> Translator {
        let bytes: [UInt8] = try #require(LanguageCatalog.bundledBytes(code))
        let translations = LanguageCatalog.Translations(try #require(LanguageJsonReader.read(bytes)))
        return Translator(language: code, translations: translations)
    }

    /// `title.contains("spot")` over the translated title — in Czech and German the spotter editor
    /// gets the spotter hint; in English ("Spotter blacklist", capital S) it gets the callsign hint (Kotlin defect).
    @Test func blacklistHintFollowsTheTranslatedTitle() throws {
        let spotters = "Blacklist spotterů"
        let calls = "Blacklist volaček"
        #expect(SettingsTexts.blacklistHintKey(translatedTitle: spotters) == SettingsTexts.blacklistSpottersHint)
        #expect(SettingsTexts.blacklistHintKey(translatedTitle: calls) == SettingsTexts.blacklistCallsHint)
        let en: Translator = try Self.bundled("en")
        #expect(en.translate(spotters) == "Spotter blacklist")
        #expect(SettingsTexts.blacklistHintKey(translatedTitle: en.translate(spotters)) == SettingsTexts.blacklistCallsHint)
        let de: Translator = try Self.bundled("de")
        #expect(SettingsTexts.blacklistHintKey(translatedTitle: de.translate(spotters)) == SettingsTexts.blacklistCallsHint)
        #expect(SettingsTexts.blacklistHintKey(translatedTitle: de.translate(calls)) == SettingsTexts.blacklistCallsHint)
    }

    /// Every translated key exists in the shipped English and German.
    @Test(arguments: ["en", "de"]) func translatedKeysAreShipped(_ code: String) throws {
        let t: Translator = try Self.bundled(code)
        let keys: [String] = [
            SettingsTexts.saved, SettingsTexts.saveFailed, SettingsTexts.bandDataSaveFailed,
            SettingsTexts.catReconfigured, SettingsTexts.profileLoaded, SettingsTexts.capturePrompt,
            SettingsTexts.keyNotAllowed, SettingsTexts.blacklistSpottersHint, SettingsTexts.blacklistCallsHint,
        ]
        #expect(SettingsTexts.profileFailurePrefix == "Profil: ")
        for key in keys {
            #expect(t.translate(key) != key, "\(code): \(key)")
        }
    }
}
