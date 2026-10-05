import AppKit
import MCLAppModel
import MCLCore
import SwiftUI

/// The window's own state (Kotlin `remember`): the tab and the „add" sheet.
@MainActor
final class BlacklistWindowState: ObservableObject {
    @Published var callTab: Bool = true
    @Published var adding: Bool = false
    @Published var addValue: String = ""
    @Published var addNote: String = ""
    @Published var sheetFontSize: Int = WindowFont.defaultSize
}

/// Kotlin `BlacklistWindow` (`blacklist` 640×480, `BlacklistWindow.kt:38-117`): two lists (Volačky / Spotteři) as a
/// table — the value and the note editable in their cells (saved when the focus leaves), the time added, delete — and
/// an add button that opens a sheet.
struct BlacklistWindowView: View {
    static let id = "blacklist"

    let host: AppHost

    @StateObject private var session = WindowSession(id: BlacklistWindowView.id, persistSize: true,
                                                     defaultSize: CGSize(width: 640, height: 480))
    @StateObject private var state = BlacklistWindowState()

    var body: some View {
        Group {
            if let app = host.model {
                content(app)
                    .modifier(RadioWindowChrome(host: host, app: app, id: Self.id, title: "Blacklist",
                                                binder: session.binder))
            } else {
                Color.clear
            }
        }
        .frame(minWidth: 420, minHeight: 240)
    }

    private func content(_ app: AppModel) -> some View {
        let language: LanguageModel = app.language
        let model: BlacklistModel = app.blacklist
        let isCall: Bool = state.callTab
        _ = model.revision
        let entries: [BlacklistEntry] = model.entries(isCall: isCall)
        return VStack(alignment: .leading, spacing: 0) {
            WindowTopBar(size: $session.fontSize, language: language)
                .padding(.horizontal, 8)
                .padding(.top, 4)
            tabs(language)
            summary(language: language, count: entries.count, isCall: isCall)
            Divider()
            header(language: language, isCall: isCall)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                        BlacklistRow(language: language, model: model, entry: entry, isCall: isCall,
                                     fontSize: WindowFont.size(13, windowSize: session.fontSize))
                        Divider()
                    }
                }
            }
        }
        .environment(\.windowFontSize, session.fontSize)
        .sheet(isPresented: Binding(get: { state.adding }, set: { state.adding = $0 })) {
            BlacklistAddSheet(language: language, model: model, state: state)
        }
    }

    private func tabs(_ language: LanguageModel) -> some View {
        Picker(selection: Binding(get: { state.callTab }, set: { state.callTab = $0 })) {
            Text(verbatim: language.tr("Volačky")).tag(true)
            Text(verbatim: language.tr("Spotteři")).tag(false)
        } label: {
            EmptyView()
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }

    /// `"${n} záznamů — ${volačky|spotteři}"` (the first part is not translated in Kotlin) and the add button.
    private func summary(language: LanguageModel, count: Int, isCall: Bool) -> some View {
        HStack(alignment: .center) {
            Text(verbatim: "\(count) záznamů — " + (isCall ? language.tr("volačky") : language.tr("spotteři")))
                .windowFont(13)
            Spacer(minLength: 0)
            IconButton(symbol: "plus", label: language.tr("Přidat na blacklist"), size: CGSize(width: 28, height: 28)) {
                state.addValue = ""
                state.addNote = ""
                state.sheetFontSize = session.fontSize
                state.adding = true
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("blacklist.add")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func header(language: LanguageModel, isCall: Bool) -> some View {
        GeometryReader { proxy in
            let widths: [CGFloat] = BlacklistRow.widths(total: proxy.size.width)
            HStack(spacing: 0) {
                head(isCall ? language.tr("Volačka") : "Spotter", widths[0])
                head(language.tr("Přidáno"), widths[1])
                head(language.tr("Poznámka"), widths[2])
                head("Akce", widths[3])
            }
        }
        .frame(height: WindowFont.size(22, windowSize: session.fontSize))
        .padding(.horizontal, 8)
    }

    private func head(_ title: String, _ width: CGFloat) -> some View {
        Text(verbatim: title)
            .windowFont(11, weight: .bold)
            .frame(width: width, alignment: .leading)
    }
}

/// One entry: the value and the note edited in their cells, the time added, delete.
private struct BlacklistRow: View {
    let language: LanguageModel
    let model: BlacklistModel
    let entry: BlacklistEntry
    let isCall: Bool
    let fontSize: CGFloat

    /// Kotlin weights 1.2 / 1.3 / 2 / 1.4 of the width minus the 8 pt paddings.
    static func widths(total: CGFloat) -> [CGFloat] {
        let usable: CGFloat = Swift.max(total - 16, 0)
        return [1.2, 1.3, 2, 1.4].map { usable * $0 / 5.9 }
    }

    var body: some View {
        GeometryReader { proxy in
            let widths: [CGFloat] = Self.widths(total: proxy.size.width)
            HStack(spacing: 0) {
                CommitTextField(value: entry.value, fontSize: fontSize, bold: true,
                                accessibilityLabel: isCall ? language.tr("Volačka") : "Spotter") { new in
                    model.updateValue(isCall: isCall, oldValue: entry.value, newValue: new)
                }
                .frame(width: widths[0] - 8, alignment: .leading)
                .padding(.trailing, 8)
                Text(verbatim: ClusterTexts.fmtAdded(entry.addedAtUtc))
                    .windowFont(11)
                    .frame(width: widths[1], alignment: .leading)
                CommitTextField(value: entry.note, placeholder: "—", fontSize: fontSize,
                                accessibilityLabel: language.tr("Poznámka")) { new in
                    model.setNote(isCall: isCall, value: entry.value, note: new)
                }
                .frame(width: widths[2] - 8, alignment: .leading)
                .padding(.trailing, 8)
                HStack {
                    IconButton(symbol: "trash", label: language.tr("Smazat"), size: CGSize(width: 32, height: 32)) {
                        model.remove(isCall: isCall, value: entry.value)
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 0)
                }
                .frame(width: widths[3])
            }
            .padding(.horizontal, 8)
        }
        .frame(height: fontSize * 2.4)
    }
}

/// Kotlin `AddDialog`: the value (the call or the spotter) and a note; „Přidat" needs a non-blank value.
struct BlacklistAddSheet: View {
    let language: LanguageModel
    let model: BlacklistModel
    @ObservedObject var state: BlacklistWindowState

    var body: some View {
        let state: BlacklistWindowState = self.state
        let isCall: Bool = state.callTab
        VStack(alignment: .leading, spacing: 8) {
            WindowTopBar(size: $state.sheetFontSize, language: language) {
                Text(verbatim: "Přidat " + (isCall ? language.tr("volačku") : "spottera") + " na blacklist")
                    .windowFont(15, weight: .semibold)
            }
            field(isCall ? language.tr("Volačka") : "Spotter", text: $state.addValue)
            field(language.tr("Poznámka"), text: $state.addNote)
            DialogButtonRow {
                Button(language.tr("Zrušit")) {
                    state.adding = false
                }
                Button(language.tr("Přidat")) {
                    model.add(isCall: isCall, value: state.addValue, note: state.addNote)
                    state.adding = false
                }
                .disabled(KotlinStrings.isBlank(state.addValue))
            }
        }
        .padding(16)
        .frame(width: 420)
        .environment(\.windowFontSize, state.sheetFontSize)
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: title).windowFont(11).foregroundStyle(.secondary)
            TextField(text: text) {
                Text(verbatim: "")
            }
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .windowFont(13)
            .accessibilityLabel(title)
        }
    }
}
