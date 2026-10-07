import Foundation
import Testing
@testable import MCLCore

/// The core of Kotlin `ui/I18n` (`use`, `available`, `tr`) carried over into `Translator` and
/// the divergences for non-string values and of a format crash (a deliberate divergence from Java v1.1.1).
@Suite struct TranslatorTests {

    private static func w(_ dir: String, _ name: String, _ json: String) throws {
        try LanguageCatalogTests.write(dir, name, json)
    }

    @Test func withoutTranslationCzechStays() {
        let tr: Translator = Translator.use(nil, in: nil as String?)
        #expect(tr == .source)
        #expect(tr.translate("Skóre") == "Skóre")
        #expect(tr.translate("Neznámý text") == "Neznámý text")
    }

    @Test func useLoadsTheFileOfTheWantedCode() throws {
        try LanguageCatalogTests.withTemporaryDirectory { dir in
            try Self.w(dir, "lang_en.json", "{\"_name\":\"English\",\"Skóre\":\"Score\",\"Bod\":1}")
            try Self.w(dir, "lang_cs.json", "{\"Skóre\":\"nikdy\"}")
            let en: Translator = Translator.use("en", in: dir)
            #expect(en.language == "en")
            #expect(en.translate("Skóre") == "Score")
            #expect(en.translate("Chybí") == "Chybí")
            // Decision 9: a non-string is omitted (Java: `ClassCastException` in `tr()`), key = original.
            #expect(en.translate("Bod") == "Bod")
            // `cs` is always the source, even when `lang_cs.json` is present; an unknown and a blank code (Kotlin `isBlank` and NBSP) = Czech.
            #expect(Translator.use("cs", in: dir) == .source)
            #expect(Translator.use("xx", in: dir) == .source)
            #expect(Translator.use(" \u{a0}", in: dir) == .source)
            #expect(Translator.use("EN", in: dir) == .source)
            let available: [LanguageCatalog.Language] = en.available(in: dir)
            #expect(available.map(\.code) == ["cs", "cs", "en"])
            #expect(available[0] == LanguageCatalog.Language(code: "cs", label: "Čeština", file: nil))
        }
    }

    @Test func nonStringNameFallsBackToCode() throws {
        // Java: `list` throws `ClassCastException` (the Settings and the start crash); Swift label = the code in uppercase.
        try LanguageCatalogTests.withTemporaryDirectory { dir in
            try Self.w(dir, "lang_xy.json", "{\"_name\":5,\"Skóre\":\"Wynik\"}")
            #expect(LanguageCatalog.list(dir) == [LanguageCatalog.Language(
                code: "xy", label: "XY", file: dir + "/lang_xy.json")])
        }
    }

    @Test func keysCompareByUtf16Units() throws {
        // NFC and NFD `é` are two keys in Java; the translation of an NFD key is not used for NFC text in the code.
        try LanguageCatalogTests.withTemporaryDirectory { dir in
            try Self.w(dir, "lang_en.json", "{\"Kan\u{e1}l\":\"Channel\",\"Mo\u{301}d\":\"Mode\"}")
            let en: Translator = Translator.use("en", in: dir)
            #expect(en.translate("Kan\u{e1}l") == "Channel")
            #expect(en.translate("M\u{f3}d") == "M\u{f3}d")
            #expect(en.translations.count == 2)
        }
    }

    @Test func formatsTranslationLikeKotlin() {
        let en = Translator(language: "en", translations: LanguageCatalog.Translations([
            JavaStringKey("Frekvence %.1f kHz označena v bandmapě"): "Frequency %.1f kHz marked in the bandmap",
            JavaStringKey("%s z %s"): "%2$s: %1$s",
            JavaStringKey("Vadný %s"): "Broken %d",
            JavaStringKey("Chybí %s"): "Missing %s %s",
            JavaStringKey("Procenta %s"): "100% sure %s",
        ]))
        #expect(en.translate("Frekvence %.1f kHz označena v bandmapě", [3525.25]) ==
            "Frequency 3525.3 kHz marked in the bandmap")
        #expect(en.translate("Frekvence %.1f kHz označena v bandmapě", [3525.25], decimalSeparator: ",") ==
            "Frequency 3525,3 kHz marked in the bandmap")
        #expect(en.translate("%s z %s", ["a", "b"]) == "b: a")
        #expect(en.translate("Nepřeloženo %s", [.string(nil)]) == "Nepřeloženo null")
        // Java: an exception → a UI crash; Swift: the formatted Czech original.
        #expect(en.translate("Vadný %s", ["x"]) == "Vadný x")
        #expect(en.translate("Chybí %s", ["x"]) == "Chybí x")
        #expect(en.translate("Procenta %s", ["x"]) == "Procenta x")
        // Not even the original works → the original without formatting.
        #expect(Translator.source.translate("%d bodů", ["x"]) == "%d bodů")
        #expect(Translator.format("%d bodů", ["x"]) == nil)
    }

    /// The labels of the built-in `menu.json`.
    private static func menuLabels() throws -> Set<String> {
        var menu = ""
        try LanguageCatalogTests.withTemporaryDirectory { dir in
            let file: URL = try #require(try MenuConfigStore.writeBuiltIn(dataDir: URL(fileURLWithPath: dir),
                overwrite: true))
            menu = String(decoding: try Data(contentsOf: file), as: UTF8.self)
        }
        let regex = try NSRegularExpression(pattern: "\"label\"\\s*:\\s*\"([^\"]+)\"")
        let range = NSRange(menu.startIndex..., in: menu)
        return Set(regex.matches(in: menu, range: range).compactMap { match in
            Range(match.range(at: 1), in: menu).map { String(menu[$0]) }
        })
    }

    private static func bundled(_ code: String) throws -> LanguageCatalog.Translations {
        let bytes: [UInt8] = try #require(LanguageCatalog.bundledBytes(code))
        return LanguageCatalog.Translations(try #require(LanguageJsonReader.read(bytes)))
    }

    /// Kotlin `I18nTest.menuFullyTranslated` (both resources are in the core): every label
    /// of the built-in `menu.json` with Czech diacritics has a translation in the shipped English — and, in the
    /// Swift version, in the shipped German too.
    @Test(arguments: ["en", "de"]) func menuFullyTranslated(_ code: String) throws {
        let diacritics: Set<Character> = Set("áčďéěíňóřšťúůýžÁČĎÉĚÍŇÓŘŠŤÚŮÝŽ")
        let czech: [String] = try Self.menuLabels().filter { $0.contains(where: diacritics.contains) }.sorted()
        let translations = try Self.bundled(code)
        #expect(!czech.isEmpty)
        #expect(czech.filter { translations[$0] == nil }.isEmpty, "translation missing")
    }

    /// The 20 `menu.json` labels Java v1.1.1 left out of its language files (already English, so English
    /// is the key itself) are in the shipped English and German, so every menu label is a key of both.
    @Test(arguments: ["en", "de"]) func everyMenuLabelIsAKey(_ code: String) throws {
        let translations = try Self.bundled(code)
        let missing: [String] = try Self.menuLabels().filter { translations[$0] == nil }.sorted()
        #expect(missing.isEmpty, "missing: \(missing)")
        #expect(try Self.bundled("en")["Export Cabrillo…"] == "Export Cabrillo…")
        #expect(try Self.bundled("de")["Function Keys"] == "Funktionstasten")
    }

    @Test func bundledEnglishIsComplete() throws {
        let bytes: [UInt8] = try #require(LanguageCatalog.bundledBytes("en"))
        let map = LanguageCatalog.Translations(try #require(LanguageJsonReader.read(bytes)))
        // Java v1.1.1 ships 1,006 entries; the Swift file adds 61 keys of the Swift UI and the 20
        // `menu.json` labels Java leaves out and 1 key of the post-port QO-100
        // tooltip line (a deliberate divergence from Java v1.1.1) and 2 accessibility labels of the SCP and N+1 rows (section 73) and
        // 2 Settings labels of the SCP and N+1 switches (section 73) and
        // 12 keys of the manual callbook lookups and 1 key of the missing-frequency spot status and
        // 1 accessibility label of the DX Cluster window parallel switch and 1 Settings Apply button and
        // 16 keys of the Club Log DXCC update and 16 keys of the DX cluster spot filter and
        // 80 keys of the window plugins and 19 keys of the new menu bar (File, Edit, Tools, Help and their items) and
        // 3 keys of File → Open recent and
        // 20 keys of copying a contest to another database and rescoring the last N hours.
        #expect(map.count == 1_267)
        let german = try Self.bundled("de")
        #expect(german.count == 1_267)
        #expect(map["_name"] == "English")
        #expect(map["Čeština"] != nil)
        #expect(LanguageCatalog.bundledBytes("xx") == nil)
    }
}
