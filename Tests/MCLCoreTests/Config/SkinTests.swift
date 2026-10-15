import Foundation
@testable import MCLCore
import Testing

/// Settings › Colors, Fonts and Skins (N1MM Configurer Colors / Fonts / Skins): the colour text, the stored
/// overrides, the skin file and what a skin does to the draft.
@Suite struct SkinTests {

    @Test func hexParsesAndFormats() {
        #expect(ColorHex.parse("#1e88e5") == 0x1E88E5)
        #expect(ColorHex.parse(" FF0000 ") == 0xFF0000)
        #expect(ColorHex.parse("#FFF") == nil)
        #expect(ColorHex.parse("#GG0000") == nil)
        #expect(ColorHex.parse("") == nil)
        #expect(ColorHex.format(0x00FF0A) == "#00FF0A")
        #expect(ColorHex.format(0) == "#000000")
    }

    @Test func sanitizedKeepsKnownSlotsWithValidColours() {
        let out = ColorHex.sanitized([
            ColorSlot.callMult.rawValue: "ff0000", ColorSlot.entryFocus.rawValue: "#zzzzzz", "mcl.unknown": "#000000",
        ])
        #expect(out == [ColorSlot.callMult.rawValue: "#FF0000"])
    }

    static func draft(_ config: AppConfig = AppConfig()) -> ConfigurerDraft {
        ConfigurerDraft(config: config, bandSegments: [], digi: DigiFreqFile.Table(channels: []),
                        defaultContestDataDir: "/data/contest-data")
    }

    @Test func draftAppliesSanitizedOverridesAndFonts() {
        var config = AppConfig()
        var draft = Self.draft(config)
        draft.colorOverrides = [ColorSlot.spotGood.rawValue: "0000ff", "bad": "#000000"]
        draft.fontFamily = "  Menlo "
        draft.fixedFontFamily = "Courier"
        draft.spotTooltips = false
        config = draft.applied(to: config, now: JavaInstant.ofEpochSecond(1_790_000_000, 0)!)
        #expect(config.colorOverrides == [ColorSlot.spotGood.rawValue: "#0000FF"])
        #expect(config.fontFamily == "Menlo")
        #expect(config.fixedFontFamily == "Courier")
        #expect(config.spotTooltips == false)
    }

    @Test func configDefaultsAndLenientDecode() throws {
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(#"{"colorOverrides":7}"#.utf8))
        #expect(config.colorOverrides.isEmpty)
        #expect(config.fontFamily.isEmpty)
        #expect(config.spotTooltips)
    }

    @Test func skinFileRoundTrips() throws {
        let skin = Skin(name: "Contest", themeMode: "DARK", themeAccent: "BLUE",
                        colors: [ColorSlot.dupe.rawValue: "#808080"], fontFamily: "Helvetica",
                        fixedFontFamily: "Menlo")
        #expect(try Skin.decode(skin.encoded()) == skin)
    }

    @Test func skinDecodeIsLenient() throws {
        let skin = try Skin.decode(Data(##"{"name":"X","colors":{"mcl.callNew":"00ff00","nope":"#000000"}}"##.utf8))
        #expect(skin.name == "X")
        #expect(skin.themeMode == "SYSTEM")
        #expect(skin.colors == [ColorSlot.callNew.rawValue: "#00FF00"])
        #expect(throws: (any Error).self) { try Skin.decode(Data("[]".utf8)) }
    }

    @Test func skinAppliesToDraftAndBack() {
        var draft = Self.draft()
        draft.themeMode = "LIGHT"
        draft.colorOverrides = [ColorSlot.callMult.rawValue: "#123456"]
        let night: Skin = Skin.builtIns[2]
        night.apply(to: &draft)
        #expect(draft.themeMode == "DARK")
        #expect(draft.themeAccent == "ORANGE")
        #expect(draft.colorOverrides == night.colors)
        let back = Skin.from(draft, name: "mine")
        #expect(back.name == "mine")
        #expect(back.colors == night.colors)
        // The default skin clears every override.
        Skin.builtIns[0].apply(to: &draft)
        #expect(draft.colorOverrides.isEmpty)
        #expect(draft.themeMode == "SYSTEM")
    }

    @Test func builtInSkinsUseKnownSlotsAndValidColours() {
        for skin in Skin.builtIns {
            #expect(ColorHex.sanitized(skin.colors) == skin.colors, "\(skin.name)")
        }
    }

    /// Every label and built-in skin name is translated in the shipped English and German.
    @Test(arguments: ["en", "de"]) func labelsAreTranslated(_ code: String) throws {
        let bytes: [UInt8] = try #require(LanguageCatalog.bundledBytes(code))
        let translations = LanguageCatalog.Translations(try #require(LanguageJsonReader.read(bytes)))
        let keys: [String] = ColorSlot.allCases.map(\.labelKey) + Skin.builtIns.map(\.name)
        #expect(keys.filter { translations[$0] == nil }.isEmpty)
    }
}
