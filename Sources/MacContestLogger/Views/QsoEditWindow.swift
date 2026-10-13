import AppKit
import MCLAppModel
import MCLCore
import SwiftUI

/// N1MM's Edit Contact dialog (Ctrl+Y, the Entry window's Edit button, Edit → Edit Current Contact): the fields of the
/// QSO, OK saves (Enter), Esc or „Zrušit" closes without a change.
struct QsoEditWindowView: View {
    let host: AppHost

    var body: some View {
        DialogWindowView(host: host, dialog: .qsoEdit, padding: 10, title: { app in
            app.dialogs.qsoEdit?.target == .current ? app.language.tr("Upravit rozpracované spojení")
                : app.language.tr("Upravit spojení")
        }) { app in
            if let model = app.dialogs.qsoEdit {
                QsoEditContent(app: app, model: model)
            }
        }
    }
}

private struct QsoEditContent: View {
    let app: AppModel
    @Bindable var model: QsoEditModel

    @StateObject private var keys = DialogKeyMonitor(escapeOnPress: true)

    var body: some View {
        let language: LanguageModel = app.language
        VStack(alignment: .leading, spacing: 8) {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                if model.editsLoggedQso {
                    row(language.tr("Čas UTC"), $model.form.time)
                }
                row(language.tr("Volačka"), uppercased(\.call))
                row(language.tr("Frekvence (kHz)"), $model.form.freqKHz)
                row(language.tr("Mód"), uppercased(\.mode))
                row(language.tr("RST tx"), $model.form.rstSent)
                if model.showsExchangeFields {
                    ForEach(Array(model.exchangeFields.enumerated()), id: \.offset) { index, field in
                        row(field.label, Binding(get: { model.exchangeFields[index].text },
                                                 set: { model.setExchangeField(index, $0) }))
                    }
                } else {
                    row(language.tr("RST rx"), $model.form.rstRcvd)
                    if model.editsLoggedQso {
                        row(language.tr("Nr tx"), $model.form.serialSent)
                        row(language.tr("Nr rx"), $model.form.serialRcvd)
                    }
                    row("Exchange", uppercased(\.exchange))
                }
                row(language.tr("Pozn."), $model.form.note)
                if model.editsLoggedQso {
                    row(language.tr("Operátor"), uppercased(\.operator))
                    GridRow {
                        Text(verbatim: "")
                        Toggle(isOn: $model.form.xqso) {
                            Text(verbatim: language.tr("X-QSO (nepočítá se)"))
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }
            if let problem = model.problem {
                Text(verbatim: language.text(problem))
                    .foregroundStyle(Color(domain: DomainColors.dupe))
                    .accessibilityIdentifier("qsoEdit.problem")
            }
            Spacer(minLength: 0)
            DialogButtonRow {
                Button(language.tr("Zrušit")) {
                    model.cancel()
                }
                Button(language.tr("Uložit")) {
                    model.save()
                }
            }
        }
        .background(WindowAccessor { window in
            keys.attach(window)
        })
        .onAppear {
            let model: QsoEditModel = self.model
            keys.onEnter = { model.save() }
            keys.onEscape = { model.cancel() }
        }
        .onDisappear {
            keys.detach()
        }
    }

    private func uppercased(_ path: WritableKeyPath<QsoEditForm, String>) -> Binding<String> {
        let model: QsoEditModel = self.model
        return Binding(get: { model.form[keyPath: path] },
                       set: { model.form[keyPath: path] = KotlinStrings.uppercase($0) })
    }

    private func row(_ label: String, _ text: Binding<String>) -> some View {
        GridRow {
            Text(verbatim: label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            TextField(text: text) {
                Text(verbatim: label)
            }
            .textFieldStyle(.roundedBorder)
            .windowFont(13, design: .monospaced)
            .accessibilityLabel(Text(verbatim: label))
        }
    }
}
