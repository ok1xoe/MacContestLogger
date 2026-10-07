import MCLAppModel
import MCLCore
import SwiftUI

/// „Export ADIF podle data" (`adif-range` 460×300): the first and last UTC day of the ADIF to write, with the number of
/// QSOs of the open log in it. „Exportovat…" asks for the file.
struct AdifRangeWindowView: View {
    let host: AppHost

    var body: some View {
        DialogWindowView(host: host, dialog: .adifRange, padding: 10, title: { app in
            app.language.tr("Export ADIF podle data")
        }) { app in
            AdifRangeContent(app: app)
        }
    }
}

private struct AdifRangeContent: View {
    let app: AppModel

    var body: some View {
        if let model = app.dialogs.adifRange {
            AdifRangeForm(app: app, model: model)
        }
    }
}

private struct AdifRangeForm: View {
    let app: AppModel
    let model: AdifRangeModel

    /// The days are UTC days: the picker shows and edits them in UTC whatever the Mac's zone is.
    private static let utc: TimeZone = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0)!

    var body: some View {
        let language: LanguageModel = app.language
        VStack(alignment: .leading, spacing: 10) {
            DatePicker(selection: Binding(get: { model.first }, set: { model.first = $0 }),
                       displayedComponents: .date) {
                Text(verbatim: language.tr("Od (UTC):"))
            }
            DatePicker(selection: Binding(get: { model.last }, set: { model.last = $0 }),
                       displayedComponents: .date) {
                Text(verbatim: language.tr("Do (UTC):"))
            }
            if model.range == nil {
                Text(verbatim: language.tr("Konec je před začátkem."))
                    .foregroundStyle(Color(domain: DomainColors.dupe))
            } else {
                Text(verbatim: language.tr("QSO v období: %s", .int(model.qsoCount)))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            DialogButtonRow {
                Button(language.tr("Zrušit")) {
                    app.dialogs.setOpen(.adifRange, false)
                }
                Button(language.tr("Exportovat…")) {
                    guard let range = model.range else { return }
                    let name: String = model.suggestedName
                    app.dialogs.setOpen(.adifRange, false)
                    ExportPanels.run(.saveAdifRange(suggestedName: name, range: range), app: app)
                }
                .disabled(!model.canExport)
            }
        }
        .environment(\.timeZone, Self.utc)
        .environment(\.calendar, {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = Self.utc
            return calendar
        }())
    }
}
