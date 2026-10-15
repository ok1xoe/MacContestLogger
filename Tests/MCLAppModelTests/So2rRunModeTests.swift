import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// N1MM: with two entry windows each has its own Run/S&P (Run/S&P, S&P/S&P, Run/Run): the CQ of one window makes
/// it Run without touching the other, the F-key sets follow the window, and the focused window's state is
/// `operating.runMode`.
@MainActor @Suite struct So2rRunModeTests {

    @Test func eachWindowKeepsItsRunMode() async throws {
        let app = try await RigApp.make { config, _ in
            config.radioMode = "SO2R"
            config.cwKeyer.runMessages[0] = FunctionKeyMessage(label: "CQ", text: "CQ TEST")
            config.cwKeyer.spMessages[0] = FunctionKeyMessage(label: "CALL", text: "OK1XOE")
        }
        let second: EntryModel = app.model.vfoB.entry
        second.isWindowShown = true
        let operating: OperatingModel = app.model.operating
        for entry in [app.entry, second] {
            entry.setMode(.cw)
        }
        app.entry.setFrequency("14025")
        second.setFrequency("7010")
        // A CQ on rig 1: its window is Run, rig 2's stays S&P.
        app.entry.runShortcut(.toggleRun)
        #expect(app.entry.runMode == .run)
        #expect(second.runMode == .searchAndPounce)
        #expect(app.entry.currentKeySet(opposite: false)[0].text == "CQ TEST")
        #expect(second.currentKeySet(opposite: false)[0].text == "OK1XOE")
        // The focus to rig 2: the focused state is rig 2's, rig 1 keeps Run.
        app.entry.runShortcut(.switchRadio)
        #expect(operating.focusWindow == 1)
        #expect(operating.runMode == .searchAndPounce)
        #expect(operating.isRun(window: 0))
        // A CQ from rig 2's window: Run/Run.
        second.runShortcut(.toggleRun)
        #expect(operating.isRun(window: 0) && operating.isRun(window: 1))
        app.entry.runShortcut(.toggleRun)
        #expect(!operating.isRun(window: 0) && operating.isRun(window: 1))
        second.runShortcut(.switchRadio)
        #expect(operating.focusWindow == 0)
        #expect(operating.runMode == .searchAndPounce)
    }

    @Test func oneWindowStaysAsBefore() async throws {
        let app = try await RigApp.make()
        let operating: OperatingModel = app.model.operating
        app.entry.setFrequency("14025")
        app.entry.runShortcut(.toggleRun)
        #expect(operating.runMode == .run)
        #expect(operating.isRun(window: 0))
        #expect(operating.focusWindow == 0)
    }
}
