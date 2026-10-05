import AppKit
import MCLAppModel
import SwiftUI

/// Kotlin `NewDatabaseDialog` (`db-new` 420×200).
struct NewDatabaseWindowView: View {
    let host: AppHost

    var body: some View {
        DialogWindowView(host: host, dialog: .databaseNew, padding: 10, title: { app in
            app.language.tr("Nová databáze")
        }) { app in
            NewDatabaseContent(app: app)
        }
    }
}

private struct NewDatabaseContent: View {
    let app: AppModel

    var body: some View {
        let dialogs: DialogsModel = app.dialogs
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: app.language.tr("Název databáze:"))
            TextField(text: Binding(get: { dialogs.newDatabaseName }, set: { dialogs.newDatabaseName = $0 })) {
                EmptyView()
            }
            .textFieldStyle(.roundedBorder)
            .padding(.top, 6)
            Spacer(minLength: 0)
            DialogButtonRow {
                Button(app.language.tr("Zrušit")) {
                    dialogs.setOpen(.databaseNew, false)
                }
                Button(app.language.tr("Založit")) {
                    dialogs.createDatabase()
                }
            }
        }
    }
}

/// Kotlin `OpenDatabaseDialog` (`db-open` 420×360).
struct OpenDatabaseWindowView: View {
    let host: AppHost

    var body: some View {
        DialogWindowView(host: host, dialog: .databaseOpen, padding: 10, title: { app in
            app.language.tr("Otevřít databázi")
        }) { app in
            OpenDatabaseContent(app: app)
        }
    }
}

private struct OpenDatabaseContent: View {
    let app: AppModel

    var body: some View {
        let dialogs: DialogsModel = app.dialogs
        let current: String = app.database.currentName
        let names: [String] = dialogs.databaseNames ?? []
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if dialogs.databaseNames?.isEmpty == true {
                        Text(verbatim: app.language.tr("Žádné databáze."))
                    }
                    ForEach(names, id: \.self) { name in
                        Button {
                            dialogs.openDatabase(name)
                        } label: {
                            Text(verbatim: name == current ? app.language.tr("%s  (aktuální)", .string(name)) : name)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
            }
            DialogButtonRow {
                Button(app.language.tr("Zavřít")) {
                    dialogs.setOpen(.databaseOpen, false)
                }
            }
            .padding(.top, 6)
        }
        // `DatabaseCatalog.list()` once per opening, off the main thread.
        .task(id: current) {
            await dialogs.loadDatabases()
        }
    }
}

/// Kotlin `FirstRunDatabaseDirDialog`: a dialog that cannot be dismissed without choosing (or creating) the
/// databases directory. An alert, so it is a sheet over the main window without the font stepper.
struct FirstRunDatabaseDirAlert: View {
    let app: AppModel

    var body: some View {
        let language: LanguageModel = app.language
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: language.tr("Adresář databází"))
                .font(.headline)
            Text(verbatim: language.tr("Vyber (nebo založ) adresář, kam se budou ukládat databázové soubory závodů. Vytvoří se v něm výchozí databáze „Deník“."))
                .fixedSize(horizontal: false, vertical: true)
            DialogButtonRow {
                Button(language.tr("Vybrat adresář…")) {
                    if let dir = DirectoryPanel.choose(title: language.tr("Adresář databází")) {
                        app.dialogs.chooseDatabasesDir(dir)
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 420)
        .interactiveDismissDisabled()
    }
}

/// Kotlin `chooseDirectory()` (AWT `FileDialog` with `apple.awt.fileDialogForDirectories`): `NSOpenPanel` for a
/// directory, which may also be created there.
@MainActor
enum DirectoryPanel {
    static func choose(title: String) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}
