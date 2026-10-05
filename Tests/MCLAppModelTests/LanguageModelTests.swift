import Foundation
import MCLCore
import Observation
import Testing
@testable import MCLAppModel

/// `LanguageModel` (checklist rows 45; 46): the switch replaces the translator, observers are told, and the
/// decimal separator is the model's.
@MainActor @Suite struct LanguageModelTests {

    private static func model(_ dir: TempDir, decimalSeparator: String = ".") async -> LanguageModel {
        let languageDir: URL = dir.child("language")
        let translator: Translator = await LanguageModel.load(code: "cs", languageDir: languageDir)
        return LanguageModel(translator: translator, languageDir: languageDir, decimalSeparator: decimalSeparator)
    }

    @Test func loadUnpacksShippedLanguages() async throws {
        let dir = try TempDir()
        let languageDir: URL = dir.child("language")
        let translator: Translator = await LanguageModel.load(code: "en", languageDir: languageDir)
        #expect(FileManager.default.fileExists(atPath: languageDir.appendingPathComponent("lang_en.json").path))
        #expect(FileManager.default.fileExists(atPath: languageDir.appendingPathComponent("lang_de.json").path))
        #expect(translator.language == "en")
    }

    @Test func switchToEnglishTranslatesAndNotifiesObservers() async throws {
        let dir = try TempDir()
        let model: LanguageModel = await Self.model(dir)
        #expect(model.tr("Zatím nedostupné") == "Zatím nedostupné")
        final class Flag: @unchecked Sendable { var changed = false }
        let flag = Flag()
        withObservationTracking {
            _ = model.translator
        } onChange: {
            flag.changed = true
        }
        await model.switchTo("en")
        #expect(flag.changed)
        #expect(model.code == "en")
        #expect(model.tr("Zatím nedostupné") == "Not available yet")
    }

    @Test func unknownLanguageFallsBackToCzech() async throws {
        let dir = try TempDir()
        let model: LanguageModel = await Self.model(dir)
        await model.switchTo("en")
        await model.switchTo("xx")
        #expect(model.code == "cs")
        #expect(model.tr("Zatím nedostupné") == "Zatím nedostupné")
    }

    @Test func argumentsUseTheDecimalSeparator() async throws {
        let dir = try TempDir()
        let comma: LanguageModel = await Self.model(dir, decimalSeparator: ",")
        let dot: LanguageModel = await Self.model(dir, decimalSeparator: ".")
        #expect(comma.tr("%.1f kHz", .double(14025.5)) == "14025,5 kHz")
        #expect(dot.tr("%.1f kHz", .double(14025.5)) == "14025.5 kHz")
    }

    @Test func availableListsCzechAndTheDirectory() async throws {
        let dir = try TempDir()
        let model: LanguageModel = await Self.model(dir)
        let codes: [String] = await model.available().map(\.code)
        #expect(codes.first == "cs")
        #expect(codes.contains("en"))
        #expect(codes.contains("de"))
    }

    @Test func statusTextFollowsTheLanguage() async throws {
        let dir = try TempDir()
        let model: LanguageModel = await Self.model(dir)
        let status = StatusModel(language: model)
        status.show("Spuštěn závod %s", .string("CQ WW"))
        #expect(status.message == "Spuštěn závod CQ WW")
        await model.switchTo("en")
        #expect(status.message == "Contest CQ WW started")
        status.showJoined([.verbatim("Menu: "), ContestMessage("vadný menu.json")], separator: "")
        #expect(status.message.hasPrefix("Menu: "))
        status.clear()
        #expect(status.message == "")
    }
}
