import MCLAppModel
import MCLCore
import SwiftUI

/// The spot filter controls (N1MM-style "Bands/Modes" and "Filters" parts), shared by the DX Cluster window's
/// filter sheet (applies at once) and Settings → DX Cluster (applies with Save).
struct SpotFilterEditor: View {
    let language: LanguageModel
    @Binding var filter: SpotFilter
    var idPrefix: String = "spotfilter"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            bandRows
            Divider()
            modeRow
            Divider()
            SettingsCheckbox(label: language.tr("Jen pásma a módy aktivního závodu"), isOn: $filter.contestOnly)
                .accessibilityIdentifier("\(idPrefix).contest")
            Divider()
            originRow
            SettingsCheckbox(label: language.tr("Zobrazovat nepracovatelné spoty"),
                             isOn: Binding(get: { !filter.hideNonWorkable },
                                           set: { filter.hideNonWorkable = !$0 }))
                .accessibilityIdentifier("\(idPrefix).nonworkable")
            SettingsCaption(language.tr(
                "Nepracovatelný spot = pásmo nebo mód, který aktivní závod nepovoluje. Dupe se skrývají jen ručně."))
            SettingsCaption(language.tr(
                "Filtr se použije v okně DX Cluster (řádky spotů), v bandmapě, v Dostupných a při skoku na spot. Vlastní spoty se nikdy neskrývají."))
            HStack {
                SettingsButton(language.tr("Obnovit výchozí")) { filter.reset() }
                    .accessibilityIdentifier("\(idPrefix).reset")
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - bands

    private var bandRows: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: language.tr("Pásma")).windowFont(12, weight: .semibold)
            ForEach(SpotFilter.Group.allCases, id: \.self) { group in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    SettingsButton(group.rawValue) { filter.toggleGroup(group) }
                        .accessibilityLabel(language.tr("Přepnout skupinu pásem %s", .string(group.rawValue)))
                        .accessibilityIdentifier("\(idPrefix).group.\(group.rawValue)")
                    FlowLayout(spacing: 10) {
                        ForEach(group.bands, id: \.self) { band in
                            Toggle(isOn: Binding(get: { filter.isBandOn(band) },
                                                 set: { filter.setBand(band, on: $0) })) {
                                Text(verbatim: band.rawValue).windowFont(12)
                            }
                            .toggleStyle(.checkbox)
                            .accessibilityIdentifier("\(idPrefix).band.\(band.rawValue)")
                        }
                    }
                }
            }
        }
    }

    // MARK: - modes

    private var modeRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: language.tr("Módy")).windowFont(12, weight: .semibold)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                ForEach(SpotFilter.modes, id: \.self) { mode in
                    Toggle(isOn: Binding(get: { filter.isModeOn(mode) },
                                         set: { filter.setMode(mode, on: $0) })) {
                        Text(verbatim: modeLabel(mode)).windowFont(12)
                    }
                    .toggleStyle(.checkbox)
                    .accessibilityIdentifier("\(idPrefix).mode.\(mode)")
                }
                SettingsButton(language.tr("Všechny módy")) { filter.allModes() }
                    .accessibilityIdentifier("\(idPrefix).allmodes")
            }
            SettingsCaption(language.tr(
                "Spot s neurčitelným módem se zobrazí, pokud není vypnutý žádný mód. Digi zahrnuje RTTY, FT8, PSK…"))
        }
    }

    private func modeLabel(_ mode: String) -> String {
        switch mode {
        case SpotModeCategory.cw: "CW"
        case SpotModeCategory.phone: language.tr("Fonie")
        default: "Digi"
        }
    }

    // MARK: - spotter origin

    private var originRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: language.tr("Jen spoty od spotterů z")).windowFont(12, weight: .semibold)
            FlowLayout(spacing: 10) {
                ForEach(SpotFilter.continents, id: \.self) { code in
                    Toggle(isOn: Binding(get: { filter.spotterContinents.contains(code) },
                                         set: { filter.setContinent(code, on: $0) })) {
                        Text(verbatim: code).windowFont(12)
                    }
                    .toggleStyle(.checkbox)
                    .accessibilityIdentifier("\(idPrefix).origin.\(code)")
                }
                Toggle(isOn: $filter.spotterOwnCountry) {
                    Text(verbatim: language.tr("Vlastní země")).windowFont(12)
                }
                .toggleStyle(.checkbox)
                .accessibilityIdentifier("\(idPrefix).origin.own")
            }
            SettingsCaption(language.tr("Nic nezaškrtnuto = bez filtru. Skimmer spoty se řídí polohou skimmeru."))
        }
    }
}

/// The DX Cluster window's "Filtr spotů" sheet; every change applies and is saved at once.
struct SpotFilterSheet: View {
    let app: AppModel
    @ObservedObject var state: DxClusterWindowState

    var body: some View {
        let language: LanguageModel = app.language
        VStack(alignment: .leading, spacing: 8) {
            WindowTopBar(size: $state.sheetFontSize, language: language) {
                Text(verbatim: language.tr("Filtr spotů")).windowFont(15, weight: .semibold)
            }
            ScrollView {
                SpotFilterEditor(language: language,
                                 filter: Binding(get: { app.dxCluster.spotFilter },
                                                 set: { app.dxCluster.setSpotFilter($0) }))
                    .padding(.vertical, 4)
            }
            DialogButtonRow {
                Button(language.tr("Zavřít")) { state.showFilter = false }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 560, height: 520)
        .environment(\.windowFontSize, state.sheetFontSize)
    }
}
