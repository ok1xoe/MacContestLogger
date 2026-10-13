import MCLAppModel
import MCLCore
import SwiftUI

/// The band map's top bar (N1MM Logger+ Bandmap window): SH/DX, Wide/Narrow, CQ, the RIT offset (a click clears it),
/// the mode (a click picks another one) and the editor of the programmable buttons.
struct BandmapTopBar: View {
    let model: BandmapModel
    let language: LanguageModel

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            textButton("SH/DX", help: language.tr("Pošle SH/DX do DX clusteru"), id: "bandmap.shdx") {
                model.showDx()
            }
            textButton(filterLabel, help: language.tr("Přepne šířku filtru rigu (Wide/Narrow)"), id: "bandmap.filter") {
                model.toggleFilterWidth()
            }
            textButton("CQ", help: language.tr("Zpět na CQ frekvenci"), id: "bandmap.cq") {
                model.jumpToCq()
            }
            .disabled(!model.canJumpToCq)
            textButton(model.ritText, help: language.tr("Klik vynuluje RIT"), id: "bandmap.rit") {
                model.clearRit()
            }
            Menu {
                ForEach(BandmapModel.modeCommands, id: \.self) { mode in
                    Button(mode) { model.setMode(mode) }
                }
            } label: {
                Text(verbatim: model.modeText.isEmpty ? "–" : model.modeText)
                    .windowFont(12, design: .monospaced)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel(language.tr("Mód"))
            .accessibilityValue(model.modeText)
            .help(language.tr("Klik vybere mód"))
            .accessibilityIdentifier("bandmap.mode")
            Spacer(minLength: 0)
            IconButton(symbol: "slider.horizontal.3", label: language.tr("Uživatelská tlačítka…"),
                       size: CGSize(width: 24, height: 24), outlined: true) {
                model.editButtons()
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }

    private var filterLabel: String {
        switch model.filterIsNarrow {
        case true?: return "Narrow"
        case false?: return "Wide"
        case nil: return "Wide/Narrow"
        }
    }

    private func textButton(_ title: String, help: String, id: String,
                            action: @escaping @MainActor () -> Void) -> some View {
        Button {
            action()
        } label: {
            Text(verbatim: title).windowFont(12, design: .monospaced)
        }
        .help(help)
        .accessibilityHint(help)
        .accessibilityIdentifier(id)
    }
}

/// The programmable buttons in rows of four (N1MM: up to 36); a right click edits them.
struct BandmapButtonGrid: View {
    let model: BandmapModel
    let language: LanguageModel

    var body: some View {
        let count: Int = model.buttons.count
        if count > 0 {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 4) {
                ForEach(0..<count, id: \.self) { index in
                    Button {
                        model.pressButton(index)
                    } label: {
                        Text(verbatim: model.buttonLabel(index))
                            .windowFont(12)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                    }
                    .help("⌘⌥⇧" + BandmapModel.buttonKey(index))
                    .accessibilityIdentifier("bandmap.button.\(index)")
                    .contextMenu {
                        Button(language.tr("Upravit tlačítka…")) { model.editButtons(index) }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
        }
    }
}

/// One row of the editor.
private struct ButtonDraft: Identifiable {
    let id = UUID()
    var label: String
    var command: String
}

/// The editor of the programmable buttons: a label and a command per button, `|` between toggle states.
struct BandmapButtonsEditor: View {
    let model: BandmapModel
    let language: LanguageModel
    @Binding var fontSize: Int
    @State private var rows: [ButtonDraft] = []
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WindowTopBar(size: $fontSize, language: language) {
                Text(verbatim: language.tr("Uživatelská tlačítka bandmapy")).windowFont(15, weight: .semibold)
            }
            Text(verbatim: language.tr(
                "Popisek a příkaz; | odděluje přepínané stavy. Příkaz: {CAT příkaz rigctld}, {WIPE}, {RUN}, {S&P}, "
                    + "{CLEARRIT}, {CQFREQ}, {NOSPLIT}, {CLRSTACK} nebo textové příkazy pole volačky oddělené ; (CW, "
                    + "14025, SPLIT, RIT 100…). Tlačítko nikdy nevysílá."))
                .windowFont(11)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach($rows) { $row in
                        let index: Int = rows.firstIndex { $0.id == row.id } ?? 0
                        HStack(spacing: 6) {
                            Text(verbatim: BandmapModel.buttonKey(index))
                                .windowFont(12, design: .monospaced)
                                .frame(width: 18)
                                .accessibilityHidden(true)
                            TextField(text: $row.label) { Text(verbatim: language.tr("Popisek")) }
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 140)
                                .accessibilityLabel(language.tr("Popisek tlačítka %s",
                                                                .string(BandmapModel.buttonKey(index))))
                            TextField(text: $row.command) { Text(verbatim: language.tr("Příkaz")) }
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel(language.tr("Příkaz tlačítka %s",
                                                                .string(BandmapModel.buttonKey(index))))
                            IconButton(symbol: "trash", label: language.tr("Smazat"),
                                       size: CGSize(width: 24, height: 24), outlined: false) {
                                rows.removeAll { $0.id == row.id }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            HStack {
                Button(language.tr("Přidat tlačítko")) {
                    rows.append(ButtonDraft(label: "", command: ""))
                }
                .disabled(rows.count >= DxClusterConfig.bandmapButtonLimit)
                Spacer(minLength: 0)
                Button(language.tr("Zrušit")) { model.editingButtons = nil }
                    .keyboardShortcut(.cancelAction)
                Button(language.tr("Uložit")) {
                    model.saveButtons(rows.map { DxClusterCommand(label: $0.label, command: $0.command) })
                    model.editingButtons = nil
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 620, height: 520)
        .environment(\.windowFontSize, fontSize)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            rows = model.buttons.map { ButtonDraft(label: $0.label, command: $0.command) }
            if rows.isEmpty {
                rows = [ButtonDraft(label: "", command: "")]
            }
        }
    }
}
