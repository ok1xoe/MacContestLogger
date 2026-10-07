import MCLAppModel
import MCLCore
import SwiftUI

/// Kotlin `KeysTab` (`KT:45-109`, N1MM Key Mapper): every `ShortcutAction` with its keys (bold = remapped, red = in
/// conflict), „Změnit" waits for a new combination (Esc cancels, the window's `KeyCaptureMonitor` takes the keys),
/// „Výchozí" back to the N1MM key, „Žádná" no key, and „Vše na výchozí (N1MM)". The capture and its hint are the
/// tab's own state (Kotlin `remember`).
struct KeysTab: View {
    let app: AppModel
    @Binding var draft: ConfigurerDraft

    @EnvironmentObject private var keys: KeyCaptureMonitor
    @StateObject private var capturingState = ViewState<ShortcutAction?>(nil)
    private var capturing: ShortcutAction? {
        get { capturingState.value }
        nonmutating set { capturingState.value = newValue }
    }
    @StateObject private var hintState = ViewState<String>("")
    private var hint: String {
        get { hintState.value }
        nonmutating set { hintState.value = newValue }
    }

    private var language: LanguageModel { app.language }

    var body: some View {
        let rows: [KeyCaptureRules.Row] = KeyCaptureRules.rows(overrides: draft.keyOverrides)
        SettingsGroup(title: language.tr("Klávesové zkratky zadávacího okna")) {
            // A grid: the columns share their widths and shrink with the window (long labels wrap).
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 2) {
                GridRow {
                    Text(verbatim: "Akce")
                        .windowFont(12, weight: .bold)
                    Text(verbatim: language.tr("Klávesy"))
                        .windowFont(12, weight: .bold)
                    Color.clear
                        .gridCellUnsizedAxes([.horizontal, .vertical])
                        .gridCellColumns(3)
                }
                ForEach(rows, id: \.action) { row in
                    rowView(row)
                }
            }
            if !hint.isEmpty {
                SettingsText(hint, size: 12, isError: true)
                    .padding(.top, 4)
            }
            SettingsButton(language.tr("Vše na výchozí (N1MM)")) {
                KeyCaptureRules.resetAll(&draft.keyOverrides)
            }
            .padding(.top, 6)
            footnote
        }
        PluginKeysGroup(app: app)
            .padding(.top, 12)
            .onDisappear { keys.stopCapture() }
    }

    @ViewBuilder private func rowView(_ row: KeyCaptureRules.Row) -> some View {
        GridRow {
            SettingsText(row.action.label)
                .frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)
            keysCell(row)
                .frame(minWidth: 140, maxWidth: 170, alignment: .leading)
            SettingsButton(language.tr("Změnit"), borderless: true) { startCapture(row.action) }
                .fixedSize()
            SettingsButton(language.tr("Výchozí"), borderless: true) {
                KeyCaptureRules.resetToDefault(row.action, in: &draft.keyOverrides)
            }
            .fixedSize()
            .disabled(!row.isCustom)
            SettingsButton(language.tr("Žádná"), borderless: true) {
                KeyCaptureRules.setNone(row.action, in: &draft.keyOverrides)
            }
            .fixedSize()
        }
        if let conflict = row.conflictText {
            GridRow {
                SettingsText(conflict, size: 12, isError: true)
                    .gridCellColumns(5)
            }
        }
    }

    @ViewBuilder private func keysCell(_ row: KeyCaptureRules.Row) -> some View {
        if capturing == row.action {
            Text(verbatim: language.tr(SettingsTexts.capturePrompt))
                .windowFont(13)
                .foregroundStyle(.tint)
        } else {
            SettingsText(row.keys, weight: row.isCustom ? .bold : .regular, isError: !row.conflicts.isEmpty)
        }
    }

    private var footnote: some View {
        let first: String = language.tr(
            "Tučně = přemapováno. Při kolizi platí přemapovaná akce. Na Macu je Alt klávesa Option (⌥); ")
        let second: String = language.tr(
            "Skoky na spoty jsou na Cmd+↓/↑, protože Ctrl+šipky bere macOS pro Mission Control. ")
        let third: String = language.tr(
            "F1–F12 (zprávy), Enter, Esc, Tab, mezerník a šipky pro ladění se nepřemapovávají.")
        return SettingsCaption(first + second + third)
            .padding(.top, 4)
    }

    /// „Změnit": the next key press is captured for `action` (`KT:61-80`).
    private func startCapture(_ action: ShortcutAction) {
        capturing = action
        hint = ""
        keys.startCapture { result in
            switch result {
            case .cancelled:
                finishCapture()
            case .ignored:
                break
            case .accepted(let text):
                KeyCaptureRules.assign(text, to: action, in: &draft.keyOverrides)
                finishCapture()
            case .rejected(let key, let args):
                let values: [Translator.Arg] = args.map { .string($0) }
                hint = translate(key, values)
            }
        }
    }

    private func finishCapture() {
        capturing = nil
        hint = ""
        keys.stopCapture()
    }

    private func translate(_ key: String, _ args: [Translator.Arg]) -> String {
        guard let first = args.first else { return language.tr(key) }
        return language.tr(key, first)
    }
}
