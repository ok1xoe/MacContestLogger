import AppKit
import MCLAppModel
import MCLCore
import SwiftUI

/// Kotlin `OperatorDialog` (`operator` 400×230: with the font stepper): the operator at the key, typed
/// uppercase into one field that has the focus at once; „Uložit do nastavení stanice" also writes it into the station
/// settings. Enter logs in and Esc closes, on their release (Kotlin `KeyUp`).
struct OperatorWindowView: View {
    let host: AppHost

    var body: some View {
        DialogWindowView(host: host, dialog: .operatorLogin, padding: 10, title: { app in
            app.language.tr("Operátor u klíče")
        }) { app in
            OperatorContent(app: app)
        }
    }
}

private struct OperatorContent: View {
    let app: AppModel

    @StateObject private var form = DialogFormState()
    @StateObject private var keys = DialogKeyMonitor(escapeOnPress: false)
    @StateObject private var focusHolder = FocusHolder()

    var body: some View {
        let language: LanguageModel = app.language
        let dialogs: DialogsModel = app.dialogs
        VStack(alignment: .leading, spacing: 0) {
            WindowFontReader { size in
                // Its own focus registry: the key only focuses the field, the main window's routing never sees it.
                EntryTextField(key: .call, text: form.text, transform: .uppercase,
                               fontSize: WindowFont.size(14, windowSize: size),
                               accessibilityLabel: language.tr("Operátor u klíče"),
                               focus: focusHolder.controller) { form.text = $0 }
                    .frame(height: WindowFont.size(26, windowSize: size))
            }
            Toggle(isOn: $form.persist) {
                Text(verbatim: language.tr("Uložit do nastavení stanice"))
                    .windowFont(12)
            }
            .toggleStyle(.checkbox)
            .padding(.top, 8)
            Spacer(minLength: 0)
            DialogButtonRow {
                Button(language.tr("Zrušit")) {
                    dialogs.closeOperator()
                }
                Button(language.tr("Přihlásit")) {
                    dialogs.confirmOperator(call: form.text, persist: form.persist)
                }
            }
        }
        .background(WindowAccessor { window in
            keys.attach(window)
        })
        .onAppear {
            // Kotlin `remember` inside a window shown again: fresh state per opening.
            form.text = app.operating.operatorCall
            form.persist = false
            let form: DialogFormState = self.form
            keys.onEnter = { dialogs.confirmOperator(call: form.text, persist: form.persist) }
            keys.onEscape = { dialogs.closeOperator() }
            focusHolder.controller.focus(.call)
        }
        .onDisappear {
            keys.detach()
        }
    }
}
