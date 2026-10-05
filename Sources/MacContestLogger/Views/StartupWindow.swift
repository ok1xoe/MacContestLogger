import MCLAppModel
import SwiftUI

/// Kotlin `StartupDialog` (`startup` 460×330): continue the last contest, a new one, open an existing one, close.
struct StartupWindowView: View {
    let host: AppHost

    var body: some View {
        DialogWindowView(host: host, dialog: .startup, padding: 12, title: { app in
            app.language.tr("Databáze: %s", .string(app.database.currentName))
        }) { app in
            StartupContent(app: app)
        }
    }
}

private struct StartupContent: View {
    let app: AppModel

    var body: some View {
        let dialogs: DialogsModel = app.dialogs
        let language: LanguageModel = app.language
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: language.tr("Vyber, jak pokračovat:"))
            VStack(spacing: 8) {
                // Continuing is the usual choice, so it is the prominent button.
                if let label = dialogs.startupLabel {
                    Button {
                        dialogs.continueLastContest()
                    } label: {
                        Text(verbatim: language.tr("Pokračovat: %s", .string(label)))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                Button {
                    dialogs.startupNewContest()
                } label: {
                    Text(verbatim: language.tr("Nový závod…"))
                        .frame(maxWidth: .infinity)
                }
                Button {
                    dialogs.startupOpenContest()
                } label: {
                    Text(verbatim: language.tr("Otevřít existující…"))
                        .frame(maxWidth: .infinity)
                }
            }
            .controlSize(.large)
            .padding(.top, 10)
            Spacer(minLength: 0)
            DialogButtonRow {
                Button(language.tr("Zavřít")) {
                    dialogs.setOpen(.startup, false)
                }
            }
        }
        // The label is read once per opening (and again in another database), off the main thread.
        .task(id: app.database.currentName) {
            await dialogs.loadStartup()
        }
    }
}
