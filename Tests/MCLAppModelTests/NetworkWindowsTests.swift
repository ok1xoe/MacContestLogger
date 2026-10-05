import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// The network and integration windows in the app: their menu actions and Kotlin ids, the saved
/// `openWindows`, the unread chat count, the HamQTH log's listener, the partner field filter and the WIPELOG
/// cluster note. Stations talk over an in-memory hub; nothing reaches a socket.
@MainActor @Suite struct NetworkWindowsTests {

    static let menuToWindow: [(menu: String, window: String)] = [
        ("window.hamqthlog", "hamqthLog"), ("window.wsjtxdecodes", "wsjtxdecodes"), ("window.netstatus", "netstatus"),
        ("window.chat", "chat"), ("window.partner", "partner"),
    ]

    /// Every menu item opens its window (Kotlin `showXxx = true`) and the ids are saved in Kotlin's order.
    @Test func menuItemsOpenTheWindowsInKotlinsOrder() async throws {
        let app = try await TestApp.make()
        for (menu, window) in Self.menuToWindow.reversed() {
            #expect(app.model.menu.isImplemented(menu), "\(menu)")
            #expect(WindowsModel.implemented.contains(window), "\(window)")
            #expect(WindowsModel.menuWindows[menu] == window)
            #expect(MenuActions.perform(menu, app: app.model) == nil)
            #expect(app.model.windows.isOpen(window), "\(window)")
        }
        let expected: [String] = ["log", "hamqthLog", "wsjtxdecodes", "netstatus", "chat", "partner"]
        #expect(await app.savedConfigFlushed().openWindows == expected)
        app.model.windows.setOpen("chat", false)
        #expect(await app.savedConfigFlushed().openWindows == ["log", "hamqthLog", "wsjtxdecodes", "netstatus", "partner"])
    }

    /// The windows saved by the previous run reopen.
    @Test func savedWindowsAreRestored() async throws {
        let ids: [String] = ["log", "hamqthLog", "wsjtxdecodes", "netstatus", "chat", "partner"]
        let app = try await TestApp.make(configure: { config, _ in config.openWindows = ids })
        let reopened: [String] = app.model.windows.openIds.filter { WindowsModel.implemented.contains($0) }
        #expect(reopened == ids)
    }

    // MARK: - unread chat

    /// Kotlin zeroes the count as a side effect of drawing the chat window: with the window closed a line stays
    /// unread, with it open a line is read as it arrives, and showing the window reads the waiting ones.
    @Test func chatUnreadIsClearedOnlyWhileTheWindowIsVisible() async throws {
        let hub = InMemorySyncTransport()
        let now = NetStation.start()
        let a = try await NetStation.make(id: "OP1", hub: hub, now: now)
        let b = try await NetStation.make(id: "OP2", hub: hub, now: now)
        try await a.activate()
        try await b.activate()
        await eventually("A sees B") { a.cluster.peers.first?.online == true }

        a.network.sendChat(to: "", text: "one")
        await eventually("closed window: unread") { b.network.chat.unread == 1 }

        // The window opens (the view calls `markChatRead` when it appears).
        b.model.windows.setOpen("chat", true)
        b.network.markChatRead()
        #expect(b.network.chat.unread == 0)
        a.network.sendChat(to: "", text: "two")
        await eventually("open window: read at once") { b.network.chat.lines.count == 2 }
        #expect(b.network.chat.unread == 0)

        b.model.windows.setOpen("chat", false)
        a.network.sendChat(to: "", text: "three")
        await eventually("closed again: unread") { b.network.chat.unread == 1 }
    }

    // MARK: - the partner field

    @Test func thePartnerFieldKeepsUpperCaseLettersDigitsAndSlash() {
        #expect(NetworkModel.partnerCallFilter("ok1xoe/p") == "OK1XOE/P")
        #expect(NetworkModel.partnerCallFilter(" dl1 a-bc!") == "DL1ABC")
        #expect(NetworkModel.partnerCallFilter("") == "")
    }

    // MARK: - the HamQTH log

    @Test func theHamQthLogListensOnlyWhileTheWindowIsOpen() async throws {
        let log = HamQthLog()
        let model = HamQthLogModel(log: log)
        try log.request("https://example.invalid/?p=secret&u=x")
        #expect(model.lines.isEmpty)
        #expect(!model.isListening)

        model.open()
        #expect(model.isListening)
        #expect(model.lines.count == 1)
        #expect(model.lines[0].contains("\u{2192} GET"))
        #expect(!model.lines[0].contains("secret"))
        model.open()
        try log.response(200, "<xml/>")
        await runMainQueue()
        #expect(model.lines.count == 2)
        #expect(model.clipboardText == model.lines.joined(separator: "\n"))

        model.close()
        #expect(!model.isListening)
        try log.info("while closed")
        await runMainQueue()
        #expect(model.lines.count == 2)

        // A reopened window takes the snapshot again; clearing empties the log and the window.
        model.open()
        #expect(model.lines.count == 3)
        model.clear()
        #expect(model.lines.isEmpty)
        #expect(log.snapshot().isEmpty)
        try log.info("after clear")
        await runMainQueue()
        #expect(model.lines.count == 1)
        model.close()
    }

    // MARK: - WIPELOG

    /// The cluster note follows `cluster.connected` (Kotlin `state.clusterConnected`), read when the dialog shows.
    @Test func theWipeConfirmationMentionsTheClusterOnlyWhenConnected() async throws {
        let hub = InMemorySyncTransport()
        let off = try await NetStation.make(id: "OP9", hub: hub, enabled: false)
        off.model.dialogs.ask(.wipeLog)
        let plain: String? = off.model.dialogs.confirmationText?.czech
        #expect(plain == "Smažou se všechna spojení aktuálního deníku a skóre se vynuluje. Akci nelze vzít zpět.")

        let on = try await NetStation.make(id: "OP1", hub: hub)
        try await on.activate()
        await eventually("connected") { on.cluster.connected }
        on.model.dialogs.ask(.wipeLog)
        let withNote: String? = on.model.dialogs.confirmationText?.czech
        #expect(withNote == (plain ?? "") + "\n\nJsi připojený ke clusteru — QSO zmizí i na ostatních stanicích.")
        // The other confirmations carry no note.
        on.model.dialogs.cancelConfirmation()
        on.model.dialogs.ask(.deleteLast)
        #expect(on.model.dialogs.confirmationText?.czech == "Spojení se odstraní z deníku a skóre se přepočítá.")
    }
}
