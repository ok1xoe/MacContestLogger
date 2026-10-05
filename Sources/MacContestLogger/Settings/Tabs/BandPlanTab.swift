import MCLAppModel
import MCLCore
import SwiftUI

/// Kotlin `BandPlanTab` (`BP:47-102`): the mode segments of one region (chips R1–R3), each row with its mode chips,
/// from–to kHz and „překryv!" when it overlaps another segment of the region, plus the band map shading option.
struct BandPlanTab: View {
    let app: AppModel
    @Binding var draft: ConfigurerDraft

    @StateObject private var regionState = ViewState<String>("R1")
    private var region: String {
        get { regionState.value }
        nonmutating set { regionState.value = newValue }
    }

    private var language: LanguageModel { app.language }

    var body: some View {
        let rows: [BandSegmentDraft] = draft.bandSegments
        let inRegion: [Int] = rows.indices.filter { rows[$0].region == region }
        let anyOverlap: Bool = inRegion.contains { BandPlanOverlap.overlaps(rows, $0) }
        SettingsGroup(title: language.tr("Bandplán — segmenty módů (kHz), region %s", .string(region))) {
            HStack(spacing: 6) {
                ForEach(ConfigurerCatalogs.regions, id: \.self) { name in
                    SettingsChip(label: name, selected: region == name) { region = name }
                }
            }
            header
            ForEach($draft.bandSegments) { $segment in
                if segment.region == region {
                    SegmentRow(language: language, segment: $segment,
                               overlap: overlaps(segment.id, rows)) {
                        draft.bandSegments.removeAll { $0.id == segment.id }
                    }
                }
            }
            SettingsButton(language.tr("Přidat segment")) {
                draft.bandSegments.append(BandSegmentDraft(region: region, mode: "CW", fromKhz: 0, toKhz: 0))
            }
            .padding(.top, 4)
            SettingsCheckbox(label: language.tr("Podbarvit úseky v bandmapě (proužek u osy)"),
                             isOn: $draft.showBandPlan)
                .padding(.top, 4)
            if anyOverlap {
                SettingsText(language.tr(
                    "Některé segmenty se překrývají — mód na překryvu by byl nejednoznačný. Uprav rozsahy."),
                             size: 12, isError: true)
                    .padding(.top, 4)
            }
            SettingsCaption(language.tr(
                "Pozn.: v jednom regionu může být víc segmentů stejného módu, jen se nesmí krýt."))
                .padding(.top, 4)
        }
    }

    private func overlaps(_ id: UUID, _ rows: [BandSegmentDraft]) -> Bool {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return false }
        return BandPlanOverlap.overlaps(rows, index)
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text(verbatim: language.tr("Mód"))
                .windowFont(12, weight: .bold)
                .frame(width: 210, alignment: .leading)
            Text(verbatim: "Od (kHz)")
                .windowFont(12, weight: .bold)
                .frame(width: 90, alignment: .leading)
            Text(verbatim: "Do (kHz)")
                .windowFont(12, weight: .bold)
                .frame(width: 90, alignment: .leading)
        }
        .padding(.top, 6)
    }
}

private struct SegmentRow: View {
    let language: LanguageModel
    @Binding var segment: BandSegmentDraft
    let overlap: Bool
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(ConfigurerCatalogs.bandPlanModes, id: \.self) { mode in
                    SettingsChip(label: mode, selected: segment.mode == mode) { segment.mode = mode }
                }
            }
            .frame(width: 210, alignment: .leading)
            SettingsTextField(text: $segment.fromKhz)
                .frame(width: 84)
            SettingsTextField(text: $segment.toKhz)
                .frame(width: 78)
                .padding(.leading, 6)
            if overlap {
                SettingsText(language.tr("překryv!"), size: 11, isError: true)
                    .padding(.leading, 6)
            }
            SettingsDeleteButton(help: "Smazat segment", action: onDelete)
                .padding(.leading, 6)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}
