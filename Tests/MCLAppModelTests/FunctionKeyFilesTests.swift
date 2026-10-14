import Foundation
import MCLCore
import Testing
@testable import MCLAppModel

/// N1MM function key files in the app: the contest's associated `.mc` files and the operators' own files.
@MainActor @Suite struct FunctionKeyFilesTests {

    private static func settle(_ app: TestApp) async {
        for _ in 0..<4 {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DispatchQueue.main.async { continuation.resume() }
            }
            await app.model.contest.settleActivations()
        }
    }

    private static func keys(_ tag: String) -> FunctionKeySet {
        FunctionKeySet(run: (1...12).map { FunctionKeyMessage(label: tag + "\($0)", text: tag.lowercased() + " \($0)") },
                       sp: (1...12).map { FunctionKeyMessage(label: tag + "S\($0)", text: "sp \($0)") })
    }

    @Test func theContestsFileLoadsWhenItOpensAndGetsTheChanges() async throws {
        var path = ""
        let app = try await TestApp.make { _, dataDir in
            let url: URL = dataDir.appendingPathComponent("WW CW.mc")
            #expect(FunctionKeyFilesModel.write(Self.keys("WW"), kind: .cw, to: url))
            path = url.path
        }
        var setup = ContestSetup()
        setup.sentExchange = ["zone": "15"]
        setup.functionKeyFiles = ["CW": path]
        #expect(await app.model.contest.createAndStart(definitionId: "cq-ww-cw", setup: setup))
        await Self.settle(app)
        let config: ConfigModel = app.model.config
        #expect(config.config.cwKeyer.runMessages[0] == FunctionKeyMessage(label: "WW1", text: "ww 1"))
        #expect(config.config.cwKeyer.spMessages[11].text == "sp 12")
        #expect(app.model.functionKeyFiles.associatedFile(.cw) == path)
        // A commit that changes the set writes the file back.
        config.config.cwKeyer.runMessages[1] = FunctionKeyMessage(label: "New", text: "new text")
        config.bumpRevision()
        await Self.settle(app)
        let back = try #require(FunctionKeyFilesModel.read(URL(fileURLWithPath: path)))
        #expect(back.run[1] == FunctionKeyMessage(label: "New", text: "new text"))
        #expect(back.run[0].label == "WW1")
    }

    @Test func associatingAndRemovingAFile() async throws {
        let app = try await TestApp.make()
        try await app.startCqWwCw()
        let files: FunctionKeyFilesModel = app.model.functionKeyFiles
        #expect(files.associatedFile(.ssb) == nil)
        #expect(await files.associate(.ssb, path: " /x/SSB.mc "))
        #expect(files.associatedFile(.ssb) == "/x/SSB.mc")
        #expect(app.model.contest.activeSetup?.functionKeyFiles == ["SSB": "/x/SSB.mc"])
        #expect(await files.associate(.ssb, path: nil))
        #expect(files.associatedFile(.ssb) == nil)
    }

    @Test func anUnreadableFileKeepsTheMessages() async throws {
        let app = try await TestApp.make()
        var setup = ContestSetup()
        setup.functionKeyFiles = ["CW": app.dataDir.appendingPathComponent("missing.mc").path]
        #expect(await app.model.contest.createAndStart(definitionId: "cq-ww-cw", setup: setup))
        await Self.settle(app)
        #expect(app.model.config.config.cwKeyer.runMessages == CwKeyerConfig.defaultRun())
    }

    /// Each operator gets a copy of the station's messages; their changes stay theirs, the station's come back.
    @Test func operatorsHaveTheirOwnMessages() async throws {
        let app = try await TestApp.make { config, _ in
            config.functionKeysPerOperator = true
        }
        let config: ConfigModel = app.model.config
        let operating: OperatingModel = app.model.operating
        let files: FunctionKeyFilesModel = app.model.functionKeyFiles
        #expect(files.owner == "OK1XOE")
        operating.setOperator("ok1abc", persist: false)
        await Self.settle(app)
        #expect(files.owner == "OK1ABC")
        #expect(config.config.cwKeyer.runMessages == CwKeyerConfig.defaultRun())
        // OK1ABC edits F1.
        config.config.cwKeyer.runMessages[0] = FunctionKeyMessage(label: "Abc", text: "cq abc")
        config.bumpRevision()
        await Self.settle(app)
        let own = try #require(FunctionKeyFilesModel.read(files.operatorFile("OK1ABC", .cw)))
        #expect(own.run[0].text == "cq abc")
        // The station signs on again: the master messages.
        operating.setOperator("OK1XOE", persist: false)
        await Self.settle(app)
        #expect(config.config.cwKeyer.runMessages == CwKeyerConfig.defaultRun())
        // OK1ABC again: their own.
        operating.setOperator("OK1ABC", persist: false)
        await Self.settle(app)
        #expect(config.config.cwKeyer.runMessages[0].text == "cq abc")
    }

    @Test func withoutSeparateFilesTheOperatorDoesNotMatter() async throws {
        let app = try await TestApp.make()
        let config: ConfigModel = app.model.config
        config.config.cwKeyer.runMessages[0] = FunctionKeyMessage(label: "X", text: "x")
        app.model.operating.setOperator("OK1ABC", persist: false)
        await Self.settle(app)
        #expect(config.config.cwKeyer.runMessages[0].text == "x")
        #expect(!FileManager.default.fileExists(atPath: app.dataDir.appendingPathComponent("FunctionKeys").path))
    }

    @Test func rightClickOpensTheShownSet() async throws {
        let app = try await TestApp.make()
        let entry: EntryModel = app.model.entry
        entry.setMode(.cw)
        #expect(entry.functionKeyText(0) == CwKeyerConfig.defaultRun()[0].text
            || entry.functionKeyText(0) == CwKeyerConfig.defaultSp()[0].text)
        entry.openFunctionKeyEditor()
        #expect(app.model.menu.functionKeysFocus?.kind == .cw)
        #expect(app.model.menu.pendingSettingsTab == "function-keys")
    }
}

/// N1MM File → Export Function Keys to file.
@MainActor @Suite struct FunctionKeyExportMenuTests {

    @Test func exportsTheSetTheKeysSendNow() async throws {
        let app = try await TestApp.make()
        app.model.entry.setMode(.cw)
        #expect(MenuActions.perform("fkeys.export", app: app.model)
            == .saveFunctionKeys(kind: .cw, suggestedName: "CW Messages.mc"))
        app.model.entry.setMode(.ssb)
        #expect(MenuActions.perform("fkeys.export", app: app.model)
            == .saveFunctionKeys(kind: .ssb, suggestedName: "SSB Messages.mc"))
        #expect(app.model.menu.isImplemented("fkeys.export"))
    }
}
