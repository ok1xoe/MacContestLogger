import MCLAppModel
import MCLCore
import SwiftUI

/// The result of a manual callbook lookup from the log or band map menu (`callbook-result`): call, service, name,
/// country, locator and zones, or why nothing was found, and „Otevřít na webu". Read-only: nothing is written to the
/// logbook.
struct CallbookResultWindowView: View {
    let host: AppHost

    var body: some View {
        DialogWindowView(host: host, dialog: .callbookResult, padding: 12, title: { app in
            app.language.tr("Dohledání volačky")
        }) { app in
            CallbookResultContent(app: app)
        }
    }
}

private struct CallbookResultContent: View {
    let app: AppModel

    var body: some View {
        let language: LanguageModel = app.language
        VStack(alignment: .leading, spacing: 8) {
            if let result = app.callbook.windowLookup {
                Text(verbatim: result.call + " — " + result.service.displayName)
                    .windowFont(16, weight: .bold)
                    .accessibilityIdentifier("callbookResult.title")
                body(result, language)
            } else {
                Text(verbatim: language.tr("Dohledávám…"))
                    .windowFont(13)
            }
            Spacer(minLength: 0)
            DialogButtonRow {
                if let result = app.callbook.windowLookup {
                    Button(language.tr("Otevřít na webu")) { app.callbook.openOnWeb(result) }
                        .accessibilityIdentifier("callbookResult.open")
                }
                Button(language.tr("Zavřít")) { app.dialogs.setOpen(.callbookResult, false) }
            }
        }
    }

    @ViewBuilder
    private func body(_ result: ManualLookupResult, _ language: LanguageModel) -> some View {
        switch result.state {
        case .loading:
            Text(verbatim: language.tr("Dohledávám…"))
                .windowFont(13)
        case .found(let record, let country):
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                row(language.tr("Jméno"), record.name)
                row(language.tr("Země"), country ?? "")
                row(language.tr("Lokátor"), record.grid)
                row(language.tr("CQ zóna"), record.cqZone)
                row(language.tr("ITU zóna"), record.ituZone)
            }
        default:
            Text(verbatim: result.problem.map { language.text($0) } ?? "")
                .windowFont(13)
                .foregroundStyle(.red)
                .accessibilityIdentifier("callbookResult.problem")
        }
    }

    private func row(_ caption: String, _ value: String) -> some View {
        GridRow {
            Text(verbatim: caption)
                .windowFont(13)
                .foregroundStyle(.secondary)
            Text(verbatim: value.isEmpty ? "—" : value)
                .windowFont(13, weight: .medium)
                .textSelection(.enabled)
        }
    }
}
