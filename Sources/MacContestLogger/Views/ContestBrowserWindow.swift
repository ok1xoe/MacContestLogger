import MCLAppModel
import MCLCore
import SwiftUI

/// Kotlin `ContestBrowser` (`contests` 620×520): the contests of the open database with their statistics; a row
/// opens the contest.
struct ContestBrowserWindowView: View {
    let host: AppHost

    var body: some View {
        DialogWindowView(host: host, dialog: .contests, padding: 10, title: { app in
            app.language.tr("Závody v databázi %s", .string(app.database.currentName))
        }) { app in
            ContestBrowserContent(app: app)
        }
    }
}

private struct ContestBrowserContent: View {
    let app: AppModel

    var body: some View {
        let dialogs: DialogsModel = app.dialogs
        let rows: [ContestBrowserRow] = dialogs.browserRows ?? []
        VStack(alignment: .leading, spacing: 0) {
            if dialogs.browserRows?.isEmpty == true {
                Text(verbatim: app.language.tr("Žádné uložené závody."))
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(rows, id: \.contestId) { row in
                        Button {
                            dialogs.openContest(row.contestId)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: ContestBrowserText.title(row))
                                    .windowFont(13, weight: .bold)
                                Text(verbatim: ContestBrowserText.detail(row))
                                    .windowFont(11)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 5)
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
                    dialogs.setOpen(.contests, false)
                }
            }
            .padding(.top, 6)
        }
        // Read once per opening (and again in another database), off the main thread — not on every redraw.
        .task(id: app.database.currentName) {
            await dialogs.loadBrowser()
        }
    }
}
