import MCLAppModel
import MCLCore
import SwiftUI

/// Settings → DX Cluster → „Vybrat ze seznamu…" (N1MM's cluster list of the Telnet window): the public clusters of
/// the list the project publishes (`ClusterDirectory`), searchable and sortable; „Přidat" adds the chosen one as a
/// favorite that logs in with the station's callsign (applied with Save like every Settings change). The list is
/// read from disk; „Aktualizovat seznam z GitHubu" is the only thing that reaches the network.
struct ClusterChooserSheet: View {
    let app: AppModel
    @Binding var draft: ConfigurerDraft
    let onDone: () -> Void

    @StateObject private var fontSizeState = ViewState<Int>(WindowFont.defaultSize)
    @StateObject private var queryState = ViewState<String>("")
    @StateObject private var orderState = ViewState<ClusterDirectory.SortOrder>(.rating)
    @StateObject private var skimmersState = ViewState<Bool>(true)
    @StateObject private var selectedState = ViewState<String?>(nil)
    @StateObject private var noteState = ViewState<String>("")

    private var language: LanguageModel { app.language }
    private var model: ClusterDirectoryModel { app.dataTools.clusterDirectory }

    private var entries: [ClusterDirectory.Entry] {
        let all: [ClusterDirectory.Entry] = model.directory?.clusters ?? []
        return ClusterDirectory.sorted(
            ClusterDirectory.filter(all, query: queryState.value, skimmers: skimmersState.value), by: orderState.value)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WindowTopBar(size: $fontSizeState.value, language: language)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            VStack(alignment: .leading, spacing: 10) {
                Text(verbatim: language.tr("Vybrat cluster ze seznamu")).windowFont(15, weight: .semibold)
                controls
                list
                if let line = model.statusLine {
                    SettingsCaption(language.text(line))
                }
                updateLine
                if !noteState.value.isEmpty {
                    SettingsCaption(noteState.value)
                }
            }
            .padding(16)
            Divider()
            footer
        }
        .windowFont(13)
        .environment(\.windowFontSize, fontSizeState.value)
        .frame(width: 640)
        .frame(minHeight: 420, idealHeight: 560)
        .task { await model.load() }
    }

    private var controls: some View {
        HStack(alignment: .bottom, spacing: 8) {
            SettingsField(caption: language.tr("Hledat")) {
                SettingsTextField(text: $queryState.value)
            }
            .frame(maxWidth: .infinity)
            SettingsField(caption: language.tr("Řadit podle")) {
                SettingsDropdown(label: orderLabel(orderState.value), options: ClusterDirectory.SortOrder.allCases.map(orderLabel),
                                 language: language) { picked in
                    if let order = ClusterDirectory.SortOrder.allCases.first(where: { orderLabel($0) == picked }) {
                        orderState.value = order
                    }
                }
            }
            .frame(width: 160)
            Toggle(isOn: $skimmersState.value) {
                Text(verbatim: language.tr("Včetně skimmerů (RBN)")).windowFont(12)
            }
            .toggleStyle(.checkbox)
        }
    }

    private func orderLabel(_ order: ClusterDirectory.SortOrder) -> String {
        switch order {
        case .rating: return language.tr("Hodnocení")
        case .country: return language.tr("Země")
        case .name: return language.tr("Název")
        }
    }

    private var list: some View {
        let rows: [ClusterDirectory.Entry] = entries
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if rows.isEmpty {
                    Text(verbatim: language.tr("Žádný cluster neodpovídá."))
                        .foregroundStyle(.secondary)
                        .padding(12)
                }
                ForEach(rows) { entry in
                    row(entry)
                    Divider()
                }
            }
        }
        .frame(minHeight: 200, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.35), lineWidth: 1))
    }

    private func row(_ entry: ClusterDirectory.Entry) -> some View {
        let selected: Bool = selectedState.value == entry.id
        let title: String = [entry.name, entry.callsign == entry.name ? "" : entry.callsign]
            .filter { !$0.isEmpty }.joined(separator: " · ")
        let details: String = [entry.host + ":" + String(entry.port), entry.country, entry.location, entry.grid,
                               entry.software, entry.skimmer ? language.tr("skimmer") : "",
                               entry.rating.map { language.tr("hodnocení %s/5", .int($0)) } ?? ""]
            .filter { !$0.isEmpty }.joined(separator: " · ")
        var extra: [String] = []
        if !entry.login.isEmpty { extra.append(language.tr("Přihlášení: %s", .string(entry.login))) }
        if !entry.notes.isEmpty { extra.append(entry.notes) }
        if !entry.verified.isEmpty { extra.append(language.tr("ověřeno %s", .string(entry.verified))) }
        return VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: title).windowFont(13, weight: .semibold)
            Text(verbatim: details).windowFont(12, design: .monospaced)
            if !extra.isEmpty {
                Text(verbatim: extra.joined(separator: " · ")).windowFont(11).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? AnyShapeStyle(.tint.opacity(0.25)) : AnyShapeStyle(Color.clear))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { add(entry) }
        .onTapGesture { selectedState.value = entry.id }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private var updateLine: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                SettingsButton(language.tr("Aktualizovat seznam z GitHubu")) {
                    Task { await model.update() }
                }
                .disabled(model.updating)
                .accessibilityIdentifier("settings.dxcluster.directory.update")
                if let result = model.result {
                    SettingsCaption(language.text(result))
                }
            }
            SettingsCaption(language.tr(
                "Stáhne se jen po stisku tlačítka, z raw.githubusercontent.com (repozitář MacContestLogger)."))
        }
    }

    private var footer: some View {
        let chosen: ClusterDirectory.Entry? = entries.first { $0.id == selectedState.value }
        return HStack(spacing: 8) {
            SettingsButton(language.tr("Přidat do clusterů")) {
                if let chosen { add(chosen) }
            }
            .disabled(chosen == nil)
            .accessibilityIdentifier("settings.dxcluster.directory.add")
            Spacer(minLength: 0)
            Button(action: onDone) {
                Text(verbatim: language.tr("Zavřít"))
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.cancelAction)
        }
        .padding(12)
    }

    private func add(_ entry: ClusterDirectory.Entry) {
        if draft.addDxFavorite(from: entry) {
            noteState.value = language.tr("Přidáno: %s (uloží se tlačítkem Uložit)", .string(entry.name))
        } else {
            noteState.value = language.tr("%s už v seznamu clusterů je", .string(entry.host + ":" + String(entry.port)))
        }
    }
}
