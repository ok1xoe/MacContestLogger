import AppKit
import MCLAppModel
import MCLCore
import SwiftUI

/// The raw telnet console of the DX Cluster window (an AppKit island, `NSTextView`): the traffic log's
/// lines in a fixed 12 pt monospaced font (Kotlin `fontSize = 12.sp`, not scaled by the stepper), selectable and
/// scrolled to the last line whenever they change. A change that only appends lines (and drops the oldest at the
/// log's cap) edits the text storage by range (`ConsoleDiff`); only a clear or an unrelated log rebuilds it.
struct DxClusterConsole: NSViewRepresentable {
    let lines: [String]

    private static let attributes: [NSAttributedString.Key: Any] = {
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = 2
        return [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
    }()

    final class Coordinator {
        var shown: [String] = []
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 12, height: 2)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        scroll.documentView = textView
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView, let storage = textView.textStorage else { return }
        let coordinator: Coordinator = context.coordinator
        switch ConsoleDiff.plan(old: coordinator.shown, new: lines) {
        case .none:
            return
        case .update(let deleteUTF16, let append):
            if deleteUTF16 > 0 {
                storage.deleteCharacters(in: NSRange(location: 0, length: deleteUTF16))
            }
            if !append.isEmpty {
                storage.append(NSAttributedString(string: append, attributes: Self.attributes))
            }
        case .rebuild:
            storage.setAttributedString(NSAttributedString(string: lines.joined(separator: "\n"),
                                                           attributes: Self.attributes))
        }
        coordinator.shown = lines
        textView.scrollToEndOfDocument(nil)
    }
}

/// A button being edited (Kotlin `editIndex`).
struct MacroEdit: Identifiable, Equatable {
    let id: Int
}

/// The window's own state (Kotlin `remember`): the command line and the macro button being edited.
@MainActor
final class DxClusterWindowState: ObservableObject {
    @Published var input: String = ""
    @Published var edit: MacroEdit?
    @Published var editLabel: String = ""
    @Published var editCommand: String = ""
    @Published var sheetFontSize: Int = WindowFont.defaultSize
}

/// Kotlin `DxClusterWindow` (`dxCluster` 760×560, `DxClusterWindow.kt:77-278`): the favourite, connect / log in, the
/// status, the parallel connections, ten macro buttons (a right click edits one), the command line and the console.
struct DxClusterWindowView: View {
    static let id = "dxCluster"

    let host: AppHost

    @StateObject private var session = WindowSession(id: DxClusterWindowView.id, persistSize: true,
                                                     defaultSize: CGSize(width: 760, height: 560))
    @StateObject private var state = DxClusterWindowState()

    var body: some View {
        Group {
            if let app = host.model {
                content(app)
                    .modifier(RadioWindowChrome(host: host, app: app, id: Self.id, title: "DX Cluster",
                                                binder: session.binder))
                    .onAppear { app.dxCluster.resetSelection() }
            } else {
                Color.clear
            }
        }
        .frame(minWidth: 480, minHeight: 320)
    }

    private func content(_ app: AppModel) -> some View {
        let language: LanguageModel = app.language
        let cluster: DxClusterModel = app.dxCluster
        let lines: [String] = consoleLines(cluster)
        return VStack(alignment: .leading, spacing: 0) {
            WindowTopBar(size: $session.fontSize, language: language)
                .padding(.horizontal, 8)
                .padding(.top, 4)
            header(app: app, lines: lines)
            Text(verbatim: cluster.statusText)
                .windowFont(11)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .accessibilityIdentifier("dxcluster.status")
            parallelRow(app)
            Divider().padding(.top, 8)
            macroButtons(app)
            Text(verbatim: language.tr("Tip: pravým tlačítkem myši nad tlačítkem změníš jeho popisek a příkaz."))
                .windowFont(10)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
            Divider().padding(.top, 8)
            commandLine(app)
            Divider()
            DxClusterConsole(lines: lines)
        }
        .environment(\.windowFontSize, session.fontSize)
        .sheet(item: Binding(get: { state.edit }, set: { state.edit = $0 })) { edit in
            MacroEditSheet(app: app, state: state, index: edit.id)
        }
    }

    /// The traffic log as of the last revision (the model coalesces the log's listener into `logRevision`).
    private func consoleLines(_ cluster: DxClusterModel) -> [String] {
        _ = cluster.logRevision
        return cluster.log.snapshot()
    }

    // MARK: - header

    /// The favourite, Připojit / Odpojit, Přihlásit / Odhlásit, then Kopírovat and Vymazat.
    private func header(app: AppModel, lines: [String]) -> some View {
        let language: LanguageModel = app.language
        let cluster: DxClusterModel = app.dxCluster
        let selected: DxClusterFavorite? = cluster.selectedFavorite
        return HStack(alignment: .center, spacing: 8) {
            favoriteMenu(app: app, selected: selected)
            Button {
                if let selected {
                    cluster.toggle(selected)
                }
            } label: {
                Text(verbatim: cluster.connected ? "Odpojit" : language.tr("Připojit")).windowFont(13)
            }
            .disabled(selected == nil)
            .accessibilityIdentifier("dxcluster.connect")
            Button {
                if cluster.loggedIn {
                    cluster.logout()
                } else if let selected {
                    cluster.login(selected)
                }
            } label: {
                Text(verbatim: cluster.loggedIn ? language.tr("Odhlásit") : language.tr("Přihlásit")).windowFont(13)
            }
            .disabled(!cluster.connected || selected == nil)
            .accessibilityIdentifier("dxcluster.login")
            Spacer(minLength: 0)
            Button {
                let board = NSPasteboard.general
                board.clearContents()
                board.setString(lines.joined(separator: "\n"), forType: .string)
            } label: {
                Text(verbatim: language.tr("Kopírovat")).windowFont(13)
            }
            Button {
                cluster.clearLog()
            } label: {
                Text(verbatim: "Vymazat").windowFont(13)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// Kotlin `KitDropdown`: the selected favourite's label (or „— žádný cluster —"), the labels as the options;
    /// disabled without favourites and while connected.
    private func favoriteMenu(app: AppModel, selected: DxClusterFavorite?) -> some View {
        let language: LanguageModel = app.language
        let cluster: DxClusterModel = app.dxCluster
        let labels: [String] = cluster.favorites.map { ClusterTexts.favLabel($0, translator: language.translator) }
        let title: String = selected.map { ClusterTexts.favLabel($0, translator: language.translator) }
            ?? language.tr(ClusterTexts.noCluster)
        return Menu {
            ForEach(Array(labels.enumerated()), id: \.offset) { _, label in
                Button(label) { cluster.selectFavorite(label) }
            }
        } label: {
            Text(verbatim: title).windowFont(13)
        }
        .frame(width: WindowFont.size(240, windowSize: session.fontSize))
        .disabled(labels.isEmpty || cluster.connected)
        .accessibilityLabel(title)
        .accessibilityIdentifier("dxcluster.favorite")
    }

    /// „Souběžně:" and one checkbox per favourite that can run in parallel (RBN, skimmers), each with its state mark;
    /// hidden without such favourites. The main connection's favourite is not offered.
    @ViewBuilder
    private func parallelRow(_ app: AppModel) -> some View {
        let language: LanguageModel = app.language
        let cluster: DxClusterModel = app.dxCluster
        let choices: [DxClusterModel.ParallelChoice] = cluster.parallelChoices
        if !choices.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: language.tr("Souběžně"))
                    .windowFont(11)
                    .foregroundStyle(.secondary)
                FlowLayout(spacing: 10) {
                    ForEach(choices) { choice in
                        let name: String = ClusterTexts.favLabel(choice.favorite, translator: language.translator)
                        let label: String = choice.mark.map { name + " " + $0 } ?? name
                        Toggle(isOn: Binding(get: { choice.isOn },
                                             set: { cluster.setParallel($0, favoriteAt: choice.id) })) {
                            Text(verbatim: label).windowFont(11)
                        }
                        .toggleStyle(.checkbox)
                        .accessibilityLabel(language.tr(ClusterTexts.parallelToggleKey, .string(name)))
                        .accessibilityValue(choice.mark ?? "")
                        .accessibilityIdentifier("dxcluster.parallel.\(choice.id)")
                    }
                }
            }
            .padding(.horizontal, 12)
        }
    }

    // MARK: - macros and the command line

    private func macroButtons(_ app: AppModel) -> some View {
        let language: LanguageModel = app.language
        let cluster: DxClusterModel = app.dxCluster
        let macros: [DxClusterCommand] = cluster.macros
        return FlowLayout(spacing: 6) {
            ForEach(Array(macros.enumerated()), id: \.offset) { index, macro in
                let label: String = ClusterTexts.macroLabel(macro, translator: language.translator)
                Button {
                    cluster.send(macro.command)
                } label: {
                    Text(verbatim: label).windowFont(13).lineLimit(1)
                }
                .overlay(SecondaryClickArea { beginEdit(index: index, macro: macro) })
                .accessibilityAction(named: Text(verbatim: language.tr("Upravit tlačítko"))) {
                    beginEdit(index: index, macro: macro)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func beginEdit(index: Int, macro: DxClusterCommand) {
        state.editLabel = macro.label
        state.editCommand = macro.command
        state.sheetFontSize = session.fontSize
        state.edit = MacroEdit(id: index)
    }

    private func commandLine(_ app: AppModel) -> some View {
        let language: LanguageModel = app.language
        let cluster: DxClusterModel = app.dxCluster
        let state: DxClusterWindowState = self.state
        let submit: @MainActor () -> Void = {
            guard !KotlinStrings.isBlank(state.input) else { return }
            cluster.send(state.input)
            state.input = ""
        }
        return HStack(alignment: .center, spacing: 8) {
            TextField(text: Binding(get: { state.input }, set: { state.input = $0 })) {
                Text(verbatim: "")
            }
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .windowFont(13)
            .disabled(!cluster.connected)
            .onSubmit(submit)
            .accessibilityLabel(language.tr("Příkaz"))
            .accessibilityIdentifier("dxcluster.command")
            Button {
                submit()
            } label: {
                Text(verbatim: "Odeslat").windowFont(13)
            }
            .disabled(!cluster.connected)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// Kotlin's „Upravit tlačítko" dialog: the label and the command, Uložit / Zrušit. Saving writes the ten buttons.
struct MacroEditSheet: View {
    let app: AppModel
    @ObservedObject var state: DxClusterWindowState
    let index: Int

    var body: some View {
        let language: LanguageModel = app.language
        let state: DxClusterWindowState = self.state
        VStack(alignment: .leading, spacing: 8) {
            WindowTopBar(size: $state.sheetFontSize, language: language) {
                Text(verbatim: language.tr("Upravit tlačítko"))
                    .windowFont(15, weight: .semibold)
            }
            field("Popisek", text: $state.editLabel)
            field(language.tr("Příkaz"), text: $state.editCommand)
            DialogButtonRow {
                Button(language.tr("Zrušit")) {
                    state.edit = nil
                }
                Button(language.tr("Uložit")) {
                    app.dxCluster.saveMacro(index: index, label: state.editLabel, command: state.editCommand)
                    state.edit = nil
                }
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
