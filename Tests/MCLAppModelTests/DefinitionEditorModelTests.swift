import Foundation
import MCLCore
import Testing
@testable import MCLAppModel

/// The contest definition editor (`DE:1-244`): lists, opening, new definitions, county import, saving with
/// reload, the delayed check and the footer.
@MainActor @Suite struct DefinitionEditorModelTests {

    /// An app over a writable copy of the contest data, with the editor's lists read.
    /// Keep the returned `app` bound for the whole test: its temporary directory goes away with it.
    static func make() async throws -> (app: TestApp, editor: DefinitionEditorModel, root: URL) {
        let app = try await DataToolsModelTests.makeWithDataCopy()
        let editor: DefinitionEditorModel = app.model.definitionEditor
        editor.refresh()
        await editor.settle()
        let root = URL(fileURLWithPath: try #require(app.model.config.config.contestDataDir))
        return (app, editor, root)
    }

    /// Fires the 250 ms check and waits for its result.
    static func runCheck(_ app: TestApp) async {
        app.editorClock.advance(by: 250)
        await app.model.definitionEditor.settle()
    }

    // MARK: - lists

    @Test func listsAreReadFromTheContestDataRoot() async throws {
        let (app, editor, root) = try await Self.make()
        defer { withExtendedLifetime(app) {} }
        #expect(editor.root.path == root.path)
        #expect(editor.contestsDir.path == root.appendingPathComponent("contests").path)
        #expect(editor.ids == DefinitionEditing.listIds(root.appendingPathComponent("contests")))
        #expect(editor.ids.contains("cq-ww-cw"))
        #expect(editor.knownSets == DefinitionEditing.knownSets(root.appendingPathComponent("multipliers")))
        #expect(!editor.knownSets.isEmpty)
    }

    @Test func aChangedContestDataDirectoryRefreshesTheLists() async throws {
        let (app, editor, _) = try await Self.make()
        let other: URL = app.dir.child("other-data")
        try FileManager.default.createDirectory(at: other.appendingPathComponent("contests"),
                                                withIntermediateDirectories: true)
        try Data("x".utf8).write(to: other.appendingPathComponent("contests/solo.yaml"))

        app.model.config.config.contestDataDir = other.path
        await DataToolsModelTests.mainHop()
        await editor.settle()

        #expect(editor.root.path == other.path)
        #expect(editor.ids == ["solo"])
        #expect(editor.knownSets.isEmpty)
    }

    // MARK: - opening

    @Test func openReadsTheFileAndTheCheckFollowsAfterTheDelay() async throws {
        let (app, editor, root) = try await Self.make()
        let file: URL = root.appendingPathComponent("contests/cq-ww-cw.yaml")

        await editor.open("cq-ww-cw")

        #expect(editor.currentId == "cq-ww-cw")
        #expect(editor.text == (try String(contentsOf: file, encoding: .utf8)))
        #expect(editor.original == editor.text)
        #expect(!editor.isDirty)
        #expect(editor.footerText == "")
        #expect(editor.check == nil)
        app.editorClock.advance(by: 249)
        await editor.settle()
        #expect(editor.check == nil)
        await Self.runCheck(app)
        let check = try #require(editor.check)
        #expect(!check.hasErrors)
        #expect(check.definition?.id == "cq-ww-cw")
    }

    @Test func openIsRefusedWhileTheTextIsUnsaved() async throws {
        let (app, editor, _) = try await Self.make()
        defer { withExtendedLifetime(app) {} }
        await editor.open("cq-ww-cw")
        editor.text += "\n# edit"

        await editor.open("cq-wpx-cw")

        #expect(editor.currentId == "cq-ww-cw")
        #expect(editor.footerText == "Neuložené změny — ulož je, nebo zahoď")
    }

    @Test func openOfAMissingFileShowsJavasMessage() async throws {
        let (app, editor, root) = try await Self.make()
        defer { withExtendedLifetime(app) {} }
        await editor.open("nope")
        #expect(editor.currentId == nil)
        #expect(editor.footerText == "Nelze otevřít nope.yaml: " + root.appendingPathComponent("contests/nope.yaml").path)
    }

    @Test func openOfInvalidUtf8ShowsTheMalformedInput() async throws {
        let (app, editor, root) = try await Self.make()
        defer { withExtendedLifetime(app) {} }
        try Data([0x69, 0x64, 0x3A, 0xC3, 0x28]).write(to: root.appendingPathComponent("contests/bad.yaml"))
        await editor.open("bad")
        #expect(editor.currentId == nil)
        #expect(editor.footerText == "Nelze otevřít bad.yaml: Input length = 1")
    }

    /// An `open` whose read finishes after the text was edited is dropped (the edit wins). The read blocks on a
    /// FIFO until the test has edited the text.
    @Test func aReadFinishingAfterAnEditIsDropped() async throws {
        let (app, editor, root) = try await Self.make()
        defer { withExtendedLifetime(app) {} }
        let fifo: String = root.appendingPathComponent("contests/slow.yaml").path
        #expect(mkfifo(fifo, 0o600) == 0)
        let opening = Task { await editor.open("slow") }
        // Returns once the editor's read has opened the FIFO (so `open` has started).
        let writer: Int32 = try await BlockingQueue.run { Darwin.open(fifo, O_WRONLY) }
        #expect(writer >= 0)
        editor.text = "typed meanwhile"
        try await BlockingQueue.run {
            let bytes: [UInt8] = Array("id: slow\n".utf8)
            _ = bytes.withUnsafeBytes { Darwin.write(writer, $0.baseAddress, $0.count) }
            close(writer)
        }
        await opening.value

        #expect(editor.currentId == nil)
        #expect(editor.text == "typed meanwhile")
    }

    @Test func duplicateNeedsAnOpenDefinition() async throws {
        let (app, editor, _) = try await Self.make()
        defer { withExtendedLifetime(app) {} }
        editor.duplicate(id: "copy")
        #expect(editor.currentId == nil)
        #expect(editor.status == nil)
    }

    // MARK: - new definitions

    @Test func startNewChecksTheIdAndDropsUnsavedChangesSilently() async throws {
        let (app, editor, _) = try await Self.make()
        defer { withExtendedLifetime(app) {} }
        editor.startNew(id: "Bad Id")
        #expect(editor.footerText == "Id smí mít jen malá písmena, číslice, - a _")
        #expect(editor.currentId == nil)
        editor.startNew(id: " cq-ww-cw ")
        #expect(editor.footerText == "Závod 'cq-ww-cw' už existuje")

        await editor.open("cq-ww-cw")
        editor.text += "\n# unsaved"
        editor.startNew(id: "  my-test\t")

        // Kotlin: no question, the unsaved text is gone.
        #expect(editor.currentId == "my-test")
        #expect(editor.original == "")
        #expect(editor.text == DefinitionEditing.template("my-test", "my-test"))
        #expect(editor.isDirty)
        #expect(editor.footerText == "Nový závod my-test — ulož ho")
    }

    @Test func duplicateUsesTheCurrentTextAndQsoPartyTheKotlinArguments() async throws {
        let (app, editor, _) = try await Self.make()
        defer { withExtendedLifetime(app) {} }
        await editor.open("cq-ww-cw")
        editor.text += "\n# edited"
        let edited: String = editor.text

        editor.duplicate(id: " ww-copy ")
        #expect(editor.currentId == "ww-copy")
        #expect(editor.text == DefinitionEditing.withId(edited, "ww-copy"))

        editor.newQsoParty(id: " oh-qp ")
        #expect(editor.currentId == "oh-qp")
        #expect(editor.text == CountyListImport.qsoPartyTemplate("oh-qp", "OH-QP", "oh_qp_counties"))
    }

    // MARK: - saving

    @Test func saveWritesTheFileAndRefreshesTheList() async throws {
        let (app, editor, root) = try await Self.make()
        defer { withExtendedLifetime(app) {} }
        editor.startNew(id: "my-test")
        let text: String = editor.text

        await editor.save(reload: false)

        #expect(editor.footerText == "Uloženo my-test.yaml")
        #expect(editor.original == text)
        #expect(!editor.isDirty)
        let saved: String = try String(contentsOf: root.appendingPathComponent("contests/my-test.yaml"),
                                       encoding: .utf8)
        #expect(saved == (text.hasSuffix("\n") ? text : text + "\n"))
        await editor.settle()
        #expect(editor.ids.contains("my-test"))
    }

    @Test func saveWithReloadDuringAContestKeepsItOpen() async throws {
        let (app, editor, _) = try await Self.make()
        try await app.startCqWwCw()
        let activeId: String? = app.model.contest.activeId
        editor.startNew(id: "my-test")

        await editor.save(reload: true)

        #expect(editor.footerText == "Uloženo my-test.yaml a definice přenačteny")
        #expect(app.model.contest.environment.catalog.contains { $0.id == "my-test" })
        #expect(app.model.contest.activeId == activeId)
    }

    @Test func saveFailureIsReported() async throws {
        let (app, editor, root) = try await Self.make()
        defer { withExtendedLifetime(app) {} }
        let contests: URL = root.appendingPathComponent("contests")
        editor.startNew(id: "my-test")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: contests.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: contests.path) }

        await editor.save(reload: false)

        #expect(editor.footerText.hasPrefix("Uložení selhalo: "))
        #expect(editor.isDirty)
    }

    @Test func discardRestoresTheOriginal() async throws {
        let (app, editor, _) = try await Self.make()
        defer { withExtendedLifetime(app) {} }
        await editor.open("cq-ww-cw")
        let original: String = editor.original
        editor.text = "broken"

        editor.discard()

        #expect(editor.text == original)
        #expect(!editor.isDirty)
        #expect(editor.footerText == "Změny zahozeny")
    }

    // MARK: - check and footer

    /// Closing the window resets the editor (Kotlin's state is the window's): an edited definition, its check in
    /// flight and its status are gone, and nothing comes back later.
    @Test func resetClearsTheEditorAndDropsALateCheck() async throws {
        let (app, editor, _) = try await Self.make()
        await editor.open("cq-ww-cw")
        await Self.runCheck(app)
        #expect(editor.check != nil)
        editor.text += "\n# edit"
        editor.discard()
        editor.text += "\n# edit again"
        // The check of the edited text is running when the window closes.
        app.editorClock.advance(by: 250)

        editor.reset()
        await editor.settle()

        #expect(editor.currentId == nil)
        #expect(editor.text == "")
        #expect(editor.original == "")
        #expect(!editor.isDirty)
        #expect(editor.check == nil)
        #expect(editor.footerText == "")
        await Self.runCheck(app)
        #expect(editor.check == nil)
        #expect(editor.currentId == nil)
    }

    /// An `open` still reading when the window closes does not reopen the definition afterwards.
    @Test func anOpenFinishingAfterResetIsDropped() async throws {
        let (app, editor, root) = try await Self.make()
        defer { withExtendedLifetime(app) {} }
        let fifo: String = root.appendingPathComponent("contests/slow.yaml").path
        #expect(mkfifo(fifo, 0o600) == 0)
        let opening = Task { await editor.open("slow") }
        let writer: Int32 = try await BlockingQueue.run { Darwin.open(fifo, O_WRONLY) }
        #expect(writer >= 0)
        editor.reset()
        try await BlockingQueue.run {
            let bytes: [UInt8] = Array("id: slow\n".utf8)
            _ = bytes.withUnsafeBytes { Darwin.write(writer, $0.baseAddress, $0.count) }
            close(writer)
        }
        await opening.value

        #expect(editor.currentId == nil)
        #expect(editor.text == "")
        #expect(editor.footerText == "")
    }

    @Test func aLateCheckOfAnOlderTextIsDropped() async throws {
        let (app, editor, _) = try await Self.make()
        await editor.open("cq-ww-cw")
        let valid: String = editor.text
        editor.text = "id: [unclosed"
        app.editorClock.advance(by: 250)
        // The broken text's check is running; the text changes before its result is taken.
        editor.text = valid
        await editor.settle()
        #expect(editor.check == nil)

        await Self.runCheck(app)

        #expect(editor.check?.hasErrors == false)
    }

    @Test func footerShowsTheStatusThenTheErrorsThenUnsaved() async throws {
        let (app, editor, _) = try await Self.make()
        await editor.open("cq-ww-cw")
        editor.text += "\n# more"
        #expect(editor.footerText == "Neuloženo")
        #expect(!editor.hasCheckErrors)

        editor.text = "id: [unclosed"
        await Self.runCheck(app)
        #expect(editor.hasCheckErrors)
        #expect(editor.footerText == "Definice má chyby — se chybami se závod nenačte")

        editor.discard()
        #expect(editor.footerText == "Změny zahozeny")
    }

    @Test func noCheckWithoutADefinition() async throws {
        let (app, editor, _) = try await Self.make()
        editor.text = "anything"
        await Self.runCheck(app)
        #expect(editor.check == nil)
    }

    // MARK: - county import

    @Test func countyImportWritesTheSetAndReloads() async throws {
        let (app, editor, root) = try await Self.make()
        try await app.startCqWwCw()
        let activeId: String? = app.model.contest.activeId
        let file: URL = app.dir.child("counties.csv")
        try Data("AB,Alpha\nCD,Charlie\n".utf8).write(to: file)

        await editor.importCounties(file: file, setId: " oh_counties ")

        #expect(editor.footerText == "Sada oh_counties: 2 okresů z counties.csv")
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("multipliers/oh_counties.csv").path))
        await editor.settle()
        #expect(editor.knownSets.contains("oh_counties"))
        #expect(app.model.contest.activeId == activeId)
    }

    @Test func countyImportReadsStrictUtf8() async throws {
        let (app, editor, root) = try await Self.make()
        let file: URL = app.dir.child("counties.csv")
        try Data([0x41, 0x42, 0x2C, 0xC3, 0x28, 0x0A]).write(to: file)

        await editor.importCounties(file: file, setId: "oh_counties")

        #expect(editor.footerText == "Import okresů: Input length = 1")
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("multipliers/oh_counties.csv").path))
    }

    @Test func countyImportWithAnInvalidSetIdIsReported() async throws {
        let (app, editor, _) = try await Self.make()
        let file: URL = app.dir.child("counties.csv")
        try Data("AB,Alpha\n".utf8).write(to: file)

        await editor.importCounties(file: file, setId: "Bad-Id")

        #expect(editor.footerText == "Import okresů: Id sady smí mít jen malá písmena, číslice a _: Bad-Id")
    }
}
