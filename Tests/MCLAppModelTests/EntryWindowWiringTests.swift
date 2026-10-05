import Foundation
import MCLCore
import Testing
@testable import MCLAppModel

/// The entry window's key flow: the AppKit monitor hands every key event here as plain values; actions fire on
/// the Kotlin phase, the modifier keys see the previous flags of every `flagsChanged` the app received.
@MainActor @Suite struct EntryKeyFlowTests {

    private static let returnKey: UInt16 = 0x24
    private static let escapeKey: UInt16 = 0x35
    private static let leftShift: UInt16 = 0x38

    private static func key(_ kind: MacKeyEvent.Kind, _ code: UInt16, _ text: String,
                            flags: UInt = 0) -> MacKeyEvent {
        MacKeyEvent(kind: kind, keyCode: code, characters: text, charactersIgnoringModifiers: text,
                    modifierFlags: flags)
    }

    private static func flags(_ code: UInt16, _ flags: UInt) -> MacKeyEvent {
        MacKeyEvent(kind: .flagsChanged, keyCode: code, modifierFlags: flags)
    }

    @Test func enterLogsOnReleaseOnly() async throws {
        let app = try await PortedApp.make()
        try await app.startCqWw()
        let flow = EntryKeyFlow(entry: app.entry)
        app.type(call: "DL1ABC", zone: "14")
        // The press goes on to the field (whose delegate swallows `insertNewline:`).
        #expect(!flow.process(Self.key(.keyDown, Self.returnKey, "\r"), target: .entry(.call)))
        await app.settle()
        #expect(app.model.logbook.rows.isEmpty)
        #expect(flow.process(Self.key(.keyUp, Self.returnKey, "\r"), target: .entry(.call)))
        await app.settle()
        #expect(app.model.logbook.rows.map(\.call) == ["DL1ABC"])
    }

    /// A release whose press the entry did not see (a dialog's default button took the press) does nothing.
    @Test func aReleaseWithoutItsPressIsNotRouted() async throws {
        let app = try await PortedApp.make()
        try await app.startCqWw()
        let flow = EntryKeyFlow(entry: app.entry)
        app.type(call: "DL1ABC", zone: "14")
        #expect(!flow.process(Self.key(.keyDown, Self.returnKey, "\r"), target: .elsewhere))
        #expect(!flow.process(Self.key(.keyUp, Self.returnKey, "\r"), target: .entry(.call)))
        await app.settle()
        #expect(app.model.logbook.rows.isEmpty)
        #expect(app.entry.form.call == "DL1ABC")
        // Esc the same.
        #expect(!flow.process(Self.key(.keyUp, Self.escapeKey, "\u{1B}"), target: .entry(.call)))
        #expect(app.entry.form.call == "DL1ABC")
        // A press seen after focus left and came back is routed again.
        #expect(!flow.process(Self.key(.keyDown, Self.escapeKey, "\u{1B}"), target: .entry(.call)))
        #expect(flow.process(Self.key(.keyUp, Self.escapeKey, "\u{1B}"), target: .entry(.call)))
        #expect(app.entry.form.call == "")
    }

    /// JDK `sPreviousNSFlags`: every `flagsChanged` the app receives updates the previous flags, also outside the
    /// entry fields, so the next Shift event in the entry is read against them.
    @Test func modifierKeysUseThePreviousFlagsOfEveryFlagsChanged() async throws {
        let app = try await PortedApp.make()
        let flow = EntryKeyFlow(entry: app.entry)
        let shift: UInt = AwtKeyCodes.macShiftFlag
        // Shift goes down while another window has the focus.
        #expect(!flow.process(Self.flags(Self.leftShift, shift), target: .elsewhere))
        #expect(flow.previousModifierFlags == shift)
        #expect(!app.entry.shiftHeld)
        // Its release in the entry: previous ^ current = Shift → a released Shift.
        #expect(!flow.process(Self.flags(Self.leftShift, 0), target: .entry(.call)))
        #expect(!app.entry.shiftHeld)
        #expect(!flow.process(Self.flags(Self.leftShift, shift), target: .entry(.exchange)))
        #expect(app.entry.shiftHeld)
        #expect(!flow.process(Self.flags(Self.leftShift, 0), target: .entry(.exchange)))
        #expect(!app.entry.shiftHeld)
    }

    /// L12: while the entry takes no input, keys the router would act on are swallowed without an action.
    @Test func noInputSwallowsWithoutActing() async throws {
        let app = try await PortedApp.make()
        try await app.startCqWw()
        let flow = EntryKeyFlow(entry: app.entry)
        app.type(call: "DL1ABC", zone: "14")
        let accepts = InputSwitch()
        app.entry.inputGate = { accepts.on }
        #expect(!flow.process(Self.key(.keyDown, Self.returnKey, "\r"), target: .entry(.call)))
        #expect(flow.process(Self.key(.keyUp, Self.returnKey, "\r"), target: .entry(.call)))
        #expect(!flow.process(Self.key(.keyDown, Self.escapeKey, "\u{1B}"), target: .entry(.call)))
        #expect(flow.process(Self.key(.keyUp, Self.escapeKey, "\u{1B}"), target: .entry(.call)))
        // Ctrl+W (wipe) on its press.
        let ctrlW = MacKeyEvent(kind: .keyDown, keyCode: 0x0D, characters: "\u{17}", charactersIgnoringModifiers: "w",
                                modifierFlags: AwtKeyCodes.macControlFlag)
        #expect(flow.process(ctrlW, target: .entry(.call)))
        // Typing still reaches the field.
        #expect(!flow.process(Self.key(.keyDown, 0x00, "a"), target: .entry(.call)))
        await app.settle()
        #expect(app.model.logbook.rows.isEmpty)
        #expect(app.entry.form.call == "DL1ABC")
        accepts.on = true
        #expect(flow.process(ctrlW, target: .entry(.call)))
        #expect(app.entry.form.call == "")
    }

    /// Outside the entry fields nothing is routed (the frequency field, other windows).
    @Test func otherTargetsPassThrough() async throws {
        let app = try await PortedApp.make()
        let flow = EntryKeyFlow(entry: app.entry)
        app.entry.callChanged("DL1ABC")
        #expect(!flow.process(Self.key(.keyDown, Self.escapeKey, "\u{1B}"), target: .elsewhere))
        #expect(!flow.process(Self.key(.keyUp, Self.escapeKey, "\u{1B}"), target: .elsewhere))
        #expect(app.entry.form.call == "DL1ABC")
    }

    /// Czech dead ´ then Space in the call field: the space commits the accent (marked text) and does not jump to
    /// the exchange; the release after the composition is not routed either.
    @Test func markedTextKeepsTheSpaceForTheComposition() async throws {
        let app = try await PortedApp.make()
        try await app.startCqWw()
        let flow = EntryKeyFlow(entry: app.entry)
        app.entry.callChanged("DL1AB")
        let exchangeRequests: Int = app.entry.exchangeFocusRequest
        let dead = MacKeyEvent(kind: .keyDown, keyCode: 0x18, characters: "", charactersIgnoringModifiers: "´",
                               deadKeyCharacter: 0x00B4)
        #expect(!flow.process(dead, target: .entry(.call)))
        var deadUp = dead
        deadUp.kind = .keyUp
        #expect(!flow.process(deadUp, target: .composing(.call)))
        #expect(!flow.process(Self.key(.keyDown, 0x31, " "), target: .composing(.call)))
        #expect(!flow.process(Self.key(.keyUp, 0x31, " "), target: .entry(.call)))
        #expect(app.entry.exchangeFocusRequest == exchangeRequests)
        // Without marked text the space jumps.
        #expect(flow.process(Self.key(.keyDown, 0x31, " "), target: .entry(.call)))
        #expect(app.entry.exchangeFocusRequest == exchangeRequests + 1)
    }

    /// Enter that commits an input-method composition does not log on its release.
    @Test func enterCommittingACompositionDoesNotLog() async throws {
        let app = try await PortedApp.make()
        try await app.startCqWw()
        let flow = EntryKeyFlow(entry: app.entry)
        app.type(call: "DL1ABC", zone: "14")
        #expect(!flow.process(Self.key(.keyDown, Self.returnKey, "\r"), target: .composing(.exchange)))
        #expect(!flow.process(Self.key(.keyUp, Self.returnKey, "\r"), target: .entry(.exchange)))
        await app.settle()
        #expect(app.model.logbook.rows.isEmpty)
        // ↓ with marked text belongs to the candidate list, not to the suggestions.
        #expect(!flow.process(Self.key(.keyDown, 0x7D, "\u{F701}"), target: .composing(.call)))
    }

    /// The window lost the key status with a key held: its release later is not the entry's.
    @Test func resetForgetsHeldKeys() async throws {
        let app = try await PortedApp.make()
        let flow = EntryKeyFlow(entry: app.entry)
        app.entry.callChanged("DL1ABC")
        #expect(!flow.process(Self.key(.keyDown, Self.escapeKey, "\u{1B}"), target: .entry(.call)))
        flow.reset()
        #expect(!flow.process(Self.key(.keyUp, Self.escapeKey, "\u{1B}"), target: .entry(.call)))
        #expect(app.entry.form.call == "DL1ABC")
    }
}

/// Enter and Esc of the entry dialogs (`DialogKeyGate`).
@Suite struct DialogKeyGateTests {

    @Test func promptSubmitsOnTheReleaseAndCancelsOnTheEscapePress() {
        var gate = DialogKeyGate(enterSubmits: true, escapeOnPress: true)
        #expect(gate.press(.enter, composing: false) == .init(consumed: true, action: nil))
        #expect(gate.release(.enter) == .init(consumed: true, action: .submit))
        #expect(gate.press(.escape, composing: false) == .init(consumed: true, action: .cancel))
        #expect(gate.release(.escape) == .init(consumed: false, action: nil))
    }

    /// Enter in a field with marked text commits the composition (the field gets the press) and does not submit.
    @Test func enterCommittingACompositionDoesNotSubmit() {
        var gate = DialogKeyGate(enterSubmits: true, escapeOnPress: true)
        #expect(gate.press(.enter, composing: true) == .init(consumed: false, action: nil))
        #expect(gate.release(.enter) == .init(consumed: false, action: nil))
        // Esc in a composition cancels the composition, not the dialog.
        #expect(gate.press(.escape, composing: true) == .init(consumed: false, action: nil))
        // A press seen before a composition started and released after it: still nothing.
        #expect(gate.press(.enter, composing: false).consumed)
        #expect(gate.press(.enter, composing: true) == .init(consumed: false, action: nil))
        #expect(gate.release(.enter).action == nil)
    }

    @Test func operatorWindowClosesOnTheEscapeRelease() {
        var gate = DialogKeyGate(enterSubmits: true, escapeOnPress: false)
        #expect(gate.press(.escape, composing: false) == .init(consumed: true, action: nil))
        #expect(gate.release(.escape) == .init(consumed: true, action: .cancel))
        // A release without its press (the main window took the press) does nothing.
        #expect(gate.release(.enter) == .init(consumed: false, action: nil))
        #expect(gate.press(.enter, composing: false).consumed)
        gate.reset()
        #expect(gate.release(.enter).action == nil)
    }

    /// The Settings window: Esc cancels on its release; a dead key followed by Esc (the press aborts the composition)
    /// keeps the window and its draft.
    @Test func settingsWindowEscapeSparesACompositionAbort() {
        var gate = DialogKeyGate.settingsWindow()
        #expect(gate.press(.escape, composing: true) == .init(consumed: false, action: nil))
        #expect(gate.release(.escape) == .init(consumed: false, action: nil))
        #expect(gate.press(.escape, composing: false) == .init(consumed: true, action: nil))
        #expect(gate.release(.escape) == .init(consumed: true, action: .cancel))
        #expect(gate.press(.enter, composing: false).action == nil)
        #expect(gate.release(.enter).action == nil)
    }

    @Test func confirmationHasNoEnterAction() {
        var gate = DialogKeyGate(enterSubmits: false, escapeOnPress: true)
        #expect(gate.press(.enter, composing: false) == .init(consumed: true, action: nil))
        #expect(gate.release(.enter) == .init(consumed: true, action: nil))
        #expect(gate.press(.escape, composing: false).action == .cancel)
    }
}

/// The entry's input gate in a test.
@MainActor private final class InputSwitch {
    var on = false
}

/// The callsign help wired into the app model (models): suggestions follow the entry form, the entry's keys
/// move the one highlight, the call history prefill comes back without touch marks, the info strip reads the entry
/// and operating states, and the `master.scp` download menu action is registered.
@MainActor @Suite struct EntryWindowWiringTests {

    private static func app(callHistory: String = "", scp: String = "") async throws -> TestApp {
        try await TestApp.make { config, dataDir in
            if !scp.isEmpty {
                let url: URL = dataDir.appendingPathComponent("MASTER.SCP")
                try Data(scp.utf8).write(to: url)
                config.scpFile = url.path
            }
            if !callHistory.isEmpty {
                let url: URL = dataDir.appendingPathComponent("CALLHISTORY.txt")
                try Data(callHistory.utf8).write(to: url)
                config.callHistoryFile = url.path
            }
        }
    }

    /// Lets the observation re-arm (posted to the main queue) run and waits for what it started, a few rounds (a
    /// load raises a revision, which refreshes the suggestions again).
    private func settleHelp(_ app: TestApp) async {
        for _ in 0..<3 {
            await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                MainHop.post { done.resume() }
            }
            await app.model.callData.settle()
            await app.model.suggestions.settle()
        }
    }

    @Test func suggestionsFollowTheFormAndTheKeysMoveTheirHighlight() async throws {
        let app = try await Self.app(scp: "OK1ABC\nOK1ABD\nDL1ABC\n")
        try await app.startCqWwCw()
        await settleHelp(app)
        #expect(app.model.callData.scpRevision == 1)
        app.model.entry.callChanged("OK1AB")
        await settleHelp(app)
        #expect(app.model.suggestions.suggestions == ["OK1ABC", "OK1ABD"])
        #expect(app.model.entry.suggestions() == ["OK1ABC", "OK1ABD"])
        let context: EntryKeyContext = app.model.entry.keyContext(field: .call)
        #expect(context.suggestionCount == 2)
        app.model.entry.handle(.scpMove(by: 1, to: 1))
        #expect(app.model.suggestions.scpPick == 1)
        #expect(app.model.entry.keyContext(field: .call).scpPick == 1)
        app.model.entry.handle(.enter(ctrl: false, step: .takeSuggestion(1)))
        #expect(app.model.entry.form.call == "OK1ABD")
        #expect(app.model.suggestions.scpPick == -1)
        app.model.entry.takeCall("DL1ABC")
        #expect(app.model.entry.form.call == "DL1ABC")
    }

    @Test func callHistoryPrefillLeavesNoTouchMarks() async throws {
        let app = try await Self.app(callHistory: "!!Order!!,Call,CQZone\nDL1ABC,14\n")
        try await app.startCqWwCw()
        await settleHelp(app)
        app.model.entry.callChanged("DL1ABC")
        await settleHelp(app)
        app.suggestionClock.advance(by: SuggestionsModel.fillDelayMilliseconds)
        #expect(app.model.entry.form.contestExchange["zone"] == "14")
        #expect(app.model.suggestions.chFilled["zone"] == "14")
        #expect(app.model.entry.form.touchedFields.isEmpty)
        // Another call takes the prefilled value back.
        app.model.entry.callChanged("W1AW")
        await settleHelp(app)
        app.suggestionClock.advance(by: SuggestionsModel.fillDelayMilliseconds)
        #expect(app.model.entry.form.contestExchange["zone"] == nil)
        #expect(app.model.suggestions.chFilled.isEmpty)
    }

    @Test func infoStripReadsTheEntryAndOperatingStates() async throws {
        let app = try await TestApp.make()
        #expect(app.model.infoStrip.text == "")
        app.model.operating.applyPostContest(true)
        #expect(app.model.infoStrip.items == [ContestMessage("DODATEČNÉ ZADÁNÍ")])
        app.model.operating.applyPostContest(false)
        app.model.operating.applyCqRepeat(true)
        #expect(app.model.infoStrip.text.contains("RPT"))
    }

    @Test func downloadScpIsRegistered() async throws {
        let app = try await TestApp.make()
        #expect(app.model.extraMenuActions["settings.downloadScp"] != nil)
        #expect(app.model.menu.isImplemented("settings.downloadScp"))
    }

    @Test func operatorWindowFollowsTheModel() async throws {
        let app = try await TestApp.make()
        let dialogs: DialogsModel = app.model.dialogs
        #expect(!dialogs.isOpen(.operatorLogin))
        dialogs.openOperator()
        #expect(dialogs.openDialogs.contains(.operatorLogin))
        dialogs.setOpen(.operatorLogin, false)
        #expect(!dialogs.showOperator)
        #expect(DialogsModel.Window.operatorLogin.rawValue == "operator")
        #expect(DialogsModel.Window.operatorLogin.defaultSize == CGSize(width: 400, height: 230))
        #expect(DialogsModel.Window.operatorLogin.savesGeometry)
    }
}
