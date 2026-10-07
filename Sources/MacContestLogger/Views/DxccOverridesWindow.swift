import MCLAppModel
import MCLCore
import SwiftUI

/// „Přiřadit volačku k zemi" (`dxcc-overrides` 620×640): the own call → DXCC entity list, asked before every other
/// DXCC source. Add a call and pick its country, remove an assignment; the QSOs already in the log change only through
/// „Přepočítat DXCC v deníku…", which the window offers.
struct DxccOverridesWindowView: View {
    let host: AppHost

    var body: some View {
        DialogWindowView(host: host, dialog: .dxccOverrides, padding: 10, title: { app in
            app.language.tr("Přiřadit volačku k zemi")
        }) { app in
            DxccOverridesContent(app: app)
        }
    }
}

private struct DxccOverridesContent: View {
    let app: AppModel

    var body: some View {
        if let model = app.dialogs.dxccOverrides {
            DxccOverridesForm(app: app, model: model)
        }
    }
}

private struct DxccOverridesForm: View {
    let app: AppModel
    let model: DxccOverridesModel

    var body: some View {
        let language: LanguageModel = app.language
        VStack(alignment: .leading, spacing: 8) {
            if !model.hasEngine {
                Text(verbatim: language.tr("Chybí data o zemích (~/dxcc-json)."))
                    .foregroundStyle(Color(domain: DomainColors.dupe))
            }
            Text(verbatim: language.tr("Volačka:"))
            TextField(text: Binding(get: { model.call }, set: { model.call = $0.uppercased() })) {
                Text(verbatim: language.tr("Volačka:"))
            }
            .textFieldStyle(.roundedBorder)
            Text(verbatim: language.tr("Země:"))
            TextField(text: Binding(get: { model.filter }, set: { model.filter = $0 })) {
                Text(verbatim: language.tr("Hledat zemi (název, prefix, číslo)"))
            }
            .textFieldStyle(.roundedBorder)
            List(model.shown, selection: Binding(get: { model.selected }, set: { model.selected = $0 })) { choice in
                Text(verbatim: choice.label)
            }
            .frame(minHeight: 140)
            DialogButtonRow {
                Button(language.tr("Přiřadit")) {
                    Task { await model.add() }
                }
                .disabled(!model.canAdd)
            }
            Divider()
            Text(verbatim: language.tr("Vlastní přiřazení:"))
                .windowFont(13, weight: .bold)
            if model.entries.isEmpty {
                Text(verbatim: language.tr("Žádná vlastní přiřazení."))
                    .foregroundStyle(.secondary)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(model.entries, id: \.call) { entry in
                        HStack {
                            Text(verbatim: entry.call + "  →  " + entry.name + " · " + String(entry.dxcc))
                            Spacer()
                            Button(language.tr("Odebrat")) {
                                Task { await model.remove(entry.call) }
                            }
                        }
                        .padding(.vertical, 3)
                        Divider()
                    }
                }
            }
            .frame(minHeight: 90)
            Text(verbatim: language.tr("Přiřazení platí pro další vyhledávání (nová spojení, spoty, přepočet). Spojení, která už jsou v deníku, si nechají dosavadní zemi, dokud nepřepočítáš DXCC v deníku."))
                .windowFont(11)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            DialogButtonRow {
                Button(language.tr("Přepočítat DXCC v deníku…")) {
                    ExportPanels.run(.confirmRefillDxcc(count: app.logbook.rows.count), app: app)
                }
                Button(language.tr("Zavřít")) {
                    app.dialogs.setOpen(.dxccOverrides, false)
                }
            }
        }
    }
}
