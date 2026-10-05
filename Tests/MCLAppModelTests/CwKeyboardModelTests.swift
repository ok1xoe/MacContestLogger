import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// The CW keyboard window (`CwKeyboardWindow.kt`): word by word or on Enter, upper case, the typed call for `!`,
/// Esc stops sending and clears. The keyer is a fake Winkeyer (nothing is keyed).
@MainActor @Suite struct CwKeyboardModelTests {

    private static func sends(_ app: KeyingApp) -> [String] {
        (app.keying.lastKeyer?.events ?? []).filter { $0.hasPrefix("send ") }
    }

    /// Word by word (the default): a word goes out once a space follows it, in upper case; text already sent is not
    /// sent again; Enter sends the rest and clears the field.
    @Test func wordByWordThenEnter() async throws {
        let app = try await KeyingApp.make(configure: { config, _ in winkeyerConfig(&config) })
        let keyboard: CwKeyboardModel = app.model.makeCwKeyboard()
        #expect(keyboard.wordByWord)
        keyboard.textChanged("cq te")
        #expect(keyboard.text == "CQ TE")
        await app.settle()
        #expect(Self.sends(app) == ["send CQ@28"])
        keyboard.textChanged("CQ TEST ")
        await app.settle()
        #expect(Self.sends(app) == ["send CQ@28", "send TEST@28"])
        keyboard.textChanged("CQ TEST de")
        keyboard.enter()
        #expect(keyboard.text.isEmpty)
        await app.settle()
        #expect(Self.sends(app) == ["send CQ@28", "send TEST@28", "send DE@28"])
        // A blank rest sends nothing.
        keyboard.textChanged("   ")
        keyboard.enter()
        await app.settle()
        #expect(Self.sends(app).count == 3)
    }

    /// „Po Enteru": nothing until Enter; `!` is the call typed in the entry window.
    @Test func onEnterWithTheTypedCall() async throws {
        let app = try await KeyingApp.make(configure: { config, _ in winkeyerConfig(&config) })
        app.entry.callChanged("DL1ABC")
        let keyboard: CwKeyboardModel = app.model.makeCwKeyboard()
        keyboard.wordByWord = false
        keyboard.textChanged("! 5nn ")
        await app.settle()
        #expect(Self.sends(app).isEmpty)
        keyboard.enter()
        await app.settle()
        #expect(Self.sends(app) == ["send DL1ABC 5NN@28"])
    }

    /// Esc (or „Stop (Esc)"): `stopSending()` — the CQ repeat goes off, the open keyer aborts — and the field clears;
    /// the hint follows the CW lamp.
    @Test func escapeStopsAndClears() async throws {
        let app = try await KeyingApp.make(configure: { config, _ in winkeyerConfig(&config) })
        let keyboard: CwKeyboardModel = app.model.makeCwKeyboard()
        keyboard.textChanged("TEST ")
        #expect(keyboard.isSending)
        await app.settle()
        app.model.operating.applyCqRepeat(true)
        keyboard.textChanged("TEST AB")
        keyboard.escape()
        #expect(keyboard.text.isEmpty)
        #expect(!app.model.operating.cqRepeat)
        #expect(!keyboard.isSending)
        await app.settle()
        #expect(app.keying.lastKeyer?.events.last == "abort")
        // The buffer starts again: the next word is sent from the start of the new text.
        keyboard.textChanged("AGN ")
        await app.settle()
        #expect(Self.sends(app).last == "send AGN@28")
    }
}
