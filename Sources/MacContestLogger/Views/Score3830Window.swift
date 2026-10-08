import AppKit
import MCLAppModel
import MCLCore
import SwiftUI

/// „Odeslat výsledek na 3830" (`score-3830` 560×560): the lines of the 3830scores.com score form for the active
/// contest, an editable soapbox, „Zkopírovat" and „Otevřít 3830scores.com". Nothing is posted and no credentials are
/// kept (the site has no API and no documented way to prefill its forms).
struct Score3830WindowView: View {
    let host: AppHost

    var body: some View {
        DialogWindowView(host: host, dialog: .score3830, padding: 10, title: { app in
            app.language.tr("Odeslat výsledek na 3830")
        }) { app in
            Score3830Content(app: app)
        }
    }
}

private struct Score3830Content: View {
    let app: AppModel

    var body: some View {
        if let model = app.dialogs.score3830 {
            Score3830Form(app: app, model: model)
        }
    }
}

private struct Score3830Form: View {
    let app: AppModel
    let model: ScoreSubmitModel

    var body: some View {
        let language: LanguageModel = app.language
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: language.tr("Údaje pro formulář 3830scores.com:"))
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(model.submission.lines.enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .top) {
                            Text(verbatim: line.label)
                                .foregroundStyle(.secondary)
                                .frame(width: 150, alignment: .leading)
                            Text(verbatim: line.value)
                                .textSelection(.enabled)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 150)
            Text(verbatim: language.tr("Soapbox:"))
            TextEditor(text: Binding(get: { model.soapbox }, set: { model.soapbox = $0 }))
                .frame(minHeight: 70)
                .border(Color.secondary.opacity(0.4))
            Text(verbatim: language.tr("3830scores.com má pro každý závod vlastní formulář, který nejde předvyplnit, a žádné API: otevři web, vyber formulář závodu v levém menu a vlož zkopírované údaje. MCL nic neodesílá a neukládá žádné přihlašovací údaje."))
                .windowFont(11)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            DialogButtonRow {
                Button(language.tr("Zavřít")) {
                    app.dialogs.setOpen(.score3830, false)
                }
                Button(language.tr("Zkopírovat")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.text, forType: .string)
                    app.status.show("Údaje pro 3830 zkopírovány do schránky")
                }
                Button(language.tr("Otevřít 3830scores.com")) {
                    model.openSite()
                }
            }
        }
    }
}
