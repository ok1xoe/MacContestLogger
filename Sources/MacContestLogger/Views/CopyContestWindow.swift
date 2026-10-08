import MCLAppModel
import MCLCore
import SwiftUI

/// „Zkopírovat závod do jiné databáze" (`copy-contest` 520×330): a contest of the open database, or all of them,
/// copied with its QSOs into another database (existing or new). The open database is not changed.
struct CopyContestWindowView: View {
    let host: AppHost

    var body: some View {
        DialogWindowView(host: host, dialog: .copyContest, padding: 10, title: { app in
            app.language.tr("Zkopírovat závod do jiné databáze")
        }) { app in
            CopyContestContent(app: app)
        }
    }
}

private struct CopyContestContent: View {
    let app: AppModel

    var body: some View {
        if let model = app.dialogs.copyContest {
            CopyContestForm(app: app, model: model)
        }
    }
}

private struct CopyContestForm: View {
    let app: AppModel
    let model: CopyContestModel

    var body: some View {
        let language: LanguageModel = app.language
        let databases: [String] = model.databases ?? []
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: language.tr("Závod:"))
            Picker(selection: Binding(get: { model.selectedContest }, set: { model.selectedContest = $0 })) {
                Text(verbatim: language.tr("Všechny závody")).tag(String?.none)
                ForEach(model.contests ?? [], id: \.contestId) { row in
                    Text(verbatim: ContestBrowserText.title(row)).tag(Optional(row.contestId))
                }
            } label: {
                Text(verbatim: language.tr("Závod:"))
            }
            .labelsHidden()
            Text(verbatim: language.tr("Cílová databáze:"))
            if databases.isEmpty {
                Text(verbatim: language.tr("Žádná jiná databáze, zadej název nové."))
                    .foregroundStyle(.secondary)
            } else {
                Picker(selection: Binding(get: { model.targetExisting }, set: { model.targetExisting = $0 })) {
                    ForEach(databases, id: \.self) { name in
                        Text(verbatim: name).tag(name)
                    }
                } label: {
                    Text(verbatim: language.tr("Cílová databáze:"))
                }
                .labelsHidden()
            }
            Text(verbatim: language.tr("Nebo nová databáze (název):"))
            TextField(text: Binding(get: { model.newName }, set: { model.newName = $0 })) {
                Text(verbatim: language.tr("Nebo nová databáze (název):"))
            }
            .textFieldStyle(.roundedBorder)
            Text(verbatim: language.tr("Závod i jeho QSO se zkopírují beze změny, otevřená databáze zůstane jak je."))
                .windowFont(11)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            DialogButtonRow {
                Button(language.tr("Zrušit")) {
                    app.dialogs.setOpen(.copyContest, false)
                }
                Button(language.tr("Zkopírovat")) {
                    Task { await model.copy() }
                }
                .disabled(!model.canCopy)
            }
        }
        .task(id: app.database.currentName) {
            await model.load()
        }
    }
}
