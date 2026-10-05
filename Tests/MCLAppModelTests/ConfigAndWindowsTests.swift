import Foundation
import MCLCore
import Testing
@testable import MCLAppModel

/// `ConfigWriter`: the bytes of `ConfigStore.save`, in order, with errors reported.
@Suite struct ConfigWriterTests {

    @Test func bytesMatchConfigStoreSave() async throws {
        let dir = try TempDir()
        let config: AppConfig = ConfigStore(file: Fixtures.configV111).load()
        let viaStore: URL = dir.child("store/config.json")
        ConfigStore(file: viaStore).save(config)
        let viaWriter: URL = dir.child("writer/config.json")
        let writer = ConfigWriter(file: viaWriter)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            writer.enqueue(config) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
        #expect(try Data(contentsOf: viaWriter) == Data(contentsOf: viaStore))
    }

    @Test func snapshotsAreWrittenInOrder() async throws {
        let dir = try TempDir()
        let file: URL = dir.child("config.json")
        let writer = ConfigWriter(file: file)
        for index in 0..<20 {
            var config = AppConfig()
            config.lastDatabase = "db-\(index)"
            writer.enqueue(config) { _ in }
        }
        await writer.flush()
        #expect(ConfigStore(file: file).load().lastDatabase == "db-19")
    }
}

/// `WindowsModel` over `config.openWindows`.
@MainActor @Suite struct WindowsModelTests {

    private static func model(_ open: [String], dir: TempDir) -> (WindowsModel, ConfigModel) {
        var config = AppConfig()
        config.openWindows = open
        let language = LanguageModel(translator: .source, languageDir: dir.child("language"))
        let file: URL = dir.child("config.json")
        let model = ConfigModel(config: config, store: ConfigStore(file: file), writer: ConfigWriter(file: file),
                                status: StatusModel(language: language))
        return (WindowsModel(config: model), model)
    }

    @Test func otherIdsAreKept() async throws {
        let dir = try TempDir()
        let (windows, config) = Self.model(["bandmap", "mult:dxcc", "future-window", "chat"], dir: dir)
        #expect(!windows.isOpen("log"))
        windows.setOpen("log", true)
        #expect(windows.isOpen("log"))
        #expect(config.config.openWindows == ["log", "bandmap", "chat", "mult:dxcc", "future-window"])
        await config.flush()
        let saved: AppConfig = ConfigStore(file: dir.child("config.json")).load()
        #expect(saved.openWindows == ["log", "bandmap", "chat", "mult:dxcc", "future-window"])
        windows.setOpen("log", false)
        #expect(config.config.openWindows == ["bandmap", "chat", "mult:dxcc", "future-window"])
    }

    @Test func unchangedSetIsNotSaved() async throws {
        let dir = try TempDir()
        let (windows, config) = Self.model(["log"], dir: dir)
        windows.setOpen("log", true)
        await config.flush()
        #expect(!FileManager.default.fileExists(atPath: dir.child("config.json").path))
    }

    @Test func defaultOpensTheLog() throws {
        let dir = try TempDir()
        let language = LanguageModel(translator: .source, languageDir: dir.child("language"))
        let file: URL = dir.child("config.json")
        let config = ConfigModel(config: AppConfig(), store: ConfigStore(file: file), writer: ConfigWriter(file: file),
                                 status: StatusModel(language: language))
        #expect(WindowsModel(config: config).isOpen("log"))
    }

    /// The windows open with their Kotlin ids; `profiles` is never saved (Kotlin `showProfiles` starts `false`),
    /// `defeditor` is (`showDefinitionEditor = "defeditor" in openOnStart`).
    @Test func editorAndProfilesWindowsAreImplemented() async throws {
        #expect(WindowsModel.implemented == [
            "log", "defeditor", "profiles", "catLog", "rotator", "cwkeyboard", "cwreader", "digitalinterface",
            "waterfall", "dxCluster", "bandmap", "availMult", "blacklist", "netstatus", "chat", "partner", "wsjtxdecodes",
            "hamqthLog", "rate", "goals", "goals-from-log", "statistics", "score", "dupesheet", "skeds", "qtc",
            "simulator", "bandnotes", "movemults", "propagation", "worldmap", "worldmap-dxcc", "mult:dxcc",
            "mult:grid", "mult:itu", "mult:cq", "mult:districts", "mult:other", "mult:sections",
        ])
        let dir = try TempDir()
        let (windows, config) = Self.model(["log"], dir: dir)
        windows.setOpen("profiles", true)
        windows.setOpen("defeditor", true)
        #expect(windows.isOpen("profiles"))
        #expect(config.config.openWindows == ["log", "defeditor"])
    }
}
