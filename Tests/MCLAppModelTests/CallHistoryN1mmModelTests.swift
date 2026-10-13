import Foundation
import MCLCore
import Testing
@testable import MCLAppModel

/// The N1MM call history features of the app: the lookup switch (menu and `#CONTEST` lines), the contest's own file,
/// the merged additional files and their import, update from the log into the primary file only, and the user
/// information lines.
@MainActor @Suite struct CallHistoryN1mmModelTests {

    /// Lets the posted observation hops and the loads they start finish.
    private static func settle(_ app: TestApp) async {
        for _ in 0..<4 {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DispatchQueue.main.async { continuation.resume() }
            }
            await app.model.contest.settleActivations()
            await app.model.callData.settle()
        }
    }

    private static func write(_ text: String, _ name: String, in dataDir: URL) throws -> String {
        let url: URL = dataDir.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        return url.path
    }

    // MARK: - the contest's own file

    @Test func theContestsOwnFileReplacesTheGlobalOne() async throws {
        var own = ""
        let app = try await TestApp.make { config, dataDir in
            config.callHistoryFile = try Self.write("!!Order!!,Call,Name\nW1AW,Global\n", "global.txt", in: dataDir)
            own = try Self.write("!!Order!!,Call,Name\nW1AW,Contest\n", "contest.txt", in: dataDir)
        }
        await Self.settle(app)
        let callData: CallDataModel = app.model.callData
        #expect(callData.callHistory.lookup("W1AW")?["name"] == "Global")
        var setup = ContestSetup()
        setup.callHistoryFile = own
        #expect(await app.model.contest.createAndStart(definitionId: "cq-ww-cw", setup: setup))
        await Self.settle(app)
        #expect(callData.primaryCallHistoryPath == own)
        #expect(callData.callHistory.lookup("W1AW")?["name"] == "Contest")
        app.model.contest.deactivate()
        await Self.settle(app)
        #expect(callData.callHistory.lookup("W1AW")?["name"] == "Global")
    }

    @Test func assigningAFileToTheActiveContestSwitchesAtOnce() async throws {
        var own = ""
        let app = try await TestApp.make { config, dataDir in
            config.callHistoryFile = try Self.write("!!Order!!,Call,Name\nW1AW,Global\n", "global.txt", in: dataDir)
            own = try Self.write("!!Order!!,Call,Name\nW1AW,Contest\n", "contest.txt", in: dataDir)
        }
        try await app.startCqWwCw()
        let tools: DataToolsModel = app.model.dataTools
        #expect(tools.contestCallHistoryFile == "")
        tools.setContestCallHistoryFile(" " + own + " ")
        await tools.settle()
        await Self.settle(app)
        #expect(tools.contestCallHistoryFile == own)
        #expect(app.model.callData.callHistory.lookup("W1AW")?["name"] == "Contest")
        tools.setContestCallHistoryFile("")
        await tools.settle()
        await Self.settle(app)
        #expect(app.model.callData.callHistory.lookup("W1AW")?["name"] == "Global")
    }

    // MARK: - #CONTEST

    private static func lookupAfterOpening(_ file: String, enabled: Bool) async throws -> TestApp {
        let app = try await TestApp.make { config, dataDir in
            config.callHistoryFile = try Self.write(file, "ch.txt", in: dataDir)
            config.callHistoryLookupEnabled = enabled
        }
        await Self.settle(app)
        try await app.startCqWwCw()
        await Self.settle(app)
        return app
    }

    @Test func aFileOfAnotherContestDisablesTheLookup() async throws {
        let app = try await Self.lookupAfterOpening("# CQ WW SSB\n!!Order!!,Call,CQZone\nW1AW,5\n", enabled: true)
        #expect(!app.model.callData.callHistoryLookupEnabled)
        #expect(await !app.savedConfigFlushed().callHistoryLookupEnabled)
    }

    @Test func aFileOfThisContestEnablesTheLookup() async throws {
        let app = try await Self.lookupAfterOpening("#CQWWSSB\n#cq-ww-cw\n!!Order!!,Call\nW1AW\n", enabled: false)
        #expect(app.model.callData.callHistoryLookupEnabled)
    }

    @Test func commentsNamingNoKnownContestLeaveTheSwitchAlone() async throws {
        let off = try await Self.lookupAfterOpening("# my club members\n!!Order!!,Call\nW1AW\n", enabled: false)
        #expect(!off.model.callData.callHistoryLookupEnabled)
        let on = try await Self.lookupAfterOpening("#NAQPCW\n!!Order!!,Call\nW1AW\n", enabled: true)
        #expect(on.model.callData.callHistoryLookupEnabled)
    }

    /// Applied once per opening: the operator's later choice in the menu stands.
    @Test func theMenuChoiceAfterOpeningStands() async throws {
        let app = try await Self.lookupAfterOpening("#CQWWSSB\n!!Order!!,Call\nW1AW\n", enabled: true)
        #expect(!app.model.callData.callHistoryLookupEnabled)
        #expect(MenuActions.perform("settings.callHistoryLookup", app: app.model) == nil)
        #expect(app.model.callData.callHistoryLookupEnabled)
        #expect(MenuActions.isChecked("settings.callHistoryLookup", app: app.model))
        app.model.callData.reloadCallHistory()
        await Self.settle(app)
        #expect(app.model.callData.callHistoryLookupEnabled)
        #expect(MenuActions.perform("settings.callHistoryLookup", app: app.model) == nil)
        #expect(!MenuActions.isChecked("settings.callHistoryLookup", app: app.model))
        #expect(app.model.status.message == "Dohledávání v call history vypnuto")
    }

    // MARK: - merged files

    @Test func extraFilesAreMergedAndUpdateFromLogWritesThePrimaryOnly() async throws {
        var primary = ""
        let app = try await TestApp.make { config, dataDir in
            primary = try Self.write("!!Order!!,Call,CQZone\nDL1ABC,14\n", "primary.txt", in: dataDir)
            config.callHistoryFile = primary
            config.callHistoryExtraFiles = [
                try Self.write("!!Order!!;Call;Name;UserText\nOK1ABC;Pavel;club\nDL1ABC;Hans;dx\n", "extra.txt",
                               in: dataDir),
            ]
        }
        await Self.settle(app)
        let callData: CallDataModel = app.model.callData
        #expect(callData.callHistory.size == 2)
        #expect(callData.callHistory.lookup("DL1ABC")?["name"] == "Hans")
        #expect(callData.callHistory.lookup("DL1ABC")?["cqzone"] == "14")
        #expect(callData.primaryCallHistory.size == 1)
        try await app.startCqWwCw()
        await app.logContestQso(call: "K1ABC", zone: "5")
        app.model.dataTools.updateCallHistoryFromLog()
        await app.model.dataTools.settle()
        let written = CallHistory.load(primary)
        #expect(written.size == 2)
        #expect(written.lookup("K1ABC")?["cqzone"] == "5")
        #expect(written.lookup("OK1ABC") == nil, "the additional files are not copied into the primary one")
        #expect(callData.callHistory.size == 3)
        #expect(callData.callHistory.lookup("OK1ABC")?["usertext"] == "club")
    }

    @Test func importAddsTheChosenFilesToTheMergedOnes() async throws {
        var paths: [String] = []
        let app = try await TestApp.make { config, dataDir in
            paths = [
                try Self.write("!!Order!!,Call\nW1AW\n", "a.txt", in: dataDir),
                try Self.write("!!Order!!,Call\nK1AB\n", "b.txt", in: dataDir),
                try Self.write("!!Order!!,Call\nN1XX\n", "c.txt", in: dataDir),
            ]
            config.callHistoryFile = paths[0]
        }
        await Self.settle(app)
        #expect(MenuActions.perform("callhistory.import", app: app.model) == .openCallHistoryImport)
        let tools: DataToolsModel = app.model.dataTools
        tools.importCallHistoryFiles(paths.map { URL(fileURLWithPath: $0) })
        #expect(app.model.config.config.callHistoryExtraFiles == [paths[1], paths[2]])
        #expect(app.model.status.message == "Call history: přidáno 2 souborů ke sloučení")
        await Self.settle(app)
        #expect(app.model.callData.callHistory.size == 3)
        #expect(await app.savedConfigFlushed().callHistoryExtraFiles == [paths[1], paths[2]])
        tools.importCallHistoryFiles([URL(fileURLWithPath: paths[2])])
        #expect(app.model.status.message == "Vybrané soubory už call history používá")
    }

    // MARK: - the entry window

    @MainActor private final class FormBox {
        var form = EntryForm()
    }

    @Test func lookupSwitchStopsThePrefillButNotTheUserText() async throws {
        let app = try await TestApp.make { config, dataDir in
            config.callHistoryFile = try Self.write(
                "!!Order!!,Call,Name,CQZone,UserText\nDL1ABC,Hans,14,club member\n", "ch.txt", in: dataDir)
            config.callHistoryLookupEnabled = false
        }
        try await app.startCqWwCw()
        let callData = CallDataModel(config: app.model.config, status: app.model.status, dataDir: app.dataDir)
        callData.reload()
        await callData.settle()
        let clock = ManualClock()
        let suggestions = SuggestionsModel(callData: callData, logbook: app.model.logbook,
                                           contest: app.model.contest, clock: clock)
        let box = FormBox()
        suggestions.formSource = { box.form }
        suggestions.formSink = { box.form = $0 }
        box.form.call = "DL1ABC"
        suggestions.refresh()
        clock.advance(by: 250)
        #expect(box.form.contestExchange["zone"] == nil)
        #expect(suggestions.callHistoryLine == nil)
        #expect(suggestions.userTextLine == "club member")
        app.model.config.config.callHistoryLookupEnabled = true
        suggestions.refresh()
        clock.advance(by: 250)
        #expect(box.form.contestExchange["zone"] == "14")
        #expect(suggestions.callHistoryLine == "Call history: Name: Hans, CQZone: 14")
        app.model.config.config.callHistoryShowUserInfo = false
        #expect(suggestions.callHistoryLine == nil)
        #expect(suggestions.userTextLine == nil)
        box.form.call = "K1ZZZ"
        app.model.config.config.callHistoryShowUserInfo = true
        #expect(suggestions.callHistoryLine == nil)
        #expect(suggestions.userTextLine == nil)
    }
}
