import AppKit
import MCLAppModel
import MCLCore
import SwiftUI

/// Enter and Esc of an entry dialog in Kotlin's phases (`DialogKeyGate`): a local monitor for the application's own
/// events only, acting on the dialog's window, removed with the dialog. A press while the field holds marked text
/// goes to the input system untouched.
@MainActor
final class DialogKeyMonitor: ObservableObject {

    private static let escapeKey: UInt16 = 0x35

    var onEnter: (@MainActor () -> Void)?
    var onEscape: (@MainActor () -> Void)?
    private var gate: DialogKeyGate
    private var token: Any?
    private var observer: NSObjectProtocol?
    private weak var window: NSWindow?

    init(enterSubmits: Bool = true, escapeOnPress: Bool) {
        gate = DialogKeyGate(enterSubmits: enterSubmits, escapeOnPress: escapeOnPress)
    }

    func attach(_ window: NSWindow) {
        guard self.window !== window || token == nil else { return }
        detach()
        self.window = window
        token = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            let isKeyUp: Bool = event.type == .keyUp
            let code: UInt16 = event.keyCode
            let number: Int = event.windowNumber
            let consumed: Bool = MainActor.assumeIsolated {
                self?.handle(keyUp: isKeyUp, code: code, windowNumber: number) ?? false
            }
            return consumed ? nil : event
        }
        observer = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window,
                                                          queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.gate.reset() }
        }
    }

    func detach() {
        if let token {
            NSEvent.removeMonitor(token)
        }
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        token = nil
        observer = nil
        window = nil
        gate.reset()
    }

    private func handle(keyUp: Bool, code: UInt16, windowNumber: Int) -> Bool {
        guard let window, window.windowNumber == windowNumber else { return false }
        let key: DialogKeyGate.Key
        if AwtKeyCodes.isMacEnterKey(code) {
            key = .enter
        } else if code == Self.escapeKey {
            key = .escape
        } else {
            return false
        }
        let outcome: DialogKeyGate.Outcome
        if keyUp {
            outcome = gate.release(key)
        } else {
            let composing: Bool = (window.firstResponder as? NSTextView)?.hasMarkedText() ?? false
            outcome = gate.press(key, composing: composing)
        }
        switch outcome.action {
        case .submit?:
            onEnter?()
        case .cancel?:
            onEscape?()
        case nil:
            break
        }
        return outcome.consumed
    }
}

/// The state of a dialog's form across view updates (`@StateObject`).
@MainActor
final class DialogFormState: ObservableObject {
    @Published var text: String = ""
    @Published var persist: Bool = false
    @Published var fontSize: Int = WindowFont.defaultSize
}

/// Kotlin `TextPromptDialog` (`AS:1028`) of the entry window: the model's prompt in `TextInputSheet`, uppercased as
/// it is typed.
struct TextPromptSheet: View {
    let app: AppModel
    let prompt: DialogsModel.TextPrompt

    var body: some View {
        let language: LanguageModel = app.language
        let dialogs: DialogsModel = app.dialogs
        TextInputSheet(language: language, title: language.text(prompt.title), hint: language.text(prompt.hint),
                       initial: prompt.initial, uppercase: true,
                       onOk: { dialogs.submitPrompt($0) }, onCancel: { dialogs.cancelPrompt() })
    }
}

/// Kotlin `TextInputDialog` (`TextPromptDialog.kt:42-77`): the title, the hint, one line of text (uppercased as it
/// is typed when `uppercase`, `it.uppercase()`), OK and „Zrušit"; Enter confirms on its release, Esc cancels on its
/// press (a Compose `Dialog` layer, see `DialogKeyGate`).
struct TextInputSheet: View {
    let language: LanguageModel
    let title: String
    let hint: String
    let initial: String
    let uppercase: Bool
    let onOk: @MainActor (String) -> Void
    let onCancel: @MainActor () -> Void

    @StateObject private var form = DialogFormState()
    @StateObject private var keys = DialogKeyMonitor(escapeOnPress: true)
    @StateObject private var focusHolder = FocusHolder()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WindowTopBar(size: $form.fontSize, language: language) {
                Text(verbatim: title)
                    .windowFont(15, weight: .semibold)
            }
            Text(verbatim: hint)
                .windowFont(12)
                .foregroundStyle(.secondary)
            WindowFontReader { size in
                // Its own focus registry: the key only focuses the field, the main window's routing never sees it.
                EntryTextField(key: .call, text: form.text, transform: uppercase ? .uppercase : .none,
                               fontSize: WindowFont.size(14, windowSize: size),
                               accessibilityLabel: title,
                               focus: focusHolder.controller) { form.text = $0 }
                    .frame(width: 420 * Double(size) / Double(WindowFont.defaultSize),
                           height: WindowFont.size(26, windowSize: size))
            }
            DialogButtonRow {
                Button(language.tr("Zrušit")) {
                    onCancel()
                }
                Button("OK") {
                    onOk(form.text)
                }
            }
        }
        .padding(16)
        .environment(\.windowFontSize, form.fontSize)
        .background(WindowAccessor { window in
            keys.attach(window)
        })
        .onAppear {
            form.text = initial
            let form: DialogFormState = self.form
            let onOk = self.onOk
            keys.onEnter = { onOk(form.text) }
            keys.onEscape = onCancel
            focusHolder.controller.focus(.call)
        }
        .onDisappear {
            keys.detach()
        }
    }
}

/// The confirmations of the entry window (`WipeLogConfirmDialog.kt`, `DeleteLastQsoDialog`, the EXIT dialog of
/// `App.kt:276-286`): title, text, „Zrušit" and the confirm button; texts read when shown. As in Kotlin's
/// `AlertDialog`, Enter does not confirm and Esc cancels on its press.
struct ConfirmSheet: View {
    let app: AppModel

    @StateObject private var keys = DialogKeyMonitor(enterSubmits: false, escapeOnPress: true)
    @StateObject private var form = DialogFormState()

    var body: some View {
        let language: LanguageModel = app.language
        let dialogs: DialogsModel = app.dialogs
        VStack(alignment: .leading, spacing: 10) {
            WindowTopBar(size: $form.fontSize, language: language) {
                Text(verbatim: dialogs.confirmationTitle.map { language.text($0) } ?? "")
                    .windowFont(15, weight: .semibold)
            }
            Text(verbatim: dialogs.confirmationText.map { language.text($0) } ?? "")
                .windowFont(13)
                .fixedSize(horizontal: false, vertical: true)
            DialogButtonRow {
                Button(language.tr("Zrušit")) {
                    dialogs.cancelConfirmation()
                }
                Button {
                    dialogs.confirm()
                } label: {
                    Text(verbatim: dialogs.confirmationButton.map { language.text($0) } ?? "")
                        .foregroundStyle(Color(domain: DomainColors.dupe))
                }
                .disabled(!dialogs.confirmationEnabled)
            }
        }
        .padding(16)
        .frame(width: 420)
        .environment(\.windowFontSize, form.fontSize)
        .background(WindowAccessor { window in
            keys.attach(window)
        })
        .onAppear {
            keys.onEscape = { dialogs.cancelConfirmation() }
        }
        .onDisappear {
            keys.detach()
        }
    }
}

/// Presents the entry dialogs of the main window: the text prompt and the confirmations as sheets, the operator window
/// through `DialogPresenter`; an accepted EXIT quits.
struct EntryDialogPresenter: ViewModifier {
    let app: AppModel

    func body(content: Content) -> some View {
        let dialogs: DialogsModel = app.dialogs
        content
            // The sheets close only through the model (their buttons and keys), so SwiftUI's dismissal writes nothing
            // back (a submit already cleared the prompt, and a cancel there could hit a newer prompt).
            .sheet(item: Binding(get: { dialogs.textPrompt }, set: { _ in })) {
                TextPromptSheet(app: app, prompt: $0)
                    .id($0.id)
            }
            .sheet(isPresented: Binding(get: { dialogs.confirmation != nil }, set: { _ in })) {
                ConfirmSheet(app: app)
            }
            .onChange(of: dialogs.quitRequest) {
                AppQuit.request()
            }
    }
}
