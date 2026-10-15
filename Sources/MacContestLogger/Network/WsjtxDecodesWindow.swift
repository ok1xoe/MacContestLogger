import AppKit
import MCLAppModel
import MCLCore
import SwiftUI

/// The decodes window's own state (Kotlin `remember`; not saved): the filters.
@MainActor
final class WsjtxDecodesWindowState: ObservableObject {
    @Published var onlyCq: Bool = false
    @Published var hideDupes: Bool = true
    @Published var onlyMults: Bool = false
    @Published var text: String = ""
    @Published var sort: WsjtxDecodes.Sort = .time
}

/// Kotlin `WsjtxDecodesWindow` (`wsjtxdecodes` 640×460, `WsjtxDecodesWindow.kt:41-123`, N1MM Decode List): the decodes
/// of WSJT-X coloured like the band map (grey a dupe, blue a new QSO, red a multiplier, green several); a double click
/// calls the station through WSJT-X (a Reply to the instance that sent the decode), a single click does nothing.
struct WsjtxDecodesWindowView: View {
    static let id = "wsjtxdecodes"

    let host: AppHost

    @StateObject private var session = WindowSession(id: WsjtxDecodesWindowView.id, persistSize: true,
                                                     defaultSize: CGSize(width: 640, height: 460))
    @StateObject private var state = WsjtxDecodesWindowState()

    var body: some View {
        Group {
            if let app = host.model {
                content(app)
                    .modifier(RadioWindowChrome(host: host, app: app, id: Self.id, title: "WSJT-X dekódy",
                                                binder: session.binder))
            } else {
                Color.clear
            }
        }
        .frame(minWidth: 480, minHeight: 240)
    }

    private func content(_ app: AppModel) -> some View {
        let language: LanguageModel = app.language
        let integrations: IntegrationsModel = app.integrations
        let rows: [WsjtxDecodes.Row] = integrations.wsjtxDecodes.filtered(
            onlyCq: state.onlyCq, hideDupe: state.hideDupes, onlyMult: state.onlyMults, text: state.text,
            sort: state.sort)
        let instances: Bool = integrations.wsjtxStatuses.count > 1
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                NetworkChip(label: "Jen CQ", selected: state.onlyCq, identifier: "wsjtx.onlyCq") {
                    state.onlyCq.toggle()
                }
                NetworkChip(label: language.tr("Skrýt dupe"), selected: state.hideDupes,
                            identifier: "wsjtx.hideDupes") { state.hideDupes.toggle() }
                NetworkChip(label: language.tr("Jen násobiče"), selected: state.onlyMults,
                            identifier: "wsjtx.onlyMults") { state.onlyMults.toggle() }
                TextField(language.tr("Hledat v textu"), text: $state.text)
                    .textFieldStyle(.roundedBorder)
                    .windowFont(13)
                    .frame(width: 140)
                    .accessibilityIdentifier("wsjtx.text")
                Picker(selection: $state.sort) {
                    Text(verbatim: language.tr("Čas")).tag(WsjtxDecodes.Sort.time)
                    Text(verbatim: "SNR").tag(WsjtxDecodes.Sort.snr)
                    Text(verbatim: "Hz").tag(WsjtxDecodes.Sort.frequency)
                    Text(verbatim: language.tr("Volačka")).tag(WsjtxDecodes.Sort.call)
                } label: {
                    EmptyView()
                }
                .labelsHidden()
                .frame(width: 110)
                .accessibilityLabel(Text(verbatim: language.tr("Řazení")))
            }
            .trailingFontStepper(size: $session.fontSize, language: language)
            Text(verbatim: language.text(WsjtxDecodes.statusText(status: integrations.wsjtxStatus)))
                .windowFont(14, weight: .medium)
                .accessibilityIdentifier("wsjtx.status")
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        decodeRow(row, instances: instances)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { integrations.reply(to: row) }
                    }
                }
            }
            Text(verbatim: language.tr("Dvojklik na řádek zavolá stanici ve WSJT-X. Barvy jako v bandmapě."))
                .windowFont(10)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .environment(\.windowFontSize, session.fontSize)
    }

    private func decodeRow(_ row: WsjtxDecodes.Row, instances: Bool) -> some View {
        let text: WsjtxDecodes.RowText = WsjtxDecodes.rowText(row)
        let color: Color = Self.color(row)
        let scale: Double = Double(session.fontSize) / Double(WindowFont.defaultSize)
        return HStack(spacing: 8) {
            Text(verbatim: text.time).windowFont(13, design: .monospaced).frame(width: 70 * scale, alignment: .leading)
            Text(verbatim: text.snr).windowFont(13, design: .monospaced).frame(width: 40 * scale, alignment: .leading)
            Text(verbatim: text.deltaFrequency).windowFont(13, design: .monospaced)
                .frame(width: 50 * scale, alignment: .leading)
            // N1MM's Band/Mode column (and the instance with two WSJT-X).
            Text(verbatim: (row.band?.adif ?? "") + " " + row.modeName
                 + (instances ? " " + (row.decode.id ?? "") : ""))
                .windowFont(12, design: .monospaced)
                .foregroundStyle(.secondary)
                .frame(width: (instances ? 150 : 80) * scale, alignment: .leading)
            Text(verbatim: text.message)
                .windowFont(13, weight: row.parsed.cq ? .bold : .regular, design: .monospaced)
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: text.label).windowFont(12).foregroundStyle(color)
        }
        .padding(.vertical, 1)
    }

    /// Kotlin `decodeColor`: a message without a caller is grey text, otherwise the spot palette.
    static func color(_ row: WsjtxDecodes.Row) -> Color {
        if KotlinStrings.isBlank(row.parsed.caller) {
            return .secondary
        }
        let key: SpotColorClassifier.SpotColorKey = SpotColorClassifier.classify(dupe: row.dupe,
                                                                                 newMultCount: row.newMultCount)
        return Color(nsColor: SpotColors.color(key))
    }
}
