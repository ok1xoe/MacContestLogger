import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// The radio tool windows in the app (`App.kt:161-183, 309-397, 645-662`): their menu actions and ids, the saved
/// `openWindows`, and what they hand to the active entry window (`prefillCall`, `prefillExchange`).
@MainActor @Suite struct RadioWindowsTests {

    static let menuToWindow: [(menu: String, window: String)] = [
        ("window.catlog", "catLog"), ("window.rotator", "rotator"), ("window.cwkeyboard", "cwkeyboard"),
        ("window.cwreader", "cwreader"), ("window.digitalinterface", "digitalinterface"),
        ("window.waterfall", "waterfall"),
    ]

    /// Every menu item opens its window (Kotlin `showXxx = true`), the id is saved in `openWindows` in Kotlin's
    /// order, and a closed window leaves it.
    @Test func menuItemsOpenTheWindows() async throws {
        let app = try await TestApp.make()
        for (menu, window) in Self.menuToWindow {
            #expect(app.model.menu.isImplemented(menu), "\(menu)")
            #expect(WindowsModel.implemented.contains(window), "\(window)")
            #expect(MenuActions.perform(menu, app: app.model) == nil)
            #expect(app.model.windows.isOpen(window), "\(window)")
        }
        let saved: [String] = await app.savedConfigFlushed().openWindows
        #expect(saved == ["log", "catLog", "rotator", "cwkeyboard", "cwreader", "digitalinterface", "waterfall"])
        app.model.windows.setOpen("cwreader", false)
        #expect(await app.savedConfigFlushed().openWindows
            == ["log", "catLog", "rotator", "cwkeyboard", "digitalinterface", "waterfall"])
    }

    /// The built-in menu has no Digital Interface item (only `menu.json` has it) — kept as in v1.1.1.
    @Test func defaultMenuHasNoDigitalInterface() {
        #expect(DefaultMenu.labelFor("window.digitalinterface") == nil)
        #expect(DefaultMenu.labelFor("window.catlog") == "CAT log")
    }

    /// `prefillCall`: the active entry window takes the call and the call field the focus; a blank call does nothing.
    /// `prefillExchange`: non-blank values into the contest fields as they are.
    @Test func prefillGoesToTheActiveWindow() async throws {
        let app = try await TestApp.make()
        let entry: EntryModel = app.model.entry
        #expect(app.model.activeEntry === entry)
        let focus: Int = entry.focusRequest
        app.model.prefillCall("DL1ABC")
        #expect(entry.form.call == "DL1ABC")
        #expect(entry.focusRequest == focus + 1)
        #expect(app.model.typedCall == "DL1ABC")
        app.model.prefillCall("  ")
        #expect(entry.form.call == "DL1ABC")
        app.model.prefillExchange([(id: "zone", value: "14"), (id: "state", value: " ")])
        #expect(entry.form.contestExchange["zone"] == "14")
        #expect(entry.form.contestExchange["state"] == nil)
        #expect(app.model.currentExchange["zone"] == "14")
        // The hidden VFO B window never takes anything.
        #expect(app.model.vfoB.entry.form.call.isEmpty)
    }

    /// Esc from the Digital Interface always stops: with no active entry window it runs the global `stopSending()`
    /// (a safety rule); F-keys and Enter then do nothing.
    @Test func escapeStopsWithoutAnActiveWindow() async throws {
        let app = try await TestApp.make()
        app.model.entry.isWindowShown = false
        #expect(app.model.activeEntry == nil)
        app.model.operating.applyCqRepeat(true)
        app.model.perform(.stopSending)
        #expect(!app.model.operating.cqRepeat)
        app.model.entry.callChanged("DL1ABC")
        app.model.status.clear()
        app.model.perform(.enter)
        #expect(app.model.entry.form.call == "DL1ABC")
        #expect(app.model.status.message.isEmpty)
    }
}
