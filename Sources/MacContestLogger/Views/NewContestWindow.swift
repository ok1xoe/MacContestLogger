import MCLAppModel
import MCLCore
import SwiftUI

/// Kotlin `NewContestWindow` (`DialogWindow` 760×900, geometry not saved): the contest from the definitions
/// directory, the Cabrillo categories, the sent exchange, operators, soapbox and the UTC start/end. OK remembers the
/// setup for the definition and starts the contest.
///
/// Kotlin literals without `tr` („Kategorie", „Operators", „Soapbox", „Datum (UTC)", „Konec", „OK" and the category
/// labels of `CategoryCatalog`) are translated here.
struct NewContestWindowView: View {
    let host: AppHost

    var body: some View {
        DialogWindowView(host: host, dialog: .newContest, padding: 0, title: { app in
            app.language.tr("Nový závod")
        }) { app in
            if let form = app.dialogs.newContest {
                NewContestContent(app: app, form: form)
            }
        }
    }
}

private struct NewContestContent: View {
    let app: AppModel
    let form: NewContestModel

    private var language: LanguageModel { app.language }

    var body: some View {
        if form.contests.isEmpty {
            Text(verbatim: language.tr("Žádné závody. Nastav adresář v Nastavení → Nastavení dat závodů."))
                .padding(16)
            Spacer(minLength: 0)
        } else {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        contestGroup
                        categoryGroup
                        if !form.sentFieldIds.isEmpty {
                            sentGroup
                        }
                        otherGroup
                        dateGroup
                    }
                    .padding(16)
                }
                Divider()
                HStack(spacing: 8) {
                    Button(language.tr("OK")) {
                        app.dialogs.confirmNewContest()
                    }
                    .buttonStyle(.borderedProminent)
                    Button(language.tr("Zrušit")) {
                        app.dialogs.setOpen(.newContest, false)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(12)
            }
        }
    }

    private var contestGroup: some View {
        FormGroup(title: language.tr("Závod")) {
            Text(verbatim: language.tr(
                "Vyber závod z adresáře definic. Formulář níže se sestaví podle jeho konfigurace."))
                .windowFont(11)
                .foregroundStyle(.secondary)
            OptionMenu(value: form.selectedLabel, options: form.labels.map(\.text)) { label in
                form.select(label: label)
            }
        }
    }

    private var categoryGroup: some View {
        let fixed: [CategoryCatalog.CategoryDim] = form.fixedCategories
        let pairs: [[CategoryCatalog.CategoryDim]] = stride(from: 0, to: fixed.count, by: 2).map { start in
            Array(fixed[start..<min(start + 2, fixed.count)])
        }
        return FormGroup(title: language.tr("Kategorie")) {
            ForEach(pairs.indices, id: \.self) { index in
                let pair: [CategoryCatalog.CategoryDim] = pairs[index]
                FormRow2(left: categoryCell(pair[0]), right: pair.count > 1 ? categoryCell(pair[1]) : nil)
            }
            FormRow2(
                left: FormCell(label: language.tr("Pásmo"), control: AnyView(
                    OptionMenu(value: form.category("BAND"), options: form.bandOptions) { value in
                        form.setCategory("BAND", value)
                    })),
                right: FormCell(label: language.tr("Mód"), control: AnyView(
                    OptionMenu(value: form.category("MODE"), options: form.modeOptions) { value in
                        form.setCategory("MODE", value)
                    }
                    .disabled(form.modeOptions.isEmpty))))
        }
    }

    private func categoryCell(_ dim: CategoryCatalog.CategoryDim) -> FormCell {
        FormCell(label: language.tr(dim.label), control: AnyView(
            OptionMenu(value: form.category(dim.key), options: dim.options) { value in
                form.setCategory(dim.key, value)
            }))
    }

    private var sentGroup: some View {
        let ids: [String] = form.sentFieldIds
        let pairs: [[String]] = stride(from: 0, to: ids.count, by: 2).map { start in
            Array(ids[start..<min(start + 2, ids.count)])
        }
        return FormGroup(title: language.tr("Odesílaná výměna")) {
            ForEach(pairs.indices, id: \.self) { index in
                let pair: [String] = pairs[index]
                FormRow2(left: sentCell(pair[0]), right: pair.count > 1 ? sentCell(pair[1]) : nil)
            }
        }
    }

    private func sentCell(_ id: String) -> FormCell {
        FormCell(label: id, control: AnyView(
            TextField(text: Binding(get: { form.sent(id) }, set: { form.setSent(id, $0) })) { EmptyView() }
                .textFieldStyle(.roundedBorder)))
    }

    private var otherGroup: some View {
        FormGroup(title: language.tr("Ostatní")) {
            HStack(spacing: 12) {
                Text(verbatim: language.tr("Operators"))
                    .frame(width: 140, alignment: .leading)
                TextField(text: Binding(get: { form.form.operators }, set: { form.form.operators = $0 })) {
                    EmptyView()
                }
                .textFieldStyle(.roundedBorder)
            }
            Text(verbatim: language.tr("Soapbox"))
                .windowFont(11)
                .foregroundStyle(.secondary)
            TextEditor(text: Binding(get: { form.form.soapbox }, set: { form.form.soapbox = $0 }))
                .frame(height: 120)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.4)))
        }
    }

    private var dateGroup: some View {
        FormGroup(title: language.tr("Datum (UTC)")) {
            Text(verbatim: language.tr("Časy jsou v UTC."))
                .windowFont(11)
                .foregroundStyle(.secondary)
            FormRow2(
                left: FormCell(label: language.tr("Začátek"), control: AnyView(
                    DateTimeField(form: form, value: Binding(get: { form.form.startedAt },
                                                             set: { form.form.startedAt = $0 })))),
                right: FormCell(label: language.tr("Konec"), control: AnyView(
                    DateTimeField(form: form, value: Binding(get: { form.form.endedAt },
                                                             set: { form.form.endedAt = $0 })))))
        }
    }
}

/// Kotlin `Grp`: a titled group.
private struct FormGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text(verbatim: title)
                .windowFont(13, weight: .semibold)
        }
    }
}

/// A label and its control (one half of Kotlin `FormRow2`).
private struct FormCell {
    let label: String
    let control: AnyView
}

/// Kotlin `FormRow2`: two label + control pairs in one row; the right one is optional.
private struct FormRow2: View {
    let left: FormCell
    let right: FormCell?

    var body: some View {
        HStack(spacing: 16) {
            cell(left)
            if let right {
                cell(right)
            } else {
                Spacer(minLength: 0)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func cell(_ cell: FormCell) -> some View {
        HStack(spacing: 12) {
            Text(verbatim: cell.label)
                .frame(width: 100, alignment: .leading)
            cell.control
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Kotlin `KitDropdown`: shows the current value (even one that is not among the options) and offers the options.
private struct OptionMenu: View {
    let value: String
    let options: [String]
    let onSelect: (String) -> Void

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button {
                    onSelect(option)
                } label: {
                    Text(verbatim: option)
                }
            }
        } label: {
            Text(verbatim: value)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Kotlin `DateTimeField`: the date (a picker over UTC days) and an `HH:mm` field.
private struct DateTimeField: View {
    let form: NewContestModel
    @Binding var value: String

    private static let utc: TimeZone = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0) ?? .current
    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar
    }()

    var body: some View {
        HStack(spacing: 8) {
            DatePicker(selection: Binding(get: { form.pickerDate(value) },
                                          set: { value = form.withDate(value, date: $0) }),
                       displayedComponents: .date) {
                EmptyView()
            }
            .labelsHidden()
            .environment(\.timeZone, Self.utc)
            .environment(\.calendar, Self.utcCalendar)
            TextField(text: Binding(get: { form.timePart(value) },
                                    set: { value = form.withTime(value, time: $0) })) {
                EmptyView()
            }
            .textFieldStyle(.roundedBorder)
            .frame(width: 80)
        }
    }
}
