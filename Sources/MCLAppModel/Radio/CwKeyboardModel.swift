import Foundation
import MCLCore
import Observation

/// The CW keyboard window (`CwKeyboardWindow.kt`, N1MM CW keyboard, Ctrl+K): the typed text goes out word by word
/// (a word as soon as a space follows it) or, with „Po Enteru", only on Enter; Esc and „Stop (Esc)" stop sending and
/// clear the field. The text is the window's own state (Kotlin `remember`): a new window starts empty, word by word.
@Observable @MainActor
public final class CwKeyboardModel {

    /// The field (always upper case, Kotlin `v.uppercase()`).
    public private(set) var text: String = ""
    /// „Po slovech" (default) or „Po Enteru".
    public var wordByWord: Bool = true

    @ObservationIgnored private var buffer = CwKeyboardBuffer()
    @ObservationIgnored private let keyer: KeyerModel
    @ObservationIgnored private let stop: @MainActor () -> Void
    @ObservationIgnored private let typedCall: @MainActor () -> String

    init(keyer: KeyerModel, stop: @escaping @MainActor () -> Void, typedCall: @escaping @MainActor () -> String) {
        self.keyer = keyer
        self.stop = stop
        self.typedCall = typedCall
    }

    /// `state.cwSendingKey != null`: the hint line shows „vysílá se…".
    public var isSending: Bool {
        keyer.cwSendingKey != nil
    }

    /// The field changed (`onValueChange`): upper case, then the finished words are sent.
    public func textChanged(_ value: String) {
        text = KotlinStrings.uppercase(value)
        send(buffer.onTextChanged(text, wordByWord: wordByWord))
    }

    /// Enter: the rest is sent, the field cleared.
    public func enter() {
        send(buffer.flush(text))
        clearField()
    }

    /// Esc or „Stop (Esc)": `state.stopSending()`, the field cleared.
    public func escape() {
        stop()
        clearField()
    }

    private func clearField() {
        text = ""
        buffer.reset()
    }

    /// Kotlin `send(chunk)`: a non-blank chunk as free CW text with the typed call for `!`.
    private func send(_ chunk: String) {
        guard !KotlinStrings.isBlank(chunk) else { return }
        keyer.sendCwText(chunk, call: typedCall())
    }
}
